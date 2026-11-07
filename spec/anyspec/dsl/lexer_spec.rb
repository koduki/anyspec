# frozen_string_literal: true

require 'spec_helper'
require 'anyspec/dsl/ast'
require 'anyspec/dsl/lexer'

RSpec.describe Anyspec::DSL::Lexer do
  def tokenize(source)
    lexer = described_class.new(source, file: '<test>')
    lexer.tokenize
  end

  def token_types(source)
    tokenize(source).map(&:type)
  end

  describe 'basic tokens' do
    it 'tokenizes identifiers' do
      expect(token_types('foo bar')).to eq([:IDENTIFIER, :IDENTIFIER, :EOF])
    end

    it 'tokenizes variables' do
      expect(token_types('$foo $bar')).to eq([:VARIABLE, :VARIABLE, :EOF])
    end

    it 'tokenizes numbers' do
      tokens = tokenize('42 -3.14')
      expect(tokens[0].value).to eq('42')
      expect(tokens[1].value).to eq('-3.14')
    end

    it 'tokenizes strings' do
      tokens = tokenize("'hello' \"world\"")
      expect(tokens[0].type).to eq(:SINGLE_STRING)
      expect(tokens[1].type).to eq(:DOUBLE_STRING)
    end

    it 'tokenizes flags' do
      expect(token_types('--compartment-id -a')).to eq([:FLAG, :SHORT_FLAG, :EOF])
    end

    it 'tokenizes operators' do
      expect(token_types('| = . [ ] { } ,')).to eq(
        [:PIPE, :ASSIGN, :DOT, :LBRACKET, :RBRACKET, :LBRACE, :RBRACE, :COMMA, :EOF]
      )
    end

    it 'tokenizes keywords' do
      expect(token_types('foreach in true false null')).to eq(
        [:FOREACH, :IN, :TRUE, :FALSE, :NULL, :EOF]
      )
    end
  end

  describe 'comments' do
    it 'tokenizes comments' do
      tokens = tokenize("# this is a comment\nfoo")
      expect(tokens[0].type).to eq(:COMMENT)
      expect(tokens[0].value).to eq('# this is a comment')
    end
  end

  describe 'OCIDs' do
    it 'tokenizes OCIDs' do
      tokens = tokenize('ocid1.tenancy.oc1..aaaaaaaaqkabcdefgh')
      expect(tokens[0].type).to eq(:OCID)
    end
  end

  describe 'location tracking' do
    it 'tracks line and column' do
      tokens = tokenize("foo\nbar baz")
      expect(tokens[0].location.line).to eq(1)
      expect(tokens[0].location.column).to eq(1)
      expect(tokens[2].location.line).to eq(2)
      expect(tokens[2].location.column).to eq(1)
      expect(tokens[3].location.line).to eq(2)
      expect(tokens[3].location.column).to eq(5)
    end
  end

  describe 'error handling' do
    it 'raises error on unexpected character' do
      expect { tokenize('foo @bar') }.to raise_error(
        Anyspec::DSL::LexerError, /Unexpected character/
      )
    end
  end
end
