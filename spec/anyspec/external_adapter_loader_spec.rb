# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'

RSpec.describe Anyspec::ExternalAdapterLoader do
  around do |example|
    saved_registry = Anyspec::AdapterRegistry.registry.dup
    saved_external = Anyspec::AdapterRegistry.external_definitions.dup
    saved_files = Anyspec::AdapterRegistry.loaded_definition_files.dup
    saved_overrides = Anyspec::AdapterRegistry.overridden_builtins.dup
    example.run
  ensure
    Anyspec::AdapterRegistry.instance_variable_set(:@registry, saved_registry)
    Anyspec::AdapterRegistry.instance_variable_set(:@external_definitions, saved_external)
    Anyspec::AdapterRegistry.instance_variable_set(:@loaded_definition_files, saved_files)
    Anyspec::AdapterRegistry.instance_variable_set(:@overridden_builtins, saved_overrides)
  end

  describe '#load_all' do
    context 'with multi-type YAML file' do
      it 'loads multiple adapter types from one file' do
        Dir.mktmpdir do |tmpdir|
          File.write(File.join(tmpdir, 'adapters.yml'), <<~YAML)
            schema_version: "1.0"
            adapters:
              - type: resource_type_1
                locators:
                  - subcommand: service1 get
                    required_fields: [id]
                    flag_mappings:
                      id: --id
              - type: resource_type_2
                locators:
                  - subcommand: service2 list
                    required_fields: [compartment_id]
                    flag_mappings:
                      compartment_id: --compartment-id
          YAML

          loader = described_class.new(adapters_dir: tmpdir)
          types = loader.load_all

          expect(types.keys).to contain_exactly('resource_type_1', 'resource_type_2')
          expect(Anyspec::AdapterRegistry.registered?('resource_type_1')).to be true
          expect(Anyspec::AdapterRegistry.registered?('resource_type_2')).to be true
        end
      end

      it 'records which files were loaded' do
        Dir.mktmpdir do |tmpdir|
          adapter_file = File.join(tmpdir, 'adapters.yml')
          File.write(adapter_file, <<~YAML)
            schema_version: "1.0"
            adapters:
              - type: test_type
                locators:
                  - subcommand: test get
                    required_fields: [id]
                    flag_mappings: { id: --id }
          YAML

          loader = described_class.new(adapters_dir: tmpdir)
          loader.load_all

          expect(Anyspec::AdapterRegistry.loaded_definition_files).to include(adapter_file)
        end
      end
    end

    context 'with schema version' do
      it 'accepts valid schema version' do
        Dir.mktmpdir do |tmpdir|
          File.write(File.join(tmpdir, 'versioned.yml'), <<~YAML)
            schema_version: "1.0"
            adapters:
              - type: versioned_type
                locators:
                  - subcommand: test get
                    required_fields: [id]
                    flag_mappings: { id: --id }
          YAML

          loader = described_class.new(adapters_dir: tmpdir)
          expect { loader.load_all }.not_to raise_error
        end
      end

      it 'rejects unsupported major schema version' do
        Dir.mktmpdir do |tmpdir|
          File.write(File.join(tmpdir, 'future.yml'), <<~YAML)
            schema_version: "99.0"
            adapters:
              - type: future_type
                locators:
                  - subcommand: test get
                    required_fields: [id]
                    flag_mappings: { id: --id }
          YAML

          loader = described_class.new(adapters_dir: tmpdir)
          expect { loader.load_all }.to output(/Unsupported schema version/).to_stderr
        end
      end
    end

    context 'with search path precedence' do
      it 'higher-priority directories win on type-name conflicts' do
        Dir.mktmpdir do |high_priority_dir|
          Dir.mktmpdir do |low_priority_dir|
            File.write(File.join(high_priority_dir, 'adapters.yml'), <<~YAML)
              adapters:
                - type: conflicting_type
                  description: high priority version
                  locators:
                    - subcommand: high command
                      required_fields: [id]
                      flag_mappings: { id: --id }
            YAML

            File.write(File.join(low_priority_dir, 'adapters.yml'), <<~YAML)
              adapters:
                - type: conflicting_type
                  description: low priority version
                  locators:
                    - subcommand: low command
                      required_fields: [id]
                      flag_mappings: { id: --id }
            YAML

            dirs = "#{high_priority_dir}#{File::PATH_SEPARATOR}#{low_priority_dir}"
            loader = described_class.new(adapters_dir: dirs)
            types = loader.load_all

            expect(types['conflicting_type'][:definition]['description']).to eq('high priority version')
          end
        end
      end

      it 'uses File::PATH_SEPARATOR for multiple directories' do
        Dir.mktmpdir do |dir1|
          Dir.mktmpdir do |dir2|
            File.write(File.join(dir1, 'a.yml'), <<~YAML)
              adapters:
                - type: type_a
                  locators:
                    - subcommand: cmd a
                      required_fields: [id]
                      flag_mappings: { id: --id }
            YAML

            File.write(File.join(dir2, 'b.yml'), <<~YAML)
              adapters:
                - type: type_b
                  locators:
                    - subcommand: cmd b
                      required_fields: [id]
                      flag_mappings: { id: --id }
            YAML

            dirs = "#{dir1}#{File::PATH_SEPARATOR}#{dir2}"
            loader = described_class.new(adapters_dir: dirs)
            types = loader.load_all

            expect(types.keys).to contain_exactly('type_a', 'type_b')
          end
        end
      end
    end

    context 'with built-in adapter override' do
      it 'reports when overriding a built-in adapter' do
        Anyspec::AdapterRegistry.reset!

        builtin_adapter = Class.new(Anyspec::Adapters::Base)
        Anyspec::AdapterRegistry.register('test_builtin', builtin_adapter, priority: :builtin)

        Dir.mktmpdir do |tmpdir|
          File.write(File.join(tmpdir, 'override.yml'), <<~YAML)
            adapters:
              - type: test_builtin
                description: overridden version
                locators:
                  - subcommand: override cmd
                    required_fields: [id]
                    flag_mappings: { id: --id }
          YAML

          loader = described_class.new(adapters_dir: tmpdir)
          loader.load_all

          info = Anyspec::AdapterRegistry.external_adapter_info
          overrides = info[:overridden_builtins]

          expect(overrides.any? { |o| o[:type] == 'test_builtin' }).to be true
          expect(Anyspec::AdapterRegistry.external?('test_builtin')).to be true
        end
      end
    end

    context 'with invalid definitions' do
      it 'skips files with YAML syntax errors' do
        Dir.mktmpdir do |tmpdir|
          File.write(File.join(tmpdir, 'invalid.yml'), "invalid: yaml: content:\n  - broken")

          loader = described_class.new(adapters_dir: tmpdir)

          expect { loader.load_all }.to output(/Warning.*Failed to parse/).to_stderr
        end
      end

      it 'skips definitions missing type field' do
        Dir.mktmpdir do |tmpdir|
          File.write(File.join(tmpdir, 'no_type.yml'), <<~YAML)
            adapters:
              - locators:
                  - subcommand: test
                    required_fields: [id]
          YAML

          loader = described_class.new(adapters_dir: tmpdir)

          expect { loader.load_all }.to output(/Warning.*Invalid/).to_stderr
        end
      end

      it 'rejects definitions with potential shell injection' do
        Dir.mktmpdir do |tmpdir|
          File.write(File.join(tmpdir, 'dangerous.yml'), <<~YAML)
            adapters:
              - type: dangerous
                locators:
                  - subcommand: test `whoami`
                    required_fields: [id]
                    flag_mappings: { id: --id }
          YAML

          loader = described_class.new(adapters_dir: tmpdir)

          expect { loader.load_all }.to output(/Warning.*shell injection/).to_stderr
        end
      end
    end

    context 'with YAML safe loading' do
      it 'neutralizes unsafe Ruby object tags to scalar values' do
        Dir.mktmpdir do |tmpdir|
          File.write(File.join(tmpdir, 'tagged.yml'), <<~YAML)
            adapters:
              - type: tagged_type
                locators:
                  - subcommand: !ruby/object:Gem::Installer test
                    required_fields: [id]
                    flag_mappings: { id: --id }
          YAML

          loader = described_class.new(adapters_dir: tmpdir)
          loader.load_all

          type_info = loader.loaded_types['tagged_type']
          expect(type_info).not_to be_nil
          locator = type_info[:definition]['locators'].first
          expect(locator['subcommand']).to eq('test')
          expect(locator['subcommand']).to be_a(String)
        end
      end

      it 'rejects Date class in YAML and does not load the type' do
        Dir.mktmpdir do |tmpdir|
          File.write(File.join(tmpdir, 'date.yml'), <<~YAML)
            adapters:
              - type: date_type
                created: 2024-01-01
                locators:
                  - subcommand: test
                    required_fields: [id]
                    flag_mappings: { id: --id }
          YAML

          loader = described_class.new(adapters_dir: tmpdir)

          expect { loader.load_all }.to output(/Warning.*Unsafe YAML class.*Date/).to_stderr
          expect(loader.loaded_types).to be_empty
        end
      end

      it 'loads valid YAML with permitted types only' do
        Dir.mktmpdir do |tmpdir|
          File.write(File.join(tmpdir, 'valid.yml'), <<~YAML)
            schema_version: "1.0"
            adapters:
              - type: valid_type
                enabled: true
                count: 42
                tags:
                  - production
                  - secure
                locators:
                  - subcommand: test get
                    required_fields: [id]
                    flag_mappings: { id: --id }
          YAML

          loader = described_class.new(adapters_dir: tmpdir)
          loader.load_all

          type_info = loader.loaded_types['valid_type']
          expect(type_info[:definition]['enabled']).to be true
          expect(type_info[:definition]['count']).to eq(42)
          expect(type_info[:definition]['tags']).to eq(['production', 'secure'])
        end
      end

      it 'supports multi-document YAML files safely' do
        Dir.mktmpdir do |tmpdir|
          File.write(File.join(tmpdir, 'multi_doc.yml'), <<~YAML)
            adapters:
              - type: doc1_type
                locators:
                  - subcommand: doc1 get
                    required_fields: [id]
                    flag_mappings: { id: --id }
            ---
            adapters:
              - type: doc2_type
                locators:
                  - subcommand: doc2 get
                    required_fields: [id]
                    flag_mappings: { id: --id }
          YAML

          loader = described_class.new(adapters_dir: tmpdir)
          types = loader.load_all

          expect(types.keys).to contain_exactly('doc1_type', 'doc2_type')
        end
      end
    end

    context 'with missing directories' do
      it 'ignores non-existent directories without error' do
        loader = described_class.new(adapters_dir: '/nonexistent/path/12345')

        expect { loader.load_all }.not_to raise_error
        expect(loader.loaded_types).to be_empty
      end
    end
  end

  describe '.schema_version' do
    it 'returns the current schema version' do
      expect(described_class.schema_version).to eq('1.0')
    end
  end

  describe 'search paths' do
    it 'builds portable paths using File.join' do
      Dir.mktmpdir do |tmpdir|
        project_adapters = File.join(tmpdir, '.anyspec', 'adapters')
        FileUtils.mkdir_p(project_adapters)

        original_pwd = Dir.pwd
        begin
          Dir.chdir(tmpdir)

          loader = described_class.new
          loader.load_all

          expect(loader.search_paths).to include(project_adapters)
        ensure
          Dir.chdir(original_pwd)
        end
      end
    end
  end

  describe 'no Class.new per type' do
    it 'uses single GenericCli class for all external types' do
      Dir.mktmpdir do |tmpdir|
        File.write(File.join(tmpdir, 'multi.yml'), <<~YAML)
          adapters:
            - type: type_one
              locators:
                - subcommand: one get
                  required_fields: [id]
                  flag_mappings: { id: --id }
            - type: type_two
              locators:
                - subcommand: two get
                  required_fields: [id]
                  flag_mappings: { id: --id }
        YAML

        loader = described_class.new(adapters_dir: tmpdir)
        loader.load_all

        type_one_class = Anyspec::AdapterRegistry.get('type_one')
        type_two_class = Anyspec::AdapterRegistry.get('type_two')

        expect(type_one_class).to eq(Anyspec::Adapters::GenericCli)
        expect(type_two_class).to eq(Anyspec::Adapters::GenericCli)
        expect(type_one_class).to eq(type_two_class)
      end
    end
  end
end
