require 'json'
require 'yaml'
require 'net/http'
require 'uri'
require 'logger'
require 'parallel'

# Main runner for MetadataJsonDeps
class MetadataJsonDeps::Runner
  def initialize(managed_modules_path, updated_module, updated_module_version, verbose, use_slack, logs_file)
    @default_managed_modules_path = 'https://gist.githubusercontent.com/eimlav/6df50eda0b1c57c1ab8c33b64c82c336/raw/managed_modules.yaml'
    managed_modules_path ||= @default_managed_modules_path
    @module_names = return_modules(managed_modules_path)
    @updated_module = updated_module
    @logs_file = logs_file
    @updated_module_version = updated_module_version
    @verbose = verbose
    @forge = MetadataJsonDeps::ForgeHelper.new
    @use_slack = use_slack
    @slack_webhook = ENV['METADATA_JSON_DEPS_SLACK_WEBHOOK']
  end

  def run
    validate_arguments

    message = "_*Starting dependency checks...*_\nOverriding *#{@updated_module}* version with *#{@updated_module_version}*\n\n"

    # Post warning if @updated_module is deprecated
    message += "The module you are comparing against *#{@updated_module}* is *deprecated*.\n\n" if @forge.check_module_deprecated(@updated_module)

    # Post message if using default managed_modules
    message += "No managed_modules argument specified. Defaulting to Puppet supported modules.\n\n" if @managed_modules_path == @default_managed_modules_path

    # Post results of dependency checks
    message += run_dependency_checks

    post(message)
  end

  # Validate arguments from runner and return an error if any issues are encountered
  def validate_arguments
    raise "*Error:* Could not find *#{@updated_module}* on Puppet Forge! Ensure updated_module argument is valid." unless check_module_exists(@updated_module)
    raise "*Error:* Verify semantic versioning syntax *#{@updated_module_version}* of updated_module_version argument." unless SemanticPuppet::Version.valid?(@updated_module_version)
  end

  # Check with forge if a specified module exists
  # @param module_name [String]
  # @return [Boolean] boolean based on whether the module exists or not
  def check_module_exists(module_name)
    @forge.check_module_exists(module_name)
  end

  # Perform dependency checks on modules supplied by @module_names
  def run_dependency_checks
    # Cross reference dependencies from managed_modules file with @updated_module and @updated_module_version
    messages = Parallel.map(@module_names) do |module_name|
      mod_message = "Checking *#{module_name}* dependencies.\n"
      module_name = module_name.sub('/', '-')

      # Check module_name is valid
      unless check_module_exists(module_name)
        mod_message += "\t*Error:* Could not find *#{module_name}* on Puppet Forge! Ensure the module exists.\n\n"
        next mod_message
      end

      # Fetch module dependencies
      dependencies = get_dependencies(module_name)

      # Post warning if module_name is deprecated
      mod_message += "\t*Warning:* The module *#{module_name}* is *deprecated*.\n" if @forge.check_module_deprecated(module_name)

      if dependencies.empty?
        mod_message += "\tNo dependencies listed\n\n"
        next mod_message
      end

      # Check each dependency to see if the latest version matchs the current modules' dependency constraints
      all_match = true
      found_deprecation = false
      dependencies.each do |dependency, constraint, current, satisfied|
        if satisfied && @verbose
          mod_message += "\t#{dependency} (#{constraint}) *matches* #{current}\n"
        else
          all_match = false
          mod_message += "\t#{dependency} (#{constraint}) *doesn't match* #{current}\n"
        end

        found_deprecation = true if @forge.check_module_deprecated(dependency)

        # Post warning if dependency is deprecated
        mod_message += "\tThe dependency module *#{dependency}* is *deprecated*.\n" if found_deprecation
      end

      mod_message += "\tAll dependencies match\n" if all_match && !found_deprecation
      mod_message += "\n"
      mod_message
    end

    message = ''
    messages.each do |result|
      message += result
    end

    message
  end

  # Get dependencies of a supplied module and use the override values from @updated_module and @updated_module_version
  # to verify if the depedencies are satisfied
  # @param module_name [String]
  # @return [Map] a map of dependencies along with their constraint, current version and whether they satisfy the constraint
  def get_dependencies(module_name)
    module_data = @forge.get_module_data(module_name)
    metadata = module_data.current_release.metadata
    checker = MetadataJsonDeps::MetadataChecker.new(metadata, @forge, @updated_module, @updated_module_version)
    checker.check_dependencies
  end

  # Retrieve the array of module names from the supplied filename/URL
  # @return [Array] an array of module names
  def return_modules(managed_modules_path)
    managed_modules = {}
    managed_modules_yaml = {}

    begin
      if managed_modules_path =~ URI::DEFAULT_PARSER.make_regexp
        managed_modules = Net::HTTP.get(URI.parse(managed_modules_path))
      elsif File.file?(managed_modules_path)
        managed_modules = File.read(managed_modules_path)
      else
        raise 'Error'
      end
    rescue StandardError
      raise "*Error:* Ensure *#{managed_modules_path}* is a valid file path or URL"
    end

    begin
      managed_modules_yaml = YAML.safe_load(managed_modules)
    rescue StandardError
      raise '*Error:* Ensure syntax of managed_modules file is a valid YAML array'
    end

    managed_modules_yaml
  end

  # Post message to console, Slack and/or a logfile based on whether they have been enabled
  # @param message [String]
  def post(message)
    puts message
    post_to_slack(message) if @use_slack
    post_to_logs(message) if @logs_file
  end

  # Overwrite the logfile specified by @logs_file from @logsfile with a supplied message
  # @param message [String]
  def post_to_logs(message)
    File.delete(@logs_file) if File.exist?(@logs_file)
    logger = Logger.new File.new(@logs_file, 'w')
    logger.datetime_format = '%Y-%m-%d %H:%M:%S'
    logger.info message
  end

  # Post a supplied message to Slack using a Slack webhook specified by @slack_webhook
  # @param message [String]
  def post_to_slack(message)
    raise 'METADATA_JSON_DEPS_SLACK_WEBHOOK env var not specified' unless @slack_webhook

    uri = URI.parse(@slack_webhook)
    request = Net::HTTP::Post.new(uri)
    request.content_type = 'application/json'
    request.body = JSON.dump(
      'text' => message,
    )

    req_options = {
      use_ssl: uri.scheme == 'https'
    }

    response = Net::HTTP.start(uri.hostname, uri.port, req_options) do |http|
      http.request(request)
    end

    raise 'Encountered issue posting to Slack' unless response.code == '200'
  end

  def get_metadata_from_file(filename)
    JSON.parse(File.read(filename))
  end

  def self.run(managed_modules_path, module_name, new_version, verbose = 'false', use_slack = 'false', logs_file)
    new(managed_modules_path, module_name, new_version, verbose == 'true', use_slack == 'true', logs_file).run
  end
end
