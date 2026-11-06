# frozen_string_literal: true

module Anyspec
  class Result
    STATUSES = %i[pass fail error].freeze

    attr_reader :id, :title, :intent, :note, :status, :expected, :actual, :message

    def initialize(id:, title:, intent: nil, note: nil, status:, expected:, actual:, message: nil)
      raise ArgumentError, "Invalid status: #{status}" unless STATUSES.include?(status)

      @id = id
      @title = title
      @intent = intent
      @note = note
      @status = status
      @expected = expected
      @actual = actual
      @message = message
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

    def to_h
      {
        id: @id,
        title: @title,
        intent: @intent,
        note: @note,
        status: @status.to_s,
        expected: @expected,
        actual: @actual,
        message: @message
      }.compact
    end
  end
end
