# frozen_string_literal: true

require 'yaml'

module Anyspec
  class ExternalAdapterLoader
    ADAPTER_SCHEMA_VERSION = '1.0'
    SAFE_YAML_CLASSES = [Symbol].freeze
    ADAPTER_FILE_PATTERN = '*.{yml,yaml}'
    ANYSPEC_ADAPTERS_SUBDIR = File.join('.anyspec', 'adapters')

    attr_reader :search_paths, :loaded_files, :loaded_types

    def initialize(options = {})
      @explicit_dirs = parse_explicit_dirs(options[:adapters_dir])
      @search_paths = []
      @loaded_files = []
      @loaded_types = {}
    end

    def load_all
      @search_paths = build_search_paths
      @loaded_files = []
      @loaded_types = {}

      @search_paths.each do |dir_path|
        load_from_directory(dir_path)
      end

      register_loaded_definitions
      @loaded_types
    end

    def self.schema_version
      ADAPTER_SCHEMA_VERSION
    end

    private

    def parse_explicit_dirs(adapters_dir)
      return [] unless adapters_dir

      dirs = adapters_dir.to_s.split(File::PATH_SEPARATOR)
      dirs.map { |d| File.expand_path(d) }.reject(&:empty?)
    end

    def build_search_paths
      paths = []

      paths.concat(@explicit_dirs)
      paths << beside_executable_path
      paths << project_local_path
      paths << user_home_path

      paths.compact.select { |p| Dir.exist?(p) }.uniq
    end

    def beside_executable_path
      exe_path = executable_path
      return nil unless exe_path

      File.join(File.dirname(exe_path), 'adapters')
    end

    def executable_path
      if defined?($PROGRAM_NAME) && $PROGRAM_NAME && !$PROGRAM_NAME.empty?
        path = File.expand_path($PROGRAM_NAME)
        return path if File.exist?(path)
      end

      nil
    end

    def project_local_path
      File.join(Dir.pwd, ANYSPEC_ADAPTERS_SUBDIR)
    end

    def user_home_path
      File.join(Dir.home, ANYSPEC_ADAPTERS_SUBDIR)
    rescue ArgumentError
      nil
    end

    def load_from_directory(dir_path)
      pattern = File.join(dir_path, '**', ADAPTER_FILE_PATTERN)
      Dir.glob(pattern).sort.each do |file_path|
        load_definition_file(file_path)
      end
    end

    def load_definition_file(file_path)
      content = File.read(file_path)

      documents = safe_load_yaml_documents(content, file_path)

      documents.each do |data|
        next unless data.is_a?(Hash)

        if data['adapters'].is_a?(Array)
          load_multi_adapter_document(data, file_path)
        elsif data['type']
          load_single_adapter(data, file_path)
        end
      end

      AdapterRegistry.loaded_definition_files << file_path unless AdapterRegistry.loaded_definition_files.include?(file_path)
    rescue Errno::ENOENT, Errno::EACCES => e
      warn "Warning: Failed to read adapter definition #{file_path}: #{e.message}"
    rescue Psych::SyntaxError => e
      warn "Warning: Failed to parse adapter definition #{file_path}: #{e.message}"
    rescue Psych::DisallowedClass => e
      warn "Warning: Unsafe YAML class in #{file_path}: #{e.message}"
    rescue Anyspec::Error => e
      warn "Warning: Invalid adapter definition #{file_path}: #{e.message}"
    end

    def safe_load_yaml_documents(content, file_path)
      documents = []

      content.split(/^---\s*$/).each do |doc_content|
        next if doc_content.strip.empty?

        data = YAML.safe_load(
          doc_content,
          permitted_classes: SAFE_YAML_CLASSES,
          permitted_symbols: [],
          aliases: false
        )
        documents << data if data
      end

      documents
    end

    def load_multi_adapter_document(data, file_path)
      validate_schema_version!(data, file_path)

      data['adapters'].each_with_index do |adapter_def, idx|
        unless adapter_def.is_a?(Hash)
          warn "Warning: Invalid adapter definition #{file_path}: adapter at index #{idx} is not a Hash"
          next
        end

        unless adapter_def['type']
          warn "Warning: Invalid adapter definition #{file_path}: adapter at index #{idx} missing 'type' field"
          next
        end

        validate_adapter_definition!(adapter_def, file_path)
        register_type(adapter_def, file_path)
      end
    end

    def load_single_adapter(data, file_path)
      validate_schema_version!(data, file_path)
      validate_adapter_definition!(data, file_path)
      register_type(data, file_path)
    end

    def register_type(adapter_def, file_path)
      type_name = adapter_def['type']
      return if @loaded_types.key?(type_name)

      @loaded_types[type_name] = {
        definition: adapter_def,
        source_file: file_path
      }
    end

    def register_loaded_definitions
      @loaded_types.each do |type_name, info|
        AdapterRegistry.register_external_definition(
          type_name,
          info[:definition],
          source_file: info[:source_file]
        )
      end
    end

    def validate_schema_version!(data, file_path)
      version = data['schema_version'] || data['version']
      return unless version

      major_version = version.to_s.split('.').first.to_i
      current_major = ADAPTER_SCHEMA_VERSION.split('.').first.to_i

      if major_version > current_major
        raise Anyspec::Error, "Unsupported schema version #{version} (current: #{ADAPTER_SCHEMA_VERSION})"
      end
    end

    def validate_adapter_definition!(data, file_path)
      unless data['type'].is_a?(String) && !data['type'].empty?
        raise Anyspec::Error, "Missing or invalid 'type' field"
      end

      if data['dsl']
        unless data['dsl'].is_a?(String) && data['inputs'].is_a?(Array) && data['inputs'].all? { |key| key.is_a?(String) }
          raise Anyspec::Error, 'DSL definition requires a script path and inputs array'
        end
        source_path = File.realpath(File.expand_path(data['dsl'], File.dirname(file_path)))
        root = File.realpath(File.dirname(file_path)) + File::SEPARATOR
        raise Anyspec::Error, 'DSL script must reside within its definition directory' unless source_path.start_with?(root)
        source = File.read(source_path)
        nodes = DSL::Parser.new(source, file: source_path).parse
        DSL::Runtime.new.validate(nodes, file: source_path)
        data['_source'], data['_file'] = source, source_path
        return
      end

      locators = data['locators']
      unless locators
        raise Anyspec::Error, "Missing 'locators' field"
      end

      locators_array = locators.is_a?(Array) ? locators : [locators]
      locators_array.each_with_index do |loc, idx|
        validate_locator!(loc, idx)
      end

      validate_no_dangerous_content!(data)
    end

    def validate_locator!(locator, index)
      unless locator.is_a?(Hash)
        raise Anyspec::Error, "Locator at index #{index} must be a Hash"
      end

      unless locator['subcommand']
        raise Anyspec::Error, "Locator at index #{index} missing 'subcommand'"
      end

      if locator['flag_mappings'] && !locator['flag_mappings'].is_a?(Hash)
        raise Anyspec::Error, "Locator at index #{index}: 'flag_mappings' must be a Hash"
      end

      if locator['required_fields'] && !locator['required_fields'].is_a?(Array)
        raise Anyspec::Error, "Locator at index #{index}: 'required_fields' must be an Array"
      end

      if locator['extract_fields'] && !locator['extract_fields'].is_a?(Array)
        raise Anyspec::Error, "Locator at index #{index}: 'extract_fields' must be an Array"
      end
    end

    def validate_no_dangerous_content!(data)
      check_for_dangerous_values(data, [])
    end

    def check_for_dangerous_values(obj, path)
      case obj
      when Hash
        obj.each do |key, value|
          if key.to_s.include?('eval') || key.to_s.include?('exec')
            raise Anyspec::Error, "Forbidden key '#{key}' at #{path.join('.')}"
          end
          check_for_dangerous_values(value, path + [key])
        end
      when Array
        obj.each_with_index do |item, idx|
          check_for_dangerous_values(item, path + [idx])
        end
      when String
        if obj =~ /`.*`/ || obj =~ /\$\(.*\)/
          raise Anyspec::Error, "Potential shell injection at #{path.join('.')}: #{obj[0, 50]}"
        end
      end
    end
  end
end
