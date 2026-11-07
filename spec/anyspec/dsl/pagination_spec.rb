# frozen_string_literal: true

require 'spec_helper'
require 'anyspec/dsl/runner'

RSpec.describe Anyspec::DSL::OCI::Pagination do
  let(:config) { Anyspec::Config.new(oci_cli: FAKE_OCI_CLI) }

  describe 'SCIM pagination' do
    it 'collects single page' do
      mock_responses = {
        'test list' => {
          'Resources' => [{ 'id' => 'r1' }, { 'id' => 'r2' }],
          'totalResults' => 2,
          'startIndex' => 1,
          'itemsPerPage' => 1000
        }
      }

      executor = Anyspec::DSL::MockExecutor.new(responses: mock_responses)
      pagination = described_class.new(executor: executor)

      result = pagination.scim_paginate(
        ['oci', 'identity-domains', 'test', 'list', '--endpoint', 'https://test'],
        location: nil
      )

      expect(result.length).to eq(2)
      expect(result.map { |r| r['id'] }).to eq(%w[r1 r2])
    end

    it 'handles empty result' do
      mock_responses = {
        'test list' => {
          'Resources' => [],
          'totalResults' => 0,
          'startIndex' => 1,
          'itemsPerPage' => 1000
        }
      }

      executor = Anyspec::DSL::MockExecutor.new(responses: mock_responses)
      pagination = described_class.new(executor: executor)

      result = pagination.scim_paginate(
        ['oci', 'identity-domains', 'test', 'list', '--endpoint', 'https://test'],
        location: nil
      )

      expect(result).to eq([])
    end
  end

  describe 'IAM pagination' do
    it 'uses --all flag' do
      mock_responses = {
        'compartment list' => {
          'data' => [{ 'id' => 'c1' }, { 'id' => 'c2' }]
        }
      }

      executor = Anyspec::DSL::MockExecutor.new(responses: mock_responses)
      pagination = described_class.new(executor: executor)

      result = pagination.iam_paginate(
        ['oci', 'iam', 'compartment', 'list'],
        location: nil
      )

      expect(result.length).to eq(2)
      expect(executor.calls.first[:argv]).to include('--all')
    end

    it 'handles empty output for domain list (no domains in compartment)' do
      mock_responses = {
        'domain list' => []
      }

      executor = Anyspec::DSL::MockExecutor.new(responses: mock_responses)
      pagination = described_class.new(executor: executor)

      result = pagination.iam_paginate(
        ['oci', 'iam', 'domain', 'list', '--compartment-id', 'ocid1.compartment.oc1..test'],
        location: nil
      )

      expect(result).to eq([])
    end
  end

  describe 'Group members pagination' do
    it 'collects members with attribute pagination' do
      mock_responses = {
        /members\[startIndex=1/ => {
          'id' => 'grp1',
          'members' => [
            { 'value' => 'u1', 'type' => 'User' },
            { 'value' => 'u2', 'type' => 'User' }
          ]
        }
      }

      executor = Anyspec::DSL::MockExecutor.new(responses: mock_responses)
      pagination = described_class.new(executor: executor)

      result = pagination.group_members_paginate(
        group_id: 'grp1',
        endpoint: 'https://test',
        location: nil
      )

      expect(result.length).to eq(2)
    end
  end
end
