# frozen_string_literal: true

require 'spec_helper'
require 'open3'

RSpec.describe Anyspec::Adapters::GenericCli do
  let(:config) do
    instance_double(
      Anyspec::Config,
      oci_cli_path: '/usr/bin/oci',
      profile: 'DEFAULT',
      config_path: nil,
      auth_mode: 'config_file',
      region: nil
    )
  end

  let(:adapter) { described_class.new(config) }

  before do
    Anyspec::AdapterRegistry.reset!
  end

  after do
    Anyspec::AdapterRegistry.reset!
  end

  describe '#fetch' do
    context 'with a registered external definition' do
      let(:definition) do
        {
          'type' => 'test_resource',
          'locators' => [
            {
              'subcommand' => 'test service get',
              'required_fields' => ['resource_id'],
              'flag_mappings' => {
                'resource_id' => '--resource-id'
              },
              'extract_fields' => %w[id name status]
            }
          ]
        }
      end

      let(:cli_output) do
        {
          'data' => {
            'id' => 'ocid1.test',
            'display-name' => 'TestResource',
            'lifecycle-state' => 'ACTIVE'
          }
        }.to_json
      end

      before do
        Anyspec::AdapterRegistry.register_external_definition('test_resource', definition, source_file: '/test/adapters.yml')
        allow(Open3).to receive(:capture3).and_return([cli_output, '', instance_double(Process::Status, success?: true)])
      end

      it 'executes OCI CLI using config.oci_cli_path' do
        spec = { 'type' => 'test_resource', 'resource_id' => 'ocid1.test' }
        adapter.fetch(spec)

        expect(Open3).to have_received(:capture3) do |*args|
          expect(args.first).to eq('/usr/bin/oci')
        end
      end

      it 'builds correct argv array (no shell string)' do
        spec = { 'type' => 'test_resource', 'resource_id' => 'ocid1.test' }
        adapter.fetch(spec)

        expect(Open3).to have_received(:capture3) do |*args|
          expect(args).to be_an(Array)
          expect(args).to include('test')
          expect(args).to include('service')
          expect(args).to include('get')
          expect(args).to include('--resource-id')
          expect(args).to include('ocid1.test')
          expect(args).to include('--output')
          expect(args).to include('json')
        end
      end

      it 'normalizes kebab-case to snake_case' do
        spec = { 'type' => 'test_resource', 'resource_id' => 'ocid1.test' }

        definition_with_kebab = definition.dup
        definition_with_kebab['locators'][0]['extract_fields'] = %w[id display_name lifecycle_state]
        Anyspec::AdapterRegistry.register_external_definition('test_resource', definition_with_kebab, source_file: '/test/adapters.yml')

        result = adapter.fetch(spec)

        expect(result['display_name']).to eq('TestResource')
        expect(result['lifecycle_state']).to eq('ACTIVE')
      end
    end

    context 'with alternative locators (get-by-id vs list-by-name)' do
      let(:definition) do
        {
          'type' => 'target_resource',
          'locators' => [
            {
              'subcommand' => 'service target get',
              'required_fields' => %w[compartment_id target_id],
              'flag_mappings' => {
                'compartment_id' => '--compartment-id',
                'target_id' => '--target-id'
              },
              'extract_fields' => %w[id display_name]
            },
            {
              'subcommand' => 'service target list',
              'required_fields' => %w[compartment_id name],
              'flag_mappings' => {
                'compartment_id' => '--compartment-id'
              },
              'static_flags' => [{ '--limit' => '100' }],
              'list_filter_field' => 'display-name',
              'list_filter_spec_field' => 'name',
              'extract_fields' => %w[id display_name]
            }
          ]
        }
      end

      before do
        Anyspec::AdapterRegistry.register_external_definition('target_resource', definition, source_file: '/test/adapters.yml')
      end

      it 'uses get locator when target_id is provided' do
        get_output = { 'data' => { 'id' => 'target1', 'display-name' => 'Target 1' } }.to_json
        allow(Open3).to receive(:capture3).and_return([get_output, '', instance_double(Process::Status, success?: true)])

        spec = { 'type' => 'target_resource', 'compartment_id' => 'ocid1.comp', 'target_id' => 'ocid1.target' }
        adapter.fetch(spec)

        expect(Open3).to have_received(:capture3) do |*args|
          expect(args).to include('get')
          expect(args).to include('--target-id')
        end
      end

      it 'uses list locator when name is provided instead of target_id' do
        list_output = {
          'data' => [
            { 'id' => 'target1', 'display-name' => 'Target 1' },
            { 'id' => 'target2', 'display-name' => 'Target 2' }
          ]
        }.to_json
        allow(Open3).to receive(:capture3).and_return([list_output, '', instance_double(Process::Status, success?: true)])

        spec = { 'type' => 'target_resource', 'compartment_id' => 'ocid1.comp', 'name' => 'Target 1' }
        adapter.fetch(spec)

        expect(Open3).to have_received(:capture3) do |*args|
          expect(args).to include('list')
          expect(args).to include('--limit')
          expect(args).to include('100')
        end
      end

      it 'filters list results by name' do
        list_output = {
          'data' => [
            { 'id' => 'target1', 'display-name' => 'Target 1' },
            { 'id' => 'target2', 'display-name' => 'Target 2' }
          ]
        }.to_json
        allow(Open3).to receive(:capture3).and_return([list_output, '', instance_double(Process::Status, success?: true)])

        spec = { 'type' => 'target_resource', 'compartment_id' => 'ocid1.comp', 'name' => 'Target 2' }
        result = adapter.fetch(spec)

        expect(result['id']).to eq('target2')
        expect(result['display_name']).to eq('Target 2')
      end
    end

    context 'with auth modes' do
      let(:definition) do
        {
          'type' => 'auth_test',
          'locators' => [{
            'subcommand' => 'test get',
            'required_fields' => ['id'],
            'flag_mappings' => { 'id' => '--id' }
          }]
        }
      end

      before do
        Anyspec::AdapterRegistry.register_external_definition('auth_test', definition, source_file: '/test/adapters.yml')
        allow(Open3).to receive(:capture3).and_return(['{"data":{}}', '', instance_double(Process::Status, success?: true)])
      end

      it 'adds --auth flag for instance_principal' do
        ip_config = instance_double(
          Anyspec::Config,
          oci_cli_path: 'oci',
          profile: 'DEFAULT',
          config_path: nil,
          auth_mode: 'instance_principal',
          region: nil
        )
        adapter = described_class.new(ip_config)

        adapter.fetch({ 'type' => 'auth_test', 'id' => 'test' })

        expect(Open3).to have_received(:capture3) do |*args|
          expect(args).to include('--auth')
          expect(args).to include('instance_principal')
          expect(args).not_to include('--config-file')
        end
      end

      it 'does not add --config-file for instance_principal' do
        ip_config = instance_double(
          Anyspec::Config,
          oci_cli_path: 'oci',
          profile: 'DEFAULT',
          config_path: nil,
          auth_mode: 'instance_principal',
          region: nil
        )
        adapter = described_class.new(ip_config)

        adapter.fetch({ 'type' => 'auth_test', 'id' => 'test' })

        expect(Open3).to have_received(:capture3) do |*args|
          expect(args).not_to include('--config-file')
        end
      end
    end

    context 'with no matching locator' do
      let(:definition) do
        {
          'type' => 'strict_resource',
          'locators' => [{
            'subcommand' => 'test get',
            'required_fields' => %w[required_field_1 required_field_2],
            'flag_mappings' => {}
          }]
        }
      end

      before do
        Anyspec::AdapterRegistry.register_external_definition('strict_resource', definition, source_file: '/test/adapters.yml')
      end

      it 'raises error when no locator matches' do
        spec = { 'type' => 'strict_resource', 'required_field_1' => 'value' }

        expect { adapter.fetch(spec) }.to raise_error(Anyspec::Error, /No matching locator/)
      end
    end
  end
end
