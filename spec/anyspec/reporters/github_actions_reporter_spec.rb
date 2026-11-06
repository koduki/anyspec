# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'

RSpec.describe Anyspec::Reporters::GitHubActionsReporter do
  let(:pass_result) do
    Anyspec::Result.new(
      id: 'pass-test',
      title: 'Pass Test',
      intent: 'Test intent',
      owner: 'test-team',
      status: :pass,
      expected: { 'status' => 'ENABLED' },
      actual: { 'status' => 'ENABLED' },
      source_file: '/workspace/specs/test.yml'
    )
  end

  let(:fail_result) do
    Anyspec::Result.new(
      id: 'fail-test',
      title: 'Fail Test',
      intent: 'Test intent for fail',
      owner: 'security',
      note: 'Important note',
      status: :fail,
      expected: { 'status' => 'ENABLED' },
      actual: { 'status' => 'DISABLED' },
      message: "status: expected 'ENABLED', got 'DISABLED'",
      mismatches: [{ path: 'status', expected: 'ENABLED', actual: 'DISABLED' }],
      source_file: '/workspace/specs/fail.yml'
    )
  end

  let(:error_result) do
    Anyspec::Result.new(
      id: 'error-test',
      title: 'Error Test',
      status: :error,
      expected: { 'status' => 'ENABLED' },
      actual: nil,
      message: 'API Error: Connection refused',
      source_file: '/workspace/specs/error.yml'
    )
  end

  let(:waived_result) do
    Anyspec::Result.new(
      id: 'waived-test',
      title: 'Waived Test',
      intent: 'Temporarily waived',
      status: :pass,
      expected: { 'status' => 'ENABLED' },
      actual: { 'status' => 'DISABLED' },
      message: 'Waiver active until 2027-12-31. Mismatch: status',
      mismatches: [{ path: 'status', expected: 'ENABLED', actual: 'DISABLED' }],
      source_file: '/workspace/specs/waived.yml',
      waiver_until: '2027-12-31'
    )
  end

  let(:summary) { { total: 4, pass: 2, fail: 1, error: 1 } }
  let(:results) { [pass_result, fail_result, error_result, waived_result] }
  let(:reporter) { described_class.new(results, summary) }

  describe '.github_actions?' do
    it 'returns true when GITHUB_ACTIONS=true' do
      original = ENV['GITHUB_ACTIONS']
      ENV['GITHUB_ACTIONS'] = 'true'

      expect(described_class.github_actions?).to be true

      ENV['GITHUB_ACTIONS'] = original
    end

    it 'returns false when GITHUB_ACTIONS is not set' do
      original = ENV['GITHUB_ACTIONS']
      ENV.delete('GITHUB_ACTIONS')

      expect(described_class.github_actions?).to be false

      ENV['GITHUB_ACTIONS'] = original if original
    end
  end

  describe '.ci_context' do
    before do
      @original_env = {
        'GITHUB_ACTIONS' => ENV['GITHUB_ACTIONS'],
        'GITHUB_SHA' => ENV['GITHUB_SHA'],
        'GITHUB_RUN_ID' => ENV['GITHUB_RUN_ID'],
        'GITHUB_REF' => ENV['GITHUB_REF'],
        'GITHUB_WORKFLOW' => ENV['GITHUB_WORKFLOW'],
        'GITHUB_SERVER_URL' => ENV['GITHUB_SERVER_URL'],
        'GITHUB_REPOSITORY' => ENV['GITHUB_REPOSITORY']
      }
    end

    after do
      @original_env.each do |key, value|
        if value
          ENV[key] = value
        else
          ENV.delete(key)
        end
      end
    end

    it 'returns CI context when running in GitHub Actions' do
      ENV['GITHUB_ACTIONS'] = 'true'
      ENV['GITHUB_SHA'] = 'abc123'
      ENV['GITHUB_RUN_ID'] = '12345'
      ENV['GITHUB_REF'] = 'refs/heads/main'
      ENV['GITHUB_WORKFLOW'] = 'CI'
      ENV['GITHUB_SERVER_URL'] = 'https://github.com'
      ENV['GITHUB_REPOSITORY'] = 'koduki/anyspec'

      context = described_class.ci_context

      expect(context[:github_sha]).to eq('abc123')
      expect(context[:github_run_id]).to eq('12345')
      expect(context[:github_ref]).to eq('refs/heads/main')
      expect(context[:github_workflow]).to eq('CI')
      expect(context[:github_run_url]).to eq('https://github.com/koduki/anyspec/actions/runs/12345')
    end

    it 'returns empty hash when not in GitHub Actions' do
      ENV.delete('GITHUB_ACTIONS')

      expect(described_class.ci_context).to eq({})
    end
  end

  describe '#write_step_summary' do
    it 'writes markdown to GITHUB_STEP_SUMMARY file' do
      Dir.mktmpdir do |tmpdir|
        summary_file = File.join(tmpdir, 'step_summary.md')
        original = ENV['GITHUB_STEP_SUMMARY']
        ENV['GITHUB_STEP_SUMMARY'] = summary_file

        reporter.write_step_summary

        content = File.read(summary_file)
        expect(content).to include('# Anyspec チェック結果')
        expect(content).to include('pass-test')
        expect(content).to include('fail-test')
        expect(content).to include('ウェイバー')

        ENV['GITHUB_STEP_SUMMARY'] = original
      end
    end

    it 'does nothing when GITHUB_STEP_SUMMARY is not set' do
      original = ENV['GITHUB_STEP_SUMMARY']
      ENV.delete('GITHUB_STEP_SUMMARY')

      expect { reporter.write_step_summary }.not_to raise_error

      ENV['GITHUB_STEP_SUMMARY'] = original if original
    end
  end

  describe '#emit_workflow_commands' do
    before do
      @original_workspace = ENV['GITHUB_WORKSPACE']
      ENV['GITHUB_WORKSPACE'] = '/workspace'
    end

    after do
      ENV['GITHUB_WORKSPACE'] = @original_workspace
    end

    it 'emits ::error for failed results' do
      single_fail_reporter = described_class.new([fail_result], { total: 1, pass: 0, fail: 1, error: 0 })

      expect { single_fail_reporter.emit_workflow_commands }
        .to output(/::error file=specs\/fail\.yml::\[fail-test\]/).to_stdout
    end

    it 'emits ::error for error results' do
      single_error_reporter = described_class.new([error_result], { total: 1, pass: 0, fail: 0, error: 1 })

      expect { single_error_reporter.emit_workflow_commands }
        .to output(/::error file=specs\/error\.yml::\[error-test\]/).to_stdout
    end

    it 'emits ::notice for waived results' do
      single_waived_reporter = described_class.new([waived_result], { total: 1, pass: 1, fail: 0, error: 0 })

      expect { single_waived_reporter.emit_workflow_commands }
        .to output(/::notice file=specs\/waived\.yml::\[waived-test\].*ウェイバー中/).to_stdout
    end

    it 'does not emit commands for passing non-waived results' do
      single_pass_reporter = described_class.new([pass_result], { total: 1, pass: 1, fail: 0, error: 0 })

      expect { single_pass_reporter.emit_workflow_commands }
        .not_to output(/::error/).to_stdout
    end

    it 'includes intent and owner in annotations' do
      single_fail_reporter = described_class.new([fail_result], { total: 1, pass: 0, fail: 1, error: 0 })

      expect { single_fail_reporter.emit_workflow_commands }
        .to output(/意図.*担当/).to_stdout
    end
  end

  describe '#write_github_output' do
    it 'writes output variables to GITHUB_OUTPUT file' do
      Dir.mktmpdir do |tmpdir|
        output_file = File.join(tmpdir, 'github_output')
        original = ENV['GITHUB_OUTPUT']
        ENV['GITHUB_OUTPUT'] = output_file

        reporter.write_github_output(1)

        content = File.read(output_file)
        expect(content).to include('pass=false')
        expect(content).to include('fail=true')
        expect(content).to include('error=true')
        expect(content).to include('exit_code=1')

        ENV['GITHUB_OUTPUT'] = original
      end
    end

    it 'does nothing when GITHUB_OUTPUT is not set' do
      original = ENV['GITHUB_OUTPUT']
      ENV.delete('GITHUB_OUTPUT')

      expect { reporter.write_github_output(0) }.not_to raise_error

      ENV['GITHUB_OUTPUT'] = original if original
    end
  end
end
