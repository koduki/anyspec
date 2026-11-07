# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Collector E2E Test' do
  let(:mock_executor) { DSLTestHelper::CollectorMockExecutor.new }

  describe 'Full collector script execution' do
    it 'runs the collector script with fixtures and produces non-empty output' do
      result = DSLTestHelper.run_collector_script(executor: mock_executor)

      expect(result.value).to be_a(Hash)
      expect(result['domains']).not_to be_empty
      expect(result['warnings']).to be_an(Array)
    end

    it 'collects at least one domain' do
      result = DSLTestHelper.run_collector_script(executor: mock_executor)

      expect(result['domains'].keys.length).to be >= 1
    end

    it 'uses OCID as domain key without dot-splitting' do
      result = DSLTestHelper.run_collector_script(executor: mock_executor)

      domain_keys = result['domains'].keys
      expect(domain_keys.first).to start_with('ocid1.domain.oc1..')
      expect(domain_keys.first).to eq('ocid1.domain.oc1..aaaaaaaatestdomain12345')
    end
  end

  describe 'Domain meta fields (Issue B regression)' do
    it 'includes all required meta fields' do
      result = DSLTestHelper.run_collector_script(executor: mock_executor)

      domain = result['domains'].values.first
      meta = domain['meta']

      expect(meta['id']).to eq('ocid1.domain.oc1..aaaaaaaatestdomain12345')
      expect(meta['name']).to eq('Default')
      expect(meta['url']).to be_a(String)
      expect(meta['compartment-id']).to be_a(String)
      expect(meta['lifecycle-state']).to eq('ACTIVE')
      expect(meta['type']).to eq('DEFAULT')
      expect(meta['home-region']).to eq('us-ashburn-1')
    end

    it 'retains inactive domain metadata without attempting collection' do
      domains = DSLTestHelper.load_fixture('domains')
      inactive = domains['data'].first.merge('id' => 'inactive-domain', 'lifecycle-state' => 'INACTIVE',
                                               'url' => 'https://inactive.example.test')
      domains['data'] << inactive
      executor = DSLTestHelper::CollectorMockExecutor.new(fixtures: { domains: domains })
      result = DSLTestHelper.run_collector_script(executor: executor)

      expect(result['domains'].keys).to include('inactive-domain', domains['data'].first['id'])
      expect(result['domains']['inactive-domain']).to include('collected' => false, 'reason' => 'domain_not_active')
      expect(result['domains']['inactive-domain']['meta']).to include('lifecycle-state' => 'INACTIVE',
                                                                        'type' => 'DEFAULT', 'home-region' => 'us-ashburn-1')
      expect(result['domains']['inactive-domain']).not_to have_key('collections')
      expect(executor.calls.none? { |call| call[:argv].include?('https://inactive.example.test') }).to be(true)
      expect(result['domains'][domains['data'].first['id']]['collected']).to be(true)
    end

    it 'retains an inactive-only inventory' do
      domains = DSLTestHelper.load_fixture('domains')
      domains['data'].first['lifecycle-state'] = 'INACTIVE'
      result = DSLTestHelper.run_collector_script(executor: DSLTestHelper::CollectorMockExecutor.new(fixtures: { domains: domains }))
      expect(result['domains'].values.first['collected']).to be(false)
    end
  end

  describe 'Collections completeness' do
    let(:result) { DSLTestHelper.run_collector_script(executor: mock_executor) }
    let(:domain) { result['domains'].values.first }
    let(:collections) { domain['collections'] }

    it 'includes policies collection' do
      expect(collections['policies']).to be_an(Array)
      expect(collections['policies'].length).to be >= 1
    end

    it 'includes rules collection' do
      expect(collections['rules']).to be_an(Array)
    end

    it 'includes conditions collection' do
      expect(collections['conditions']).to be_an(Array)
    end

    it 'includes networkPerimeters collection' do
      expect(collections['networkPerimeters']).to be_an(Array)
    end

    it 'includes conditionGroups collection' do
      expect(collections['conditionGroups']).to be_an(Array)
    end

    it 'includes identityProviders collection' do
      expect(collections['identityProviders']).to be_an(Array)
    end

    it 'includes socialIdentityProviders collection' do
      expect(collections['socialIdentityProviders']).to be_an(Array)
    end

    it 'includes passwordPolicies collection' do
      expect(collections['passwordPolicies']).to be_an(Array)
    end

    it 'includes authenticationFactorSettings collection' do
      expect(collections['authenticationFactorSettings']).to be_an(Array)
    end

    it 'includes kmsiSettings collection' do
      expect(collections['kmsiSettings']).to be_an(Array)
    end

    it 'includes ssoSettings collection' do
      expect(collections['ssoSettings']).to be_an(Array)
    end

    it 'includes apps collection' do
      expect(collections['apps']).to be_an(Array)
    end

    it 'includes adminAppRoles collection' do
      expect(collections['adminAppRoles']).to be_an(Array)
    end

    it 'includes adminGrants collection' do
      expect(collections['adminGrants']).to be_an(Array)
    end

    it 'includes targetGroups collection' do
      expect(collections['targetGroups']).to be_an(Array)
    end

    it 'includes targetUsers collection' do
      expect(collections['targetUsers']).to be_an(Array)
    end
  end

  describe 'Apps signon-policy extraction (Issue D regression)' do
    it 'preserves signon-policy reference in apps' do
      result = DSLTestHelper.run_collector_script(executor: mock_executor)
      apps = result['domains'].values.first['collections']['apps']

      oci_console = apps.find { |a| a['name'] == 'OciConsole_APPID' }
      expect(oci_console).not_to be_nil
      expect(oci_console['signon-policy']).not_to be_nil
      expect(oci_console['signon-policy']['value']).to eq('OciConsolePolicy')
    end
  end

  describe 'Admin grants and grantees (Issue E regression)' do
    it 'collects admin grants with grantee data' do
      result = DSLTestHelper.run_collector_script(executor: mock_executor)
      grants = result['domains'].values.first['collections']['adminGrants']

      expect(grants).not_to be_empty
      grant = grants.first
      expect(grant['grantee']).to be_a(Hash)
      expect(grant['grantee']['type']).to be_a(String)
      expect(grant['grantee']['value']).to be_a(String)
    end

    it 'collects target groups from grantees' do
      result = DSLTestHelper.run_collector_script(executor: mock_executor)
      target_groups = result['domains'].values.first['collections']['targetGroups']

      expect(target_groups).not_to be_empty
    end

    it 'collects target users from grantees and group members' do
      result = DSLTestHelper.run_collector_script(executor: mock_executor)
      target_users = result['domains'].values.first['collections']['targetUsers']

      expect(target_users).not_to be_empty
    end
  end

  describe 'SsoSettings extraction (Issue C regression)' do
    it 'extracts SsoSettings from raw-request response' do
      result = DSLTestHelper.run_collector_script(executor: mock_executor)
      sso_settings = result['domains'].values.first['collections']['ssoSettings']

      expect(sso_settings).to be_an(Array)
      expect(sso_settings).not_to eq([nil])

      unless sso_settings.empty?
        expect(sso_settings.first).to be_a(Hash)
        expect(sso_settings.first['id']).to eq('SsoSettingsId')
      end
    end
  end

  describe 'foreach scoping regression (empty domains)' do
    it 'domains map is not empty after foreach processing' do
      result = DSLTestHelper.run_collector_script(executor: mock_executor)

      expect(result['domains']).not_to eq({})
      expect(result['domains'].keys.length).to be >= 1
    end

    it 'each domain has collections that were set inside foreach' do
      result = DSLTestHelper.run_collector_script(executor: mock_executor)

      result['domains'].each_value do |domain|
        expect(domain['collections']).not_to be_nil
        expect(domain['collections']).not_to be_empty
      end
    end
  end

  describe 'Warnings collection' do
    it 'interpreter collects warnings emitted during execution' do
      result = DSLTestHelper.run_dsl(<<~DSL)
        warn 'Test warning 1'
        warn 'Test warning 2'
        'done'
      DSL

      expect(result.warnings.length).to eq(2)
      expect(result.warnings[0][:message]).to eq('Test warning 1')
      expect(result.warnings[1][:message]).to eq('Test warning 2')
    end

    it 'collects warnings from foreach loops' do
      result = DSLTestHelper.run_dsl(<<~DSL)
        $items = ['a', 'b', 'c']
        foreach item in $items {
          warn "Processing $item"
        }
        'done'
      DSL

      expect(result.warnings.length).to eq(3)
    end

    it 'keeps collecting and includes missing-reference and duplicate-sequence warnings in output' do
      policies = DSLTestHelper.load_fixture('policies_all')
      rules = policies['data']['resources'].first['rules']
      rules.first['sequence'] = 1
      rules << { 'value' => 'missing-rule', 'sequence' => 1 }
      executor = DSLTestHelper::CollectorMockExecutor.new(fixtures: { policies: policies })
      result = DSLTestHelper.run_collector_script(executor: executor)

      expect(result['domains']).not_to be_empty
      expect(result['warnings']).to eq(result.warnings)
      messages = result['warnings'].map { |warning| warning[:message] }
      expect(messages.any? { |message| message.include?('missing-rule') }).to be(true)
      expect(messages.any? { |message| message.include?('duplicate rule sequence') }).to be(true)
      expect(messages.any? { |message| message.include?('TestSignOnPolicy') }).to be(true)
    end
  end

  describe 'CLI call patterns' do
    it 'calls compartment list first' do
      DSLTestHelper.run_collector_script(executor: mock_executor)

      first_call = mock_executor.calls.first
      expect(first_call[:argv].join(' ')).to include('compartment list')
    end

    it 'calls domain list after compartment list' do
      DSLTestHelper.run_collector_script(executor: mock_executor)

      domain_call = mock_executor.calls.find { |c| c[:argv].join(' ').include?('domain list') }
      expect(domain_call).not_to be_nil
    end

    it 'uses --all flag for SCIM list calls' do
      DSLTestHelper.run_collector_script(executor: mock_executor)

      scim_calls = mock_executor.calls.select { |c| c[:argv].join(' ').include?('identity-domains') }
      list_calls = scim_calls.select { |c| c[:argv].join(' ').include?(' list') }

      list_calls.each do |call|
        next if call[:argv].join(' ').include?('group-members')
        expect(call[:argv]).to include('--all'), "Expected --all in: #{call[:argv].join(' ')}"
      end
    end

    it 'uses raw-request for ConditionGroups' do
      DSLTestHelper.run_collector_script(executor: mock_executor)

      raw_calls = mock_executor.calls.select { |c| c[:argv].join(' ').include?('raw-request') }
      cg_call = raw_calls.find { |c| c[:argv].join(' ').include?('ConditionGroups') }

      expect(cg_call).not_to be_nil
    end

    it 'uses raw-request for SsoSettings' do
      DSLTestHelper.run_collector_script(executor: mock_executor)

      raw_calls = mock_executor.calls.select { |c| c[:argv].join(' ').include?('raw-request') }
      sso_call = raw_calls.find { |c| c[:argv].join(' ').include?('SsoSettings') }

      expect(sso_call).not_to be_nil
    end
  end
end
