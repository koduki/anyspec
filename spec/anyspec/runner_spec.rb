# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Anyspec::Runner do
  let(:config) { instance_double(Anyspec::Config, oci_client_config: {}) }
  let(:runner) { described_class.new(config: config) }

  describe '#run' do
    let(:mock_adapter) { instance_double(Anyspec::Adapters::Base) }

    before do
      allow(Anyspec::AdapterRegistry).to receive(:get).with('cloud_guard_configuration')
        .and_return(Class.new(Anyspec::Adapters::Base) do
          define_method(:fetch) { |_spec| { 'status' => 'ENABLED' } }
        end)
    end

    context 'when expected matches actual' do
      it 'returns pass result' do
        specs = [{
          'id' => 'test-1',
          'title' => 'Test',
          'intent' => 'Test intent',
          'type' => 'cloud_guard_configuration',
          'compartment_id' => 'ocid1.test',
          'expect' => { 'status' => 'ENABLED' }
        }]

        results = runner.run(specs)

        expect(results.first.pass?).to be true
        expect(results.first.actual).to eq({ 'status' => 'ENABLED' })
      end
    end

    context 'when expected does not match actual' do
      before do
        allow(Anyspec::AdapterRegistry).to receive(:get).with('cloud_guard_configuration')
          .and_return(Class.new(Anyspec::Adapters::Base) do
            define_method(:fetch) { |_spec| { 'status' => 'DISABLED' } }
          end)
      end

      it 'returns fail result' do
        specs = [{
          'id' => 'test-1',
          'title' => 'Test',
          'type' => 'cloud_guard_configuration',
          'compartment_id' => 'ocid1.test',
          'expect' => { 'status' => 'ENABLED' }
        }]

        results = runner.run(specs)

        expect(results.first.fail?).to be true
        expect(results.first.message).to include('status')
      end
    end

    context 'when adapter raises an error' do
      before do
        allow(Anyspec::AdapterRegistry).to receive(:get).with('cloud_guard_configuration')
          .and_return(Class.new(Anyspec::Adapters::Base) do
            define_method(:fetch) { |_spec| raise StandardError, 'API error' }
          end)
      end

      it 'returns error result' do
        specs = [{
          'id' => 'test-1',
          'title' => 'Test',
          'type' => 'cloud_guard_configuration',
          'compartment_id' => 'ocid1.test',
          'expect' => { 'status' => 'ENABLED' }
        }]

        results = runner.run(specs)

        expect(results.first.error?).to be true
        expect(results.first.message).to include('API error')
      end
    end

    context 'with unknown adapter type' do
      it 'returns error result' do
        allow(Anyspec::AdapterRegistry).to receive(:get).with('unknown_type')
          .and_raise(Anyspec::UnknownAdapterError, "Unknown adapter type: 'unknown_type'")

        specs = [{
          'id' => 'test-1',
          'title' => 'Test',
          'type' => 'unknown_type',
          'expect' => { 'status' => 'ENABLED' }
        }]

        results = runner.run(specs)

        expect(results.first.error?).to be true
        expect(results.first.message).to include('Unknown adapter type')
      end
    end
  end

  describe '#summary' do
    before do
      allow(Anyspec::AdapterRegistry).to receive(:get).and_return(
        Class.new(Anyspec::Adapters::Base) do
          define_method(:fetch) { |spec| { 'status' => spec['return_status'] } }
        end
      )
    end

    it 'calculates summary counts' do
      specs = [
        { 'id' => '1', 'title' => 'T1', 'type' => 'test', 'return_status' => 'ENABLED', 'expect' => { 'status' => 'ENABLED' } },
        { 'id' => '2', 'title' => 'T2', 'type' => 'test', 'return_status' => 'DISABLED', 'expect' => { 'status' => 'ENABLED' } }
      ]

      runner.run(specs)
      summary = runner.summary

      expect(summary[:total]).to eq(2)
      expect(summary[:pass]).to eq(1)
      expect(summary[:fail]).to eq(1)
      expect(summary[:error]).to eq(0)
    end
  end

  describe '#success?' do
    before do
      allow(Anyspec::AdapterRegistry).to receive(:get).and_return(
        Class.new(Anyspec::Adapters::Base) do
          define_method(:fetch) { |spec| { 'status' => spec['return_status'] } }
        end
      )
    end

    it 'returns true when all pass' do
      specs = [
        { 'id' => '1', 'title' => 'T1', 'type' => 'test', 'return_status' => 'ENABLED', 'expect' => { 'status' => 'ENABLED' } }
      ]

      runner.run(specs)
      expect(runner.success?).to be true
    end

    it 'returns false when any fail' do
      specs = [
        { 'id' => '1', 'title' => 'T1', 'type' => 'test', 'return_status' => 'DISABLED', 'expect' => { 'status' => 'ENABLED' } }
      ]

      runner.run(specs)
      expect(runner.success?).to be false
    end
  end

  describe 'subset matching' do
    before do
      allow(Anyspec::AdapterRegistry).to receive(:get).and_return(
        Class.new(Anyspec::Adapters::Base) do
          define_method(:fetch) do |_spec|
            {
              'status' => 'ENABLED',
              'extra_field' => 'ignored',
              'nested' => {
                'a' => 1,
                'b' => 2,
                'c' => 3
              }
            }
          end
        end
      )
    end

    it 'passes when expected is a subset of actual' do
      specs = [{
        'id' => 'test',
        'title' => 'Test',
        'type' => 'test',
        'expect' => {
          'status' => 'ENABLED',
          'nested' => { 'a' => 1 }
        }
      }]

      results = runner.run(specs)
      expect(results.first.pass?).to be true
    end

    it 'only includes expected fields in actual output' do
      specs = [{
        'id' => 'test',
        'title' => 'Test',
        'type' => 'test',
        'expect' => { 'status' => 'ENABLED' }
      }]

      results = runner.run(specs)
      expect(results.first.actual).to eq({ 'status' => 'ENABLED' })
      expect(results.first.actual).not_to have_key('extra_field')
    end
  end
end
