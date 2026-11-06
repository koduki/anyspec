# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Anyspec::AdapterRegistry do
  describe '.get' do
    it 'returns registered adapter' do
      adapter = described_class.get('cloud_guard_configuration')
      expect(adapter).to eq(Anyspec::Adapters::CloudGuardConfiguration)
    end

    it 'raises error for unknown type' do
      expect do
        described_class.get('nonexistent_type')
      end.to raise_error(Anyspec::UnknownAdapterError, /Unknown adapter type: 'nonexistent_type'/)
    end
  end

  describe '.available_types' do
    it 'lists all registered adapter types' do
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
      expect(described_class.registered?('cloud_guard_configuration')).to be true
    end

    it 'returns false for unregistered types' do
      expect(described_class.registered?('nonexistent')).to be false
    end
  end
end
