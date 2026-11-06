# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Anyspec::Adapters::CloudGuardConfiguration do
  let(:oci_config) { instance_double('OCI::Config') }
  let(:config) { instance_double(Anyspec::Config, oci_client_config: oci_config) }
  let(:adapter) { described_class.new(config) }

  describe '#fetch' do
    let(:mock_client) { instance_double(OCI::CloudGuard::CloudGuardClient) }
    let(:mock_response) { instance_double(OCI::Response) }
    let(:mock_configuration) do
      instance_double(
        'OCI::CloudGuard::Models::Configuration',
        status: 'ENABLED',
        reporting_region: 'us-ashburn-1',
        self_manage_resources: false
      )
    end

    before do
      allow(OCI::CloudGuard::CloudGuardClient).to receive(:new).and_return(mock_client)
      allow(mock_client).to receive(:get_configuration).and_return(mock_response)
      allow(mock_response).to receive(:data).and_return(mock_configuration)
    end

    it 'fetches configuration from OCI' do
      spec = {
        'compartment_id' => 'ocid1.tenancy.oc1..test'
      }

      result = adapter.fetch(spec)

      expect(result['status']).to eq('ENABLED')
      expect(result['reporting_region']).to eq('us-ashburn-1')
      expect(result['self_manage_resources']).to eq(false)
    end

    it 'raises error when compartment_id is missing' do
      spec = {}

      expect do
        adapter.fetch(spec)
      end.to raise_error(Anyspec::Error, /compartment_id is required/)
    end

    it 'calls OCI API with correct compartment_id' do
      spec = { 'compartment_id' => 'ocid1.tenancy.oc1..test' }

      adapter.fetch(spec)

      expect(mock_client).to have_received(:get_configuration).with('ocid1.tenancy.oc1..test')
    end
  end
end
