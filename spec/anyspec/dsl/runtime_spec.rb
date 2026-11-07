# frozen_string_literal: true
require 'spec_helper'

RSpec.describe Anyspec::DSL::Runtime do
  def run(source, **options)
    described_class.new.run(source, **options)
  end

  it 'evaluates typed data, pipelines and nested bounded loops without string expansion' do
    result = run(<<~'DSL')
      items = value [{"id":"a","v":false},{"id":"b","v":0}]
      for item in value $items do
        value $item.v | emit rows $item.id
      end
      value '$(touch /tmp/nope) | `id`' | emit literal
    DSL
    expect(result['rows']).to eq('a' => false, 'b' => 0)
    expect(result['literal']).to eq('$(touch /tmp/nope) | `id`')
  end

  it 'validates all commands before executing any effects' do
    transport = double('transport')
    expect(transport).not_to receive(:call)
    expect { described_class.new(transport: transport).run("oci []\nfor x in value [] do\n  exec bad\nend", file: 'test.dsl') }
      .to raise_error(Anyspec::DSL::Error, /test.dsl:3:3: unknown command/)
  end

  it 'reports missing variables and paths with source locations' do
    expect { run('value $absent', file: 'a.dsl') }.to raise_error(/a.dsl:1:7: undefined variable/)
    expect { run('value {} | get required', file: 'a.dsl') }.to raise_error(/a.dsl:1:12: missing path/)
    expect(run('value {} | get? missing | emit result')['result']).to be_nil
  end

  it 'rejects unsupported syntax, unterminated blocks and bad arity' do
    ['x = value $(id)', 'value `id`', 'value x > file', 'for x in value [] do', 'value 1 |', 'end', 'get'].each do |source|
      expect { run(source) }.to raise_error(Anyspec::DSL::Error)
    end
  end

  it 'enforces execution and source limits' do
    expect { described_class.new(max_steps: 2).run("for n in value [1,2,3] do\nvalue $n\nend") }.to raise_error(/step limit/)
    expect { run(' ' * 1_048_577) }.to raise_error(/source exceeds/)
  end

  it 'supports map collisions, typed set operations and partial array matching' do
    expect { run('value [{"id":"a"},{"id":"a"}] | index id') }.to raise_error(/duplicate index/)
    expect { run('value {"a":1} | merge {"a":2}') }.to raise_error(/collision/)
    expect(run('value [1,2] | union [2,3] | difference [1] | intersection [3] | emit x')['x']).to eq([3])
    expect(run('value [{"members":[{"id":"a","extra":1}]},{"members":[]}] | where-contains members {"id":"a"} | emit x')['x'].size).to eq(1)
  end

  it 'decodes embedded JSON without treating expressions as executable' do
    result = run(<<~'DSL')
      value [{"attributeValue":"[\"g1\"]"},{"attributeValue":"#inIPRange(\"np1\")"}] | decode-field attributeValue | emit data
      value '#inIPRange("np1")' | scan '#inIPRange\("([^"]+)"\)' | emit ids
    DSL
    expect(result['data'].first['attributeValue']).to eq(['g1'])
    expect(result['ids']).to eq(['np1'])
    expect { run('value "[broken" | decode-json') }.to raise_error(Anyspec::DSL::Error)
  end

  it 'preserves semantic arrays and normalizes only declared unordered/evaluation paths' do
    result = run(<<~'DSL')
      value {"meta":{},"rules":[{"value":"a","sequence":10},{"value":"z","sequence":2}],"steps":["b","a"],"members":[{"value":"z"},{"value":"a"}]} | normalize {"drop":["meta"],"arrays":{"**.rules":"sequence","**.members":"value"}} | emit x
    DSL
    expect(result['x']['rules'].map { |r| r['sequence'] }).to eq([2,10])
    expect(result['x']['steps']).to eq(%w[b a])
    expect(result['x']['members'].map { |r| r['value'] }).to eq(%w[a z])
    expect(result['x']).not_to have_key('meta')
  end

  it 'keeps warnings separate and includes domain context' do
    result = run(<<~DSL)
      context domain1
      value ["missing"] | warn-missing {} Groups
      value [{"sequence":1},{"sequence":1}] | warn-duplicates sequence policy1
    DSL
    expect(result['warnings'].map { |w| w['code'] }).to eq(%w[DUPLICATE_PRIORITY MISSING_REFERENCE])
    expect(result['warnings'].first['context']).to eq('domain1')
  end
end
