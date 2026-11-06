# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Anyspec::Adapters::ObjectStorageBucket do
  let(:config) { Anyspec::Config.new(oci_cli: FAKE_OCI_CLI) }
  let(:adapter) { described_class.new(config) }

  describe '#fetch' do
    context 'with valid namespace and bucket_name' do
      let(:spec) do
        {
          'namespace' => 'test-namespace',
          'bucket_name' => 'test-bucket'
        }
      end

      it 'returns bucket data' do
        result = adapter.fetch(spec)

        expect(result['name']).to eq('test-bucket')
        expect(result['namespace']).to eq('test-namespace')
        expect(result['public_access_type']).to eq('NoPublicAccess')
        expect(result['versioning']).to eq('Enabled')
        expect(result['storage_tier']).to eq('Standard')
      end
    end

    context 'with name as alias for bucket_name' do
      let(:spec) do
        {
          'namespace' => 'test-namespace',
          'name' => 'test-bucket'
        }
      end

      it 'accepts name as alias' do
        result = adapter.fetch(spec)
        expect(result['name']).to eq('test-bucket')
      end
    end

    context 'without namespace' do
      let(:spec) { { 'bucket_name' => 'test-bucket' } }

      it 'raises error' do
        expect { adapter.fetch(spec) }.to raise_error(Anyspec::Error, /namespace is required/)
      end
    end

    context 'without bucket_name' do
      let(:spec) { { 'namespace' => 'test-namespace' } }

      it 'raises error' do
        expect { adapter.fetch(spec) }.to raise_error(Anyspec::Error, /bucket_name or name is required/)
      end
    end
  end
end
