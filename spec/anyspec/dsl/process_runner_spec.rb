# frozen_string_literal: true
require 'spec_helper'
require 'rbconfig'

RSpec.describe Anyspec::DSL::ProcessRunner do
  def invoke(code, *args, **options)
    described_class.new(**options).call([RbConfig.ruby, '-e', code, *args])
  end

  it 'closes stdin and preserves shell-looking arguments literally' do
    result = invoke('require "json"; puts JSON.generate([STDIN.read, ARGV])', '$(echo bad)', '; touch never')
    expect(result).to eq(['', ['$(echo bad)', '; touch never']])
  end

  it 'rejects failed, empty and malformed responses' do
    expect { invoke('exit 7') }.to raise_error(/exited 7/)
    expect { invoke('puts " "') }.to raise_error(/empty output/)
    expect { invoke('puts "bad json"') }.to raise_error(/invalid JSON/)
  end

  it 'bounds stdout and stderr, and kills stalled commands' do
    expect { invoke('STDOUT.write("x" * 10000)', max_output: 100) }.to raise_error(/output limit/)
    expect { invoke('STDERR.write("x" * 10000)', max_output: 100) }.to raise_error(/output limit/)
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    expect { invoke('sleep 10', timeout: 0.1) }.to raise_error(/timed out/)
    expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).to be < 3
  end
end
