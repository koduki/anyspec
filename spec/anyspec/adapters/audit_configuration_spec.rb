# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Anyspec::Adapters::AuditConfiguration do
  let(:config) { Anyspec::Config.new(oci_cli: FAKE_OCI_CLI) }
  let(:adapter) { described_class.new(config) }

  describe '#fetch' do
    context 'with valid compartment_id' do
      let(:spec) do
        {
          'compartment_id' => 'ocid1.tenancy.oc1..test'
        }
      end

      it 'returns audit configuration' do
        result = adapter.fetch(spec)
        expect(result['retention_period_days']).to eq(365)
      end
    end

    context 'without compartment_id' do
      let(:spec) { {} }

      it 'raises error' do
        expect { adapter.fetch(spec) }.to raise_error(Anyspec::Error, /compartment_id is required/)
      end
    end
  end
end
