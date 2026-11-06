# frozen_string_literal: true

require 'json'
require 'time'
require 'securerandom'

module Anyspec
  module Reporters
    class JsonReporter
      def initialize(results, summary, run_metadata: {})
        @results = results
        @summary = summary
        @run_metadata = run_metadata
        @run_id = SecureRandom.uuid
      end

      def generate
        {
          metadata: build_metadata,
          results: @results.map(&:to_h)
        }
      end

      def write(path)
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, JSON.pretty_generate(generate))
      end

      private

      def build_metadata
        metadata = {
          tool: 'anyspec',
          version: Anyspec::VERSION,
          run_id: @run_id,
          timestamp: Time.now.utc.iso8601,
          summary: @summary
        }

        if @run_metadata[:duration_ms]
          metadata[:duration_ms] = @run_metadata[:duration_ms]
        end

        if @run_metadata[:profile]
          metadata[:profile] = @run_metadata[:profile]
        end

        if @run_metadata[:region]
          metadata[:region] = @run_metadata[:region]
        end

        if @run_metadata[:auth_mode]
          metadata[:auth_mode] = @run_metadata[:auth_mode]
        end

        if @run_metadata[:spec_paths]&.any?
          metadata[:spec_paths] = @run_metadata[:spec_paths]
        end

        ci_context = GitHubActionsReporter.ci_context
        metadata[:ci] = ci_context unless ci_context.empty?

        metadata
      end
    end
  end
end
