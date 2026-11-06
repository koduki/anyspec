# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'

RSpec.describe Anyspec::CLI do
  describe '#run' do
    context 'with version command' do
      it 'prints version and returns 0' do
        cli = described_class.new(['version'])

        expect { cli.run }.to output(/anyspec #{Anyspec::VERSION}/).to_stdout
      end

      it 'handles -v flag' do
        cli = described_class.new(['-v'])

        expect { cli.run }.to output(/anyspec/).to_stdout
      end
    end

    context 'with help command' do
      it 'prints help and returns 0' do
        cli = described_class.new(['help'])

        expect { cli.run }.to output(/Usage:/).to_stdout
      end
    end

    context 'with unknown command' do
      it 'prints error and returns 1' do
        cli = described_class.new(['unknown'])

        expect { cli.run }.to output(/Unknown command/).to_stderr
      end
    end

    context 'with check command' do
      let(:fixtures_path) { File.expand_path('../fixtures', __dir__) }

      it 'returns error when spec file not provided' do
        cli = described_class.new(['check'])

        result = nil
        expect { result = cli.run }.to output(/spec file or directory required/).to_stderr
        expect(result).to eq(1)
      end

      it 'returns error when spec file not found' do
        cli = described_class.new(['check', '/nonexistent/spec.yml'])

        result = nil
        expect { result = cli.run }.to output(/not found/).to_stderr
        expect(result).to eq(1)
      end
    end
  end

  describe 'option parsing' do
    it 'parses --out-dir option' do
      cli = described_class.new(['--out-dir', '/custom/output', 'help'])
      cli.run
      expect(cli.instance_variable_get(:@options)[:out_dir]).to eq('/custom/output')
    end

    it 'parses --profile option' do
      cli = described_class.new(['--profile', 'PROD', 'help'])
      cli.run
      expect(cli.instance_variable_get(:@options)[:profile]).to eq('PROD')
    end
  end
end
