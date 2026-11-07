# frozen_string_literal: true

require 'json'
require 'strscan'

module Anyspec
  module DSL
    class Error < Anyspec::Error; end
    Token = Struct.new(:kind, :value, :line, :column, keyword_init: true)
    Node = Struct.new(:kind, :name, :pipeline, :body, :token, keyword_init: true)

    # Deliberately not a shell parser: no expansion, eval, redirection or functions.
    class Parser
      attr_reader :file

      def initialize(source, file: '(dsl)')
        @file = file
        raise Error, "#{file}:1:1: source exceeds 1 MiB" if source.bytesize > 1_048_576
        @tokens = lex(source)
        @offset = 0
      end

      def parse
        block(false, 0)
      end

      private

      def lex(source)
        scanner = StringScanner.new(source)
        tokens = []
        line = 1
        column = 1
        until scanner.eos?
          start_line, start_column = line, column
          text = scanner.scan(/[ \t\r]+|#[^\n]*/)
          unless text
            kind = :word
            text = scanner.scan(/\n|\||=/)
            if text
              kind = { "\n" => :newline, '|' => :pipe, '=' => :equals }.fetch(text)
              value = text
            elsif scanner.peek(1) == "'"
              text = scanner.scan(/'[^'\n]*'/)
              fail_at(start_line, start_column, 'unterminated literal string') unless text
              kind, value = :literal, text[1...-1]
            elsif ['"', '[', '{'].include?(scanner.peek(1))
              text = json_token(scanner, start_line, start_column)
              begin
                kind, value = :literal, JSON.parse(text)
              rescue JSON::ParserError
                fail_at(start_line, start_column, 'invalid JSON literal')
              end
            else
              text = scanner.scan(/[^\s|=]+/)
              fail_at(start_line, start_column, 'invalid token') unless text
              if text.match?(/\A\$[a-zA-Z_][\w]*(?:\.[\w-]+)*\z/)
                kind, value = :variable, text[1..]
              elsif text.start_with?('$') || text.match?(/[`;<>]/)
                fail_at(start_line, start_column, 'shell syntax is not supported; quote literal data')
              elsif text.match?(/\A(?:true|false|null|-?\d+(?:\.\d+)?)\z/)
                kind, value = :literal, JSON.parse(text)
              else
                value = text
              end
            end
            tokens << Token.new(kind: kind, value: value, line: start_line, column: start_column)
          end
          if text.include?("\n")
            line += text.count("\n")
            column = text.split("\n", -1).last.length + 1
          else
            column += text.length
          end
        end
        tokens
      end

      def json_token(scanner, line, column)
        text = +''
        stack = []
        quoted = false
        escaped = false
        loop do
          ch = scanner.getch
          fail_at(line, column, 'unterminated JSON literal') unless ch
          text << ch
          if quoted
            if escaped
              escaped = false
            elsif ch == '\\'
              escaped = true
            elsif ch == '"'
              quoted = false
              break if stack.empty?
            end
          elsif ch == '"'
            quoted = true
          elsif ['[', '{'].include?(ch)
            stack << ch
            fail_at(line, column, 'JSON nesting exceeds 64') if stack.size > 64
          elsif [']', '}'].include?(ch)
            expected = ch == ']' ? '[' : '{'
            fail_at(line, column, 'unbalanced JSON') unless stack.pop == expected
            break if stack.empty?
          end
        end
        text
      end

      def block(nested, depth)
        fail_at(1, 1, 'loop nesting exceeds 32') if depth > 32
        nodes = []
        while (token = peek)
          if token.kind == :newline
            take
            next
          end
          if token.kind == :word && token.value == 'end'
            fail_token(token, 'unexpected end') unless nested
            take
            line_end!
            return nodes
          end
          if token.kind == :word && token.value == 'for'
            take
            name = take
            fail_token(name || token, 'expected loop variable') unless name&.kind == :word && name.value.match?(/\A[a-zA-Z_]\w*\z/)
            keyword!('in')
            expression = []
            expression << take until peek.nil? || peek.kind == :newline
            last = expression.pop
            fail_token(last || token, 'expected do') unless last&.kind == :word && last.value == 'do'
            nodes << Node.new(kind: :for, name: name.value, pipeline: pipeline(expression), body: block(true, depth + 1), token: token)
          else
            expression = []
            expression << take until peek.nil? || peek.kind == :newline
            name = nil
            if expression[1]&.kind == :equals
              name = expression.shift.value
              expression.shift
              fail_token(token, 'invalid variable name') unless token.kind == :word && name.match?(/\A[a-zA-Z_]\w*\z/)
            end
            nodes << Node.new(kind: name ? :assign : :pipeline, name: name, pipeline: pipeline(expression), token: token)
          end
        end
        fail_at(1, 1, 'missing end') if nested
        nodes
      end

      def pipeline(tokens)
        fail_at(1, 1, 'empty pipeline') if tokens.empty?
        stages = [[]]
        tokens.each do |token|
          if token.kind == :pipe
            fail_token(token, 'empty pipeline stage') if stages.last.empty?
            stages << []
          else
            fail_token(token, 'unexpected assignment') if token.kind == :equals
            stages.last << token
          end
        end
        fail_token(tokens.last, 'empty pipeline stage') if stages.last.empty?
        stages.each { |stage| fail_token(stage.first, 'expected command name') unless stage.first.kind == :word }
        stages
      end

      def keyword!(word)
        token = take
        fail_token(token, "expected #{word}") unless token&.kind == :word && token.value == word
      end

      def line_end!
        fail_token(peek, 'expected end of line') if peek && peek.kind != :newline
      end

      def peek
        @tokens[@offset]
      end

      def take
        token = peek
        @offset += 1
        token
      end

      def fail_token(token, message)
        fail_at(token&.line || 1, token&.column || 1, message)
      end

      def fail_at(line, column, message)
        raise Error, "#{file}:#{line}:#{column}: #{message}"
      end
    end
  end
end
