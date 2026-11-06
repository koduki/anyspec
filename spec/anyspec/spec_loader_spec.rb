# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Anyspec::SpecLoader do
  let(:loader) { described_class.new }
  let(:fixtures_path) { File.expand_path('../fixtures', __dir__) }

  describe '#load' do
    context 'with a valid spec file' do
      it 'loads specs from YAML file' do
        specs = loader.load(File.join(fixtures_path, 'valid_spec.yml'))

        expect(specs).to be_an(Array)
        expect(specs.size).to eq(1)
        expect(specs.first['id']).to eq('test-cloud-guard')
        expect(specs.first['title']).to eq('Test Cloud Guard')
        expect(specs.first['type']).to eq('cloud_guard_configuration')
      end
    end

    context 'with multiple specs in one file' do
      it 'loads all specs' do
        specs = loader.load(File.join(fixtures_path, 'multiple_specs.yml'))

        expect(specs.size).to eq(2)
        expect(specs.map { |s| s['id'] }).to eq(%w[spec-one spec-two])
      end
    end

    context 'with environment variable interpolation' do
      before do
        ENV['TEST_COMPARTMENT_ID'] = 'ocid1.compartment.oc1..interpolated'
      end

      after do
        ENV.delete('TEST_COMPARTMENT_ID')
      end

      it 'interpolates environment variables' do
        specs = loader.load(File.join(fixtures_path, 'spec_with_env.yml'))

        expect(specs.first['compartment_id']).to eq('ocid1.compartment.oc1..interpolated')
      end
    end

    context 'with missing environment variable' do
      it 'raises an error' do
        ENV.delete('TEST_COMPARTMENT_ID')

        expect do
          loader.load(File.join(fixtures_path, 'spec_with_env.yml'))
        end.to raise_error(Anyspec::Error, /Environment variable not set: TEST_COMPARTMENT_ID/)
      end
    end

    context 'with a directory' do
      it 'loads all YAML files recursively' do
        specs = loader.load(fixtures_path)

        expect(specs.size).to be >= 3
      end
    end
  end

  describe 'validation' do
    it 'validates required fields' do
      invalid_yaml = <<~YAML
        - id: missing-fields
          title: Missing Fields Test
      YAML

      allow(File).to receive(:directory?).with('/tmp/invalid.yml').and_return(false)
      allow(File).to receive(:read).with('/tmp/invalid.yml').and_return(invalid_yaml)

      expect do
        loader.load('/tmp/invalid.yml')
      end.to raise_error(Anyspec::SpecValidationError, /missing required fields/)
    end

    it 'detects duplicate IDs' do
      duplicate_yaml = <<~YAML
        - id: duplicate-id
          title: First
          cloud: oci
          type: cloud_guard_configuration
          expect:
            status: ENABLED
        - id: duplicate-id
          title: Second
          cloud: oci
          type: audit_configuration
          expect:
            retention_period_days: 365
      YAML

      allow(File).to receive(:directory?).with('/tmp/duplicate.yml').and_return(false)
      allow(File).to receive(:read).with('/tmp/duplicate.yml').and_return(duplicate_yaml)

      expect do
        loader.load('/tmp/duplicate.yml')
      end.to raise_error(Anyspec::SpecValidationError, /Duplicate spec IDs/)
    end
  end
end
