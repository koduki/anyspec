# frozen_string_literal: true

module Anyspec
  module DSL
    class ParseError < StandardError
      attr_reader :location

      def initialize(message, location)
        @location = location
        super("#{location}: #{message}")
      end
    end

    class Parser
      def initialize(tokens, file: '<script>')
        @tokens = tokens
        @file = file
        @pos = 0
      end

      def parse
        statements = []
        skip_newlines
        while !at_end?
          stmt = parse_statement
          statements << stmt if stmt
          skip_newlines
        end
        AST::Program.new(statements: statements, location: first_location)
      end

      private

      def parse_statement
        skip_comments_and_newlines
        return nil if at_end?

        case current.type
        when :COMMENT
          parse_comment
        when :NEWLINE
          advance
          nil
        when :FOREACH
          parse_foreach
        when :VARIABLE
          parse_assignment_or_expression
        else
          parse_pipeline
        end
      end

      def parse_comment
        token = consume(:COMMENT)
        AST::Comment.new(text: token.value[1..].strip, location: token.location)
      end

      def parse_foreach
        loc = consume(:FOREACH).location
        var_token = consume(:IDENTIFIER)
        consume(:IN)
        collection = parse_expression
        consume(:LBRACE)
        skip_newlines
        body = []
        while !check(:RBRACE) && !at_end?
          stmt = parse_statement
          body << stmt if stmt
          skip_newlines
        end
        consume(:RBRACE)
        AST::Foreach.new(
          variable: var_token.value,
          collection: collection,
          body: body,
          location: loc
        )
      end

      def parse_assignment_or_expression
        if peek_next&.type == :ASSIGN
          parse_assignment
        else
          parse_pipeline
        end
      end

      def parse_assignment
        var_token = consume(:VARIABLE)
        consume(:ASSIGN)
        value = if check(:FOREACH)
                  parse_foreach
                else
                  parse_pipeline
                end
        AST::Assignment.new(
          name: var_token.value[1..],
          value: value,
          location: var_token.location
        )
      end

      def parse_pipeline
        left = parse_command_or_expression
        commands = [left]

        while check(:PIPE)
          advance
          skip_newlines
          commands << parse_command_or_expression
        end

        if commands.length == 1
          commands.first
        else
          AST::Pipeline.new(commands: commands, location: left.location)
        end
      end

      def parse_command_or_expression
        if command_start?
          parse_command
        else
          parse_expression
        end
      end

      def command_start?
        return false unless check(:IDENTIFIER)
        name = current.value
        !%w[true false null].include?(name) &&
          (peek_next.nil? || 
           [:IDENTIFIER, :VARIABLE, :FLAG, :SHORT_FLAG, :SINGLE_STRING, 
            :DOUBLE_STRING, :NUMBER, :OCID, :PIPE, :NEWLINE, :EOF, :RBRACE, 
            :LBRACKET, :LPAREN, :TRUE, :FALSE, :NULL, :RPAREN].include?(peek_next.type))
      end

      def parse_command
        name_token = consume(:IDENTIFIER)
        args = []

        while argument_token?
          args << parse_argument
        end

        AST::Command.new(
          name: name_token.value,
          arguments: args,
          location: name_token.location
        )
      end

      def argument_token?
        [:IDENTIFIER, :VARIABLE, :FLAG, :SHORT_FLAG, :SINGLE_STRING, 
         :DOUBLE_STRING, :NUMBER, :OCID, :LPAREN, :LBRACKET, 
         :TRUE, :FALSE, :NULL].include?(current.type)
      end

      def parse_argument
        case current.type
        when :FLAG, :SHORT_FLAG
          token = advance
          AST::StringLiteral.new(value: token.value, location: token.location)
        when :VARIABLE
          parse_variable_access
        when :SINGLE_STRING
          parse_single_string
        when :DOUBLE_STRING
          parse_double_string
        when :NUMBER
          parse_number
        when :OCID
          token = advance
          AST::StringLiteral.new(value: token.value, location: token.location)
        when :IDENTIFIER
          token = advance
          AST::StringLiteral.new(value: token.value, location: token.location)
        when :LPAREN
          parse_parenthesized
        when :LBRACKET
          parse_array
        when :TRUE
          loc = advance.location
          AST::BooleanLiteral.new(value: true, location: loc)
        when :FALSE
          loc = advance.location
          AST::BooleanLiteral.new(value: false, location: loc)
        when :NULL
          loc = advance.location
          AST::NullLiteral.new(location: loc)
        else
          raise ParseError.new("Unexpected token in argument: #{current.type}", current.location)
        end
      end

      def parse_expression
        parse_primary_with_access
      end

      def parse_primary_with_access
        expr = parse_primary

        loop do
          if check(:DOT)
            advance
            field_token = consume(:IDENTIFIER)
            expr = AST::FieldAccess.new(
              object: expr,
              field: field_token.value,
              location: field_token.location
            )
          elsif check(:LBRACKET)
            advance
            index = parse_expression
            consume(:RBRACKET)
            expr = AST::IndexAccess.new(
              object: expr,
              index: index,
              location: index.location
            )
          else
            break
          end
        end

        expr
      end

      def parse_primary
        case current.type
        when :VARIABLE
          parse_variable_access
        when :SINGLE_STRING
          parse_single_string
        when :DOUBLE_STRING
          parse_double_string
        when :NUMBER
          parse_number
        when :TRUE
          loc = advance.location
          AST::BooleanLiteral.new(value: true, location: loc)
        when :FALSE
          loc = advance.location
          AST::BooleanLiteral.new(value: false, location: loc)
        when :NULL
          loc = advance.location
          AST::NullLiteral.new(location: loc)
        when :LBRACKET
          parse_array
        when :LBRACE
          parse_hash
        when :LPAREN
          parse_parenthesized
        when :IDENTIFIER
          if command_start?
            parse_command
          else
            token = advance
            AST::StringLiteral.new(value: token.value, location: token.location)
          end
        else
          raise ParseError.new("Unexpected token: #{current.type} (#{current.value.inspect})", current.location)
        end
      end

      def parse_parenthesized
        consume(:LPAREN)
        skip_newlines
        expr = parse_pipeline
        skip_newlines
        consume(:RPAREN)
        expr
      end

      def parse_variable_access
        var_token = consume(:VARIABLE)
        expr = AST::VariableRef.new(name: var_token.value[1..], location: var_token.location)

        while check(:DOT) || (check(:LBRACKET) && !empty_array_ahead?)
          if check(:DOT)
            advance
            field_token = consume(:IDENTIFIER)
            expr = AST::FieldAccess.new(
              object: expr,
              field: field_token.value,
              location: field_token.location
            )
          elsif check(:LBRACKET)
            advance
            index = parse_expression
            consume(:RBRACKET)
            expr = AST::IndexAccess.new(
              object: expr,
              index: index,
              location: index.location
            )
          end
        end

        expr
      end

      def empty_array_ahead?
        check(:LBRACKET) && peek_next&.type == :RBRACKET
      end

      def parse_single_string
        token = consume(:SINGLE_STRING)
        value = token.value[1..-2].gsub(/\\'/, "'").gsub(/\\\\/, '\\')
        AST::StringLiteral.new(value: value, location: token.location)
      end

      def parse_double_string
        token = consume(:DOUBLE_STRING)
        raw = token.value[1..-2]
        
        interpolations = []
        value = raw.gsub(/\$\{([^}]+)\}|\$([a-zA-Z_][a-zA-Z0-9_]*)/) do |match|
          var_name = ::Regexp.last_match(1) || ::Regexp.last_match(2)
          interpolations << var_name
          "\x00#{interpolations.length - 1}\x00"
        end
        
        value = value.gsub(/\\"/, '"').gsub(/\\n/, "\n").gsub(/\\t/, "\t").gsub(/\\\\/, '\\')
        
        AST::StringLiteral.new(value: value, interpolations: interpolations, location: token.location)
      end

      def parse_number
        token = consume(:NUMBER)
        value = token.value.include?('.') ? token.value.to_f : token.value.to_i
        AST::NumberLiteral.new(value: value, location: token.location)
      end

      def parse_array
        loc = consume(:LBRACKET).location
        elements = []
        skip_newlines

        unless check(:RBRACKET)
          elements << parse_expression
          while check(:COMMA)
            advance
            skip_newlines
            break if check(:RBRACKET)
            elements << parse_expression
          end
        end

        skip_newlines
        consume(:RBRACKET)
        AST::ArrayLiteral.new(elements: elements, location: loc)
      end

      def parse_hash
        loc = consume(:LBRACE).location
        pairs = []
        skip_newlines

        unless check(:RBRACE)
          pairs << parse_hash_pair
          while check(:COMMA)
            advance
            skip_newlines
            break if check(:RBRACE)
            pairs << parse_hash_pair
          end
        end

        skip_newlines
        consume(:RBRACE)
        AST::HashLiteral.new(pairs: pairs, location: loc)
      end

      def parse_hash_pair
        key = case current.type
              when :IDENTIFIER, :SINGLE_STRING, :DOUBLE_STRING
                parse_expression
              else
                raise ParseError.new("Expected hash key", current.location)
              end
        consume(:COLON)
        skip_newlines
        value = parse_expression
        [key, value]
      end

      def skip_newlines
        advance while check(:NEWLINE)
      end

      def skip_comments_inline
        advance while check(:COMMENT) && !at_end?
      end

      def skip_comments_and_newlines
        while (check(:COMMENT) || check(:NEWLINE)) && !at_end?
          advance
        end
      end

      def current
        @tokens[@pos] || @tokens.last
      end

      def peek_next
        @tokens[@pos + 1]
      end

      def check(type)
        current.type == type
      end

      def at_end?
        current.type == :EOF
      end

      def advance
        token = current
        @pos += 1 unless at_end?
        token
      end

      def consume(type)
        if check(type)
          advance
        else
          raise ParseError.new("Expected #{type}, got #{current.type}", current.location)
        end
      end

      def first_location
        @tokens.first&.location || AST::Location.new(file: @file, line: 1, column: 1)
      end
    end
  end
end
