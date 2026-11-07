# frozen_string_literal: true

require 'spec_helper'
require 'anyspec/dsl/runner'
require 'json'

RSpec.describe 'OCI Identity Domains Collection Mechanism' do
  let(:fixtures_path) { File.join(__dir__, '../../fixtures/oci') }

  def load_fixture(name)
    JSON.parse(File.read(File.join(fixtures_path, "#{name}.json")))
  end

  def run(source)
    lexer = Anyspec::DSL::Lexer.new(source, file: '<test>')
    tokens = lexer.tokenize
    parser = Anyspec::DSL::Parser.new(tokens, file: '<test>')
    program = parser.parse
    builtins = Anyspec::DSL::Builtins.new
    config = Anyspec::Config.new
    executor = Anyspec::DSL::OCI::Executor.new(config: config)
    pagination = Anyspec::DSL::OCI::Pagination.new(executor: executor)
    oci_builtins = Anyspec::DSL::OCI::OciBuiltins.new(executor: executor, pagination: pagination)
    oci_builtins.register_all(builtins)
    interpreter = Anyspec::DSL::Interpreter.new(builtins: builtins)
    interpreter.evaluate(program)
  end

  describe 'set_key builtin (Issue A regression)' do

    it 'preserves OCID with dots as single key' do
      result = run(<<~DSL)
        $domains = {}
        $domain_id = 'ocid1.domain.oc1..aaaaaaaatestdomain12345'
        $domain_data = { "meta": { "id": $domain_id } }
        set_key $domains $domain_id $domain_data
      DSL

      expect(result.keys).to eq(['ocid1.domain.oc1..aaaaaaaatestdomain12345'])
      expect(result['ocid1.domain.oc1..aaaaaaaatestdomain12345']['meta']['id']).to eq('ocid1.domain.oc1..aaaaaaaatestdomain12345')
    end

    it 'does not split OCID by dots like set_at would' do
      result = run(<<~DSL)
        $result = { "domains": {} }
        $domain_id = 'ocid1.domain.oc1..test'
        $domains = get_opt $result 'domains' {}
        $domains = set_key $domains $domain_id { "test": true }
        set_at $result 'domains' $domains
      DSL

      expect(result['domains'].keys).to eq(['ocid1.domain.oc1..test'])
      expect(result['domains']['ocid1']).to be_nil
    end
  end

  describe 'SCIM --all response handling (Issue A/D regression)' do
    it 'extracts resources from --all response with opc-total-items' do
      mock_responses = {
        'apps list' => load_fixture('apps_all')
      }

      executor = Anyspec::DSL::MockExecutor.new(responses: mock_responses)
      pagination = Anyspec::DSL::OCI::Pagination.new(executor: executor)

      result = pagination.scim_all(
        ['oci', 'identity-domains', 'apps', 'list', '--endpoint', 'https://test.example.com'],
        location: nil
      )

      expect(result.length).to eq(2)
      expect(result[0]['name']).to eq('OciConsole_APPID')
      expect(result[0]['signon-policy']).not_to be_nil
      expect(result[0]['signon-policy']['value']).to eq('OciConsolePolicy')
    end

    it 'handles kebab-case field names in response' do
      mock_responses = {
        'policy list' => load_fixture('policies_all')
      }

      executor = Anyspec::DSL::MockExecutor.new(responses: mock_responses)
      pagination = Anyspec::DSL::OCI::Pagination.new(executor: executor)

      result = pagination.scim_all(
        ['oci', 'identity-domains', 'policy', 'list', '--endpoint', 'https://test.example.com'],
        location: nil
      )

      expect(result.length).to eq(2)
      expect(result[0]['policy-type']['value']).to eq('SignOn')
    end
  end

  describe 'IAM empty output handling (Issue regression)' do
    it 'returns empty array for domain list with empty stdout' do
      config = Anyspec::Config.new(oci_cli: '/bin/echo')
      executor = Anyspec::DSL::OCI::Executor.new(config: config)

      allow(Open3).to receive(:capture3).and_return(['', '', double(success?: true, exitstatus: 0)])

      result = executor.execute(
        ['oci', 'iam', 'domain', 'list', '--compartment-id', 'test'],
        location: nil
      )

      expect(result).to eq([])
    end
  end

  describe 'SsoSettings raw-get extraction (Issue C regression)' do
    it 'extracts Resources array from raw-request JSON response' do
      config = Anyspec::Config.new(oci_cli: '/bin/echo')
      executor = Anyspec::DSL::OCI::Executor.new(config: config)
      pagination = Anyspec::DSL::OCI::Pagination.new(executor: executor)
      builtins = Anyspec::DSL::Builtins.new
      oci_builtins = Anyspec::DSL::OCI::OciBuiltins.new(executor: executor, pagination: pagination)
      oci_builtins.register_all(builtins)

      sso_response = load_fixture('sso_settings_raw')
      allow(executor).to receive(:execute).and_return(sso_response)

      result = builtins.call('oci_raw_get', ['https://test.example.com', '/admin/v1/SsoSettings'], nil, nil)

      expect(result).to be_an(Array)
      expect(result.length).to eq(1)
      expect(result[0]['id']).to eq('SsoSettingsId')
    end

    it 'returns parsed Resources not wrapped in extra array' do
      config = Anyspec::Config.new(oci_cli: '/bin/echo')
      executor = Anyspec::DSL::OCI::Executor.new(config: config)
      pagination = Anyspec::DSL::OCI::Pagination.new(executor: executor)
      builtins = Anyspec::DSL::Builtins.new
      oci_builtins = Anyspec::DSL::OCI::OciBuiltins.new(executor: executor, pagination: pagination)
      oci_builtins.register_all(builtins)

      sso_response = load_fixture('sso_settings_raw')
      allow(executor).to receive(:execute).and_return(sso_response)

      result = builtins.call('oci_raw_get', ['https://test.example.com', '/admin/v1/SsoSettings'], nil, nil)

      expect(result).not_to eq([nil])
      expect(result[0]).to be_a(Hash)
    end
  end

  describe 'Grant filter and grantee extraction (Issue E regression)' do
    it 'extracts grantee type and value from grants with kebab-case fields' do
      grant = {
        'grantee' => {
          'type' => 'Group',
          'value' => 'TestAdminGroupId',
          'display' => 'Administrators'
        },
        'entitlement' => {
          'attribute-name' => 'appRoles',
          'attribute-value' => 'IdentityDomainAdminRoleId'
        }
      }

      result = run(<<~DSL)
        $grant = #{grant.to_json}
        $grantee = $grant.grantee
        $grantee_type = get_opt $grantee 'type' null
        $grantee_value = get_opt $grantee 'value' null
        { "type": $grantee_type, "value": $grantee_value }
      DSL

      expect(result['type']).to eq('Group')
      expect(result['value']).to eq('TestAdminGroupId')
    end

    it 'handles concat with array literal in grantee collection' do
      result = run(<<~DSL)
        $grantee_value = 'TestGroupId'
        $is_group = true
        $base = []
        $result = if_then $is_group (concat $base [$grantee_value]) $base
        $result
      DSL

      expect(result).to eq(['TestGroupId'])
    end

    it 'processes admin roles with admin-role kebab-case field' do
      admin_roles = load_fixture('admin_roles_all')['data']['resources']

      result = run(<<~DSL)
        $app_roles = #{admin_roles.to_json}
        find_admin_roles $app_roles
      DSL

      expect(result.length).to eq(2)
      expect(result.all? { |r| r['admin-role'] == true }).to be true
    end
  end

  describe 'Domain meta fields (Issue B regression)' do
    it 'domain object contains all required meta fields' do
      domain = load_fixture('domains')['data'][0]

      expect(domain['lifecycle-state']).to eq('ACTIVE')
      expect(domain['type']).to eq('DEFAULT')
      expect(domain['home-region']).to eq('us-ashburn-1')
      expect(domain['url']).to be_a(String)
      expect(domain['compartment-id']).to be_a(String)
    end

    it 'script can copy all meta fields from domain object' do
      domain = load_fixture('domains')['data'][0]

      result = run(<<~DSL)
        $domain = #{domain.to_json}
        $domain_meta = {
          "id": $domain.id,
          "name": $domain["display-name"],
          "url": $domain.url,
          "compartment-id": $domain["compartment-id"],
          "lifecycle-state": $domain["lifecycle-state"],
          "type": $domain.type,
          "home-region": $domain["home-region"]
        }
        $domain_meta
      DSL

      expect(result['id']).to eq('ocid1.domain.oc1..aaaaaaaatestdomain12345')
      expect(result['name']).to eq('Default')
      expect(result['lifecycle-state']).to eq('ACTIVE')
      expect(result['type']).to eq('DEFAULT')
      expect(result['home-region']).to eq('us-ashburn-1')
    end
  end

  describe 'Apps signon-policy extraction (Issue D regression)' do
    it 'app objects include signon-policy reference when present' do
      apps = load_fixture('apps_all')['data']['resources']
      oci_console = apps.find { |a| a['name'] == 'OciConsole_APPID' }

      expect(oci_console['signon-policy']).not_to be_nil
      expect(oci_console['signon-policy']['value']).to eq('OciConsolePolicy')
    end

    it 'script can extract signon-policy value using kebab-case' do
      apps = load_fixture('apps_all')['data']['resources']

      result = run(<<~DSL)
        $apps = #{apps.to_json}
        $results = foreach app in $apps {
          $signon_policy = get_opt $app 'signon-policy' null
          $policy_value = get_opt $signon_policy 'value' null
          { "name": $app.name, "policy": $policy_value }
        }
        $results
      DSL

      oci_console = result.find { |r| r['name'] == 'OciConsole_APPID' }
      expect(oci_console['policy']).to eq('OciConsolePolicy')

      login_client = result.find { |r| r['name'] == 'LoginClient_APPID' }
      expect(login_client['policy']).to be_nil
    end
  end

  describe 'foreach scoping regression (domains not empty)' do
    it 'foreach does not persist outer variable assignments' do
      result = run(<<~DSL)
        $result = {}
        $items = [{ "id": "a", "val": 1 }, { "id": "b", "val": 2 }]
        foreach item in $items {
          $result = set_key $result $item.id $item.val
        }
        $result
      DSL

      # This should be empty because assignments in foreach don't persist
      expect(result).to eq({})
    end

    it 'foreach result collection pattern works for building maps' do
      result = run(<<~DSL)
        $items = [{ "id": "a", "val": 1 }, { "id": "b", "val": 2 }]
        $pairs = foreach item in $items {
          { "key": $item.id, "value": $item.val }
        }
        pairs_to_map $pairs 'key' 'value'
      DSL

      expect(result).to eq({ 'a' => 1, 'b' => 2 })
    end

    it 'collector pattern: domains map is built from foreach results' do
      result = run(<<~DSL)
        $domains = [
          { "id": "ocid1.domain.oc1..aaa", "name": "Domain1" },
          { "id": "ocid1.domain.oc1..bbb", "name": "Domain2" }
        ]
        $domain_results = foreach domain in $domains {
          $domain_id = $domain.id
          $domain_data = { "meta": { "name": $domain.name }, "collections": {} }
          { "id": $domain_id, "data": $domain_data }
        }
        $domains_map = pairs_to_map $domain_results 'id' 'data'
        { "domains": $domains_map }
      DSL

      expect(result['domains'].keys.length).to eq(2)
      expect(result['domains']['ocid1.domain.oc1..aaa']['meta']['name']).to eq('Domain1')
      expect(result['domains']['ocid1.domain.oc1..bbb']['meta']['name']).to eq('Domain2')
    end
  end

  describe 'Pagination opc-total-items validation' do
    it 'validates count against string opc-total-items' do
      mock_responses = {
        'policy list' => {
          'data' => {
            'resources' => [{ 'id' => 'p1' }]
          },
          'opc-total-items' => '5'
        }
      }

      executor = Anyspec::DSL::MockExecutor.new(responses: mock_responses)
      pagination = Anyspec::DSL::OCI::Pagination.new(executor: executor)

      expect do
        pagination.scim_all(
          ['oci', 'identity-domains', 'policy', 'list', '--endpoint', 'https://test.example.com'],
          location: nil
        )
      end.to raise_error(Anyspec::DSL::OCI::PaginationError, /Count mismatch: got 1, expected 5/)
    end
  end
end
