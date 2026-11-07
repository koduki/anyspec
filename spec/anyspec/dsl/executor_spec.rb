# frozen_string_literal: true

require 'spec_helper'
require 'anyspec/dsl/runner'
require 'tmpdir'
require 'rbconfig'

RSpec.describe Anyspec::DSL::OCI::Executor do
  let(:config) { Anyspec::Config.new(oci_cli: '/bin/echo') }

  describe 'empty stdout handling' do
    it 'returns empty array for IAM list command with empty stdout and exit 0' do
      executor = described_class.new(config: config)
      
      allow(executor).to receive(:run_with_timeout).and_return(['', '', double(success?: true, exitstatus: 0)])

      result = executor.execute(
        ['oci', 'iam', 'domain', 'list', '--compartment-id', 'test'],
        location: nil
      )

      expect(result).to eq([])
    end

    it 'returns empty array for IAM compartment list with empty stdout and exit 0' do
      executor = described_class.new(config: config)
      
      allow(executor).to receive(:run_with_timeout).and_return(['', '', double(success?: true, exitstatus: 0)])

      result = executor.execute(
        ['oci', 'iam', 'compartment', 'list', '--compartment-id', 'test'],
        location: nil
      )

      expect(result).to eq([])
    end

    it 'raises error for non-IAM command with empty stdout and exit 0' do
      executor = described_class.new(config: config)
      
      allow(executor).to receive(:run_with_timeout).and_return(['', '', double(success?: true, exitstatus: 0)])

      expect do
        executor.execute(
          ['oci', 'identity-domains', 'policy', 'list', '--endpoint', 'test'],
          location: nil
        )
      end.to raise_error(Anyspec::DSL::OCI::CLIError, /empty output/)
    end

    it 'raises error for IAM command with non-zero exit' do
      executor = described_class.new(config: config)
      
      allow(executor).to receive(:run_with_timeout).and_return(['', 'error', double(success?: false, exitstatus: 1)])

      expect do
        executor.execute(
          ['oci', 'iam', 'domain', 'list', '--compartment-id', 'test'],
          location: nil
        )
      end.to raise_error(Anyspec::DSL::OCI::CLIError, /exit 1/)
    end
  end

  describe 'normal response handling' do
    it 'parses JSON response with data wrapper' do
      executor = described_class.new(config: config)
      json_response = '{"data": [{"id": "d1"}, {"id": "d2"}]}'
      
      allow(executor).to receive(:run_with_timeout).and_return([json_response, '', double(success?: true, exitstatus: 0)])

      result = executor.execute(
        ['oci', 'iam', 'domain', 'list', '--compartment-id', 'test'],
        location: nil
      )

      expect(result).to eq([{ 'id' => 'd1' }, { 'id' => 'd2' }])
    end

    it 'parses SCIM response without data wrapper' do
      executor = described_class.new(config: config)
      json_response = '{"Resources": [], "totalResults": 0}'
      
      allow(executor).to receive(:run_with_timeout).and_return([json_response, '', double(success?: true, exitstatus: 0)])

      result = executor.execute(
        ['oci', 'identity-domains', 'policy', 'list', '--endpoint', 'test'],
        location: nil
      )

      expect(result).to eq({ 'Resources' => [], 'totalResults' => 0 })
    end
  end
end

RSpec.describe 'OCI Executor process limits' do
  def with_fake_oci(code, timeout: 2, max_output: 1_048_576)
    skip 'process-group tests require a POSIX host' if Gem.win_platform?
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'oci')
      File.write(path, "#!#{RbConfig.ruby}\n#{code}\n")
      File.chmod(0o755, path)
      executor = Anyspec::DSL::OCI::Executor.new(config: Anyspec::Config.new(oci_cli: path), timeout: timeout, max_output: max_output)
      yield executor, dir
    end
  end

  it 'interrupts a stalled command and returns near its timeout' do
    with_fake_oci('sleep 5', timeout: 0.2) do |executor|
      start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      expect { executor.execute(%w[oci iam domain list]) }.to raise_error(Anyspec::DSL::OCI::TimeoutError)
      expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - start).to be < 3
    end
  end

  %w[STDOUT STDERR].each do |stream|
    it "terminates a command when #{stream} exceeds the output limit" do
      with_fake_oci("#{stream}.write('x' * 200_000); sleep 5", max_output: 4096) do |executor|
        start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        expect { executor.execute(%w[oci iam domain list]) }.to raise_error(Anyspec::DSL::OCI::OutputTooLargeError)
        expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - start).to be < 3
      end
    end
  end

  it 'terminates children that inherit the OCI process group' do
    skip 'requires Linux process state inspection' unless File.directory?('/proc')
    Dir.mktmpdir do |dir|
      pid_path = File.join(dir, 'child.pid')
      code = "pid = Process.spawn(#{RbConfig.ruby.dump}, '-e', 'sleep 30'); File.write(#{pid_path.dump}, pid); sleep 30"
      with_fake_oci(code, timeout: 0.5) do |executor|
        expect { executor.execute(%w[oci iam domain list]) }.to raise_error(Anyspec::DSL::OCI::TimeoutError)
        pid = Integer(File.read(pid_path))
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 2
        loop do
          stat = File.read("/proc/#{pid}/stat") rescue nil
          break if stat.nil? || stat.split[2] == 'Z'
          raise 'child process survived timeout' if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
          sleep 0.01
        end
      ensure
        Process.kill('KILL', pid) rescue nil if pid
      end
    end
  end
end
