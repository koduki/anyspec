# frozen_string_literal: true

require 'json'
require 'time'

module Anyspec
  module Reporters
    class JsonReporter
      def initialize(results, summary)
        @results = results
        @summary = summary
      end

      def generate
        {
          metadata: {
            tool: 'anyspec',
            version: Anyspec::VERSION,
            timestamp: Time.now.utc.iso8601,
            summary: @summary
          },
          results: @results.map(&:to_h)
        }
      end

      def write(path)
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, JSON.pretty_generate(generate))
      end
    end
  end
end
