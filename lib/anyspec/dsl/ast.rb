# frozen_string_literal: true

module Anyspec
  module DSL
    module AST
      class Location
        attr_reader :file, :line, :column

        def initialize(file:, line:, column:)
          @file = file
          @line = line
          @column = column
        end

        def to_s
          "#{file}:#{line}:#{column}"
        end
      end

      class Node
        attr_reader :location

        def initialize(location:)
          @location = location
        end
      end

      class Program < Node
        attr_reader :statements

        def initialize(statements:, location:)
          super(location: location)
          @statements = statements
        end
      end

      class Assignment < Node
        attr_reader :name, :value

        def initialize(name:, value:, location:)
          super(location: location)
          @name = name
          @value = value
        end
      end

      class Pipeline < Node
        attr_reader :commands

        def initialize(commands:, location:)
          super(location: location)
          @commands = commands
        end
      end

      class Command < Node
        attr_reader :name, :arguments

        def initialize(name:, arguments:, location:)
          super(location: location)
          @name = name
          @arguments = arguments
        end
      end

      class Foreach < Node
        attr_reader :variable, :collection, :body

        def initialize(variable:, collection:, body:, location:)
          super(location: location)
          @variable = variable
          @collection = collection
          @body = body
        end
      end

      class VariableRef < Node
        attr_reader :name

        def initialize(name:, location:)
          super(location: location)
          @name = name
        end
      end

      class FieldAccess < Node
        attr_reader :object, :field

        def initialize(object:, field:, location:)
          super(location: location)
          @object = object
          @field = field
        end
      end

      class IndexAccess < Node
        attr_reader :object, :index

        def initialize(object:, index:, location:)
          super(location: location)
          @object = object
          @index = index
        end
      end

      class StringLiteral < Node
        attr_reader :value, :interpolations

        def initialize(value:, interpolations: [], location:)
          super(location: location)
          @value = value
          @interpolations = interpolations
        end

        def interpolated?
          !@interpolations.empty?
        end
      end

      class NumberLiteral < Node
        attr_reader :value

        def initialize(value:, location:)
          super(location: location)
          @value = value
        end
      end

      class BooleanLiteral < Node
        attr_reader :value

        def initialize(value:, location:)
          super(location: location)
          @value = value
        end
      end

      class NullLiteral < Node
        def initialize(location:)
          super(location: location)
        end
      end

      class ArrayLiteral < Node
        attr_reader :elements

        def initialize(elements:, location:)
          super(location: location)
          @elements = elements
        end
      end

      class HashLiteral < Node
        attr_reader :pairs

        def initialize(pairs:, location:)
          super(location: location)
          @pairs = pairs
        end
      end

      class Comment < Node
        attr_reader :text

        def initialize(text:, location:)
          super(location: location)
          @text = text
        end
      end
    end
  end
end
