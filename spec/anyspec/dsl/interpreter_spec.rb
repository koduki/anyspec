# frozen_string_literal: true

require 'spec_helper'
require 'anyspec/dsl/runner'

RSpec.describe Anyspec::DSL::Interpreter do
  let(:config) { Anyspec::Config.new(oci_cli: FAKE_OCI_CLI) }
  let(:builtins) { Anyspec::DSL::Builtins.new }
  let(:interpreter) { described_class.new(builtins: builtins) }

  def run(source)
    lexer = Anyspec::DSL::Lexer.new(source, file: '<test>')
    tokens = lexer.tokenize
    parser = Anyspec::DSL::Parser.new(tokens, file: '<test>')
    program = parser.parse
    interpreter.run(program)
  end

  describe 'basic evaluation' do
    it 'evaluates number literals' do
      expect(run('42')).to eq(42)
    end

    it 'evaluates string literals' do
      expect(run("'hello'")).to eq('hello')
    end

    it 'evaluates boolean literals' do
      expect(run('true')).to be true
      expect(run('false')).to be false
    end

    it 'evaluates null' do
      expect(run('null')).to be_nil
    end

    it 'evaluates array literals' do
      expect(run('[1, 2, 3]')).to eq([1, 2, 3])
    end

    it 'evaluates hash literals' do
      result = run('{ "a": 1, "b": 2 }')
      expect(result).to eq({ 'a' => 1, 'b' => 2 })
    end
  end

  describe 'variable assignment' do
    it 'assigns and retrieves variables' do
      expect(run("$x = 42\n$x")).to eq(42)
    end

    it 'assigns complex values' do
      expect(run("$arr = [1, 2, 3]\n$arr")).to eq([1, 2, 3])
    end
  end

  describe 'field access' do
    it 'accesses hash fields with dot notation' do
      expect(run('$obj = { "name": "test" }' + "\n" + '$obj.name')).to eq('test')
    end

    it 'accesses nested fields' do
      expect(run('$obj = { "a": { "b": 42 } }' + "\n" + '$obj.a.b')).to eq(42)
    end

    it 'accesses fields with bracket notation' do
      expect(run('$obj = { "key": "value" }' + "\n" + '$obj["key"]')).to eq('value')
    end

    it 'handles kebab-case to underscore conversion' do
      expect(run('$obj = { "foo-bar": 42 }' + "\n" + '$obj.foo_bar')).to eq(42)
    end
  end

  describe 'string interpolation' do
    it 'interpolates variables' do
      expect(run('$name = "world"' + "\n" + '"hello $name"')).to eq('hello world')
    end

    it 'interpolates complex expressions' do
      expect(run('$x = 42' + "\n" + '"value: ${x}"')).to eq('value: 42')
    end

    it 'interpolates object fields without executing arbitrary expressions' do
      expect(run('$x = {"nested": {"name": "policy"}}' + "\n" + '"${x.nested.name}"')).to eq('policy')
      expect { run('"${system(id)}"') }.to raise_error(Anyspec::DSL::RuntimeError, /Invalid interpolation/)
    end
  end

  describe 'foreach' do
    it 'iterates over arrays' do
      result = run(<<~DSL)
        $items = [1, 2, 3]
        foreach x in $items {
          $x
        }
      DSL
      expect(result).to eq([1, 2, 3])
    end

    it 'collects results from body' do
      result = run(<<~DSL)
        $items = [{ "n": 1 }, { "n": 2 }]
        foreach item in $items {
          $item.n
        }
      DSL
      expect(result).to eq([1, 2])
    end
  end

  describe 'pipeline' do
    it 'chains builtins with pipeline' do
      result = run(<<~DSL)
        $arr = [3, 1, 2]
        $arr | sort $_
      DSL
      expect(result).to eq([1, 2, 3])
    end
  end

  describe 'parenthesized expressions' do
    it 'evaluates parenthesized command as argument' do
      result = run(<<~DSL)
        $x = [1, 2, 3]
        if_then (is_array $x) "yes" "no"
      DSL
      expect(result).to eq('yes')
    end

    it 'evaluates nested parenthesized expressions' do
      result = run(<<~DSL)
        $a = "test"
        $b = [1, 2]
        $c = [3, 4]
        if_then (not_eq $a null) (concat $b $c) []
      DSL
      expect(result).to eq([1, 2, 3, 4])
    end
  end

  describe 'foreach as assignment' do
    it 'assigns foreach result to variable' do
      result = run(<<~DSL)
        $items = [1, 2, 3]
        $doubled = foreach x in $items {
          $x
        }
        $doubled
      DSL
      expect(result).to eq([1, 2, 3])
    end

    it 'collects nested results' do
      result = run(<<~DSL)
        $items = [[1, 2], [3, 4]]
        $flat = foreach arr in $items {
          first $arr
        }
        $flat
      DSL
      expect(result).to eq([1, 3])
    end
  end

  describe 'comment handling' do
    it 'handles scripts starting with comments' do
      result = run(<<~DSL)
        # This is a comment
        # Another comment
        $x = 42
        $x
      DSL
      expect(result).to eq(42)
    end
  end

  describe 'error handling' do
    it 'includes location in undefined variable error' do
      expect { run('$undefined') }.to raise_error(
        Anyspec::DSL::RuntimeError, /Undefined variable: \$undefined/
      )
    end

    it 'includes location in type error' do
      expect { run('foreach x in 42 { $x }') }.to raise_error(
        Anyspec::DSL::RuntimeError, /foreach requires an array/
      )
    end
  end
end
