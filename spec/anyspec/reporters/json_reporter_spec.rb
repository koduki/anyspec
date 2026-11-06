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
        status: :pass,
        expected: { 'status' => 'ENABLED' },
        actual: { 'status' => 'ENABLED' }
      ),
      Anyspec::Result.new(
        id: 'test-2',
        title: 'Test Two',
        status: :fail,
        expected: { 'status' => 'ENABLED' },
        actual: { 'status' => 'DISABLED' },
        message: 'Status mismatch'
      )
    ]
  end

  let(:summary) { { total: 2, pass: 1, fail: 1, error: 0 } }
  let(:reporter) { described_class.new(results, summary) }

  describe '#generate' do
    it 'generates valid JSON structure' do
      output = reporter.generate

      expect(output[:metadata][:tool]).to eq('anyspec')
      expect(output[:metadata][:version]).to eq(Anyspec::VERSION)
      expect(output[:metadata][:summary]).to eq(summary)
      expect(output[:results].size).to eq(2)
    end

    it 'includes all result fields' do
      output = reporter.generate
      first_result = output[:results].first

      expect(first_result[:id]).to eq('test-1')
      expect(first_result[:title]).to eq('Test One')
      expect(first_result[:intent]).to eq('Test intent')
      expect(first_result[:note]).to eq('Test note')
      expect(first_result[:status]).to eq('pass')
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
