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
        owner: 'security',
        status: :pass,
        expected: { status: 'ENABLED' },
        actual: { status: 'ENABLED' },
        duration_ms: 150
      )

      expect(result.pass?).to be true
      expect(result.fail?).to be false
      expect(result.error?).to be false
      expect(result.owner).to eq('security')
      expect(result.duration_ms).to eq(150)
    end

    it 'creates a fail result with mismatches' do
      result = described_class.new(
        id: 'test-2',
        title: 'Test Two',
        status: :fail,
        expected: { status: 'ENABLED' },
        actual: { status: 'DISABLED' },
        message: 'Status mismatch',
        mismatches: [{ path: 'status', expected: 'ENABLED', actual: 'DISABLED' }],
        duration_ms: 200
      )

      expect(result.pass?).to be false
      expect(result.fail?).to be true
      expect(result.error?).to be false
      expect(result.mismatches).to eq([{ path: 'status', expected: 'ENABLED', actual: 'DISABLED' }])
    end

    it 'creates an error result with error_details' do
      result = described_class.new(
        id: 'test-3',
        title: 'Test Three',
        status: :error,
        expected: { status: 'ENABLED' },
        actual: nil,
        message: 'API error',
        duration_ms: 50,
        error_details: { error_class: 'OCI::Errors::ServiceError', http_status: 404 }
      )

      expect(result.pass?).to be false
      expect(result.fail?).to be false
      expect(result.error?).to be true
      expect(result.error_details[:error_class]).to eq('OCI::Errors::ServiceError')
      expect(result.error_details[:http_status]).to eq(404)
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
    it 'converts to hash with all fields' do
      result = described_class.new(
        id: 'test-1',
        title: 'Test',
        intent: 'Intent text',
        note: 'Note text',
        owner: 'security',
        status: :pass,
        expected: { foo: 'bar' },
        actual: { foo: 'bar' },
        duration_ms: 100
      )

      hash = result.to_h

      expect(hash[:id]).to eq('test-1')
      expect(hash[:title]).to eq('Test')
      expect(hash[:intent]).to eq('Intent text')
      expect(hash[:note]).to eq('Note text')
      expect(hash[:owner]).to eq('security')
      expect(hash[:status]).to eq('pass')
      expect(hash[:expected]).to eq(foo: 'bar')
      expect(hash[:actual]).to eq(foo: 'bar')
      expect(hash[:duration_ms]).to eq(100)
    end

    it 'includes mismatches and error_details when present' do
      result = described_class.new(
        id: 'test-1',
        title: 'Test',
        status: :fail,
        expected: {},
        actual: {},
        mismatches: [{ path: 'status', expected: 'A', actual: 'B' }],
        error_details: { error_class: 'TestError' }
      )

      hash = result.to_h

      expect(hash[:mismatches]).to eq([{ path: 'status', expected: 'A', actual: 'B' }])
      expect(hash[:error_details]).to eq(error_class: 'TestError')
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
      expect(hash).not_to have_key(:owner)
      expect(hash).not_to have_key(:message)
      expect(hash).not_to have_key(:mismatches)
      expect(hash).not_to have_key(:duration_ms)
      expect(hash).not_to have_key(:error_details)
    end
  end
end
