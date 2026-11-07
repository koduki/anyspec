# frozen_string_literal: true

require 'time'

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

    def exit_code
      return 2 if @results.any?(&:error?)
      return 1 if @results.any?(&:fail?)

      0
    end

    def has_fail?
      @results.any?(&:fail?)
    end

    def has_error?
      @results.any?(&:error?)
    end

    private

    def check_spec(spec)
      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      adapter_class = AdapterRegistry.get(spec['type'])
      adapter = adapter_class.new(@config)

      actual = adapter.fetch(spec)
      expected = spec['expect']
      matched, mismatches = compare(expected, actual)

      duration_ms = calculate_duration_ms(start_time)

      source_file = spec['_source_file']

      if matched
        Result.new(
          id: spec['id'],
          title: spec['title'],
          intent: spec['intent'],
          note: spec['note'],
          owner: spec['owner'],
          status: :pass,
          expected: expected,
          actual: filter_actual(actual, expected),
          message: nil,
          duration_ms: duration_ms,
          source_file: source_file
        )
      elsif waiver_active?(spec)
        waiver_msg = "Waiver active until #{spec['until']}. Mismatch: #{format_mismatches(mismatches)}"
        Result.new(
          id: spec['id'],
          title: spec['title'],
          intent: spec['intent'],
          note: spec['note'],
          owner: spec['owner'],
          status: :pass,
          expected: expected,
          actual: filter_actual(actual, expected),
          message: waiver_msg,
          mismatches: mismatches,
          duration_ms: duration_ms,
          source_file: source_file,
          waiver_until: spec['until']&.to_s
        )
      else
        Result.new(
          id: spec['id'],
          title: spec['title'],
          intent: spec['intent'],
          note: spec['note'],
          owner: spec['owner'],
          status: :fail,
          expected: expected,
          actual: filter_actual(actual, expected),
          message: format_mismatches(mismatches),
          mismatches: mismatches,
          duration_ms: duration_ms,
          source_file: source_file
        )
      end
    rescue Anyspec::UnknownAdapterError => e
      duration_ms = calculate_duration_ms(start_time)
      Result.new(
        id: spec['id'],
        title: spec['title'],
        intent: spec['intent'],
        note: spec['note'],
        owner: spec['owner'],
        status: :error,
        expected: spec['expect'],
        actual: nil,
        message: e.message,
        duration_ms: duration_ms,
        error_details: { error_class: e.class.name },
        source_file: spec['_source_file']
      )
    rescue StandardError => e
      duration_ms = calculate_duration_ms(start_time)
      Result.new(
        id: spec['id'],
        title: spec['title'],
        intent: spec['intent'],
        note: spec['note'],
        owner: spec['owner'],
        status: :error,
        expected: spec['expect'],
        actual: nil,
        message: "Fetch error: #{e.message}",
        duration_ms: duration_ms,
        error_details: extract_error_details(e),
        source_file: spec['_source_file']
      )
    end

    def calculate_duration_ms(start_time)
      ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000).round
    end

    def waiver_active?(spec)
      return false unless spec['until']

      until_date = parse_until_date(spec['until'])
      return false unless until_date

      Time.now.utc < until_date
    end

    def parse_until_date(until_value)
      case until_value
      when Time, DateTime
        until_value.to_time.utc
      when Date
        Time.utc(until_value.year, until_value.month, until_value.day)
      when String
        Time.parse("#{until_value} UTC")
      else
        nil
      end
    rescue ArgumentError
      nil
    end

    def extract_error_details(error)
      details = { error_class: error.class.name }

      if error.respond_to?(:status_code)
        details[:http_status] = error.status_code
      end

      if error.respond_to?(:request_id)
        details[:opc_request_id] = error.request_id
      elsif error.respond_to?(:opc_request_id)
        details[:opc_request_id] = error.opc_request_id
      end

      if error.respond_to?(:service_code)
        details[:service_code] = error.service_code
      end

      details
    end

    def compare(expected, actual)
      mismatches = []
      compare_recursive(expected, actual, [], mismatches)
      [mismatches.empty?, mismatches]
    end

    def compare_recursive(expected, actual, path, mismatches)
      case expected
      when Hash
        if comparison_operator?(expected)
          unless evaluate_operator(expected, actual)
            mismatches << { path: path.join('.'), expected: expected, actual: actual }
          end
        else
          expected.each do |key, exp_value|
            current_path = path + [key]
            act_value = actual.is_a?(Hash) ? actual[key] : nil
            compare_recursive(exp_value, act_value, current_path, mismatches)
          end
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

    COMPARISON_OPERATORS = %w[$gte $lte $gt $lt $in $ne].freeze

    def comparison_operator?(value)
      return false unless value.is_a?(Hash)

      value.keys.any? { |k| COMPARISON_OPERATORS.include?(k.to_s) }
    end

    def evaluate_operator(operator_hash, actual)
      operator_hash.all? do |op, operand|
        case op.to_s
        when '$gte'
          actual.respond_to?(:>=) && actual >= operand
        when '$lte'
          actual.respond_to?(:<=) && actual <= operand
        when '$gt'
          actual.respond_to?(:>) && actual > operand
        when '$lt'
          actual.respond_to?(:<) && actual < operand
        when '$in'
          operand.is_a?(Array) && operand.include?(actual)
        when '$ne'
          actual != operand
        else
          true
        end
      end
    end

    def values_match?(expected, actual)
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
