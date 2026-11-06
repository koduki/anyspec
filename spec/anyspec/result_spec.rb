# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Anyspec::Result do
  describe '#initialize' do
    it 'creates a pass result' do
      result = described_class.new(
        id: 'test-1',
        title: 'Test One',
        intent: 'Test intent',
        note: 'Test note',
        status: :pass,
        expected: { status: 'ENABLED' },
        actual: { status: 'ENABLED' }
      )

      expect(result.pass?).to be true
      expect(result.fail?).to be false
      expect(result.error?).to be false
    end

    it 'creates a fail result' do
      result = described_class.new(
        id: 'test-2',
        title: 'Test Two',
        status: :fail,
        expected: { status: 'ENABLED' },
        actual: { status: 'DISABLED' },
        message: 'Status mismatch'
      )

      expect(result.pass?).to be false
      expect(result.fail?).to be true
      expect(result.error?).to be false
    end

    it 'creates an error result' do
      result = described_class.new(
        id: 'test-3',
        title: 'Test Three',
        status: :error,
        expected: { status: 'ENABLED' },
        actual: nil,
        message: 'API error'
      )

      expect(result.pass?).to be false
      expect(result.fail?).to be false
      expect(result.error?).to be true
    end

    it 'raises error for invalid status' do
      expect do
        described_class.new(
          id: 'test',
          title: 'Test',
          status: :invalid,
          expected: {},
          actual: {}
        )
      end.to raise_error(ArgumentError, /Invalid status/)
    end
  end

  describe '#to_h' do
    it 'converts to hash' do
      result = described_class.new(
        id: 'test-1',
        title: 'Test',
        intent: 'Intent text',
        note: 'Note text',
        status: :pass,
        expected: { foo: 'bar' },
        actual: { foo: 'bar' }
      )

      hash = result.to_h

      expect(hash[:id]).to eq('test-1')
      expect(hash[:title]).to eq('Test')
      expect(hash[:intent]).to eq('Intent text')
      expect(hash[:note]).to eq('Note text')
      expect(hash[:status]).to eq('pass')
      expect(hash[:expected]).to eq(foo: 'bar')
      expect(hash[:actual]).to eq(foo: 'bar')
    end

    it 'omits nil values' do
      result = described_class.new(
        id: 'test-1',
        title: 'Test',
        status: :pass,
        expected: {},
        actual: {}
      )

      hash = result.to_h

      expect(hash).not_to have_key(:intent)
      expect(hash).not_to have_key(:note)
      expect(hash).not_to have_key(:message)
    end
  end
end
