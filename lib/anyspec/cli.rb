# frozen_string_literal: true

require 'optparse'
require 'fileutils'

module Anyspec
  class CLI
    DEFAULT_OUT_DIR = 'artifacts'

    def initialize(argv)
      @argv = argv
      @options = {
        out_dir: DEFAULT_OUT_DIR,
        profile: 'DEFAULT',
        config_path: nil
      }
    end

    def run
      parse_options!
      command = @argv.shift

      case command
      when 'check'
        run_check
      when 'version', '-v', '--version'
        puts "anyspec #{Anyspec::VERSION}"
        0
      when 'help', '-h', '--help', nil
        print_help
        0
      else
        $stderr.puts "Unknown command: #{command}"
        print_help
        1
      end
    end

    private

    def parse_options!
      parser = OptionParser.new do |opts|
        opts.banner = "Usage: anyspec <command> [options]"
        opts.separator ""
        opts.separator "Commands:"
        opts.separator "  check <spec.yml|dir>  Run checks against OCI resources"
        opts.separator "  version               Show version"
        opts.separator "  help                  Show this help"
        opts.separator ""
        opts.separator "Options:"

        opts.on('--out-dir DIR', "Output directory for results (default: #{DEFAULT_OUT_DIR})") do |dir|
          @options[:out_dir] = dir
        end

        opts.on('--profile NAME', 'OCI config profile name (default: DEFAULT)') do |profile|
          @options[:profile] = profile
        end

        opts.on('--config PATH', 'Path to OCI config file (default: ~/.oci/config)') do |path|
          @options[:config_path] = path
        end

        opts.on('-h', '--help', 'Show this help') do
          puts opts
          exit 0
        end

        opts.on('-v', '--version', 'Show version') do
          puts "anyspec #{Anyspec::VERSION}"
          exit 0
        end
      end

      parser.order!(@argv)
    end

    def run_check
      spec_path = @argv.shift
      unless spec_path
        $stderr.puts "Error: spec file or directory required"
        return 1
      end

      unless File.exist?(spec_path)
        $stderr.puts "Error: #{spec_path} not found"
        return 1
      end

      config = Config.new(
        profile: @options[:profile],
        config_path: @options[:config_path]
      )

      loader = SpecLoader.new
      specs = loader.load(spec_path)

      runner = Runner.new(config: config)
      results = runner.run(specs)
      summary = runner.summary

      write_reports(results, summary)
      print_summary(summary)

      runner.success? ? 0 : 1
    rescue Anyspec::Error => e
      $stderr.puts "Error: #{e.message}"
      1
    rescue StandardError => e
      $stderr.puts "Unexpected error: #{e.message}"
      $stderr.puts e.backtrace.first(5).join("\n") if ENV['DEBUG']
      1
    end

    def write_reports(results, summary)
      out_dir = @options[:out_dir]
      FileUtils.mkdir_p(out_dir)

      json_reporter = Reporters::JsonReporter.new(results, summary)
      json_reporter.write(File.join(out_dir, 'result.json'))

      md_reporter = Reporters::MarkdownReporter.new(results, summary)
      md_reporter.write(File.join(out_dir, 'result.md'))

      puts "Results written to #{out_dir}/"
    end

    def print_summary(summary)
      puts ""
      puts "=== Anyspec Check Summary ==="
      puts "Total:  #{summary[:total]}"
      puts "Pass:   #{summary[:pass]}"
      puts "Fail:   #{summary[:fail]}"
      puts "Error:  #{summary[:error]}"
      puts ""

      if summary[:fail].positive? || summary[:error].positive?
        puts "Result: FAILED"
      else
        puts "Result: PASSED"
      end
    end

    def print_help
      puts <<~HELP
        Usage: anyspec <command> [options]

        Commands:
          check <spec.yml|dir>  Run checks against OCI resources
          version               Show version
          help                  Show this help

        Options:
          --out-dir DIR     Output directory for results (default: artifacts)
          --profile NAME    OCI config profile name (default: DEFAULT)
          --config PATH     Path to OCI config file (default: ~/.oci/config)
          -h, --help        Show this help
          -v, --version     Show version

        Examples:
          anyspec check examples/oci-guardrails.yml
          anyspec check examples/ --out-dir ./reports
          anyspec check spec.yml --profile PRODUCTION
      HELP
    end
  end
end
