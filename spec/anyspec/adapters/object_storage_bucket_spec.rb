# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Anyspec::Adapters::ObjectStorageBucket do
  let(:oci_config) { instance_double('OCI::Config') }
  let(:config) { instance_double(Anyspec::Config, oci_client_config: oci_config) }
  let(:adapter) { described_class.new(config) }

  describe '#fetch' do
    let(:mock_client) { instance_double(OCI::ObjectStorage::ObjectStorageClient) }
    let(:mock_response) { instance_double(OCI::Response) }
    let(:mock_bucket) do
      instance_double(
        'OCI::ObjectStorage::Models::Bucket',
        name: 'test-bucket',
        namespace: 'test-namespace',
        compartment_id: 'ocid1.compartment.oc1..test',
        public_access_type: 'NoPublicAccess',
        storage_tier: 'Standard',
        versioning: 'Enabled',
        is_read_only: false,
        auto_tiering: 'Disabled',
        object_events_enabled: true,
        replication_enabled: false
      )
    end

    before do
      allow(OCI::ObjectStorage::ObjectStorageClient).to receive(:new).and_return(mock_client)
      allow(mock_client).to receive(:get_bucket).and_return(mock_response)
      allow(mock_response).to receive(:data).and_return(mock_bucket)
    end

    it 'fetches bucket from OCI' do
      spec = {
        'namespace' => 'test-namespace',
        'bucket_name' => 'test-bucket'
      }

      result = adapter.fetch(spec)

      expect(result['name']).to eq('test-bucket')
      expect(result['public_access_type']).to eq('NoPublicAccess')
      expect(result['versioning']).to eq('Enabled')
    end

    it 'accepts name as alias for bucket_name' do
      spec = {
        'namespace' => 'test-namespace',
        'name' => 'test-bucket'
      }

      result = adapter.fetch(spec)

      expect(result['name']).to eq('test-bucket')
    end

    it 'raises error when namespace is missing' do
      spec = { 'bucket_name' => 'test-bucket' }

      expect do
        adapter.fetch(spec)
      end.to raise_error(Anyspec::Error, /namespace is required/)
    end

    it 'raises error when bucket_name is missing' do
      spec = { 'namespace' => 'test-namespace' }

      expect do
        adapter.fetch(spec)
      end.to raise_error(Anyspec::Error, /bucket_name or name is required/)
    end
  end
end
