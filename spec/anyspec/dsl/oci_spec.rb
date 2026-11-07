# frozen_string_literal: true
require 'spec_helper'
require 'uri'

RSpec.describe Anyspec::DSL::OCI do
  let(:calls) { [] }
  let(:pages) { [] }
  let(:runner) do
    lambda do |argv|
      calls << argv
      if argv[1,3] == %w[iam domain list]
        { 'data' => [{ 'id' => 'd1', 'url' => 'https://domain.example' }] }
      else
        pages.shift || raise('unexpected request')
      end
    end
  end
  let(:client) { described_class.new(Anyspec::Config.new, runner: runner, page_size: 2, max_pages: 3) }

  def page(ids, total: ids.size, start: 1)
    { 'status' => '200 OK', 'data' => { 'totalResults' => total, 'startIndex' => start, 'itemsPerPage' => ids.size, 'Resources' => ids.map { |id| { 'id' => id } } } }
  end

  before { client.call(%w[iam domain list --compartment-id tenant]) }

  it 'advances by actual page length and memoizes the complete collection' do
    pages.concat([page(%w[a b], total: 3), page(%w[c], total: 3, start: 3)])
    expect(client.list('https://domain.example', 'Policies').size).to eq(3)
    expect(client.list('https://domain.example', 'Policies').size).to eq(3)
    expect(calls.size).to eq(3)
    queries = calls.drop(1).map { |a| URI.decode_www_form(URI(a[a.index('--target-uri') + 1]).query).to_h }
    expect(queries.map { |q| q['startIndex'] }).to eq(%w[1 3])
    expect(queries.first['attributes']).to eq('rules')
  end

  it 'detects total changes and caches the failure' do
    pages.concat([page(%w[a b], total: 3), page(%w[c], total: 4, start: 3)])
    2.times { expect { client.list('https://domain.example', 'Rules') }.to raise_error(/totalResults changed/) }
    expect(calls.size).to eq(3)
  end

  it 'rejects duplicate IDs, wrong offsets, truncated pages and missing envelopes' do
    [page(%w[a a]), page(%w[a], start: 2), page([], total: 2), { 'status' => '200 OK', 'data' => {} }].each do |response|
      c = described_class.new(Anyspec::Config.new, runner: runner)
      c.call(%w[iam domain list --compartment-id tenant])
      pages << response
      expect { c.list('https://domain.example', 'Rules') }.to raise_error(Anyspec::DSL::Error)
    end
  end

  it 'accepts a real empty collection but not an absent resource array for a nonempty collection' do
    pages << { 'status' => '200 OK', 'data' => { 'totalResults' => 0 } }
    expect(client.list('https://domain.example', 'Rules')).to eq([])
    pages << { 'status' => '200 OK', 'data' => { 'totalResults' => 1 } }
    expect { client.list('https://domain.example', 'Policies') }.to raise_error(/Resources/)
  end

  it 'rejects writes, dangerous flags, unknown endpoints and unfiltered identity scans' do
    [ %w[iam domain delete], %w[iam domain list --endpoint evil], %w[raw-request --http-method POST], %w[iam domain list --compartment-id --debug] ].each do |args|
      expect { client.call(args) }.to raise_error(Anyspec::DSL::Error)
    end
    expect { client.list('https://evil.example', 'Rules') }.to raise_error(/not discovered/)
    expect { client.list('https://domain.example', 'Users') }.to raise_error(/unfiltered/)
    expect { client.list('https://domain.example', 'Groups') }.to raise_error(/unfiltered/)
  end

  it 'only downgrades explicit optional get 404; never a 403 or list 404' do
    pages << { 'status' => '404 Not Found' }
    expect(client.get('https://domain.example', 'Users', 'u1', optional: true)).to be_nil
    pages << { 'status' => '403 Forbidden' }
    expect { client.get('https://domain.example', 'Users', 'u2', optional: true) }.to raise_error(/403/)
    pages << { 'status' => '404 Not Found' }
    expect { client.list('https://domain.example', 'Policies') }.to raise_error(/404/)
  end

  it 'does not send pagination parameters to singleton settings collections' do
    pages << page(['s1'])
    client.list('https://domain.example', 'SsoSettings')
    uri = calls.last[calls.last.index('--target-uri') + 1]
    expect(uri).not_to include('startIndex', 'count=', 'sortBy')
  end

  it 'traverses only referenced groups, handles cycles and warns on missing groups' do
    pages.concat([
      { 'status' => '200 OK', 'data' => { 'id' => 'g1', 'members' => [{ 'type' => 'Group', 'value' => 'g2' }, { 'type' => 'Group', 'value' => 'gone' }] } },
      { 'status' => '200 OK', 'data' => { 'id' => 'g2', 'members' => [{ 'type' => 'Group', 'value' => 'g1' }] } },
      { 'status' => '404 Not Found' }
    ])
    warnings = []
    result = client.groups('https://domain.example', ['g1'], ->(*args) { warnings << args })
    expect(result.map { |g| g['id'] }).to eq(%w[g1 g2])
    expect(warnings).to eq([['MISSING_REFERENCE', 'Groups/gone']])
    expect(calls.size).to eq(4)
  end
end

RSpec.describe 'IAM raw list pagination' do
  let(:pages) { [] }
  let(:calls) { [] }
  let(:client) do
    runner = ->(argv) { calls << argv; pages.shift || raise('unexpected call') }
    Anyspec::DSL::OCI.new(Anyspec::Config.new, runner: runner, max_pages: 2)
  end
  let(:params) { { 'compartmentId' => 'tenant' } }
  let(:endpoint) { 'https://identity.example' }

  it 'distinguishes a successful empty array from missing data' do
    pages << { 'status' => '200 OK', 'headers' => {}, 'data' => [] }
    expect(client.iam_list(endpoint, 'domains', params)).to eq([])
    pages << { 'status' => '200 OK', 'headers' => {} }
    expect { client.iam_list(endpoint, 'compartments', params) }.to raise_error(/data must be an array/)
  end

  it 'follows opaque page tokens and registers discovered domain origins' do
    pages.concat([
      { 'status' => '200 OK', 'headers' => { 'opc-next-page' => 'a+/=' }, 'data' => [{ 'id' => 'd1', 'url' => 'https://d.example' }] },
      { 'status' => '200 OK', 'headers' => {}, 'data' => [] },
      { 'status' => '200 OK', 'data' => { 'totalResults' => 0 } }
    ])
    expect(client.iam_list(endpoint, 'domains', params).size).to eq(1)
    expect(client.list('https://d.example', 'Policies')).to eq([])
    uri = URI(calls[1][calls[1].index('--target-uri') + 1])
    expect(URI.decode_www_form(uri.query).to_h['page']).to eq('a+/=')
  end

  it 'fails on repeated page tokens and memoizes failures' do
    pages.concat([
      { 'status' => '200 OK', 'headers' => { 'opc-next-page' => 'same' }, 'data' => [{ 'id' => 'a' }] },
      { 'status' => '200 OK', 'headers' => { 'opc-next-page' => 'same' }, 'data' => [{ 'id' => 'b' }] }
    ])
    2.times { expect { client.iam_list(endpoint, 'domains', params) }.to raise_error(/repeated IAM page token/) }
    expect(calls.size).to eq(2)
  end

  it 'fails when a distinct next page exceeds the page budget' do
    pages.concat([
      { 'status' => '200 OK', 'headers' => { 'opc-next-page' => 'one' }, 'data' => [{ 'id' => 'a' }] },
      { 'status' => '200 OK', 'headers' => { 'opc-next-page' => 'two' }, 'data' => [{ 'id' => 'b' }] }
    ])
    expect { client.iam_list(endpoint, 'domains', params) }.to raise_error(/IAM page limit/)
  end
end
