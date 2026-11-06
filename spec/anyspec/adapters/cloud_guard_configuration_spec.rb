# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Anyspec::Adapters::CloudGuardConfiguration do
  let(:config) { Anyspec::Config.new(oci_cli: FAKE_OCI_CLI) }
  let(:adapter) { described_class.new(config) }

  describe '#fetch' do
    context 'with valid compartment_id' do
      let(:spec) do
        {
          'compartment_id' => 'ocid1.tenancy.oc1..test'
        }
      end

      it 'returns configuration data' do
        result = adapter.fetch(spec)

        expect(result['status']).to eq('ENABLED')
        expect(result['reporting_region']).to eq('ap-tokyo-1')
        expect(result['self_manage_resources']).to eq(false)
      end
    end

    context 'without compartment_id' do
      let(:spec) { {} }

      it 'raises error' do
        expect { adapter.fetch(spec) }.to raise_error(Anyspec::Error, /compartment_id is required/)
      end
    end
  end

  describe 'OCI CLI command construction' do
    it 'builds correct command array' do
      config = Anyspec::Config.new(oci_cli: FAKE_OCI_CLI)
      adapter = described_class.new(config)

      args = ['cloud-guard', 'configuration', 'get', '--compartment-id', 'ocid1.test']
      cmd_array = adapter.send(:build_oci_command_array, args)

      expect(cmd_array).to include('cloud-guard')
      expect(cmd_array).to include('configuration')
      expect(cmd_array).to include('get')
      expect(cmd_array).to include('--compartment-id')
      expect(cmd_array).to include('--output')
      expect(cmd_array).to include('json')
    end
  end
end
