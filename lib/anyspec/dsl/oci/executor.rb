# frozen_string_literal: true

require 'open3'
require 'json'
require 'timeout'

module Anyspec
  module DSL
    module OCI
      class ExecutorError < RuntimeError; end
      class TimeoutError < ExecutorError; end
      class OutputTooLargeError < ExecutorError; end
      class CLIError < ExecutorError; end

      class Executor
        ALLOWED_COMMANDS = ['oci'].freeze
        DEFAULT_TIMEOUT = 300
        MAX_OUTPUT_SIZE = 100 * 1024 * 1024

        attr_reader :config

        def initialize(config:, timeout: DEFAULT_TIMEOUT, max_output: MAX_OUTPUT_SIZE)
          @config = config
          @timeout = timeout
          @max_output = max_output
        end

        def execute(argv, location: nil)
          validate_command(argv, location)
          cmd_array = build_command_array(argv)
          
          stdout, stderr, status = run_with_timeout(cmd_array, location)
          
          validation_result = validate_output(stdout, stderr, status, location, cmd_array)
          
          if validation_result == :empty_iam_result
            return []
          end
          
          parse_response(stdout, location)
        end

        private

        def validate_command(argv, location)
          return if argv.empty?
          
          base_cmd = File.basename(argv.first.to_s)
          unless ALLOWED_COMMANDS.include?(base_cmd)
            raise ExecutorError.new(
              "Command not allowed: #{base_cmd}. Allowed: #{ALLOWED_COMMANDS.join(', ')}",
              location
            )
          end
        end

        def build_command_array(argv)
          cmd_array = argv.map(&:to_s)
          
          if cmd_array.first == 'oci'
            cmd_array[0] = @config.oci_cli_path
          end

          unless cmd_array.include?('--output')
            cmd_array << '--output' << 'json'
          end

          if @config.profile && @config.profile != 'DEFAULT' && !cmd_array.include?('--profile')
            cmd_array << '--profile' << @config.profile
          end

          if @config.config_path && !cmd_array.include?('--config-file')
            cmd_array << '--config-file' << @config.config_path
          end

          if @config.auth_mode == 'instance_principal' && !cmd_array.include?('--auth')
            cmd_array << '--auth' << 'instance_principal'
          elsif @config.auth_mode == 'resource_principal' && !cmd_array.include?('--auth')
            cmd_array << '--auth' << 'resource_principal'
          end

          if @config.region && !cmd_array.include?('--region')
            cmd_array << '--region' << @config.region
          end

          cmd_array
        end

        def run_with_timeout(cmd_array, location)
          stdout = ''
          stderr = ''
          status = nil

          begin
            Timeout.timeout(@timeout) do
              stdout, stderr, status = Open3.capture3(*cmd_array, stdin_data: '')
            end
          rescue Timeout::Error
            raise TimeoutError.new("Command timed out after #{@timeout}s", location)
          end

          if stdout.bytesize > @max_output
            raise OutputTooLargeError.new(
              "Output too large: #{stdout.bytesize} bytes (max: #{@max_output})",
              location
            )
          end

          [stdout, stderr, status]
        end

        def validate_output(stdout, stderr, status, location, cmd_array)
          unless status.success?
            error_msg = parse_error_message(stdout, stderr)
            raise CLIError.new("OCI CLI failed (exit #{status.exitstatus}): #{error_msg}", location)
          end

          if stdout.nil? || stdout.strip.empty?
            if iam_list_command?(cmd_array)
              return :empty_iam_result
            end
            raise CLIError.new('OCI CLI returned empty output', location)
          end
          
          :has_output
        end

        def iam_list_command?(cmd_array)
          cmd_str = cmd_array.join(' ')
          cmd_str.include?('iam') && cmd_str.include?('list')
        end

        def parse_response(stdout, location)
          begin
            response = JSON.parse(stdout)
          rescue JSON::ParserError => e
            raise CLIError.new("Invalid JSON response: #{e.message}", location)
          end

          if scim_error?(response)
            raise CLIError.new("SCIM Error: #{response['detail'] || response['status']}", location)
          end

          response.key?('data') ? response['data'] : response
        end

        def scim_error?(response)
          response.is_a?(Hash) &&
            response['schemas']&.any? { |s| s.include?('Error') } &&
            response.key?('status')
        end

        def parse_error_message(stdout, stderr)
          if stdout && !stdout.strip.empty?
            begin
              error_data = JSON.parse(stdout)
              return error_data['message'] if error_data['message']
              return error_data['detail'] if error_data['detail']
            rescue JSON::ParserError
            end
          end

          stderr.strip.empty? ? 'Unknown CLI error' : stderr.strip.lines.first&.strip || 'Unknown error'
        end
      end
    end
  end
end
