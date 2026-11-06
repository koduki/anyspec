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

      it 'includes --fail-on in help' do
        cli = described_class.new(['help'])

        expect { cli.run }.to output(/--fail-on/).to_stdout
      end

      it 'includes validate command in help' do
        cli = described_class.new(['help'])

        expect { cli.run }.to output(/validate/).to_stdout
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

    context 'with validate command' do
      let(:fixtures_path) { File.expand_path('../fixtures', __dir__) }

      it 'returns 0 for valid specs' do
        ENV['TEST_COMPARTMENT_ID'] = 'ocid1.test'

        cli = described_class.new(['validate', File.join(fixtures_path, 'valid_spec.yml')])

        result = nil
        expect { result = cli.run }.to output(/All specs valid/).to_stdout
        expect(result).to eq(0)

        ENV.delete('TEST_COMPARTMENT_ID')
      end

      it 'returns 2 for invalid specs' do
        Dir.mktmpdir do |tmpdir|
          spec_file = File.join(tmpdir, 'invalid.yml')
          File.write(spec_file, <<~YAML)
            - id: missing-fields
              title: Missing Fields Test
          YAML

          cli = described_class.new(['validate', spec_file])

          result = nil
          expect { result = cli.run }.to output(/Validation FAILED/).to_stdout
          expect(result).to eq(2)
        end
      end

      it 'returns error when spec path not provided' do
        cli = described_class.new(['validate'])

        result = nil
        expect { result = cli.run }.to output(/spec file or directory required/).to_stderr
        expect(result).to eq(1)
      end

      it 'returns error when spec path not found' do
        cli = described_class.new(['validate', '/nonexistent/spec.yml'])

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

    it 'parses --fail-on option' do
      cli = described_class.new(['--fail-on', 'never', 'help'])
      cli.run
      expect(cli.instance_variable_get(:@options)[:fail_on]).to eq('never')
    end

    it 'rejects invalid --fail-on value' do
      cli = described_class.new(['--fail-on', 'invalid', 'help'])

      result = nil
      expect { result = cli.run }.to output(/Invalid --fail-on value/).to_stderr
      expect(result).to eq(1)
    end

    it 'accepts fail as --fail-on value' do
      cli = described_class.new(['--fail-on', 'fail', 'help'])
      cli.run
      expect(cli.instance_variable_get(:@options)[:fail_on]).to eq('fail')
    end

    it 'accepts error as --fail-on value' do
      cli = described_class.new(['--fail-on', 'error', 'help'])
      cli.run
      expect(cli.instance_variable_get(:@options)[:fail_on]).to eq('error')
    end
  end

  describe '#calculate_exit_code' do
    let(:cli) { described_class.new([]) }

    context 'with no --fail-on option' do
      it 'returns base exit code unchanged' do
        expect(cli.send(:calculate_exit_code, 0)).to eq(0)
        expect(cli.send(:calculate_exit_code, 1)).to eq(1)
        expect(cli.send(:calculate_exit_code, 2)).to eq(2)
      end
    end

    context 'with --fail-on fail' do
      before { cli.instance_variable_get(:@options)[:fail_on] = 'fail' }

      it 'returns 1 for drift (exit code 1)' do
        expect(cli.send(:calculate_exit_code, 1)).to eq(1)
      end

      it 'returns 2 for errors only (exit code 2)' do
        expect(cli.send(:calculate_exit_code, 2)).to eq(2)
      end

      it 'returns 0 for success' do
        expect(cli.send(:calculate_exit_code, 0)).to eq(0)
      end
    end

    context 'with --fail-on error' do
      before { cli.instance_variable_get(:@options)[:fail_on] = 'error' }

      it 'returns 0 for drift (exit code 1)' do
        expect(cli.send(:calculate_exit_code, 1)).to eq(0)
      end

      it 'returns 2 for errors only (exit code 2)' do
        expect(cli.send(:calculate_exit_code, 2)).to eq(2)
      end

      it 'returns 0 for success' do
        expect(cli.send(:calculate_exit_code, 0)).to eq(0)
      end
    end

    context 'with --fail-on never' do
      before { cli.instance_variable_get(:@options)[:fail_on] = 'never' }

      it 'returns 0 for any exit code' do
        expect(cli.send(:calculate_exit_code, 0)).to eq(0)
        expect(cli.send(:calculate_exit_code, 1)).to eq(0)
        expect(cli.send(:calculate_exit_code, 2)).to eq(0)
      end
    end
  end
end
