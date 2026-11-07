# frozen_string_literal: true

require 'spec_helper'
require 'anyspec/dsl/ast'
require 'anyspec/dsl/lexer'
require 'anyspec/dsl/parser'

RSpec.describe Anyspec::DSL::Parser do
  def parse(source)
    lexer = Anyspec::DSL::Lexer.new(source, file: '<test>')
    tokens = lexer.tokenize
    parser = described_class.new(tokens, file: '<test>')
    parser.parse
  end

  describe 'assignments' do
    it 'parses variable assignment with literal' do
      program = parse('$foo = 42')
      expect(program.statements.length).to eq(1)
      stmt = program.statements.first
      expect(stmt).to be_a(Anyspec::DSL::AST::Assignment)
      expect(stmt.name).to eq('foo')
      expect(stmt.value).to be_a(Anyspec::DSL::AST::NumberLiteral)
      expect(stmt.value.value).to eq(42)
    end

    it 'parses variable assignment with string' do
      program = parse("$name = 'hello'")
      stmt = program.statements.first
      expect(stmt.value).to be_a(Anyspec::DSL::AST::StringLiteral)
      expect(stmt.value.value).to eq('hello')
    end

    it 'parses variable assignment with array' do
      program = parse('$arr = [1, 2, 3]')
      stmt = program.statements.first
      expect(stmt.value).to be_a(Anyspec::DSL::AST::ArrayLiteral)
      expect(stmt.value.elements.length).to eq(3)
    end
  end

  describe 'commands' do
    it 'parses simple command' do
      program = parse('oci iam domain list')
      stmt = program.statements.first
      expect(stmt).to be_a(Anyspec::DSL::AST::Command)
      expect(stmt.name).to eq('oci')
      expect(stmt.arguments.length).to eq(3)
    end

    it 'parses command with flags' do
      program = parse('oci iam domain list --compartment-id $cid --all')
      stmt = program.statements.first
      expect(stmt.arguments.length).to eq(6)
    end

    it 'parses command with string arguments' do
      program = parse("filter_by 'status' 'active'")
      stmt = program.statements.first
      expect(stmt.name).to eq('filter_by')
      expect(stmt.arguments.length).to eq(2)
    end
  end

  describe 'pipelines' do
    it 'parses single pipe' do
      program = parse('foo | bar')
      stmt = program.statements.first
      expect(stmt).to be_a(Anyspec::DSL::AST::Pipeline)
      expect(stmt.commands.length).to eq(2)
    end

    it 'parses multiple pipes' do
      program = parse('foo | bar | baz')
      stmt = program.statements.first
      expect(stmt.commands.length).to eq(3)
    end
  end

  describe 'foreach' do
    it 'parses foreach loop' do
      program = parse("foreach item in $items {\n  $x = $item.id\n}")
      stmt = program.statements.first
      expect(stmt).to be_a(Anyspec::DSL::AST::Foreach)
      expect(stmt.variable).to eq('item')
      expect(stmt.body.length).to eq(1)
    end
  end

  describe 'field access' do
    it 'parses dot notation' do
      program = parse('$obj.field')
      stmt = program.statements.first
      expect(stmt).to be_a(Anyspec::DSL::AST::FieldAccess)
      expect(stmt.field).to eq('field')
    end

    it 'parses chained dot notation' do
      program = parse('$obj.a.b.c')
      stmt = program.statements.first
      expect(stmt).to be_a(Anyspec::DSL::AST::FieldAccess)
      expect(stmt.field).to eq('c')
    end

    it 'parses bracket notation' do
      program = parse('$obj["key"]')
      stmt = program.statements.first
      expect(stmt).to be_a(Anyspec::DSL::AST::IndexAccess)
    end
  end

  describe 'string interpolation' do
    it 'parses interpolated strings' do
      program = parse('"hello $name"')
      stmt = program.statements.first
      expect(stmt).to be_a(Anyspec::DSL::AST::StringLiteral)
      expect(stmt.interpolated?).to be true
      expect(stmt.interpolations).to eq(['name'])
    end

    it 'parses complex interpolation' do
      program = parse('"Value: ${foo}"')
      stmt = program.statements.first
      expect(stmt.interpolations).to eq(['foo'])
    end
  end

  describe 'literals' do
    it 'parses booleans' do
      program = parse('true')
      expect(program.statements.first).to be_a(Anyspec::DSL::AST::BooleanLiteral)
      expect(program.statements.first.value).to be true
    end

    it 'parses null' do
      program = parse('null')
      expect(program.statements.first).to be_a(Anyspec::DSL::AST::NullLiteral)
    end

    it 'parses hash literals' do
      program = parse('{ "key": "value" }')
      stmt = program.statements.first
      expect(stmt).to be_a(Anyspec::DSL::AST::HashLiteral)
      expect(stmt.pairs.length).to eq(1)
    end
  end

  describe 'comment-only lines' do
    it 'parses scripts starting with comment-only lines' do
      program = parse("# This is a comment\n$x = 42")
      assignments = program.statements.reject { |s| s.is_a?(Anyspec::DSL::AST::Comment) }
      expect(assignments.length).to eq(1)
      expect(assignments.first).to be_a(Anyspec::DSL::AST::Assignment)
    end

    it 'parses multiple comment-only lines' do
      program = parse("# Comment 1\n# Comment 2\n# Comment 3\n$x = 42")
      assignments = program.statements.reject { |s| s.is_a?(Anyspec::DSL::AST::Comment) }
      expect(assignments.length).to eq(1)
    end

    it 'handles empty lines after comments' do
      program = parse("# Comment\n\n$x = 42")
      assignments = program.statements.reject { |s| s.is_a?(Anyspec::DSL::AST::Comment) }
      expect(assignments.length).to eq(1)
    end
  end

  describe 'parenthesized expressions' do
    it 'parses parenthesized command as argument' do
      program = parse('if_then (is_array $x) "yes" "no"')
      stmt = program.statements.first
      expect(stmt).to be_a(Anyspec::DSL::AST::Command)
      expect(stmt.arguments.length).to eq(3)
    end

    it 'parses nested parenthesized expressions' do
      program = parse('if_then (not_eq $a null) (concat $b $c) []')
      stmt = program.statements.first
      expect(stmt).to be_a(Anyspec::DSL::AST::Command)
      expect(stmt.arguments.length).to eq(3)
    end

    it 'parses parentheses with array argument' do
      program = parse('if_then $cond (check_ref [$id] $lookup "Type") []')
      stmt = program.statements.first
      expect(stmt.arguments.length).to eq(3)
    end
  end

  describe 'arrays as command arguments' do
    it 'parses array literal as command argument' do
      program = parse('concat [1, 2] [3, 4]')
      stmt = program.statements.first
      expect(stmt.arguments.length).to eq(2)
      expect(stmt.arguments[0]).to be_a(Anyspec::DSL::AST::ArrayLiteral)
    end

    it 'parses empty array as command argument' do
      program = parse('default $x []')
      stmt = program.statements.first
      expect(stmt.arguments.length).to eq(2)
      expect(stmt.arguments[1]).to be_a(Anyspec::DSL::AST::ArrayLiteral)
    end
  end

  describe 'array literal vs index access distinction' do
    it 'parses $arr [$item] (with space) as two arguments' do
      program = parse('concat $arr [$item]')
      stmt = program.statements.first
      expect(stmt).to be_a(Anyspec::DSL::AST::Command)
      expect(stmt.name).to eq('concat')
      expect(stmt.arguments.length).to eq(2)
      expect(stmt.arguments[0]).to be_a(Anyspec::DSL::AST::VariableRef)
      expect(stmt.arguments[0].name).to eq('arr')
      expect(stmt.arguments[1]).to be_a(Anyspec::DSL::AST::ArrayLiteral)
      expect(stmt.arguments[1].elements.length).to eq(1)
    end

    it 'parses $arr[$item] (no space) as index access' do
      program = parse('echo $arr[$item]')
      stmt = program.statements.first
      expect(stmt).to be_a(Anyspec::DSL::AST::Command)
      expect(stmt.arguments.length).to eq(1)
      expect(stmt.arguments[0]).to be_a(Anyspec::DSL::AST::IndexAccess)
      expect(stmt.arguments[0].object).to be_a(Anyspec::DSL::AST::VariableRef)
      expect(stmt.arguments[0].object.name).to eq('arr')
      expect(stmt.arguments[0].index).to be_a(Anyspec::DSL::AST::VariableRef)
      expect(stmt.arguments[0].index.name).to eq('item')
    end

    it 'parses $arr["key"] (no space) as index access with string key' do
      program = parse('echo $domain["display-name"]')
      stmt = program.statements.first
      expect(stmt.arguments.length).to eq(1)
      expect(stmt.arguments[0]).to be_a(Anyspec::DSL::AST::IndexAccess)
      expect(stmt.arguments[0].index).to be_a(Anyspec::DSL::AST::StringLiteral)
      expect(stmt.arguments[0].index.value).to eq('display-name')
    end

    it 'parses $arr [] (with space) as two arguments (empty array)' do
      program = parse('default $arr []')
      stmt = program.statements.first
      expect(stmt.arguments.length).to eq(2)
      expect(stmt.arguments[0]).to be_a(Anyspec::DSL::AST::VariableRef)
      expect(stmt.arguments[1]).to be_a(Anyspec::DSL::AST::ArrayLiteral)
      expect(stmt.arguments[1].elements).to be_empty
    end

    it 'parses multiple $arr [$x] patterns in one command' do
      program = parse('merge $a [$x] $b [$y]')
      stmt = program.statements.first
      expect(stmt.arguments.length).to eq(4)
      expect(stmt.arguments[0]).to be_a(Anyspec::DSL::AST::VariableRef)
      expect(stmt.arguments[1]).to be_a(Anyspec::DSL::AST::ArrayLiteral)
      expect(stmt.arguments[2]).to be_a(Anyspec::DSL::AST::VariableRef)
      expect(stmt.arguments[3]).to be_a(Anyspec::DSL::AST::ArrayLiteral)
    end

    it 'parses chained index access without space' do
      program = parse('echo $data[0]["name"]')
      stmt = program.statements.first
      expect(stmt.arguments.length).to eq(1)
      access = stmt.arguments[0]
      expect(access).to be_a(Anyspec::DSL::AST::IndexAccess)
      expect(access.index).to be_a(Anyspec::DSL::AST::StringLiteral)
      expect(access.object).to be_a(Anyspec::DSL::AST::IndexAccess)
      expect(access.object.index).to be_a(Anyspec::DSL::AST::NumberLiteral)
    end
  end

  describe 'booleans and null as command arguments' do
    it 'parses true as command argument' do
      program = parse('assert true "message"')
      stmt = program.statements.first
      expect(stmt.arguments[0]).to be_a(Anyspec::DSL::AST::BooleanLiteral)
      expect(stmt.arguments[0].value).to be true
    end

    it 'parses false as command argument' do
      program = parse('if_then false "no" "yes"')
      stmt = program.statements.first
      expect(stmt.arguments[0]).to be_a(Anyspec::DSL::AST::BooleanLiteral)
      expect(stmt.arguments[0].value).to be false
    end

    it 'parses null as command argument' do
      program = parse('eq $x null')
      stmt = program.statements.first
      expect(stmt.arguments[1]).to be_a(Anyspec::DSL::AST::NullLiteral)
    end
  end

  describe 'foreach as assignment value' do
    it 'parses foreach assigned to variable' do
      program = parse(<<~DSL)
        $results = foreach x in $items {
          $x
        }
      DSL
      stmt = program.statements.first
      expect(stmt).to be_a(Anyspec::DSL::AST::Assignment)
      expect(stmt.value).to be_a(Anyspec::DSL::AST::Foreach)
    end
  end

  describe 'error handling' do
    it 'includes location in error' do
      expect { parse('$x =') }.to raise_error(Anyspec::DSL::ParseError, /<test>:1:\d+/)
    end
  end
end
