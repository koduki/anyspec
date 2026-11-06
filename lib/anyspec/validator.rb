# frozen_string_literal: true

require 'yaml'
require 'time'

module Anyspec
  class Validator
    ENV_VAR_PATTERN = /\$\{([^}]+)\}/.freeze

    ValidationError = Struct.new(:spec_id, :file_path, :line, :code, :message, keyword_init: true)

    REQUIRED_FIELDS = %w[id title cloud type expect].freeze

    def initialize
      @errors = []
      @warnings = []
      @loaded_specs = []
      @env_var_refs = []
    end

    attr_reader :errors, :warnings, :loaded_specs

    def validate(path)
      @errors = []
      @warnings = []
      @loaded_specs = []
      @env_var_refs = []

      if File.directory?(path)
        validate_directory(path)
      else
        validate_file(path)
      end

      check_duplicate_ids
      check_missing_env_vars

      valid?
    end

    def valid?
      @errors.empty?
    end

    def error_messages
      @errors.map do |err|
        parts = []
        parts << "#{err.file_path}:#{err.line}" if err.file_path
        parts << "[#{err.code}]" if err.code
        parts << (err.spec_id ? "spec '#{err.spec_id}'" : nil)
        parts << err.message
        parts.compact.join(' ')
      end
    end

    private

    def validate_directory(path)
      files = Dir.glob(File.join(path, '**', '*.{yml,yaml}')).sort
      if files.empty?
        @warnings << ValidationError.new(
          file_path: path,
          code: 'NO_SPECS',
          message: 'No YAML spec files found in directory'
        )
        return
      end

      files.each { |file| validate_file(file) }
    end

    def validate_file(path)
      unless File.exist?(path)
        @errors << ValidationError.new(
          file_path: path,
          code: 'FILE_NOT_FOUND',
          message: 'File not found'
        )
        return
      end

      content = File.read(path)
      begin
        data = YAML.safe_load(content, permitted_classes: [Symbol, Date, Time])
      rescue Psych::SyntaxError => e
        @errors << ValidationError.new(
          file_path: path,
          line: e.line,
          code: 'YAML_SYNTAX',
          message: "YAML syntax error: #{e.message}"
        )
        return
      end

      items = data.is_a?(Array) ? data : [data]
      items.each_with_index do |item, idx|
        validate_spec(item, path, idx)
      end
    end

    def validate_spec(spec, file_path, index)
      return unless spec.is_a?(Hash)

      spec_id = spec['id']
      @loaded_specs << { spec: spec, file_path: file_path, index: index }

      validate_required_fields(spec, file_path, spec_id)
      validate_adapter_type(spec, file_path, spec_id) if spec['type']
      validate_until_date(spec, file_path, spec_id) if spec['until']
      collect_env_var_refs(spec, file_path, spec_id)
    end

    def validate_required_fields(spec, file_path, spec_id)
      missing = REQUIRED_FIELDS.reject { |f| spec.key?(f) && !spec[f].nil? }
      return if missing.empty?

      @errors << ValidationError.new(
        spec_id: spec_id || "(index: #{@loaded_specs.size - 1})",
        file_path: file_path,
        code: 'MISSING_FIELD',
        message: "Missing required fields: #{missing.join(', ')}"
      )
    end

    def validate_adapter_type(spec, file_path, spec_id)
      type = spec['type']
      return if AdapterRegistry.registered?(type)

      available = AdapterRegistry.available_types.join(', ')
      @errors << ValidationError.new(
        spec_id: spec_id,
        file_path: file_path,
        code: 'UNKNOWN_ADAPTER',
        message: "Unknown adapter type: '#{type}'. Available types: #{available}"
      )
    end

    def validate_until_date(spec, file_path, spec_id)
      until_value = spec['until']

      begin
        case until_value
        when Time, DateTime, Date
          # Valid date types
        when String
          Time.parse("#{until_value} UTC")
        when Integer
          @errors << ValidationError.new(
            spec_id: spec_id,
            file_path: file_path,
            code: 'INVALID_UNTIL',
            message: "Invalid until value: '#{until_value}'. Expected a date string (YYYY-MM-DD)"
          )
        else
          @errors << ValidationError.new(
            spec_id: spec_id,
            file_path: file_path,
            code: 'INVALID_UNTIL',
            message: "Invalid until type: #{until_value.class}. Expected a date string (YYYY-MM-DD)"
          )
        end
      rescue ArgumentError => e
        @errors << ValidationError.new(
          spec_id: spec_id,
          file_path: file_path,
          code: 'INVALID_UNTIL',
          message: "Invalid until date: '#{until_value}' - #{e.message}"
        )
      end
    end

    def collect_env_var_refs(obj, file_path, spec_id)
      case obj
      when Hash
        obj.each_value { |v| collect_env_var_refs(v, file_path, spec_id) }
      when Array
        obj.each { |v| collect_env_var_refs(v, file_path, spec_id) }
      when String
        obj.scan(ENV_VAR_PATTERN) do |match|
          @env_var_refs << {
            var: match[0],
            file_path: file_path,
            spec_id: spec_id
          }
        end
      end
    end

    def check_duplicate_ids
      ids_with_files = @loaded_specs
        .select { |s| s[:spec]['id'] }
        .map { |s| { id: s[:spec]['id'], file_path: s[:file_path] } }

      duplicates = ids_with_files.group_by { |h| h[:id] }.select { |_, v| v.size > 1 }

      duplicates.each do |id, occurrences|
        files = occurrences.map { |o| o[:file_path] }.uniq.join(', ')
        @errors << ValidationError.new(
          spec_id: id,
          code: 'DUPLICATE_ID',
          message: "Duplicate spec ID found in: #{files}"
        )
      end
    end

    def check_missing_env_vars
      missing_vars = @env_var_refs
        .reject { |ref| ENV.key?(ref[:var]) }
        .group_by { |ref| ref[:var] }

      missing_vars.each do |var, refs|
        files = refs.map { |r| r[:file_path] }.uniq.join(', ')
        spec_ids = refs.map { |r| r[:spec_id] }.compact.uniq.join(', ')

        @errors << ValidationError.new(
          code: 'MISSING_ENV_VAR',
          message: "Environment variable not set: #{var} (referenced in: #{files}#{spec_ids.empty? ? '' : ", specs: #{spec_ids}"})"
        )
      end
    end
  end
end
