# frozen_string_literal: true

require 'json'

module Anyspec
  module Reporters
    class GitHubActionsReporter
      def initialize(results, summary, run_metadata: {})
        @results = results
        @summary = summary
        @run_metadata = run_metadata
        @workspace_root = ENV['GITHUB_WORKSPACE']
      end

      def self.github_actions?
        ENV['GITHUB_ACTIONS'] == 'true'
      end

      def write_step_summary
        summary_path = ENV['GITHUB_STEP_SUMMARY']
        return unless summary_path

        content = generate_markdown
        File.open(summary_path, 'a') do |f|
          f.puts content
        end
      end

      def emit_workflow_commands
        @results.each do |result|
          emit_command_for_result(result)
        end
      end

      def write_github_output(exit_code)
        output_path = ENV['GITHUB_OUTPUT']
        return unless output_path

        has_pass = @results.any?(&:pass?)
        has_fail = @results.any?(&:fail?)
        has_error = @results.any?(&:error?)

        outputs = []
        outputs << "pass=#{has_pass && !has_fail && !has_error}"
        outputs << "fail=#{has_fail}"
        outputs << "error=#{has_error}"
        outputs << "exit_code=#{exit_code}"

        File.open(output_path, 'a') do |f|
          outputs.each { |line| f.puts line }
        end
      end

      def self.ci_context
        return {} unless github_actions?

        context = {}
        context[:github_sha] = ENV['GITHUB_SHA'] if ENV['GITHUB_SHA']
        context[:github_run_id] = ENV['GITHUB_RUN_ID'] if ENV['GITHUB_RUN_ID']
        context[:github_ref] = ENV['GITHUB_REF'] if ENV['GITHUB_REF']
        context[:github_workflow] = ENV['GITHUB_WORKFLOW'] if ENV['GITHUB_WORKFLOW']

        if ENV['GITHUB_SERVER_URL'] && ENV['GITHUB_REPOSITORY'] && ENV['GITHUB_RUN_ID']
          context[:github_run_url] = "#{ENV['GITHUB_SERVER_URL']}/#{ENV['GITHUB_REPOSITORY']}/actions/runs/#{ENV['GITHUB_RUN_ID']}"
        end

        context
      end

      private

      def generate_markdown
        lines = []
        lines << "# Anyspec チェック結果"
        lines << ""
        lines << "実行日時: #{Time.now.utc.strftime('%Y-%m-%d %H:%M:%S UTC')}"
        lines << ""
        lines << generate_summary_section
        lines << ""
        lines << generate_results_section
        lines.join("\n")
      end

      def generate_summary_section
        lines = []
        lines << "## サマリー"
        lines << ""
        lines << "| 項目 | 件数 |"
        lines << "|------|------|"
        lines << "| 合計 | #{@summary[:total]} |"
        lines << "| ✅ 成功 | #{@summary[:pass]} |"
        lines << "| ❌ 失敗 | #{@summary[:fail]} |"
        lines << "| ⚠️ エラー | #{@summary[:error]} |"
        lines.join("\n")
      end

      def generate_results_section
        lines = []
        lines << "## 詳細結果"
        lines << ""

        @results.each do |result|
          lines << generate_result_entry(result)
          lines << ""
        end

        lines.join("\n")
      end

      def generate_result_entry(result)
        lines = []
        emoji = status_emoji(result.status)
        status_text = status_japanese(result.status)

        lines << "### #{emoji} #{result.id}"
        lines << ""
        lines << "**タイトル**: #{result.title}"
        lines << ""
        lines << "**ステータス**: #{status_text}"

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

      def emit_command_for_result(result)
        return if result.pass? && !result.waived?

        file_param = build_file_param(result.source_file)

        if result.fail?
          message = build_annotation_message(result)
          puts "::error #{file_param}::#{escape_annotation(message)}"
        elsif result.error?
          message = "[#{result.id}] #{result.title}: #{result.message}"
          puts "::error #{file_param}::#{escape_annotation(message)}"
        elsif result.waived?
          message = "[#{result.id}] #{result.title}: ウェイバー中 (#{result.waiver_until}まで)"
          puts "::notice #{file_param}::#{escape_annotation(message)}"
        end
      end

      def build_file_param(source_file)
        return '' unless source_file

        relative_path = make_relative_path(source_file)
        "file=#{relative_path}"
      end

      def make_relative_path(absolute_path)
        return absolute_path unless @workspace_root

        if absolute_path.start_with?(@workspace_root)
          path = absolute_path.sub("#{@workspace_root}/", '')
          path = absolute_path.sub("#{@workspace_root}\\", '') if path == absolute_path
          path
        else
          absolute_path
        end
      end

      def build_annotation_message(result)
        parts = ["[#{result.id}] #{result.title}"]

        if result.intent
          parts << "意図: #{result.intent}"
        end

        if result.owner
          parts << "担当: #{result.owner}"
        end

        if result.mismatches&.any?
          mismatch_details = result.mismatches.map do |m|
            "#{m[:path]}: expected '#{m[:expected]}', got '#{m[:actual]}'"
          end.join('; ')
          parts << mismatch_details
        elsif result.message
          parts << result.message
        end

        parts.join(' | ')
      end

      def escape_annotation(message)
        message
          .gsub('%', '%25')
          .gsub("\r", '%0D')
          .gsub("\n", '%0A')
          .gsub(':', '%3A')
      end

      def status_emoji(status)
        case status
        when :pass then '✅'
        when :fail then '❌'
        when :error then '⚠️'
        end
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
