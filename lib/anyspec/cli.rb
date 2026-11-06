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
        config_path: nil,
        auth_mode: nil
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

        opts.on('--auth-mode MODE', 'OCI auth mode: config_file, instance_principal, resource_principal') do |mode|
          @options[:auth_mode] = mode
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

      run_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      config = Config.new(
        profile: @options[:profile],
        config_path: @options[:config_path],
        auth_mode: @options[:auth_mode]
      )

      loader = SpecLoader.new
      specs = loader.load(spec_path)

      runner = Runner.new(config: config)
      results = runner.run(specs)
      summary = runner.summary

      duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - run_start) * 1000).round

      run_metadata = {
        spec_paths: loader.loaded_paths,
        profile: config.profile,
        region: config.region,
        auth_mode: config.auth_mode,
        duration_ms: duration_ms
      }

      write_reports(results, summary, run_metadata)
      print_progress(results)
      print_summary(summary, runner.exit_code)

      runner.exit_code
    rescue Anyspec::Error => e
      $stderr.puts "Error: #{e.message}"
      2
    rescue StandardError => e
      $stderr.puts "Unexpected error: #{e.message}"
      $stderr.puts e.backtrace.first(5).join("\n") if ENV['DEBUG']
      2
    end

    def write_reports(results, summary, run_metadata)
      out_dir = @options[:out_dir]
      FileUtils.mkdir_p(out_dir)

      json_reporter = Reporters::JsonReporter.new(results, summary, run_metadata: run_metadata)
      json_reporter.write(File.join(out_dir, 'result.json'))

      md_reporter = Reporters::MarkdownReporter.new(results, summary, run_metadata: run_metadata)
      md_reporter.write(File.join(out_dir, 'result.md'))

      puts "Results written to #{out_dir}/"
    end

    def print_progress(results)
      puts ""
      puts "=== Check Results ==="
      results.each do |result|
        status_indicator = case result.status
                           when :pass then '[PASS]'
                           when :fail then '[FAIL]'
                           when :error then '[ERROR]'
                           end

        duration_str = result.duration_ms ? "(#{result.duration_ms}ms)" : ''

        hint = ''
        if result.fail? && result.mismatches&.any?
          first_mismatch = result.mismatches.first
          hint = " - #{first_mismatch[:path]}: expected '#{first_mismatch[:expected]}', got '#{first_mismatch[:actual]}'"
          hint = hint[0, 80] + '...' if hint.length > 83
        elsif result.error?
          hint = " - #{result.message}"
          hint = hint[0, 80] + '...' if hint.length > 83
        end

        puts "#{status_indicator} #{result.id} #{duration_str}#{hint}"
      end
    end

    def print_summary(summary, exit_code)
      puts ""
      puts "=== Anyspec Check Summary ==="
      puts "Total:  #{summary[:total]}"
      puts "Pass:   #{summary[:pass]}"
      puts "Fail:   #{summary[:fail]}"
      puts "Error:  #{summary[:error]}"
      puts ""

      case exit_code
      when 0
        puts "Result: PASSED"
      when 1
        puts "Result: FAILED (drift detected)"
      when 2
        puts "Result: ERROR (fetch/config error, no drift)"
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
          --out-dir DIR       Output directory for results (default: artifacts)
          --profile NAME      OCI config profile name (default: DEFAULT)
          --config PATH       Path to OCI config file (default: ~/.oci/config)
          --auth-mode MODE    OCI auth: config_file (default), instance_principal, resource_principal
          -h, --help          Show this help
          -v, --version       Show version

        Environment Variables:
          OCI_AUTH_MODE       Override auth mode (config_file, instance_principal, resource_principal)
          OCI_REGION          Region for instance/resource principal auth

        Exit Codes:
          0  All checks passed
          1  At least one check failed (drift detected)
          2  Error occurred (fetch/auth error), no drift detected

        Examples:
          anyspec check examples/oci-guardrails.yml
          anyspec check examples/ --out-dir ./reports
          anyspec check spec.yml --profile PRODUCTION
          anyspec check spec.yml --auth-mode instance_principal
      HELP
    end
  end
end
