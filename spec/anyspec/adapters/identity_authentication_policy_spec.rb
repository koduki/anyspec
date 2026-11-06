# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Anyspec::Adapters::IdentityAuthenticationPolicy do
  let(:config) { Anyspec::Config.new(oci_cli: FAKE_OCI_CLI) }
  let(:adapter) { described_class.new(config) }

  describe '#fetch' do
    context 'with valid compartment_id' do
      let(:spec) do
        {
          'compartment_id' => 'ocid1.tenancy.oc1..test'
        }
      end

      it 'returns authentication policy data' do
        result = adapter.fetch(spec)

        expect(result['compartment_id']).to eq('ocid1.tenancy.oc1..test')
        expect(result).to have_key('password_policy')
        expect(result['password_policy']['minimum_password_length']).to eq(14)
        expect(result['password_policy']['is_uppercase_characters_required']).to eq(true)
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
