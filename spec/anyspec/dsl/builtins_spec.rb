# frozen_string_literal: true

require 'spec_helper'
require 'anyspec/dsl/runner'

RSpec.describe Anyspec::DSL::Builtins do
  let(:config) { Anyspec::Config.new(oci_cli: FAKE_OCI_CLI) }
  let(:builtins) { described_class.new }
  let(:interpreter) { Anyspec::DSL::Interpreter.new(builtins: builtins) }

  def run(source)
    lexer = Anyspec::DSL::Lexer.new(source, file: '<test>')
    tokens = lexer.tokenize
    parser = Anyspec::DSL::Parser.new(tokens, file: '<test>')
    program = parser.parse
    interpreter.run(program)
  end

  describe 'path builtins' do
    describe 'get' do
      it 'gets a nested path' do
        result = run('$obj = { "a": { "b": 42 } }' + "\n" + 'get $obj "a.b"')
        expect(result).to eq(42)
      end

      it 'returns nil on missing path' do
        result = run('$obj = { "a": 1 }' + "\n" + 'get $obj "b"')
        expect(result).to be_nil
      end
    end

    describe 'get_opt' do
      it 'returns default on missing path' do
        result = run('$obj = { "a": 1 }' + "\n" + 'get_opt $obj "b" "default"')
        expect(result).to eq('default')
      end

      it 'returns value when present' do
        result = run('$obj = { "a": 1 }' + "\n" + 'get_opt $obj "a" "default"')
        expect(result).to eq(1)
      end
    end

    describe 'has' do
      it 'returns true for existing path' do
        result = run('$obj = { "a": 1 }' + "\n" + 'has $obj "a"')
        expect(result).to be true
      end

      it 'returns false for missing path' do
        result = run('$obj = { "a": 1 }' + "\n" + 'has $obj "b"')
        expect(result).to be false
      end
    end

    describe 'is_empty' do
      it 'returns true for empty array' do
        result = run('$arr = []' + "\n" + 'is_empty $arr')
        expect(result).to be true
      end

      it 'returns true for null' do
        result = run('$val = null' + "\n" + 'is_empty $val')
        expect(result).to be true
      end

      it 'returns false for non-empty array' do
        result = run('$arr = [1]' + "\n" + 'is_empty $arr')
        expect(result).to be false
      end
    end
  end

  describe 'array builtins' do
    describe 'filter' do
      it 'filters by field value' do
        result = run('$arr = [{ "a": 1 }, { "a": 2 }]' + "\n" + 'filter $arr "a" 1')
        expect(result).to eq([{ 'a' => 1 }])
      end
    end

    describe 'filter_not' do
      it 'excludes by field value' do
        result = run('$arr = [{ "a": 1 }, { "a": 2 }]' + "\n" + 'filter_not $arr "a" 1')
        expect(result).to eq([{ 'a' => 2 }])
      end
    end

    describe 'filter_in' do
      it 'filters by set membership' do
        result = run(<<~DSL)
          $arr = [{ "a": 1 }, { "a": 2 }, { "a": 3 }]
          $vals = [1, 3]
          filter_in $arr "a" $vals
        DSL
        expect(result).to eq([{ 'a' => 1 }, { 'a' => 3 }])
      end
    end

    describe 'map' do
      it 'extracts field from each element' do
        result = run('$arr = [{ "id": 1 }, { "id": 2 }]' + "\n" + 'map $arr "id"')
        expect(result).to eq([1, 2])
      end
    end

    describe 'flatten' do
      it 'flattens nested arrays' do
        result = run('$arr = [[1, 2], [3, 4]]' + "\n" + 'flatten $arr')
        expect(result).to eq([1, 2, 3, 4])
      end

      it 'respects depth parameter' do
        result = run('$arr = [[[1]], [[2]]]' + "\n" + 'flatten $arr 1')
        expect(result).to eq([[1], [2]])
      end
    end

    describe 'unique' do
      it 'removes duplicates' do
        result = run('$arr = [1, 2, 2, 3, 1]' + "\n" + 'unique $arr')
        expect(result).to eq([1, 2, 3])
      end
    end

    describe 'unique_by' do
      it 'removes duplicates by field' do
        result = run(<<~DSL)
          $arr = [{ "id": 1, "x": "a" }, { "id": 1, "x": "b" }]
          unique_by $arr "id"
        DSL
        expect(result.length).to eq(1)
      end
    end

    describe 'sort' do
      it 'sorts array' do
        result = run('$arr = [3, 1, 2]' + "\n" + 'sort $arr')
        expect(result).to eq([1, 2, 3])
      end
    end

    describe 'sort_by' do
      it 'sorts by field' do
        result = run('$arr = [{ "n": 3 }, { "n": 1 }]' + "\n" + 'sort_by $arr "n"')
        expect(result[0]['n']).to eq(1)
      end
    end

    describe 'first and last' do
      it 'returns first element' do
        result = run('$arr = [1, 2, 3]' + "\n" + 'first $arr')
        expect(result).to eq(1)
      end

      it 'returns last element' do
        result = run('$arr = [1, 2, 3]' + "\n" + 'last $arr')
        expect(result).to eq(3)
      end
    end

    describe 'count' do
      it 'returns array length' do
        result = run('$arr = [1, 2, 3]' + "\n" + 'count $arr')
        expect(result).to eq(3)
      end
    end

    describe 'concat' do
      it 'concatenates arrays' do
        result = run('$a = [1, 2]' + "\n" + '$b = [3, 4]' + "\n" + 'concat $a $b')
        expect(result).to eq([1, 2, 3, 4])
      end

      it 'concatenates variable with single-element array literal (space separated)' do
        result = run(<<~DSL)
          $arr = ["a", "b"]
          $item = "c"
          concat $arr [$item]
        DSL
        expect(result).to eq(['a', 'b', 'c'])
      end

      it 'handles empty array literal as second argument' do
        result = run(<<~DSL)
          $arr = [1, 2]
          concat $arr []
        DSL
        expect(result).to eq([1, 2])
      end

      it 'works with multiple single-element array concatenations' do
        result = run(<<~DSL)
          $base = []
          $x = "a"
          $y = "b"
          $step1 = concat $base [$x]
          concat $step1 [$y]
        DSL
        expect(result).to eq(['a', 'b'])
      end
    end

    describe 'compact' do
      it 'removes null values' do
        result = run('$arr = [1, null, 2, null]' + "\n" + 'compact $arr')
        expect(result).to eq([1, 2])
      end
    end
  end

  describe 'set builtins' do
    describe 'index_by' do
      it 'creates lookup table' do
        result = run(<<~DSL)
          $arr = [{ "id": "a", "v": 1 }, { "id": "b", "v": 2 }]
          index_by $arr "id"
        DSL
        expect(result['a']['v']).to eq(1)
        expect(result['b']['v']).to eq(2)
      end

      it 'raises on duplicate key' do
        expect do
          run('$arr = [{ "id": "a" }, { "id": "a" }]' + "\n" + 'index_by $arr "id"')
        end.to raise_error(Anyspec::DSL::BuiltinError, /duplicate key/)
      end
    end

    describe 'pairs_to_map' do
      it 'converts array of pairs to map' do
        result = run(<<~DSL)
          $pairs = [{ "id": "a", "data": 1 }, { "id": "b", "data": 2 }]
          pairs_to_map $pairs 'id' 'data'
        DSL
        expect(result['a']).to eq(1)
        expect(result['b']).to eq(2)
      end

      it 'handles keys with dots (like OCIDs)' do
        result = run(<<~DSL)
          $pairs = [{ "id": "ocid1.domain.oc1..xxx", "data": { "name": "test" } }]
          pairs_to_map $pairs 'id' 'data'
        DSL
        expect(result['ocid1.domain.oc1..xxx']).to eq({ 'name' => 'test' })
      end

      it 'overwrites duplicate keys (last wins)' do
        result = run(<<~DSL)
          $pairs = [{ "id": "a", "data": 1 }, { "id": "a", "data": 2 }]
          pairs_to_map $pairs 'id' 'data'
        DSL
        expect(result['a']).to eq(2)
      end
    end

    describe 'keys and values' do
      it 'returns object keys' do
        result = run('$obj = { "a": 1, "b": 2 }' + "\n" + 'keys $obj')
        expect(result.sort).to eq(%w[a b])
      end

      it 'returns object values' do
        result = run('$obj = { "a": 1, "b": 2 }' + "\n" + 'values $obj')
        expect(result.sort).to eq([1, 2])
      end
    end

    describe 'union' do
      it 'returns union of arrays' do
        result = run('$a = [1, 2]' + "\n" + '$b = [2, 3]' + "\n" + 'union $a $b')
        expect(result).to contain_exactly(1, 2, 3)
      end
    end

    describe 'difference' do
      it 'returns difference of arrays' do
        result = run('$a = [1, 2, 3]' + "\n" + '$b = [2]' + "\n" + 'difference $a $b')
        expect(result).to eq([1, 3])
      end
    end

    describe 'intersection' do
      it 'returns intersection of arrays' do
        result = run('$a = [1, 2, 3]' + "\n" + '$b = [2, 3, 4]' + "\n" + 'intersection $a $b')
        expect(result).to eq([2, 3])
      end
    end

    describe 'contains' do
      it 'checks array membership' do
        result1 = run('$arr = [1, 2, 3]' + "\n" + 'contains $arr 2')
        result2 = run('$arr = [1, 2, 3]' + "\n" + 'contains $arr 4')
        expect(result1).to be true
        expect(result2).to be false
      end
    end

    describe 'merge' do
      it 'merges two objects' do
        result = run('$a = { "a": 1 }' + "\n" + '$b = { "b": 2 }' + "\n" + 'merge $a $b')
        expect(result).to eq({ 'a' => 1, 'b' => 2 })
      end

      it 'raises on key conflict' do
        expect do
          run('$a = { "a": 1 }' + "\n" + '$b = { "a": 2 }' + "\n" + 'merge $a $b')
        end.to raise_error(Anyspec::DSL::BuiltinError, /key conflict/)
      end
    end
  end

  describe 'object builtins' do
    describe 'sort_keys' do
      it 'sorts object keys alphabetically' do
        result = run('$obj = { "b": 1, "a": 2 }' + "\n" + 'sort_keys $obj')
        expect(result.keys).to eq(%w[a b])
      end
    end

    describe 'omit' do
      it 'removes specified keys' do
        result = run('$obj = { "a": 1, "b": 2, "c": 3 }' + "\n" + 'omit $obj "b"')
        expect(result).to eq({ 'a' => 1, 'c' => 3 })
      end
    end

    describe 'pick' do
      it 'selects specified keys' do
        result = run('$obj = { "a": 1, "b": 2, "c": 3 }' + "\n" + 'pick $obj "a" "c"')
        expect(result).to eq({ 'a' => 1, 'c' => 3 })
      end
    end

    describe 'set_at' do
      it 'sets nested value' do
        result = run('$obj = { "a": {} }' + "\n" + 'set_at $obj "a.b" 42')
        expect(result['a']['b']).to eq(42)
      end
    end

    describe 'set_key' do
      it 'sets key without splitting dots' do
        result = run(<<~DSL)
          $obj = {}
          set_key $obj 'ocid1.domain.oc1..aaa' 'value'
        DSL
        expect(result['ocid1.domain.oc1..aaa']).to eq('value')
      end

      it 'preserves existing keys' do
        result = run(<<~DSL)
          $obj = { "existing": 1 }
          set_key $obj 'new.key' 2
        DSL
        expect(result['existing']).to eq(1)
        expect(result['new.key']).to eq(2)
      end

      it 'can set complex values' do
        result = run(<<~DSL)
          $obj = {}
          $nested = { "a": 1, "b": 2 }
          set_key $obj 'key.with.dots' $nested
        DSL
        expect(result['key.with.dots']).to eq({ 'a' => 1, 'b' => 2 })
      end
    end

    describe 'eq and not_eq' do
      it 'compares values' do
        expect(run('eq 1 1')).to be true
        expect(run('eq 1 2')).to be false
        expect(run('not_eq 1 2')).to be true
      end
    end
  end

  describe 'string builtins' do
    describe 'json_decode' do
      it 'parses JSON string' do
        result = run(%($str = '{"a": 1}'\njson_decode $str))
        expect(result).to eq({ 'a' => 1 })
      end

      it 'raises on invalid JSON' do
        expect { run(%($str = 'invalid'\njson_decode $str)) }
          .to raise_error(Anyspec::DSL::BuiltinError, /json_decode failed/)
      end
    end

    describe 'json_encode' do
      it 'converts to JSON string' do
        result = run('$obj = { "a": 1 }' + "\n" + 'json_encode $obj')
        expect(JSON.parse(result)).to eq({ 'a' => 1 })
      end
    end

    describe 'capture' do
      it 'captures regex groups' do
        result = run(%($str = 'hello-123'\ncapture $str '([a-z]+)-(\\\\d+)'))
        expect(result).to eq(%w[hello 123])
      end

      it 'returns named groups as hash' do
        result = run(%($str = 'hello-123'\ncapture $str '(?<word>[a-z]+)-(?<num>\\\\d+)'))
        expect(result).to eq({ 'word' => 'hello', 'num' => '123' })
      end
    end

    describe 'split and join' do
      it 'splits string' do
        result = run(%($str = 'a,b,c'\nsplit $str ','))
        expect(result).to eq(%w[a b c])
      end

      it 'joins array' do
        result = run('$arr = ["a", "b", "c"]' + "\n" + 'join $arr ","')
        expect(result).to eq('a,b,c')
      end
    end

    describe 'uri_encode' do
      it 'encodes URI components' do
        result = run(%($str = 'hello world'\nuri_encode $str))
        expect(result).to eq('hello+world')
      end
    end

    describe 'scim_escape' do
      it 'escapes SCIM filter values' do
        result = run(%($str = 'test"value'\nscim_escape $str))
        expect(result).to eq('test\\"value')
      end
    end
  end

  describe 'utility builtins' do
    describe 'warn' do
      it 'adds warning' do
        run('warn "test warning"')
        expect(interpreter.warnings).to include(hash_including(message: 'test warning'))
      end
    end

    describe 'assert' do
      it 'passes on true condition' do
        result = run('$cond = true' + "\n" + 'assert $cond "should not fail"')
        expect(result).to be true
      end

      it 'raises on false condition' do
        expect do
          run('$cond = false' + "\n" + 'assert $cond "expected failure"')
        end.to raise_error(Anyspec::DSL::BuiltinError, /Assertion failed: expected failure/)
      end
    end

    describe 'if_then' do
      it 'returns then value when condition is true' do
        result = run(<<~DSL)
          $cond = true
          $yes = "yes"
          $no = "no"
          if_then $cond $yes $no
        DSL
        expect(result).to eq('yes')
      end

      it 'returns else value when condition is false' do
        result = run(<<~DSL)
          $cond = false
          $yes = "yes"
          $no = "no"
          if_then $cond $yes $no
        DSL
        expect(result).to eq('no')
      end
    end

    describe 'default' do
      it 'returns value when not null' do
        result = run('$val = "value"' + "\n" + 'default $val "default"')
        expect(result).to eq('value')
      end

      it 'returns default when null' do
        result = run('$val = null' + "\n" + 'default $val "default"')
        expect(result).to eq('default')
      end
    end

    describe 'typeof' do
      it 'returns type names' do
        expect(run('$v = null' + "\n" + 'typeof $v')).to eq('null')
        expect(run('$v = true' + "\n" + 'typeof $v')).to eq('boolean')
        expect(run('$v = 42' + "\n" + 'typeof $v')).to eq('number')
        expect(run('$v = "str"' + "\n" + 'typeof $v')).to eq('string')
        expect(run('$v = []' + "\n" + 'typeof $v')).to eq('array')
        expect(run('$v = {}' + "\n" + 'typeof $v')).to eq('object')
      end
    end

    describe 'coalesce' do
      it 'returns first non-null value' do
        result = run(<<~DSL)
          $a = null
          $b = null
          $c = "found"
          $d = "other"
          coalesce $a $b $c $d
        DSL
        expect(result).to eq('found')
      end
    end
  end
end
