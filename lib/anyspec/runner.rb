# frozen_string_literal: true

module Anyspec
  class Runner
    attr_reader :results

    def initialize(config:)
      @config = config
      @results = []
    end

    def run(specs)
      @results = specs.map { |spec| check_spec(spec) }
      @results
    end

    def summary
      {
        total: @results.size,
        pass: @results.count(&:pass?),
        fail: @results.count(&:fail?),
        error: @results.count(&:error?)
      }
    end

    def success?
      @results.none?(&:fail?) && @results.none?(&:error?)
    end

    private

    def check_spec(spec)
      adapter_class = AdapterRegistry.get(spec['type'])
      adapter = adapter_class.new(@config)

      actual = adapter.fetch(spec)
      expected = spec['expect']
      matched, mismatches = compare(expected, actual)

      if matched
        Result.new(
          id: spec['id'],
          title: spec['title'],
          intent: spec['intent'],
          note: spec['note'],
          status: :pass,
          expected: expected,
          actual: filter_actual(actual, expected),
          message: nil
        )
      else
        Result.new(
          id: spec['id'],
          title: spec['title'],
          intent: spec['intent'],
          note: spec['note'],
          status: :fail,
          expected: expected,
          actual: filter_actual(actual, expected),
          message: format_mismatches(mismatches)
        )
      end
    rescue Anyspec::UnknownAdapterError => e
      Result.new(
        id: spec['id'],
        title: spec['title'],
        intent: spec['intent'],
        note: spec['note'],
        status: :error,
        expected: spec['expect'],
        actual: nil,
        message: e.message
      )
    rescue StandardError => e
      Result.new(
        id: spec['id'],
        title: spec['title'],
        intent: spec['intent'],
        note: spec['note'],
        status: :error,
        expected: spec['expect'],
        actual: nil,
        message: "Fetch error: #{e.message}"
      )
    end

    def compare(expected, actual)
      mismatches = []
      compare_recursive(expected, actual, [], mismatches)
      [mismatches.empty?, mismatches]
    end

    def compare_recursive(expected, actual, path, mismatches)
      case expected
      when Hash
        expected.each do |key, exp_value|
          current_path = path + [key]
          act_value = actual.is_a?(Hash) ? actual[key] : nil
          compare_recursive(exp_value, act_value, current_path, mismatches)
        end
      when Array
        if actual.is_a?(Array)
          expected.each_with_index do |exp_item, idx|
            current_path = path + [idx]
            act_item = actual[idx]
            compare_recursive(exp_item, act_item, current_path, mismatches)
          end
        else
          mismatches << { path: path.join('.'), expected: expected, actual: actual }
        end
      else
        unless values_match?(expected, actual)
          mismatches << { path: path.join('.'), expected: expected, actual: actual }
        end
      end
    end

    def values_match?(expected, actual)
      return expected.to_s == actual.to_s if expected.is_a?(String) || actual.is_a?(String)

      expected == actual
    end

    def filter_actual(actual, expected)
      return nil if actual.nil?

      case expected
      when Hash
        expected.keys.each_with_object({}) do |key, filtered|
          filtered[key] = actual.is_a?(Hash) ? filter_actual(actual[key], expected[key]) : nil
        end
      else
        actual
      end
    end

    def format_mismatches(mismatches)
      mismatches.map do |m|
        "#{m[:path]}: expected '#{m[:expected]}', got '#{m[:actual]}'"
      end.join('; ')
    end
  end
end
