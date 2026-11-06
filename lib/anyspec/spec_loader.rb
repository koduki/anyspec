# frozen_string_literal: true

require 'yaml'

module Anyspec
  class SpecLoader
    ENV_VAR_PATTERN = /\$\{([^}]+)\}/.freeze

    attr_reader :loaded_paths

    def initialize
      @specs = []
      @loaded_paths = []
    end

    def load(path)
      if File.directory?(path)
        load_directory(path)
      else
        load_file(path)
      end
      validate_specs!
      @specs
    end

    def load_file(path)
      expanded_path = File.expand_path(path)
      @loaded_paths << expanded_path
      content = File.read(path)
      data = YAML.safe_load(content, permitted_classes: [Symbol])
      items = data.is_a?(Array) ? data : [data]
      items.each do |item|
        spec = interpolate_env_vars(item)
        spec['_source_file'] = expanded_path
        @specs << spec
      end
    end

    def load_directory(path)
      Dir.glob(File.join(path, '**', '*.{yml,yaml}')).sort.each do |file|
        load_file(file)
      end
    end

    private

    def interpolate_env_vars(obj)
      case obj
      when Hash
        obj.transform_values { |v| interpolate_env_vars(v) }
      when Array
        obj.map { |v| interpolate_env_vars(v) }
      when String
        interpolate_string(obj)
      else
        obj
      end
    end

    def interpolate_string(str)
      str.gsub(ENV_VAR_PATTERN) do
        env_var = ::Regexp.last_match(1)
        ENV.fetch(env_var) do
          raise Anyspec::Error, "Environment variable not set: #{env_var}"
        end
      end
    end

    def validate_specs!
      ids = @specs.map { |s| s['id'] }
      duplicates = ids.group_by(&:itself).select { |_, v| v.size > 1 }.keys

      raise Anyspec::SpecValidationError, "Duplicate spec IDs: #{duplicates.join(', ')}" if duplicates.any?

      @specs.each do |spec|
        validate_spec(spec)
      end
    end

    def validate_spec(spec)
      required_fields = %w[id title cloud type expect]
      missing = required_fields.reject { |f| spec.key?(f) }

      return if missing.empty?

      raise Anyspec::SpecValidationError,
            "Spec '#{spec['id'] || 'unknown'}' missing required fields: #{missing.join(', ')}"
    end
  end
end
