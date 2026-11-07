# frozen_string_literal: true

require 'spec_helper'
require 'anyspec/dsl/runner'

RSpec.describe 'Identity Domains collection through the OCI subprocess' do
  it 'preserves response envelopes and returns actual settings and principals' do
    skip 'executable Ruby scripts require a POSIX host' if Gem.win_platform?
    fake_cli = File.expand_path('../../support/fake_oci_collector', __dir__)
    script = File.expand_path('../../../scripts/oci_identity_domains.flow', __dir__)
    config = Anyspec::Config.new(oci_cli: fake_cli)
    runner = Anyspec::DSL::Runner.new(config: config)
    result = runner.run_file(script, env_vars: { 'TENANCY_OCID' => 'ocid1.tenancy.oc1..aaaaaaaatesttenancy' })

    domain = result['domains'].values.first
    expect(domain['collected']).to be(true)
    collections = domain['collections']
    expect(collections['ssoSettings'].first['id']).to eq('SsoSettingsId')
    expect(collections['authenticationFactorSettings'].first['id']).to eq('AuthenticationFactorSettings')
    expect(collections['conditionGroups'].first['id']).to eq('TestConditionGroup1')
    expect(collections['adminGrants']).not_to be_empty
    expect(collections['targetUsers']).not_to be_empty
    expect(result['warnings']).to eq(runner.warnings)
  end
end
