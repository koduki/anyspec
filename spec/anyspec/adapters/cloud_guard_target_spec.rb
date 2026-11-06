# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Anyspec::Adapters::CloudGuardTarget do
  let(:config) { Anyspec::Config.new(oci_cli: FAKE_OCI_CLI) }
  let(:adapter) { described_class.new(config) }

  describe '#fetch' do
    context 'with target_id' do
      let(:spec) do
        {
          'compartment_id' => 'ocid1.tenancy.oc1..test',
          'target_id' => 'ocid1.cloudguardtarget.oc1..test'
        }
      end

      it 'fetches target by ID' do
        result = adapter.fetch(spec)

        expect(result['id']).to eq('ocid1.cloudguardtarget.oc1..test')
        expect(result['display_name']).to eq('root-target')
        expect(result['lifecycle_state']).to eq('ACTIVE')
      end
    end

    context 'with name' do
      let(:spec) do
        {
          'compartment_id' => 'ocid1.tenancy.oc1..test',
          'name' => 'root-target'
        }
      end

      it 'fetches target by name' do
        result = adapter.fetch(spec)

        expect(result['display_name']).to eq('root-target')
        expect(result['lifecycle_state']).to eq('ACTIVE')
      end
    end

    context 'without compartment_id' do
      let(:spec) { { 'name' => 'test' } }

      it 'raises error' do
        expect { adapter.fetch(spec) }.to raise_error(Anyspec::Error, /compartment_id is required/)
      end
    end

    context 'without target_id or name' do
      let(:spec) { { 'compartment_id' => 'ocid1.test' } }

      it 'raises error' do
        expect { adapter.fetch(spec) }.to raise_error(Anyspec::Error, /Either target_id or name is required/)
      end
    end
  end

  describe 'real OCI CLI JSON format' do
    it 'handles kebab-case keys from list response' do
      config = Anyspec::Config.new(oci_cli: FAKE_OCI_CLI)
      adapter = described_class.new(config)
      spec = {
        'compartment_id' => 'ocid1.tenancy.oc1..test',
        'name' => 'root-target'
      }

      result = adapter.fetch(spec)

      expect(result['display_name']).to eq('root-target')
      expect(result['lifecycle_state']).to eq('ACTIVE')
      expect(result['target_resource_type']).to eq('COMPARTMENT')
    end
  end
end
