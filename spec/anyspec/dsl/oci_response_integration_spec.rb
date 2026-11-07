# frozen_string_literal: true

require 'spec_helper'
require 'anyspec/dsl/runner'
require 'tmpdir'
require 'rbconfig'

RSpec.describe 'OCI responses through a real subprocess' do
  def with_oci_output(response)
    skip 'executable Ruby scripts require a POSIX host' if Gem.win_platform?
    Dir.mktmpdir do |dir|
      cli = File.join(dir, 'oci')
      File.write(cli, "#!#{RbConfig.ruby}\nprint #{JSON.generate(response).dump}\n")
      File.chmod(0o755, cli)
      runner = Anyspec::DSL::Runner.new(config: Anyspec::Config.new(oci_cli: cli))
      yield runner
    end
  end

  it 'retains and parses the SsoSettings raw-request body' do
    fixture = JSON.parse(File.read(File.expand_path('../../fixtures/oci/sso_settings_raw.json', __dir__)))
    with_oci_output(fixture) do |runner|
      result = runner.run_source("oci_raw_get 'https://example.test' '/admin/v1/SsoSettings'")
      expect(result.map { |item| item['id'] }).to eq(['SsoSettingsId'])
    end
  end

  it 'accepts an already parsed raw-request body' do
    response = { 'status' => '200 OK', 'data' => { 'Resources' => [{ 'id' => 'sso' }] } }
    with_oci_output(response) do |runner|
      expect(runner.run_source("oci_raw_get 'https://example.test' '/admin/v1/SsoSettings'"))
        .to eq([{ 'id' => 'sso' }])
    end
  end

  it 'rejects non-success HTTP status and malformed raw JSON' do
    [
      { 'status' => '403 Forbidden', 'data' => {} },
      { 'status' => '200 OK', 'data' => '{broken' }
    ].each do |response|
      with_oci_output(response) do |runner|
        expect { runner.run_source("oci_raw_get 'https://example.test' '/admin/v1/SsoSettings'") }
          .to raise_error(Anyspec::DSL::RuntimeError)
      end
    end
  end

  it 'validates opc-total-items retained from a SCIM --all response' do
    response = { 'data' => { 'resources' => [{ 'id' => 'one' }] }, 'opc-total-items' => '2' }
    with_oci_output(response) do |runner|
      expect { runner.run_source("oci_domain_list 'https://example.test' 'apps' null") }
        .to raise_error(Anyspec::DSL::RuntimeError, /Count mismatch/)
    end
  end

  it 'extracts singleton list items from the retained envelope' do
    response = { 'data' => { 'resources' => [{ 'id' => 'mfa', 'sms-enabled' => true }] }, 'opc-total-items' => '1' }
    with_oci_output(response) do |runner|
      expect(runner.run_source("oci_domain_singleton 'https://example.test' 'authentication-factor-settings'"))
        .to eq([{ 'id' => 'mfa', 'sms-enabled' => true }])
    end
  end
end
