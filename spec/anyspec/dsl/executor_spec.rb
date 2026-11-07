# frozen_string_literal: true

require 'spec_helper'
require 'anyspec/dsl/runner'

RSpec.describe Anyspec::DSL::OCI::Executor do
  let(:config) { Anyspec::Config.new(oci_cli: '/bin/echo') }

  describe 'empty stdout handling' do
    it 'returns empty array for IAM list command with empty stdout and exit 0' do
      executor = described_class.new(config: config)
      
      allow(Open3).to receive(:capture3).and_return(['', '', double(success?: true, exitstatus: 0)])

      result = executor.execute(
        ['oci', 'iam', 'domain', 'list', '--compartment-id', 'test'],
        location: nil
      )

      expect(result).to eq([])
    end

    it 'returns empty array for IAM compartment list with empty stdout and exit 0' do
      executor = described_class.new(config: config)
      
      allow(Open3).to receive(:capture3).and_return(['', '', double(success?: true, exitstatus: 0)])

      result = executor.execute(
        ['oci', 'iam', 'compartment', 'list', '--compartment-id', 'test'],
        location: nil
      )

      expect(result).to eq([])
    end

    it 'raises error for non-IAM command with empty stdout and exit 0' do
      executor = described_class.new(config: config)
      
      allow(Open3).to receive(:capture3).and_return(['', '', double(success?: true, exitstatus: 0)])

      expect do
        executor.execute(
          ['oci', 'identity-domains', 'policy', 'list', '--endpoint', 'test'],
          location: nil
        )
      end.to raise_error(Anyspec::DSL::OCI::CLIError, /empty output/)
    end

    it 'raises error for IAM command with non-zero exit' do
      executor = described_class.new(config: config)
      
      allow(Open3).to receive(:capture3).and_return(['', 'error', double(success?: false, exitstatus: 1)])

      expect do
        executor.execute(
          ['oci', 'iam', 'domain', 'list', '--compartment-id', 'test'],
          location: nil
        )
      end.to raise_error(Anyspec::DSL::OCI::CLIError, /exit 1/)
    end
  end

  describe 'normal response handling' do
    it 'parses JSON response with data wrapper' do
      executor = described_class.new(config: config)
      json_response = '{"data": [{"id": "d1"}, {"id": "d2"}]}'
      
      allow(Open3).to receive(:capture3).and_return([json_response, '', double(success?: true, exitstatus: 0)])

      result = executor.execute(
        ['oci', 'iam', 'domain', 'list', '--compartment-id', 'test'],
        location: nil
      )

      expect(result).to eq([{ 'id' => 'd1' }, { 'id' => 'd2' }])
    end

    it 'parses SCIM response without data wrapper' do
      executor = described_class.new(config: config)
      json_response = '{"Resources": [], "totalResults": 0}'
      
      allow(Open3).to receive(:capture3).and_return([json_response, '', double(success?: true, exitstatus: 0)])

      result = executor.execute(
        ['oci', 'identity-domains', 'policy', 'list', '--endpoint', 'test'],
        location: nil
      )

      expect(result).to eq({ 'Resources' => [], 'totalResults' => 0 })
    end
  end
end
