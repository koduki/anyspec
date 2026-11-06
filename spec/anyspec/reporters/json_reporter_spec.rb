# frozen_string_literal: true

require 'spec_helper'
require 'json'
require 'tmpdir'

RSpec.describe Anyspec::Reporters::JsonReporter do
  let(:results) do
    [
      Anyspec::Result.new(
        id: 'test-1',
        title: 'Test One',
        intent: 'Test intent',
        note: 'Test note',
        owner: 'security',
        status: :pass,
        expected: { 'status' => 'ENABLED' },
        actual: { 'status' => 'ENABLED' },
        duration_ms: 150
      ),
      Anyspec::Result.new(
        id: 'test-2',
        title: 'Test Two',
        status: :fail,
        expected: { 'status' => 'ENABLED' },
        actual: { 'status' => 'DISABLED' },
        message: 'Status mismatch',
        mismatches: [{ path: 'status', expected: 'ENABLED', actual: 'DISABLED' }],
        duration_ms: 200
      )
    ]
  end

  let(:summary) { { total: 2, pass: 1, fail: 1, error: 0 } }
  let(:run_metadata) do
    {
      spec_paths: ['/path/to/spec.yml'],
      profile: 'DEFAULT',
      region: 'ap-tokyo-1',
      auth_mode: 'config_file',
      duration_ms: 500
    }
  end
  let(:reporter) { described_class.new(results, summary, run_metadata: run_metadata) }

  describe '#generate' do
    it 'generates valid JSON structure' do
      output = reporter.generate

      expect(output[:metadata][:tool]).to eq('anyspec')
      expect(output[:metadata][:version]).to eq(Anyspec::VERSION)
      expect(output[:metadata][:summary]).to eq(summary)
      expect(output[:results].size).to eq(2)
    end

    it 'includes run_id in metadata' do
      output = reporter.generate

      expect(output[:metadata][:run_id]).to match(/^[a-f0-9-]{36}$/)
    end

    it 'includes duration_ms in metadata' do
      output = reporter.generate

      expect(output[:metadata][:duration_ms]).to eq(500)
    end

    it 'includes profile in metadata' do
      output = reporter.generate

      expect(output[:metadata][:profile]).to eq('DEFAULT')
    end

    it 'includes region in metadata' do
      output = reporter.generate

      expect(output[:metadata][:region]).to eq('ap-tokyo-1')
    end

    it 'includes auth_mode in metadata' do
      output = reporter.generate

      expect(output[:metadata][:auth_mode]).to eq('config_file')
    end

    it 'includes spec_paths in metadata' do
      output = reporter.generate

      expect(output[:metadata][:spec_paths]).to eq(['/path/to/spec.yml'])
    end

    it 'includes all result fields including owner and mismatches' do
      output = reporter.generate
      first_result = output[:results].first

      expect(first_result[:id]).to eq('test-1')
      expect(first_result[:title]).to eq('Test One')
      expect(first_result[:intent]).to eq('Test intent')
      expect(first_result[:note]).to eq('Test note')
      expect(first_result[:owner]).to eq('security')
      expect(first_result[:status]).to eq('pass')
      expect(first_result[:duration_ms]).to eq(150)
    end

    it 'includes structured mismatches in fail results' do
      output = reporter.generate
      fail_result = output[:results].last

      expect(fail_result[:mismatches]).to eq([{ path: 'status', expected: 'ENABLED', actual: 'DISABLED' }])
    end

    it 'includes timestamp in ISO8601 format' do
      output = reporter.generate

      expect(output[:metadata][:timestamp]).to match(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/)
    end
  end

  describe '#write' do
    it 'writes JSON to file' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'result.json')
        reporter.write(path)

        expect(File.exist?(path)).to be true
        content = JSON.parse(File.read(path))
        expect(content['metadata']['tool']).to eq('anyspec')
      end
    end

    it 'creates parent directories' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'nested', 'dir', 'result.json')
        reporter.write(path)

        expect(File.exist?(path)).to be true
      end
    end
  end
end
