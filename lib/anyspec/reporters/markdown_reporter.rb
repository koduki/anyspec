# frozen_string_literal: true

require 'time'
require 'fileutils'

module Anyspec
  module Reporters
    class MarkdownReporter
      STATUS_EMOJI = {
        pass: '✅',
        fail: '❌',
        error: '⚠️'
      }.freeze

      def initialize(results, summary, run_metadata: {})
        @results = results
        @summary = summary
        @run_metadata = run_metadata
      end

      def generate
        lines = []
        lines << "# Anyspec チェック結果"
        lines << ""
        lines << "実行日時: #{Time.now.utc.strftime('%Y-%m-%d %H:%M:%S UTC')}"
        lines << ""
        lines << generate_summary
        lines << ""
        lines << generate_results
        lines.join("\n")
      end

      def write(path)
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, generate)
      end

      private

      def generate_summary
        lines = []
        lines << "## サマリー"
        lines << ""
        lines << "| 項目 | 件数 |"
        lines << "|------|------|"
        lines << "| 合計 | #{@summary[:total]} |"
        lines << "| #{STATUS_EMOJI[:pass]} 成功 | #{@summary[:pass]} |"
        lines << "| #{STATUS_EMOJI[:fail]} 失敗 | #{@summary[:fail]} |"
        lines << "| #{STATUS_EMOJI[:error]} エラー | #{@summary[:error]} |"
        lines.join("\n")
      end

      def generate_results
        lines = []
        lines << "## 詳細結果"
        lines << ""

        @results.each do |result|
          lines << generate_result_section(result)
          lines << ""
        end

        lines.join("\n")
      end

      def generate_result_section(result)
        lines = []
        emoji = STATUS_EMOJI[result.status]
        status_ja = status_japanese(result.status)

        lines << "### #{emoji} #{result.id}"
        lines << ""
        lines << "**タイトル**: #{result.title}"
        lines << ""
        lines << "**ステータス**: #{status_ja}"

        if result.waived?
          lines << ""
          lines << "**ウェイバー**: #{result.waiver_until} まで設計上の例外として許容"
        end

        if result.intent
          lines << ""
          lines << "**意図**: #{result.intent}"
        end

        if result.owner
          lines << ""
          lines << "**担当**: #{result.owner}"
        end

        if result.note
          lines << ""
          lines << "**備考**: #{result.note}"
        end

        if result.fail? || result.error?
          lines << ""
          lines << "#### 期待値"
          lines << ""
          lines << "```json"
          lines << JSON.pretty_generate(result.expected)
          lines << "```"

          if result.actual
            lines << ""
            lines << "#### 実際の値"
            lines << ""
            lines << "```json"
            lines << JSON.pretty_generate(result.actual)
            lines << "```"
          end

          if result.message
            lines << ""
            lines << "**メッセージ**: #{result.message}"
          end
        elsif result.waived?
          lines << ""
          lines << "<details>"
          lines << "<summary>ウェイバー中の不一致詳細</summary>"
          lines << ""
          lines << "#### 期待値"
          lines << ""
          lines << "```json"
          lines << JSON.pretty_generate(result.expected)
          lines << "```"
          lines << ""
          lines << "#### 実際の値"
          lines << ""
          lines << "```json"
          lines << JSON.pretty_generate(result.actual)
          lines << "```"
          lines << "</details>"
        end

        lines.join("\n")
      end

      def status_japanese(status)
        case status
        when :pass then '成功'
        when :fail then '失敗'
        when :error then 'エラー'
        end
      end
    end
  end
end
