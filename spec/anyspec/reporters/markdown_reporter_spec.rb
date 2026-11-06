# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'

RSpec.describe Anyspec::Reporters::MarkdownReporter do
  let(:results) do
    [
      Anyspec::Result.new(
        id: 'test-1',
        title: 'Test One',
        intent: 'Ensure security is enabled',
        note: 'Critical setting',
        status: :pass,
        expected: { 'status' => 'ENABLED' },
        actual: { 'status' => 'ENABLED' }
      ),
      Anyspec::Result.new(
        id: 'test-2',
        title: 'Test Two',
        intent: 'Verify configuration',
        status: :fail,
        expected: { 'status' => 'ENABLED' },
        actual: { 'status' => 'DISABLED' },
        message: 'Status mismatch'
      ),
      Anyspec::Result.new(
        id: 'test-3',
        title: 'Test Three',
        status: :error,
        expected: { 'status' => 'ENABLED' },
        actual: nil,
        message: 'API error occurred'
      )
    ]
  end

  let(:summary) { { total: 3, pass: 1, fail: 1, error: 1 } }
  let(:reporter) { described_class.new(results, summary) }

  describe '#generate' do
    let(:output) { reporter.generate }

    it 'generates Markdown with header' do
      expect(output).to include('# Anyspec チェック結果')
    end

    it 'includes summary section' do
      expect(output).to include('## サマリー')
      expect(output).to include('| 合計 | 3 |')
      expect(output).to include('✅ 成功 | 1')
      expect(output).to include('❌ 失敗 | 1')
      expect(output).to include('⚠️ エラー | 1')
    end

    it 'includes intent for each result' do
      expect(output).to include('**意図**: Ensure security is enabled')
      expect(output).to include('**意図**: Verify configuration')
    end

    it 'includes note when present' do
      expect(output).to include('**備考**: Critical setting')
    end

    it 'shows expected/actual for failures' do
      expect(output).to include('#### 期待値')
      expect(output).to include('#### 実際の値')
      expect(output).to include('"status": "DISABLED"')
    end

    it 'shows error message' do
      expect(output).to include('API error occurred')
    end

    it 'uses status emojis' do
      expect(output).to include('✅')
      expect(output).to include('❌')
      expect(output).to include('⚠️')
    end
  end

  describe '#write' do
    it 'writes Markdown to file' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'result.md')
        reporter.write(path)

        expect(File.exist?(path)).to be true
        content = File.read(path)
        expect(content).to include('# Anyspec チェック結果')
      end
    end
  end
end
