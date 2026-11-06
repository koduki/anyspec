# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Anyspec::Adapters::AuditConfiguration do
  let(:oci_config) { instance_double('OCI::Config') }
  let(:config) { instance_double(Anyspec::Config, oci_client_config: oci_config, signer: nil) }
  let(:adapter) { described_class.new(config) }

  describe '#fetch' do
    let(:mock_client) { instance_double(OCI::Audit::AuditClient) }
    let(:mock_response) { instance_double(OCI::Response) }
    let(:mock_configuration) do
      instance_double(
        'OCI::Audit::Models::Configuration',
        retention_period_days: 365
      )
    end

    before do
      allow(OCI::Audit::AuditClient).to receive(:new).and_return(mock_client)
      allow(mock_client).to receive(:get_configuration).and_return(mock_response)
      allow(mock_response).to receive(:data).and_return(mock_configuration)
    end

    it 'fetches audit configuration from OCI' do
      spec = {
        'compartment_id' => 'ocid1.tenancy.oc1..test'
      }

      result = adapter.fetch(spec)

      expect(result['retention_period_days']).to eq(365)
    end

    it 'raises error when compartment_id is missing' do
      spec = {}

      expect do
        adapter.fetch(spec)
      end.to raise_error(Anyspec::Error, /compartment_id is required/)
    end
  end
end
