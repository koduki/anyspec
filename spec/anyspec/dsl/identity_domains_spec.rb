# frozen_string_literal: true
require 'spec_helper'

RSpec.describe 'Identity Domains DSL adapter' do
  let(:source) { File.read(File.expand_path('../../../adapters/identity-domains.anyspec', __dir__)) }
  let(:requests) { [] }
  let(:data) do
    {
      'Policies' => [{ 'id' => 'p1', 'rules' => [{ 'value' => 'r2', 'sequence' => 20 }, { 'value' => 'r1', 'sequence' => 1 }], 'meta' => { 'lastModified' => 'now' } }],
      'Rules' => [{ 'id' => 'r1', 'conditionGroup' => { 'type' => 'ConditionGroup', 'value' => 'cg1' } }, { 'id' => 'r2' }],
      'ConditionGroups' => [{ 'id' => 'cg1', 'conditions' => [{ 'type' => 'Condition', 'value' => 'c1' }, { 'type' => 'Condition', 'value' => 'c2' }] }],
      'Conditions' => [
        { 'id' => 'c1', 'attributeName' => 'user.groups[*].value', 'attributeValue' => '["g-policy"]' },
        { 'id' => 'c2', 'attributeName' => 'subject.ip', 'attributeValue' => '#inIPRange("np1")' },
        { 'id' => 'c3', 'attributeName' => 'user.userName', 'attributeValue' => '["alice@example.test"]' }
      ],
      'NetworkPerimeters' => [{ 'id' => 'np1', 'ipAddresses' => [{ 'value' => '192.0.2.0/24' }] }],
      'IdentityProviders' => [{ 'id' => 'idp1', 'enabled' => true }],
      'PasswordPolicies' => [{ 'id' => 'pw1', 'minLength' => 14 }],
      'AuthenticationFactorSettings' => [{ 'id' => 'AuthenticationFactorSettings', 'totpEnabled' => true }],
      'SsoSettings' => [{ 'id' => 'SsoSettings', 'sessionExpiry' => 480 }],
      'KmsiSettings' => [{ 'id' => 'KmsiSettings', 'kmsiEnabled' => true }],
      'Apps' => [{ 'id' => 'app1', 'signonPolicy' => { 'value' => 'p1' }, 'idpPolicy' => { 'value' => 'p1' } }],
      'AppRoles' => [{ 'id' => 'role1', 'adminRole' => true, 'app' => { 'value' => 'app1' } }],
      'Grants' => [{ 'id' => 'grant1', 'entitlement' => { 'attributeName' => 'appRoles', 'attributeValue' => 'role1' }, 'grantee' => { 'type' => 'Group', 'value' => 'g-admin' }, 'app' => { 'value' => 'app1' } }],
      'Groups' => [
        { 'id' => 'g-admin', 'displayName' => 'Administrators', 'members' => [{ 'type' => 'Group', 'value' => 'g-nested' }, { 'type' => 'User', 'value' => 'u-admin' }] },
        { 'id' => 'g-nested', 'displayName' => 'Nested', 'members' => [{ 'type' => 'Group', 'value' => 'g-admin' }, { 'type' => 'User', 'value' => 'u-nested' }] },
        { 'id' => 'g-policy', 'displayName' => 'Policy', 'members' => [] },
        { 'id' => 'ordinary-group', 'displayName' => 'Not in scope' }
      ],
      'Users' => [
        { 'id' => 'u-admin', 'userName' => 'admin@example.test' },
        { 'id' => 'u-nested', 'userName' => 'nested@example.test' },
        { 'id' => 'u-alice', 'userName' => 'alice@example.test' },
        { 'id' => 'ordinary-user', 'userName' => 'not-in-scope@example.test' }
      ]
    }
  end

  let(:runner) do
    lambda do |argv|
      requests << argv
      uri = URI(argv[argv.index('--target-uri') + 1])
      params = URI.decode_www_form(uri.query).to_h
      if uri.path == '/20160918/compartments'
        { 'status' => '200 OK', 'headers' => {}, 'data' => [{ 'id' => 'child', 'lifecycleState' => 'ACTIVE' }] }
      elsif uri.path == '/20160918/domains'
        compartment = params['compartmentId']
        domains = compartment == 'tenant' ? [{ 'id' => 'd1', 'url' => 'https://domain.example', 'lifecycleState' => 'ACTIVE', 'homeRegion' => 'us-ashburn-1' }] : [{ 'id' => 'inactive', 'lifecycleState' => 'INACTIVE' }]
        { 'status' => '200 OK', 'headers' => {}, 'data' => domains }
      else
        _, _, _, collection, id = uri.path.split('/')
        params = URI.decode_www_form(uri.query).to_h
        rows = data.fetch(collection)
        if id
          item = rows.find { |r| r['id'] == URI.decode_www_form_component(id) }
          item ? { 'status' => '200 OK', 'data' => item } : { 'status' => '404 Not Found' }
        else
          filter = params['filter']
          case collection
          when 'Groups'
            raise 'unfiltered groups' unless filter == 'displayName eq "Administrators"'
            raise 'missing member projection' unless params['attributes'] == 'members'
            rows = rows.select { |r| r['displayName'] == 'Administrators' }
          when 'Users'
            raise 'unfiltered users' unless filter == 'userName eq "alice@example.test"'
            rows = rows.select { |r| r['userName'] == 'alice@example.test' }
          when 'AppRoles'
            raise 'admin filter missing' unless filter == 'adminRole eq true'
          when 'Grants'
            raise 'grant filter missing' unless filter.include?('entitlement.attributeValue eq "role1"')
          when 'Policies'
            raise 'rules projection missing' unless params['attributes'] == 'rules'
          end
          start = params.fetch('startIndex', '1').to_i
          page = rows.slice(start - 1, params.fetch('count', '100').to_i) || []
          { 'status' => '200 OK', 'data' => { 'totalResults' => rows.size, 'startIndex' => start, 'itemsPerPage' => page.size, 'Resources' => page } }
        end
      end
    end
  end

  def collect
    transport = Anyspec::DSL::OCI.new(Anyspec::Config.new, runner: runner, page_size: 2)
    Anyspec::DSL::Runtime.new(transport: transport).run(source, variables: { 'input' => { 'tenancy_id' => 'tenant', 'iam_endpoint' => 'https://identity.example' } }, file: 'identity-domains.anyspec')
  end

  it 'collects all requested categories, traverses selected principals and retains domain attributes' do
    result = collect
    collections = result['domains']['d1']['collections']
    expect(collections.keys).to match_array(Anyspec::DSL::OCI::COLLECTIONS)
    expect(collections['Groups'].keys).to match_array(%w[g-admin g-policy g-nested])
    expect(collections['Users'].keys).to match_array(%w[u-admin u-nested u-alice])
    expect(collections['Policies']['p1']['rules'].map { |r| r['value'] }).to eq(%w[r1 r2])
    expect(collections['Policies']['p1']).not_to have_key('meta')
    expect(result['domains']['inactive']['collected']).to be(false)
    expect(result['warnings'].map { |w| w['code'] }).to eq(['DOMAIN_NOT_ACTIVE'])
  end

  it 'produces deterministic results when collection ordering changes' do
    first = collect
    data.each_value(&:reverse!)
    expect(collect).to eq(first)
  end

  it 'warns on dangling references and duplicate sequence without hiding valid data' do
    data['Policies'][0]['rules'] << { 'value' => 'gone', 'sequence' => 1 }
    data['ConditionGroups'][0]['conditions'] << { 'type' => 'ConditionGroup', 'value' => 'missing-cg' }
    data['Conditions'][0]['attributeValue'] = '["missing-group"]'
    result = collect
    expect(result['domains']['d1']['collected']).to be(true)
    codes = result['warnings'].map { |w| w['code'] }
    expect(codes).to include('MISSING_REFERENCE', 'DUPLICATE_PRIORITY')
  end

  it 'shares one complete collection across 500 specs and resets at the next run' do
    definition = { 'dsl' => 'identity-domains.anyspec', 'inputs' => ['tenancy_id', 'iam_endpoint'], '_source' => source, '_file' => 'identity-domains.anyspec' }
    allow(Anyspec::AdapterRegistry).to receive(:get).with('identity_domains_snapshot').and_return(Anyspec::Adapters::Dsl)
    allow(Anyspec::AdapterRegistry).to receive(:get_definition).with('identity_domains_snapshot').and_return(definition)
    allow(Anyspec::DSL::ProcessRunner).to receive(:new).and_return(runner)
    spec = { 'type' => 'identity_domains_snapshot', 'id' => 'check', 'tenancy_id' => 'tenant', 'iam_endpoint' => 'https://identity.example', 'expect' => { 'schema_version' => 1 } }
    checker = Anyspec::Runner.new(config: Anyspec::Config.new)
    expect(checker.run(Array.new(500, spec)).all?(&:pass?)).to be(true)
    first_count = requests.size
    checker.run([spec])
    expect(requests.size).to eq(first_count * 2)
  end

  it 'caches collection failures instead of retrying for every spec' do
    definition = { 'dsl' => 'test', 'inputs' => ['tenancy_id', 'iam_endpoint'], '_source' => 'oci ["iam","domain","list","--compartment-id","tenant"]', '_file' => 'test' }
    allow(Anyspec::AdapterRegistry).to receive(:get).and_return(Anyspec::Adapters::Dsl)
    allow(Anyspec::AdapterRegistry).to receive(:get_definition).and_return(definition)
    transport = double('runner')
    expect(transport).to receive(:call).once.and_raise(Anyspec::DSL::Error, 'failed')
    allow(Anyspec::DSL::ProcessRunner).to receive(:new).and_return(transport)
    spec = { 'type' => 'test', 'id' => 'check', 'tenancy_id' => 'tenant', 'iam_endpoint' => 'https://identity.example', 'expect' => {} }
    checker = Anyspec::Runner.new(config: Anyspec::Config.new)
    expect(checker.run(Array.new(500, spec)).all?(&:error?)).to be(true)
  end
end
