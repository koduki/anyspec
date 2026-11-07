# frozen_string_literal: true

require 'spec_helper'
require 'json'
require 'anyspec/dsl/runner'

RSpec.describe Anyspec::DSL::OCI::OciBuiltins do
  let(:config) { Anyspec::Config.new(oci_cli: FAKE_OCI_CLI) }
  let(:fixtures) do
    JSON.parse(File.read(File.expand_path('fixtures/oci_responses.json', __dir__)))
  end

  def mock_responses
    {
      'compartment list' => fixtures['compartments'],
      'domain list' => fixtures['domains'],
      /policy list.*--all/ => fixtures['policies'],
      /rule list.*--all/ => fixtures['rules'],
      /condition list.*--all/ => fixtures['conditions'],
      /network-perimeters list.*--all/ => fixtures['networkPerimeters'],
      /identity-providers list/ => fixtures['identityProviders'],
      /social-identity-provider list/ => fixtures['socialIdentityProviders'],
      /password-policies list/ => fixtures['passwordPolicies'],
      /authentication-factor-settings list/ => fixtures['authFactorSettings'],
      /kmsi-settings list/ => fixtures['kmsiSettings'],
      /apps list.*--all/ => fixtures['apps'],
      /app-roles list.*adminRole/ => fixtures['appRoles'],
      /grants list.*--filter/ => fixtures['grants'],
      /groups list.*Administrators/ => fixtures['adminGroups'],
      /group get/ => fixtures['group'],
      /user get/ => fixtures['user'],
      /raw-request.*ConditionGroups/ => { 'data' => JSON.generate(fixtures['conditionGroups']) },
      /raw-request.*SsoSettings/ => { 'data' => JSON.generate(fixtures['ssoSettings']) }
    }
  end

  let(:runner) { Anyspec::DSL::Runner.create_with_mock_executor(config: config, mock_responses: mock_responses) }

  describe 'classify_attribute_value' do
    it 'classifies JSON values' do
      result = runner.run_source(<<~DSL)
        $v = '{"key": "value"}'
        classify_attribute_value $v
      DSL
      expect(result['type']).to eq('json')
      expect(result['value']).to eq({ 'key' => 'value' })
    end

    it 'classifies IP range references' do
      result = runner.run_source(<<~DSL)
        $v = '#inIPRange("np1")'
        classify_attribute_value $v
      DSL
      expect(result['type']).to eq('iprange_ref')
      expect(result['value']).to eq('np1')
    end

    it 'classifies function expressions' do
      result = runner.run_source(<<~DSL)
        $v = '#someFunc(arg)'
        classify_attribute_value $v
      DSL
      expect(result['type']).to eq('function_expr')
    end

    it 'classifies plain strings' do
      result = runner.run_source(<<~DSL)
        $v = 'plain text'
        classify_attribute_value $v
      DSL
      expect(result['type']).to eq('string')
    end

    it 'classifies null' do
      result = runner.run_source(<<~DSL)
        $v = null
        classify_attribute_value $v
      DSL
      expect(result['type']).to eq('null')
    end
  end

  describe 'extract_iprange_refs' do
    it 'extracts IP range references from attribute value' do
      result = runner.run_source('extract_iprange_refs \'#inIPRange("np1") or #inIPRange("np2")\'')
      expect(result).to contain_exactly('np1', 'np2')
    end

    it 'returns empty array for no references' do
      result = runner.run_source('extract_iprange_refs \'plain value\'')
      expect(result).to eq([])
    end
  end

  describe 'extract_condition_refs' do
    it 'extracts group references' do
      result = runner.run_source(<<~DSL)
        $cond = { "attributeName": "user.memberOf", "attributeValue": "grp1" }
        extract_condition_refs $cond
      DSL
      expect(result['groups']).to eq(['grp1'])
    end

    it 'extracts user references' do
      result = runner.run_source(<<~DSL)
        $cond = { "attributeName": "user.id", "attributeValue": "user1" }
        extract_condition_refs $cond
      DSL
      expect(result['users']).to eq(['user1'])
    end
  end

  describe 'find_admin_roles' do
    it 'filters admin roles' do
      result = runner.run_source(<<~DSL)
        $roles = [
          { "id": "r1", "adminRole": true },
          { "id": "r2", "adminRole": false },
          { "id": "r3", "admin-role": true }
        ]
        find_admin_roles $roles
      DSL
      expect(result.length).to eq(2)
      expect(result.map { |r| r['id'] }).to contain_exactly('r1', 'r3')
    end
  end

  describe 'validate_sequence' do
    it 'returns warnings for duplicate sequences' do
      result = runner.run_source(<<~DSL)
        $rules = [
          { "sequence": 1 },
          { "sequence": 2 },
          { "sequence": 1 }
        ]
        validate_sequence $rules "TestPolicy"
      DSL
      expect(result).to include(/duplicate rule sequence: 1/)
    end

    it 'returns empty for valid sequences' do
      result = runner.run_source(<<~DSL)
        $rules = [{ "sequence": 1 }, { "sequence": 2 }]
        validate_sequence $rules "TestPolicy"
      DSL
      expect(result).to eq([])
    end
  end

  describe 'check_ref_integrity' do
    it 'returns missing references' do
      result = runner.run_source(<<~DSL)
        $refs = ["a", "b", "c"]
        $lookup = { "a": {}, "c": {} }
        check_ref_integrity $refs $lookup "Rule"
      DSL
      expect(result).to include('Missing Rule reference: b')
    end

    it 'returns empty when all references found' do
      result = runner.run_source(<<~DSL)
        $refs = ["a", "b"]
        $lookup = { "a": {}, "b": {} }
        check_ref_integrity $refs $lookup "Rule"
      DSL
      expect(result).to eq([])
    end
  end

  describe 'scim_filter' do
    it 'creates SCIM filter string' do
      result = runner.run_source('scim_filter "attributeName" "eq" "value"')
      expect(result).to eq('attributeName eq "value"')
    end

    it 'escapes special characters' do
      result = runner.run_source('scim_filter "name" "eq" "test\\"value"')
      expect(result).to include('\\"')
    end
  end
end
