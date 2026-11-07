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

  describe 'SCIM --all pagination' do
    it 'handles --all response with opc-total-items and no total-results (CLI aggregated)' do
      mock_responses = {
        'policy list' => {
          'data' => {
            'resources' => [
              { 'id' => 'p1', 'name' => 'Policy1' },
              { 'id' => 'p2', 'name' => 'Policy2' },
              { 'id' => 'p3', 'name' => 'Policy3' },
              { 'id' => 'p4', 'name' => 'Policy4' },
              { 'id' => 'p5', 'name' => 'Policy5' }
            ],
            'schemas' => ['urn:ietf:params:scim:api:messages:2.0:ListResponse']
          },
          'opc-total-items' => '5'
        }
      }

      executor = Anyspec::DSL::MockExecutor.new(responses: mock_responses)
      pagination = described_class.new(executor: executor)

      result = pagination.scim_all(
        ['oci', 'identity-domains', 'policy', 'list', '--endpoint', 'https://test.example.com'],
        location: nil
      )

      expect(result.length).to eq(5)
      expect(result.map { |r| r['id'] }).to eq(%w[p1 p2 p3 p4 p5])
      expect(executor.calls.first[:argv]).to include('--all')
    end

    it 'handles single-page response with kebab-case SCIM fields' do
      mock_responses = {
        'policy list' => {
          'data' => {
            'items-per-page' => 50,
            'resources' => [
              { 'id' => 'p1', 'name' => 'Policy1' },
              { 'id' => 'p2', 'name' => 'Policy2' }
            ],
            'schemas' => ['urn:ietf:params:scim:api:messages:2.0:ListResponse'],
            'start-index' => 1,
            'total-results' => 2
          },
          'opc-total-items' => '2'
        }
      }

      executor = Anyspec::DSL::MockExecutor.new(responses: mock_responses)
      pagination = described_class.new(executor: executor)

      result = pagination.scim_all(
        ['oci', 'identity-domains', 'policy', 'list', '--endpoint', 'https://test.example.com'],
        location: nil
      )

      expect(result.length).to eq(2)
    end

    it 'validates count against opc-total-items when total-results is missing' do
      mock_responses = {
        'policy list' => {
          'data' => {
            'resources' => [{ 'id' => 'p1' }],
            'schemas' => []
          },
          'opc-total-items' => '5'
        }
      }

      executor = Anyspec::DSL::MockExecutor.new(responses: mock_responses)
      pagination = described_class.new(executor: executor)

      expect do
        pagination.scim_all(
          ['oci', 'identity-domains', 'policy', 'list', '--endpoint', 'https://test.example.com'],
          location: nil
        )
      end.to raise_error(Anyspec::DSL::OCI::PaginationError, /Count mismatch: got 1, expected 5/)
    end

    it 'detects duplicate resource IDs' do
      mock_responses = {
        'policy list' => {
          'data' => {
            'resources' => [
              { 'id' => 'p1', 'name' => 'Policy1' },
              { 'id' => 'p1', 'name' => 'Policy1Dup' }
            ]
          },
          'opc-total-items' => '2'
        }
      }

      executor = Anyspec::DSL::MockExecutor.new(responses: mock_responses)
      pagination = described_class.new(executor: executor)

      expect do
        pagination.scim_all(
          ['oci', 'identity-domains', 'policy', 'list', '--endpoint', 'https://test.example.com'],
          location: nil
        )
      end.to raise_error(Anyspec::DSL::OCI::PaginationError, /Duplicate resource id: p1/)
    end

    it 'accepts response with no validation metadata (no opc-total-items, no total-results)' do
      mock_responses = {
        'policy list' => {
          'data' => {
            'resources' => [
              { 'id' => 'p1' },
              { 'id' => 'p2' }
            ]
          }
        }
      }

      executor = Anyspec::DSL::MockExecutor.new(responses: mock_responses)
      pagination = described_class.new(executor: executor)

      result = pagination.scim_all(
        ['oci', 'identity-domains', 'policy', 'list', '--endpoint', 'https://test.example.com'],
        location: nil
      )

      expect(result.length).to eq(2)
    end

    it 'handles empty resources array' do
      mock_responses = {
        'policy list' => {
          'data' => {
            'resources' => [],
            'schemas' => []
          },
          'opc-total-items' => '0'
        }
      }

      executor = Anyspec::DSL::MockExecutor.new(responses: mock_responses)
      pagination = described_class.new(executor: executor)

      result = pagination.scim_all(
        ['oci', 'identity-domains', 'policy', 'list', '--endpoint', 'https://test.example.com'],
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

  describe 'raw-request pagination' do
    let(:executor) { instance_double(Anyspec::DSL::OCI::Executor) }
    let(:pagination) { described_class.new(executor: executor) }

    def page(ids, total:, start:)
      { 'status' => '200 OK', 'data' => { 'Resources' => ids.map { |id| { 'id' => id } },
                                           'totalResults' => total, 'startIndex' => start } }
    end

    def collect_raw
      pagination.raw_request_paginate(endpoint: 'https://example.test', path: '/admin/v1/ConditionGroups', location: nil)
    end

    it 'advances by returned resources even when pages are shorter than requested' do
      responses = [page(%w[a b], total: 3, start: 1), page(['c'], total: 3, start: 3)]
      urls = []
      allow(executor).to receive(:execute) do |args, **_kwargs|
        urls << args[args.index('--target-uri') + 1]
        responses.shift
      end
      expect(collect_raw.map { |item| item['id'] }).to eq(%w[a b c])
      expect(urls.last).to include('startIndex=3')
    end

    it 'rejects incomplete pages, duplicates, changing totals and wrong offsets' do
      bad_sequences = [
        [page(['a'], total: 2, start: 1), page([], total: 2, start: 2)],
        [page(['a'], total: 2, start: 1), page(['a'], total: 2, start: 2)],
        [page(['a'], total: 2, start: 1), page(['b'], total: 3, start: 2)],
        [page(['a'], total: 2, start: 1), page(['b'], total: 2, start: 101)]
      ]
      bad_sequences.each do |responses|
        allow(executor).to receive(:execute) { responses.shift }
        expect { collect_raw }.to raise_error(Anyspec::DSL::OCI::PaginationError)
      end
    end

    it 'distinguishes a valid empty result from malformed or excessive responses' do
      allow(executor).to receive(:execute).and_return({ 'status' => '200 OK', 'data' => { 'totalResults' => 0 } })
      expect(collect_raw).to eq([])
      [ { 'status' => '200 OK', 'data' => {} }, page(%w[a b], total: 1, start: 1) ].each do |response|
        allow(executor).to receive(:execute).and_return(response)
        expect { collect_raw }.to raise_error(Anyspec::DSL::OCI::PaginationError)
      end
    end
  end
end
