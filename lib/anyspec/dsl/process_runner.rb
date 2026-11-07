# frozen_string_literal: true

require 'open3'
require 'timeout'

module Anyspec
  module DSL
    class ProcessRunner
      def initialize(timeout: 60, max_output: 16 * 1024 * 1024)
        @timeout, @max_output = timeout, max_output
      end

      def call(argv)
        stdout = +''
        stderr = +''
        # Array command form also prevents Ruby's single-string shell fallback.
        Open3.popen3({ 'OCI_CLI_AUTO_PROMPT' => 'False' }, [argv.first, argv.first], *argv.drop(1)) do |stdin, out, err, waiter|
          stdin.close
          readers = [out, err]
          begin
            Timeout.timeout(@timeout) do
              until readers.empty?
                ready = IO.select(readers, nil, nil, 0.1)
                next unless ready
                ready.first.each do |io|
                  chunk = io.read_nonblock(16_384, exception: false)
                  if chunk.nil?
                    readers.delete(io)
                  elsif chunk != :wait_readable
                    (io == out ? stdout : stderr) << chunk
                    raise Error, 'OCI output limit exceeded' if stdout.bytesize + stderr.bytesize > @max_output
                  end
                end
              end
              status = waiter.value
              raise Error, "OCI command exited #{status.exitstatus}" unless status.success?
            end
          rescue Timeout::Error
            raise Error, "OCI command timed out after #{@timeout}s"
          ensure
            unless waiter.join(0)
              begin
                Process.kill('KILL', waiter.pid)
              rescue Errno::ESRCH
                # Already exited.
              end
            end
            out.close unless out.closed?
            err.close unless err.closed?
          end
        end
        raise Error, 'OCI command returned empty output' if stdout.strip.empty?
        JSON.parse(stdout)
      rescue JSON::ParserError
        raise Error, 'OCI command returned invalid JSON'
      rescue Errno::ENOENT
        raise Error, 'OCI executable not found'
      end
    end
  end
end
