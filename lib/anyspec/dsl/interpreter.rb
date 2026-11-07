# frozen_string_literal: true

module Anyspec
  module DSL
    class RuntimeError < StandardError
      attr_reader :location

      def initialize(message, location)
        @location = location
        super("#{location}: #{message}")
      end
    end

    class Environment
      attr_reader :parent

      def initialize(parent: nil)
        @variables = {}
        @parent = parent
      end

      def get(name)
        if @variables.key?(name)
          @variables[name]
        elsif @parent
          @parent.get(name)
        else
          raise KeyError, "Undefined variable: $#{name}"
        end
      end

      def set(name, value)
        @variables[name] = value
      end

      def defined?(name)
        @variables.key?(name) || (@parent&.defined?(name) || false)
      end

      def to_h
        parent_vars = @parent&.to_h || {}
        parent_vars.merge(@variables)
      end
    end

    class Interpreter
      attr_reader :warnings, :env

      def initialize(builtins:, command_executor: nil)
        @builtins = builtins
        @command_executor = command_executor
        @env = Environment.new
        @warnings = []
        @memo_cache = {}
      end

      def run(program, input: nil)
        @env.set('_', input) if input
        result = nil
        program.statements.each do |stmt|
          result = evaluate(stmt)
        end
        result
      end

      def evaluate(node)
        case node
        when AST::Program
          run(node)
        when AST::Assignment
          evaluate_assignment(node)
        when AST::Pipeline
          evaluate_pipeline(node)
        when AST::Command
          evaluate_command(node)
        when AST::Foreach
          evaluate_foreach(node)
        when AST::VariableRef
          evaluate_variable_ref(node)
        when AST::FieldAccess
          evaluate_field_access(node)
        when AST::IndexAccess
          evaluate_index_access(node)
        when AST::StringLiteral
          evaluate_string_literal(node)
        when AST::NumberLiteral
          node.value
        when AST::BooleanLiteral
          node.value
        when AST::NullLiteral
          nil
        when AST::ArrayLiteral
          node.elements.map { |e| evaluate(e) }
        when AST::HashLiteral
          node.pairs.to_h { |k, v| [evaluate(k).to_s, evaluate(v)] }
        when AST::Comment
          nil
        else
          raise RuntimeError.new("Unknown node type: #{node.class}", node.location)
        end
      end

      def add_warning(message, location = nil)
        @warnings << { message: message, location: location&.to_s }
      end

      def memoize(key)
        return @memo_cache[key] if @memo_cache.key?(key)
        @memo_cache[key] = yield
      end

      private

      def evaluate_assignment(node)
        value = evaluate(node.value)
        @env.set(node.name, value)
        value
      end

      def evaluate_pipeline(node)
        result = nil
        node.commands.each do |cmd|
          @env.set('_', result) if result
          result = evaluate(cmd)
        end
        result
      end

      def evaluate_command(node)
        name = node.name
        args = node.arguments.map { |a| evaluate(a) }

        if @builtins.registered?(name)
          @builtins.call(name, args, self, node.location)
        elsif @command_executor && name == 'oci'
          @command_executor.execute(['oci'] + args.map(&:to_s), location: node.location)
        else
          raise RuntimeError.new("Unknown command: #{name}", node.location)
        end
      end

      def evaluate_foreach(node)
        collection = evaluate(node.collection)
        
        unless collection.is_a?(Array)
          raise RuntimeError.new("foreach requires an array, got #{collection.class}", node.location)
        end

        results = []
        collection.each do |item|
          child_env = Environment.new(parent: @env)
          child_env.set(node.variable, item)
          
          child_interpreter = Interpreter.new(
            builtins: @builtins,
            command_executor: @command_executor
          )
          child_interpreter.instance_variable_set(:@env, child_env)
          child_interpreter.instance_variable_set(:@memo_cache, @memo_cache)
          
          result = nil
          node.body.each do |stmt|
            result = child_interpreter.evaluate(stmt)
          end
          results << result
          @warnings.concat(child_interpreter.warnings)
        end
        results
      end

      def evaluate_variable_ref(node)
        @env.get(node.name)
      rescue KeyError => e
        raise RuntimeError.new(e.message, node.location)
      end

      def evaluate_field_access(node)
        object = evaluate(node.object)
        field = node.field

        case object
        when Hash
          key = object.key?(field) ? field : field.tr('_', '-')
          object[key]
        when Array
          raise RuntimeError.new("Cannot access field '#{field}' on array", node.location)
        when NilClass
          nil
        else
          raise RuntimeError.new("Cannot access field '#{field}' on #{object.class}", node.location)
        end
      end

      def evaluate_index_access(node)
        object = evaluate(node.object)
        index = evaluate(node.index)

        case object
        when Array
          object[index.to_i]
        when Hash
          object[index.to_s]
        when NilClass
          nil
        else
          raise RuntimeError.new("Cannot index #{object.class}", node.location)
        end
      end

      def evaluate_string_literal(node)
        if node.interpolated?
          result = node.value.dup
          node.interpolations.each_with_index do |var_name, idx|
            value = @env.get(var_name)
            result.gsub!("\x00#{idx}\x00", value.to_s)
          end
          result
        else
          node.value
        end
      rescue KeyError => e
        raise RuntimeError.new(e.message, node.location)
      end
    end
  end
end
