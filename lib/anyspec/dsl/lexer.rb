# frozen_string_literal: true

module Anyspec
  module DSL
    class LexerError < StandardError
      attr_reader :location

      def initialize(message, location)
        @location = location
        super("#{location}: #{message}")
      end
    end

    class Token
      attr_reader :type, :value, :location, :preceded_by_space

      def initialize(type:, value:, location:, preceded_by_space: false)
        @type = type
        @value = value
        @location = location
        @preceded_by_space = preceded_by_space
      end

      def to_s
        "Token(#{type}, #{value.inspect}, #{location})"
      end

      def inspect
        to_s
      end
    end

    class Lexer
      KEYWORDS = %w[foreach in true false null].freeze

      TOKEN_PATTERNS = [
        [:COMMENT, /\A#[^\n]*/],
        [:WHITESPACE, /\A[ \t]+/],
        [:NEWLINE, /\A\n/],
        [:PIPE, /\A\|/],
        [:LBRACE, /\A\{/],
        [:RBRACE, /\A\}/],
        [:LBRACKET, /\A\[/],
        [:RBRACKET, /\A\]/],
        [:LPAREN, /\A\(/],
        [:RPAREN, /\A\)/],
        [:COMMA, /\A,/],
        [:DOT, /\A\./],
        [:COLON, /\A:/],
        [:ASSIGN, /\A=/],
        [:NUMBER, /\A-?\d+(?:\.\d+)?/],
        [:DOUBLE_STRING, /\A"(?:[^"\\]|\\.)*"/],
        [:SINGLE_STRING, /\A'(?:[^'\\]|\\.)*'/],
        [:VARIABLE, /\A\$[a-zA-Z_][a-zA-Z0-9_]*/],
        [:FLAG, /\A--[a-zA-Z][a-zA-Z0-9-]*/],
        [:SHORT_FLAG, /\A-[a-zA-Z]/],
        [:OCID, /\Aocid1\.[a-z]+\.[a-z0-9]+\.([a-z0-9-]*\.)?[a-zA-Z0-9]+/],
        [:IDENTIFIER, /\A[a-zA-Z_][a-zA-Z0-9_-]*/]
      ].freeze

      attr_reader :file

      def initialize(source, file: '<script>')
        @source = source
        @file = file
        @pos = 0
        @line = 1
        @column = 1
        @tokens = []
      end

      def tokenize
        preceded_by_space = false
        while @pos < @source.length
          token = next_token
          if token
            if token.type == :WHITESPACE
              preceded_by_space = true
            else
              token = Token.new(
                type: token.type,
                value: token.value,
                location: token.location,
                preceded_by_space: preceded_by_space
              )
              @tokens << token
              preceded_by_space = (token.type == :NEWLINE)
            end
          end
        end
        @tokens << Token.new(type: :EOF, value: nil, location: current_location, preceded_by_space: preceded_by_space)
        @tokens
      end

      private

      def next_token
        return nil if @pos >= @source.length

        TOKEN_PATTERNS.each do |type, pattern|
          match = @source[@pos..].match(pattern)
          next unless match

          value = match[0]
          location = current_location
          advance(value)

          if type == :IDENTIFIER && KEYWORDS.include?(value)
            type = value.upcase.to_sym
          end

          return Token.new(type: type, value: value, location: location)
        end

        raise LexerError.new("Unexpected character: #{@source[@pos].inspect}", current_location)
      end

      def advance(text)
        text.each_char do |char|
          if char == "\n"
            @line += 1
            @column = 1
          else
            @column += 1
          end
          @pos += 1
        end
      end

      def current_location
        AST::Location.new(file: @file, line: @line, column: @column)
      end
    end
  end
end
