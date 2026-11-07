# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Anyspec::AdapterRegistry do
  describe '.get (builtin adapters)' do
    it 'returns registered adapter for builtin types' do
      Anyspec::AdapterRegistry.register('cloud_guard_configuration', Anyspec::Adapters::CloudGuardConfiguration, priority: :builtin) unless Anyspec::AdapterRegistry.registered?('cloud_guard_configuration')
      
      adapter = described_class.get('cloud_guard_configuration')
      expect(adapter).to eq(Anyspec::Adapters::CloudGuardConfiguration)
    end

    it 'raises error for unknown type' do
      expect do
        described_class.get('nonexistent_type_xyz_12345')
      end.to raise_error(Anyspec::UnknownAdapterError, /Unknown adapter type/)
    end
  end

  describe '.available_types' do
    it 'includes builtin adapter types when registered' do
      %w[cloud_guard_configuration cloud_guard_target identity_authentication_policy audit_configuration object_storage_bucket].each do |type|
        next if Anyspec::AdapterRegistry.registered?(type)
        
        adapter_class = case type
                        when 'cloud_guard_configuration' then Anyspec::Adapters::CloudGuardConfiguration
                        when 'cloud_guard_target' then Anyspec::Adapters::CloudGuardTarget
                        when 'identity_authentication_policy' then Anyspec::Adapters::IdentityAuthenticationPolicy
                        when 'audit_configuration' then Anyspec::Adapters::AuditConfiguration
                        when 'object_storage_bucket' then Anyspec::Adapters::ObjectStorageBucket
                        end
        Anyspec::AdapterRegistry.register(type, adapter_class, priority: :builtin)
      end

      types = described_class.available_types

      expect(types).to include('cloud_guard_configuration')
      expect(types).to include('cloud_guard_target')
      expect(types).to include('identity_authentication_policy')
      expect(types).to include('audit_configuration')
      expect(types).to include('object_storage_bucket')
    end
  end

  describe '.registered?' do
    it 'returns true for registered types' do
      Anyspec::AdapterRegistry.register('cloud_guard_configuration', Anyspec::Adapters::CloudGuardConfiguration, priority: :builtin) unless Anyspec::AdapterRegistry.registered?('cloud_guard_configuration')
      expect(described_class.registered?('cloud_guard_configuration')).to be true
    end

    it 'returns false for unregistered types' do
      expect(described_class.registered?('nonexistent_xyz_12345')).to be false
    end
  end

  describe 'priority-based registration' do
    around do |example|
      saved_registry = described_class.registry.dup
      saved_external = described_class.external_definitions.dup
      saved_files = described_class.loaded_definition_files.dup
      saved_overrides = described_class.overridden_builtins.dup
      described_class.reset!
      example.run
    ensure
      described_class.instance_variable_set(:@registry, saved_registry)
      described_class.instance_variable_set(:@external_definitions, saved_external)
      described_class.instance_variable_set(:@loaded_definition_files, saved_files)
      described_class.instance_variable_set(:@overridden_builtins, saved_overrides)
    end

    it 'registers builtin adapters with builtin priority' do
      mock_adapter = Class.new
      described_class.register('test_builtin', mock_adapter, priority: :builtin)

      expect(described_class.builtin?('test_builtin')).to be true
      expect(described_class.external?('test_builtin')).to be false
    end

    it 'registers external adapters with external priority' do
      definition = { 'type' => 'test_external', 'locators' => [] }
      described_class.register_external_definition('test_external', definition, source_file: '/test.yml')

      expect(described_class.external?('test_external')).to be true
      expect(described_class.builtin?('test_external')).to be false
    end

    it 'allows external adapters to override builtin adapters' do
      builtin_adapter = Class.new
      described_class.register('override_test', builtin_adapter, priority: :builtin)

      definition = { 'type' => 'override_test', 'locators' => [] }
      described_class.register_external_definition('override_test', definition, source_file: '/override.yml')

      expect(described_class.external?('override_test')).to be true
      expect(described_class.get('override_test')).to eq(Anyspec::Adapters::GenericCli)
    end

    it 'does not allow builtin to override external' do
      definition = { 'type' => 'priority_test', 'locators' => [] }
      described_class.register_external_definition('priority_test', definition, source_file: '/test.yml')

      builtin_adapter = Class.new
      described_class.register('priority_test', builtin_adapter, priority: :builtin)

      expect(described_class.get('priority_test')).to eq(Anyspec::Adapters::GenericCli)
    end

    it 'records overridden builtins' do
      builtin_adapter = Class.new
      described_class.register('tracked_builtin', builtin_adapter, priority: :builtin)

      definition = { 'type' => 'tracked_builtin', 'locators' => [] }
      described_class.register_external_definition('tracked_builtin', definition, source_file: '/override.yml')

      info = described_class.external_adapter_info
      expect(info[:overridden_builtins].any? { |o| o[:type] == 'tracked_builtin' }).to be true
    end
  end

  describe '.external_adapter_info' do
    around do |example|
      saved_registry = described_class.registry.dup
      saved_external = described_class.external_definitions.dup
      saved_files = described_class.loaded_definition_files.dup
      saved_overrides = described_class.overridden_builtins.dup
      described_class.reset!
      example.run
    ensure
      described_class.instance_variable_set(:@registry, saved_registry)
      described_class.instance_variable_set(:@external_definitions, saved_external)
      described_class.instance_variable_set(:@loaded_definition_files, saved_files)
      described_class.instance_variable_set(:@overridden_builtins, saved_overrides)
    end

    it 'returns loaded files, external types, and overridden builtins' do
      described_class.loaded_definition_files << '/test/adapters.yml'

      definition = { 'type' => 'info_test', 'locators' => [] }
      described_class.register_external_definition('info_test', definition, source_file: '/test/adapters.yml')

      info = described_class.external_adapter_info

      expect(info[:loaded_files]).to include('/test/adapters.yml')
      expect(info[:external_types]).to include('info_test')
      expect(info[:overridden_builtins]).to be_an(Array)
    end
  end

  describe '.get_definition' do
    around do |example|
      saved_external = described_class.external_definitions.dup
      example.run
    ensure
      described_class.instance_variable_set(:@external_definitions, saved_external)
    end

    it 'returns definition for external types' do
      definition = { 'type' => 'def_test', 'locators' => [{ 'subcommand' => 'test' }] }
      described_class.external_definitions['def_test'] = definition

      result = described_class.get_definition('def_test')

      expect(result).to eq(definition)
    end

    it 'returns nil for unknown types' do
      result = described_class.get_definition('nonexistent')

      expect(result).to be_nil
    end
  end
end
