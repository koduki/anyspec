# frozen_string_literal: true

require 'open3'
require 'json'
require 'thread'

module Anyspec
  module DSL
    module OCI
      class ExecutorError < RuntimeError; end
      class TimeoutError < ExecutorError; end
      class OutputTooLargeError < ExecutorError; end
      class CLIError < ExecutorError; end

      class Executor
        READ_ACTIONS = %w[get list].freeze
        RESTRICTED_OPTIONS = %w[--auth --profile --config-file --cli-rc-file --defaults-file --proxy].freeze
        DEFAULT_TIMEOUT = 300
        MAX_OUTPUT_SIZE = 100 * 1024 * 1024

        attr_reader :config

        def initialize(config:, timeout: DEFAULT_TIMEOUT, max_output: MAX_OUTPUT_SIZE)
          @config = config
          @timeout = timeout
          @max_output = max_output
        end

        def execute(argv, location: nil, preserve_envelope: false)
          validate_command(argv, location)
          cmd_array = build_command_array(argv)
          
          stdout, stderr, status = run_with_timeout(cmd_array, location)
          
          validation_result = validate_output(stdout, stderr, status, location, cmd_array)
          
          if validation_result == :empty_iam_result
            return []
          end
          
          parse_response(stdout, location, preserve_envelope: preserve_envelope)
        end

        private

        def validate_command(argv, location)
          unless argv.is_a?(Array) && argv.first == 'oci'
            raise ExecutorError.new('Only the configured oci executable is allowed', location)
          end
          return if @config.allow_oci_writes

          args = argv.drop(1).map(&:to_s)
          forbidden = args.find { |arg| RESTRICTED_OPTIONS.any? { |flag| arg == flag || arg.start_with?("#{flag}=") } }
          raise ExecutorError.new("OCI option is controlled by anyspec: #{forbidden}", location) if forbidden

          command = args.take_while { |arg| !arg.start_with?('-') }
          if command == ['raw-request']
            methods = args.each_with_index.filter_map do |arg, index|
              arg == '--http-method' ? args[index + 1] : arg.delete_prefix('--http-method=') if arg == '--http-method' || arg.start_with?('--http-method=')
            end
            return if methods.length == 1 && methods.first.to_s.upcase == 'GET'
          elsif command.length >= 2 && READ_ACTIONS.include?(command.last)
            return
          end

          raise ExecutorError.new('OCI command is not read-only; use --allow-oci-writes to opt in', location)
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
          buffers = { stdout: ''.b, stderr: ''.b }
          queue = SizedQueue.new(8)
          deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + @timeout
          windows = RUBY_PLATFORM.match?(/mswin|mingw|cygwin/)
          options = windows ? {} : { pgroup: true }

          Open3.popen3(*cmd_array, **options) do |stdin, stdout, stderr, wait_thread|
            stdin.close
            readers = { stdout: stdout, stderr: stderr }.map do |name, stream|
              Thread.new do
                begin
                  loop { queue.push([name, stream.readpartial(16_384)]) }
                rescue EOFError
                  queue.push([name, nil])
                rescue IOError, SystemCallError => e
                  queue.push([:read_error, e])
                end
              end
            end
            completed_streams = 0
            completed = false
            begin
              until completed_streams == 2 && !wait_thread.alive?
                if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
                  raise TimeoutError.new("Command timed out after #{@timeout}s", location)
                end
                begin
                  name, chunk = queue.pop(true)
                rescue ThreadError
                  sleep 0.005
                  next
                end
                raise ExecutorError.new("OCI CLI output read failed: #{chunk.message}", location) if name == :read_error
                if chunk.nil?
                  completed_streams += 1
                  next
                end
                buffers[name] << chunk
                if buffers[:stdout].bytesize + buffers[:stderr].bytesize > @max_output
                  raise OutputTooLargeError.new("Combined stdout/stderr exceeds #{@max_output} bytes", location)
                end
              end
              status = wait_thread.value
              completed = true
              [buffers[:stdout].force_encoding(Encoding::UTF_8), buffers[:stderr].force_encoding(Encoding::UTF_8), status]
            ensure
              terminate_process(wait_thread, windows: windows) unless completed
              [stdout, stderr].each { |stream| stream.close unless stream.closed? }
              readers.each { |thread| thread.kill if thread.alive? }
              readers.each(&:join)
            end
          end
        end

        def terminate_process(wait_thread, windows:)
          target = windows ? wait_thread.pid : -wait_thread.pid
          begin
            Process.kill('TERM', target)
          rescue Errno::ESRCH, Errno::EPERM, NotImplementedError
          end
          wait_thread.join(0.2)
          begin
            Process.kill('KILL', target)
          rescue Errno::ESRCH, Errno::EPERM, NotImplementedError
          end
          wait_thread.join
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
          command = cmd_array.drop(1).take_while { |arg| !arg.start_with?('-') }
          command.first == 'iam' && command.last == 'list'
        end

        def parse_response(stdout, location, preserve_envelope: false)
          begin
            response = JSON.parse(stdout)
          rescue JSON::ParserError => e
            raise CLIError.new("Invalid JSON response: #{e.message}", location)
          end

          if scim_error?(response)
            raise CLIError.new("SCIM Error: #{response['detail'] || response['status']}", location)
          end

          return response if preserve_envelope

          response.is_a?(Hash) && response.key?('data') ? response['data'] : response
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
