# frozen_string_literal: true

module Anyspec
  class Result
    STATUSES = %i[pass fail error].freeze

    attr_reader :id, :title, :intent, :note, :owner, :status, :expected, :actual,
                :message, :mismatches, :duration_ms, :error_details, :source_file,
                :waiver_until

    def initialize(id:, title:, intent: nil, note: nil, owner: nil, status:,
                   expected:, actual:, message: nil, mismatches: nil,
                   duration_ms: nil, error_details: nil, source_file: nil,
                   waiver_until: nil)
      raise ArgumentError, "Invalid status: #{status}" unless STATUSES.include?(status)

      @id = id
      @title = title
      @intent = intent
      @note = note
      @owner = owner
      @status = status
      @expected = expected
      @actual = actual
      @message = message
      @mismatches = mismatches
      @duration_ms = duration_ms
      @error_details = error_details
      @source_file = source_file
      @waiver_until = waiver_until
    end

    def pass?
      @status == :pass
    end

    def fail?
      @status == :fail
    end

    def error?
      @status == :error
    end

    def waived?
      @waiver_until && @message&.include?('Waiver active')
    end

    def to_h
      {
        id: @id,
        title: @title,
        intent: @intent,
        note: @note,
        owner: @owner,
        status: @status.to_s,
        expected: @expected,
        actual: @actual,
        message: @message,
        mismatches: @mismatches,
        duration_ms: @duration_ms,
        error_details: @error_details,
        source_file: @source_file,
        waiver_until: @waiver_until
      }.compact
    end
  end
end
