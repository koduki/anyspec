# frozen_string_literal: true

require_relative 'ast'
require_relative 'lexer'
require_relative 'parser'
require_relative 'interpreter'
require_relative 'builtins'
require_relative 'oci/executor'
require_relative 'oci/pagination'
require_relative 'oci/builtins'

module Anyspec
  module DSL
    class Runner
      attr_reader :warnings

      def initialize(config:, executor: nil)
        @config = config
        @builtins = Builtins.new
        @executor = executor || OCI::Executor.new(config: config)
        @pagination = OCI::Pagination.new(executor: @executor)
        @oci_builtins = OCI::OciBuiltins.new(executor: @executor, pagination: @pagination)
        @oci_builtins.register_all(@builtins)
        @warnings = []
      end

      def run_file(path, env_vars: {})
        source = File.read(path)
        run_source(source, file: path, env_vars: env_vars)
      end

      def run_source(source, file: '<script>', env_vars: {})
        lexer = Lexer.new(source, file: file)
        tokens = lexer.tokenize
        
        parser = Parser.new(tokens, file: file)
        program = parser.parse
        
        interpreter = Interpreter.new(
          builtins: @builtins,
          command_executor: @executor
        )
        
        env_vars.each do |name, value|
          interpreter.env.set(name.to_s, value)
        end
        
        result = interpreter.run(program)
        @warnings = interpreter.warnings
        
        result
      end

      def self.create_with_mock_executor(config:, mock_responses: {})
        mock_executor = MockExecutor.new(responses: mock_responses)
        new(config: config, executor: mock_executor)
      end
    end

    class MockExecutor
      attr_reader :calls

      def initialize(responses: {})
        @responses = responses
        @calls = []
      end

      def execute(argv, location: nil)
        @calls << { argv: argv, location: location }
        
        key = find_response_key(argv)
        response = @responses[key]
        
        if response.nil?
          raise OCI::CLIError.new("Mock: no response for #{argv.inspect}", location)
        end
        
        if response.is_a?(Proc)
          response.call(argv)
        else
          response
        end
      end

      private

      def find_response_key(argv)
        normalized = argv.reject { |a| a.start_with?('--output') || a == 'json' }
        
        @responses.keys.find do |key|
          if key.is_a?(Regexp)
            normalized.join(' ').match?(key)
          elsif key.is_a?(Array)
            key.all? { |k| normalized.include?(k) }
          else
            normalized.join(' ').include?(key.to_s)
          end
        end
      end
    end
  end
end
