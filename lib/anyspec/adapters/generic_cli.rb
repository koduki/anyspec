# frozen_string_literal: true

module Anyspec
  module Adapters
    class GenericCli < Base
      def fetch(spec)
        type = spec['type']
        definition = AdapterRegistry.get_definition(type)
        raise Anyspec::Error, "No external definition found for type: #{type}" unless definition

        locator = select_locator(definition, spec)
        raise Anyspec::Error, "No matching locator for spec. Check required fields." unless locator

        args = build_cli_args(locator, spec)
        data = run_oci_cli(args)

        process_response(data, locator, spec)
      end

      private

      def select_locator(definition, spec)
        locators = definition['locators'] || []
        locators = [locators] unless locators.is_a?(Array)

        locators.find do |loc|
          required = loc['required_fields'] || []
          required.all? { |field| spec.key?(field) && !spec[field].nil? && spec[field] != '' }
        end
      end

      def build_cli_args(locator, spec)
        args = []

        subcommand = locator['subcommand']
        subcommand_parts = subcommand.is_a?(Array) ? subcommand : subcommand.to_s.split
        args.concat(subcommand_parts)

        mappings = locator['flag_mappings'] || {}
        mappings.each do |spec_field, cli_flag|
          value = spec[spec_field]
          next if value.nil? || value == ''

          flag = cli_flag.to_s.start_with?('--') ? cli_flag.to_s : "--#{cli_flag}"
          args << flag << value.to_s
        end

        static_flags = locator['static_flags'] || []
        static_flags.each do |flag_entry|
          case flag_entry
          when Hash
            flag_entry.each do |flag, value|
              flag_str = flag.to_s.start_with?('--') ? flag.to_s : "--#{flag}"
              args << flag_str << value.to_s
            end
          when String
            args << (flag_entry.start_with?('--') ? flag_entry : "--#{flag_entry}")
          end
        end

        args
      end

      def process_response(data, locator, spec)
        if data.is_a?(Array) || (data.is_a?(Hash) && data['items'])
          items = data.is_a?(Array) ? data : data['items']
          data = filter_list_result(items, locator, spec)
        end

        normalized = normalize_oci_response(data)
        extract_fields(normalized, locator)
      end

      def filter_list_result(items, locator, spec)
        filter_field = locator['list_filter_field']
        filter_spec_field = locator['list_filter_spec_field']

        if filter_field && filter_spec_field && spec[filter_spec_field]
          expected_value = spec[filter_spec_field]

          if items.empty?
            raise Anyspec::Error, "No items returned from list command; cannot filter for #{filter_spec_field}='#{expected_value}'"
          end

          found = items.find do |item|
            actual = item[filter_field] || item[kebab_to_snake(filter_field.to_s)]
            actual == expected_value
          end

          unless found
            raise Anyspec::Error, "No item found with #{filter_field}='#{expected_value}' in #{items.size} result(s)"
          end

          return found
        end

        if items.empty?
          raise Anyspec::Error, "No items returned from list command"
        end

        items.first
      end

      def extract_fields(normalized, locator)
        fields = locator['extract_fields']
        return normalized unless fields && !fields.empty?

        fields.each_with_object({}) do |field, result|
          snake_field = kebab_to_snake(field.to_s)
          result[snake_field] = deep_get(normalized, snake_field)
        end
      end

      def deep_get(hash, key)
        return nil unless hash.is_a?(Hash)

        parts = key.to_s.split('.')
        result = hash

        parts.each do |part|
          return nil unless result.is_a?(Hash)

          result = result[part] || result[part.to_sym]
        end

        result
      end
    end
  end
end
