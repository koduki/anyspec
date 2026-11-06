# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'

RSpec.describe Anyspec::Validator do
  let(:validator) { described_class.new }
  let(:fixtures_path) { File.expand_path('../fixtures', __dir__) }

  describe '#validate' do
    context 'with valid spec file' do
      it 'returns true for valid specs with env vars set' do
        ENV['TEST_COMPARTMENT_ID'] = 'ocid1.test'

        result = validator.validate(File.join(fixtures_path, 'spec_with_env.yml'))

        expect(result).to be true
        expect(validator.errors).to be_empty

        ENV.delete('TEST_COMPARTMENT_ID')
      end
    end

    context 'with missing required fields' do
      it 'returns false and reports missing fields' do
        Dir.mktmpdir do |tmpdir|
          spec_file = File.join(tmpdir, 'invalid.yml')
          File.write(spec_file, <<~YAML)
            - id: missing-fields
              title: Missing Fields Test
          YAML

          result = validator.validate(spec_file)

          expect(result).to be false
          expect(validator.errors.any? { |e| e.code == 'MISSING_FIELD' }).to be true
          expect(validator.error_messages.join).to include('cloud')
          expect(validator.error_messages.join).to include('type')
          expect(validator.error_messages.join).to include('expect')
        end
      end
    end

    context 'with unknown adapter type' do
      it 'returns false and reports unknown adapter' do
        Dir.mktmpdir do |tmpdir|
          spec_file = File.join(tmpdir, 'unknown_adapter.yml')
          File.write(spec_file, <<~YAML)
            - id: unknown-adapter
              title: Unknown Adapter Test
              cloud: oci
              type: nonexistent_adapter_type
              expect:
                status: ENABLED
          YAML

          result = validator.validate(spec_file)

          expect(result).to be false
          expect(validator.errors.any? { |e| e.code == 'UNKNOWN_ADAPTER' }).to be true
          expect(validator.error_messages.join).to include('nonexistent_adapter_type')
        end
      end
    end

    context 'with duplicate IDs' do
      it 'returns false and reports duplicates' do
        Dir.mktmpdir do |tmpdir|
          spec_file = File.join(tmpdir, 'duplicates.yml')
          File.write(spec_file, <<~YAML)
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

          result = validator.validate(spec_file)

          expect(result).to be false
          expect(validator.errors.any? { |e| e.code == 'DUPLICATE_ID' }).to be true
          expect(validator.error_messages.join).to include('duplicate-id')
        end
      end
    end

    context 'with invalid until date' do
      it 'returns false for non-date string' do
        Dir.mktmpdir do |tmpdir|
          spec_file = File.join(tmpdir, 'invalid_until.yml')
          File.write(spec_file, <<~YAML)
            - id: invalid-until
              title: Invalid Until Test
              cloud: oci
              type: cloud_guard_configuration
              until: "not-a-date"
              expect:
                status: ENABLED
          YAML

          result = validator.validate(spec_file)

          expect(result).to be false
          expect(validator.errors.any? { |e| e.code == 'INVALID_UNTIL' }).to be true
        end
      end

      it 'accepts valid date string' do
        Dir.mktmpdir do |tmpdir|
          spec_file = File.join(tmpdir, 'valid_until.yml')
          File.write(spec_file, <<~YAML)
            - id: valid-until
              title: Valid Until Test
              cloud: oci
              type: cloud_guard_configuration
              until: "2027-12-31"
              expect:
                status: ENABLED
          YAML

          result = validator.validate(spec_file)

          expect(result).to be true
        end
      end
    end

    context 'with missing environment variables' do
      it 'returns false and reports missing env vars' do
        ENV.delete('MISSING_VAR_123')

        Dir.mktmpdir do |tmpdir|
          spec_file = File.join(tmpdir, 'missing_env.yml')
          File.write(spec_file, <<~YAML)
            - id: missing-env
              title: Missing Env Test
              cloud: oci
              type: cloud_guard_configuration
              compartment_id: ${MISSING_VAR_123}
              expect:
                status: ENABLED
          YAML

          result = validator.validate(spec_file)

          expect(result).to be false
          expect(validator.errors.any? { |e| e.code == 'MISSING_ENV_VAR' }).to be true
          expect(validator.error_messages.join).to include('MISSING_VAR_123')
        end
      end
    end

    context 'with YAML syntax error' do
      it 'returns false and reports syntax error' do
        Dir.mktmpdir do |tmpdir|
          spec_file = File.join(tmpdir, 'syntax_error.yml')
          File.write(spec_file, "invalid: yaml: content:\n  - broken")

          result = validator.validate(spec_file)

          expect(result).to be false
          expect(validator.errors.any? { |e| e.code == 'YAML_SYNTAX' }).to be true
        end
      end
    end

    context 'with file not found' do
      it 'returns false and reports file not found' do
        result = validator.validate('/nonexistent/path/spec.yml')

        expect(result).to be false
        expect(validator.errors.any? { |e| e.code == 'FILE_NOT_FOUND' }).to be true
      end
    end

    context 'with directory' do
      it 'validates all YAML files in directory' do
        ENV['TEST_COMPARTMENT_ID'] = 'ocid1.test'

        result = validator.validate(fixtures_path)

        expect(validator.loaded_specs.size).to be >= 3

        ENV.delete('TEST_COMPARTMENT_ID')
      end

      it 'warns when directory has no YAML files' do
        Dir.mktmpdir do |tmpdir|
          result = validator.validate(tmpdir)

          expect(result).to be true
          expect(validator.warnings.any? { |w| w.code == 'NO_SPECS' }).to be true
        end
      end
    end
  end

  describe '#error_messages' do
    it 'formats errors with file path, code, and message' do
      Dir.mktmpdir do |tmpdir|
        spec_file = File.join(tmpdir, 'test.yml')
        File.write(spec_file, <<~YAML)
          - id: test
            title: Test
        YAML

        validator.validate(spec_file)

        messages = validator.error_messages
        expect(messages.first).to include('[MISSING_FIELD]')
        expect(messages.first).to include('test.yml')
      end
    end
  end
end
