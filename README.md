# metadata-json-deps

The metadata-json-deps tool validates dependencies in `metadata.json` files in Puppet modules against a specified Puppet module and version.

## Compatibility

metadata-json-deps is compatible with Ruby versions 2.0.0 and newer.

## Usage

Install the gem by supplying it in your Gemfile:

```
source 'https://rubygems.org'
gem 'metadata_json_deps'
```

The following rake tasks are available:
- `rake compare_dependencies[managed_modules,module,version,verbose,logs_file]` Compare specified module and version against dependencies of other modules 
  - `managed_modules` Path to local YAML file or URL for a raw YAML file containing an array of modules for checking.
  - `module` Name of module on Puppet Forge using the syntax owner/name e.g. puppetlabs/stdlib
  - `version` Semantic version to compare against e.g. 5.0.1
  - `verbose` Boolean stating whether to display matches as well as non-matches. Defaults to false if not specified.
  - `logs_file` Path to logs file. This argument is optional. Logs are not saved if not specified.
- `rake compare_dependencies_current[managed_modules,verbose,logs_file]` Compare local module against dependencies of other modules. All arguments are optional.
  - `managed_modules` Path to local YAML file or URL for a raw YAML file containing an array of modules for checking. Defaults to Puppet supported modules if not specified.
  - `verbose` Boolean stating whether to display matches as well as non-matches. Defaults to false if not specified.
  - `logs_file` Path to logs file. This argument is optional. Logs are not saved if not specified.


  
The same logs are sent to logs file if the argument is specified. Logs contain details about the module which is comparing against, the module being compared from managed_modules file and the dependencies being compared.
e.g.
- The module you are comparing against module_name is DEPRECATED.
- The checked module module_name is DEPRECATED.
- The dependency module dependency_module_name is DEPRECATED.
- Checked module name module_name could not be found. Verify module_name exists on Puppet Forge.
- Error: Verify module_name exists on Puppet Forge! Verify semantic versioning syntax module_version.  
- Comparing modules against module_name version module_version
  Checking module_name
        dependency_module_name (>= 1.1.0 < 5.0.0) *doesn't match* 5.2.0
        dependency_module_name (>= 0.2.4 < 1.0.0) *matches* 0.6.0