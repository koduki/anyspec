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

  describe '#exit_code' do
    context 'when all checks pass' do
      before do
        allow(Anyspec::AdapterRegistry).to receive(:get).and_return(
          Class.new(Anyspec::Adapters::Base) do
            define_method(:fetch) { |_spec| { 'status' => 'ENABLED' } }
          end
        )
      end

      it 'returns 0' do
        specs = [
          { 'id' => '1', 'title' => 'T1', 'type' => 'test', 'expect' => { 'status' => 'ENABLED' } }
        ]

        runner.run(specs)
        expect(runner.exit_code).to eq(0)
      end
    end

    context 'when at least one check fails (drift detected)' do
      before do
        allow(Anyspec::AdapterRegistry).to receive(:get).and_return(
          Class.new(Anyspec::Adapters::Base) do
            define_method(:fetch) { |_spec| { 'status' => 'DISABLED' } }
          end
        )
      end

      it 'returns 1' do
        specs = [
          { 'id' => '1', 'title' => 'T1', 'type' => 'test', 'expect' => { 'status' => 'ENABLED' } }
        ]

        runner.run(specs)
        expect(runner.exit_code).to eq(1)
      end
    end

    context 'when there is an error but no fails' do
      before do
        allow(Anyspec::AdapterRegistry).to receive(:get).and_return(
          Class.new(Anyspec::Adapters::Base) do
            define_method(:fetch) { |_spec| raise StandardError, 'API error' }
          end
        )
      end

      it 'returns 2' do
        specs = [
          { 'id' => '1', 'title' => 'T1', 'type' => 'test', 'expect' => { 'status' => 'ENABLED' } }
        ]

        runner.run(specs)
        expect(runner.exit_code).to eq(2)
      end
    end

    context 'when there are both fails and errors' do
      it 'returns 1 (fail takes precedence)' do
        call_count = 0
        allow(Anyspec::AdapterRegistry).to receive(:get).and_return(
          Class.new(Anyspec::Adapters::Base) do
            define_method(:fetch) do |_spec|
              call_count += 1
              if call_count == 1
                { 'status' => 'DISABLED' }
              else
                raise StandardError, 'API error'
              end
            end
          end
        )

        specs = [
          { 'id' => '1', 'title' => 'T1', 'type' => 'test', 'expect' => { 'status' => 'ENABLED' } },
          { 'id' => '2', 'title' => 'T2', 'type' => 'test', 'expect' => { 'status' => 'ENABLED' } }
        ]

        runner.run(specs)
        expect(runner.exit_code).to eq(1)
      end
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

  describe 'strict comparison' do
    before do
      allow(Anyspec::AdapterRegistry).to receive(:get).and_return(
        Class.new(Anyspec::Adapters::Base) do
          define_method(:fetch) { |_spec| { 'count' => 14 } }
        end
      )
    end

    it 'fails when types do not match (integer vs string)' do
      specs = [{
        'id' => 'test',
        'title' => 'Test',
        'type' => 'test',
        'expect' => { 'count' => '14' }
      }]

      results = runner.run(specs)
      expect(results.first.fail?).to be true
    end

    it 'passes when types match exactly' do
      specs = [{
        'id' => 'test',
        'title' => 'Test',
        'type' => 'test',
        'expect' => { 'count' => 14 }
      }]

      results = runner.run(specs)
      expect(results.first.pass?).to be true
    end
  end

  describe 'time-boxed waivers (until:)' do
    before do
      allow(Anyspec::AdapterRegistry).to receive(:get).and_return(
        Class.new(Anyspec::Adapters::Base) do
          define_method(:fetch) { |_spec| { 'status' => 'DISABLED' } }
        end
      )
    end

    it 'passes when waiver is active (until date is in the future)' do
      future_date = (Date.today + 30).strftime('%Y-%m-%d')
      specs = [{
        'id' => 'test',
        'title' => 'Test',
        'type' => 'test',
        'until' => future_date,
        'expect' => { 'status' => 'ENABLED' }
      }]

      results = runner.run(specs)
      expect(results.first.pass?).to be true
      expect(results.first.message).to include('Waiver active until')
    end

    it 'fails when waiver has expired (until date is in the past)' do
      past_date = (Date.today - 1).strftime('%Y-%m-%d')
      specs = [{
        'id' => 'test',
        'title' => 'Test',
        'type' => 'test',
        'until' => past_date,
        'expect' => { 'status' => 'ENABLED' }
      }]

      results = runner.run(specs)
      expect(results.first.fail?).to be true
    end

    it 'still includes mismatches in waived results' do
      future_date = (Date.today + 30).strftime('%Y-%m-%d')
      specs = [{
        'id' => 'test',
        'title' => 'Test',
        'type' => 'test',
        'until' => future_date,
        'expect' => { 'status' => 'ENABLED' }
      }]

      results = runner.run(specs)
      expect(results.first.mismatches).not_to be_nil
      expect(results.first.mismatches.first[:path]).to eq('status')
    end

    it 'passes normally when there is no mismatch (regardless of until)' do
      allow(Anyspec::AdapterRegistry).to receive(:get).and_return(
        Class.new(Anyspec::Adapters::Base) do
          define_method(:fetch) { |_spec| { 'status' => 'ENABLED' } }
        end
      )

      future_date = (Date.today + 30).strftime('%Y-%m-%d')
      specs = [{
        'id' => 'test',
        'title' => 'Test',
        'type' => 'test',
        'until' => future_date,
        'expect' => { 'status' => 'ENABLED' }
      }]

      results = runner.run(specs)
      expect(results.first.pass?).to be true
      expect(results.first.message).to be_nil
    end
  end

  describe 'comparison operators' do
    before do
      allow(Anyspec::AdapterRegistry).to receive(:get).and_return(
        Class.new(Anyspec::Adapters::Base) do
          define_method(:fetch) { |_spec| { 'retention_period_days' => 365, 'status' => 'ENABLED' } }
        end
      )
    end

    describe '$gte operator' do
      it 'passes when actual >= expected' do
        specs = [{
          'id' => 'test',
          'title' => 'Test',
          'type' => 'test',
          'expect' => { 'retention_period_days' => { '$gte' => 365 } }
        }]

        results = runner.run(specs)
        expect(results.first.pass?).to be true
      end

      it 'fails when actual < expected' do
        specs = [{
          'id' => 'test',
          'title' => 'Test',
          'type' => 'test',
          'expect' => { 'retention_period_days' => { '$gte' => 400 } }
        }]

        results = runner.run(specs)
        expect(results.first.fail?).to be true
      end
    end

    describe '$lte operator' do
      it 'passes when actual <= expected' do
        specs = [{
          'id' => 'test',
          'title' => 'Test',
          'type' => 'test',
          'expect' => { 'retention_period_days' => { '$lte' => 400 } }
        }]

        results = runner.run(specs)
        expect(results.first.pass?).to be true
      end

      it 'fails when actual > expected' do
        specs = [{
          'id' => 'test',
          'title' => 'Test',
          'type' => 'test',
          'expect' => { 'retention_period_days' => { '$lte' => 300 } }
        }]

        results = runner.run(specs)
        expect(results.first.fail?).to be true
      end
    end

    describe '$in operator' do
      it 'passes when actual is in the list' do
        specs = [{
          'id' => 'test',
          'title' => 'Test',
          'type' => 'test',
          'expect' => { 'status' => { '$in' => %w[ENABLED ACTIVE] } }
        }]

        results = runner.run(specs)
        expect(results.first.pass?).to be true
      end

      it 'fails when actual is not in the list' do
        specs = [{
          'id' => 'test',
          'title' => 'Test',
          'type' => 'test',
          'expect' => { 'status' => { '$in' => %w[DISABLED INACTIVE] } }
        }]

        results = runner.run(specs)
        expect(results.first.fail?).to be true
      end
    end

    describe '$ne operator' do
      it 'passes when actual != expected' do
        specs = [{
          'id' => 'test',
          'title' => 'Test',
          'type' => 'test',
          'expect' => { 'status' => { '$ne' => 'DISABLED' } }
        }]

        results = runner.run(specs)
        expect(results.first.pass?).to be true
      end

      it 'fails when actual == expected' do
        specs = [{
          'id' => 'test',
          'title' => 'Test',
          'type' => 'test',
          'expect' => { 'status' => { '$ne' => 'ENABLED' } }
        }]

        results = runner.run(specs)
        expect(results.first.fail?).to be true
      end
    end

    describe 'combined operators' do
      it 'supports multiple operators (range check)' do
        specs = [{
          'id' => 'test',
          'title' => 'Test',
          'type' => 'test',
          'expect' => { 'retention_period_days' => { '$gte' => 300, '$lte' => 400 } }
        }]

        results = runner.run(specs)
        expect(results.first.pass?).to be true
      end
    end
  end
end
