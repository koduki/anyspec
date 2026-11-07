# frozen_string_literal: true

require 'spec_helper'
require 'json'
require 'anyspec/dsl/runner'

RSpec.describe Anyspec::DSL::Runner do
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

  let(:runner) { described_class.create_with_mock_executor(config: config, mock_responses: mock_responses) }

  describe '#run_source' do
    it 'executes simple script' do
      result = runner.run_source('$x = 42' + "\n" + '$x')
      expect(result).to eq(42)
    end

    it 'uses environment variables' do
      result = runner.run_source('$MYVAR', env_vars: { 'MYVAR' => 'test_value' })
      expect(result).to eq('test_value')
    end

    it 'collects warnings' do
      runner.run_source("warn 'test warning 1'\nwarn 'test warning 2'")
      expect(runner.warnings.length).to eq(2)
    end
  end

  describe 'OCI domain collection script' do
    it 'collects compartments' do
      result = runner.run_source(<<~DSL)
        $tenancy = "ocid1.tenancy.oc1..root"
        $compartments = oci_list_compartments $tenancy
        $active = filter $compartments 'lifecycle-state' 'ACTIVE'
        count $active
      DSL
      expect(result).to be >= 1
    end
  end

  describe 'mock executor' do
    it 'records all calls' do
      mock_executor = Anyspec::DSL::MockExecutor.new(responses: {
        'test' => { 'result' => 'ok' }
      })

      builtins = Anyspec::DSL::Builtins.new
      interp = Anyspec::DSL::Interpreter.new(
        builtins: builtins,
        command_executor: mock_executor
      )

      lexer = Anyspec::DSL::Lexer.new('oci test arg1 arg2', file: '<test>')
      tokens = lexer.tokenize
      parser = Anyspec::DSL::Parser.new(tokens, file: '<test>')
      program = parser.parse

      interp.run(program)

      expect(mock_executor.calls.length).to eq(1)
      expect(mock_executor.calls.first[:argv]).to include('test')
    end
  end

  describe 'reference validation flow' do
    it 'detects missing references' do
      result = runner.run_source(<<~DSL)
        $refs = ["a", "b", "c"]
        $lookup = { "a": {}, "c": {} }
        check_ref_integrity $refs $lookup "Rule"
      DSL
      expect(result).to include('Missing Rule reference: b')
    end
  end
end
