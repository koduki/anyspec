# frozen_string_literal: true
require 'spec_helper'
require 'tmpdir'

RSpec.describe 'DSL loading and CLI' do
  around do |example|
    registry = Anyspec::AdapterRegistry
    saved = %i[registry external_definitions loaded_definition_files overridden_builtins].to_h { |key| [key, registry.public_send(key).dup] }
    example.run
  ensure
    saved.each { |key, value| registry.instance_variable_set("@#{key}", value) }
  end

  it 'registers a DSL adapter and consumes declared spec inputs' do
    Dir.mktmpdir do |dir|
      File.write("#{dir}/adapter.yml", "type: dsl_test\ndsl: script.anyspec\ninputs: [tenant]\n")
      File.write("#{dir}/script.anyspec", 'value $input.tenant | emit tenant')
      Anyspec::ExternalAdapterLoader.new(adapters_dir: dir).load_all
      adapter = Anyspec::AdapterRegistry.get('dsl_test').new(Anyspec::Config.new)
      expect(adapter.fetch('type' => 'dsl_test', 'tenant' => 'a')['tenant']).to eq('a')
      expect(adapter.fetch('type' => 'dsl_test', 'tenant' => 'b')['tenant']).to eq('b')
      first = adapter.fetch('type' => 'dsl_test', 'tenant' => 'a')
      first['tenant'] = 'poison'
      expect(adapter.fetch('type' => 'dsl_test', 'tenant' => 'a')['tenant']).to eq('a')
      expect { adapter.fetch('type' => 'dsl_test') }.to raise_error(/missing DSL input/)
    end
  end

  it 'rejects scripts outside the definition directory and reports invalid syntax before registration' do
    Dir.mktmpdir do |dir|
      Dir.mkdir("#{dir}/definitions")
      File.write("#{dir}/outside.anyspec", 'value true | emit ok')
      File.write("#{dir}/definitions/adapter.yml", "type: escape_dsl\ndsl: ../outside.anyspec\ninputs: []\n")
      expect { Anyspec::ExternalAdapterLoader.new(adapters_dir: "#{dir}/definitions").load_all }.to output(/must reside/).to_stderr
      expect(Anyspec::AdapterRegistry.registered?('escape_dsl')).to be(false)
      File.write("#{dir}/definitions/adapter.yml", "type: broken_dsl\ndsl: bad.anyspec\ninputs: []\n")
      File.write("#{dir}/definitions/bad.anyspec", 'exec command')
      expect { Anyspec::ExternalAdapterLoader.new(adapters_dir: "#{dir}/definitions").load_all }.to output(/bad.anyspec:1:1: unknown command/).to_stderr
      expect(Anyspec::AdapterRegistry.registered?('broken_dsl')).to be(false)
    end
  end

  it 'validates and collects through the real CLI without invoking OCI for pure scripts' do
    Dir.mktmpdir do |dir|
      script, inputs = "#{dir}/script.anyspec", "#{dir}/inputs.json"
      File.write(script, 'value $input.name | emit name')
      File.write(inputs, '{"name":"example"}')
      expect { expect(Anyspec::CLI.new(['validate-dsl', script]).run).to eq(0) }.to output(/DSL valid/).to_stdout
      expect { expect(Anyspec::CLI.new(['collect', script, inputs]).run).to eq(0) }.to output(/"name": "example"/).to_stdout
      File.write(script, "value 1 | emit temporary\nget missing")
      expect do
        expect { expect(Anyspec::CLI.new(['collect', script, inputs]).run).to eq(2) }.to output('').to_stdout
      end.to output(/missing path/).to_stderr
    end
  end
end
