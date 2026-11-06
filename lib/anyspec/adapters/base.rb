# frozen_string_literal: true

require 'open3'
require 'json'

module Anyspec
  module Adapters
    class Base
      attr_reader :config

      def initialize(config)
        @config = config
      end

      def fetch(_spec)
        raise NotImplementedError, "#{self.class}#fetch must be implemented"
      end

      protected

      def run_oci_cli(args)
        cmd_array = build_oci_command_array(args)

        stdout, stderr, status = Open3.capture3(*cmd_array)

        unless status.success?
          error_message = parse_cli_error(stderr, stdout)
          raise Anyspec::Error, "OCI CLI error: #{error_message}"
        end

        parse_cli_response(stdout)
      end

      def build_oci_command_array(args)
        cmd_array = [config.oci_cli_path]

        cmd_array.concat(args)

        cmd_array << '--output' << 'json'

        if config.profile && config.profile != 'DEFAULT'
          cmd_array << '--profile' << config.profile
        end

        if config.config_path
          cmd_array << '--config-file' << config.config_path
        end

        if config.auth_mode == 'instance_principal'
          cmd_array << '--auth' << 'instance_principal'
        elsif config.auth_mode == 'resource_principal'
          cmd_array << '--auth' << 'resource_principal'
        end

        if config.region
          cmd_array << '--region' << config.region
        end

        cmd_array
      end

      def parse_cli_response(stdout)
        return {} if stdout.nil? || stdout.strip.empty?

        response = JSON.parse(stdout)
        response['data'] || response
      end

      def parse_cli_error(stderr, stdout)
        begin
          if stdout && !stdout.strip.empty?
            error_data = JSON.parse(stdout)
            if error_data['message']
              return error_data['message']
            end
          end
        rescue JSON::ParserError
        end

        stderr.strip.empty? ? 'Unknown CLI error' : stderr.strip.lines.first&.strip || 'Unknown CLI error'
      end

      def normalize_oci_response(data)
        return data unless data.is_a?(Hash)

        data.each_with_object({}) do |(key, value), result|
          snake_key = kebab_to_snake(key.to_s)
          result[snake_key] = case value
                              when Hash
                                normalize_oci_response(value)
                              when Array
                                value.map { |v| v.is_a?(Hash) ? normalize_oci_response(v) : v }
                              else
                                value
                              end
        end
      end

      def kebab_to_snake(str)
        str.gsub(/-/, '_')
           .gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2')
           .gsub(/([a-z\d])([A-Z])/, '\1_\2')
           .downcase
      end
    end
  end
end
