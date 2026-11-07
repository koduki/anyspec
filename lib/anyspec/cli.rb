# frozen_string_literal: true

require 'optparse'
require 'fileutils'
require 'open3'

module Anyspec
  class CLI
    DEFAULT_OUT_DIR = 'artifacts'
    FAIL_ON_OPTIONS = %w[fail error never].freeze

    def initialize(argv)
      @argv = argv
      @options = {
        out_dir: DEFAULT_OUT_DIR,
        profile: 'DEFAULT',
        config_path: nil,
        auth_mode: nil,
        fail_on: nil,
        oci_cli: nil,
        adapters_dir: ENV['ANYSPEC_ADAPTERS_DIR']
      }
      @external_adapter_info = nil
    end

    def run
      parse_options!
      return 1 if @options[:parse_error]
      return 0 if @options[:info]

      command = @argv.shift

      case command
      when 'check'
        run_check
      when 'validate'
        run_validate
      when 'collect'
        run_collect
      when 'validate-dsl'
        run_validate_dsl
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
        opts.separator "  check <spec.yml|dir>     Run checks against OCI resources"
        opts.separator "  validate <spec.yml|dir>  Validate spec files offline (no OCI access)"
        opts.separator "  collect <script> <inputs.json>  Collect a DSL snapshot as JSON on stdout"
        opts.separator "  validate-dsl <script>    Validate DSL syntax and commands offline"
        opts.separator "  version                  Show version"
        opts.separator "  help                     Show this help"
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

        opts.on('--fail-on MODE', 'When to exit non-zero: fail (drift), error (fetch issues), never') do |mode|
          unless FAIL_ON_OPTIONS.include?(mode)
            raise OptionParser::InvalidArgument, "Invalid --fail-on value '#{mode}'. Must be one of: #{FAIL_ON_OPTIONS.join(', ')}"
          end
          @options[:fail_on] = mode
        end

        opts.on('--oci-cli PATH', 'Path to OCI CLI executable (default: oci, or OCI_CLI env var)') do |path|
          @options[:oci_cli] = path
        end

        opts.on('--adapters-dir DIR', 'Directory with external adapter definitions (multiple via path separator)') do |dir|
          @options[:adapters_dir] = dir
        end

        opts.on('-h', '--help', 'Show this help') do
          puts opts
          @options[:info] = true
        end

        opts.on('-v', '--version', 'Show version') do
          puts "anyspec #{Anyspec::VERSION}"
          @options[:info] = true
        end
      end

      parser.order!(@argv)
    rescue OptionParser::InvalidArgument => e
      $stderr.puts "Error: #{e.message}"
      @options[:parse_error] = true
    end

    def run_validate_dsl
      path = @argv.shift
      raise Anyspec::Error, 'DSL script required' unless path
      nodes = DSL::Parser.new(File.read(path), file: path).parse
      DSL::Runtime.new.validate(nodes, file: path)
      puts "DSL valid: #{path}"
      0
    rescue Anyspec::Error, SystemCallError => e
      $stderr.puts "Error: #{e.message}"
      2
    end

    def run_collect
      path, inputs_path = @argv.shift(2)
      raise Anyspec::Error, 'DSL script and JSON input file required' unless path && inputs_path
      inputs = JSON.parse(File.read(inputs_path))
      raise Anyspec::Error, 'DSL inputs must be a JSON object' unless inputs.is_a?(Hash)
      config = Config.new(profile: @options[:profile], config_path: @options[:config_path],
                          auth_mode: @options[:auth_mode], oci_cli: @options[:oci_cli])
      runtime = DSL::Runtime.new(transport: DSL::OCI.new(config))
      snapshot = runtime.run(File.read(path), variables: { 'input' => inputs }, file: path)
      runtime.warnings.each { |w| $stderr.puts "Warning [#{w['code']}] #{w['context']}: #{w['message']}" }
      puts JSON.pretty_generate(snapshot)
      0
    rescue Anyspec::Error, SystemCallError, JSON::ParserError => e
      $stderr.puts "Error: #{e.message}"
      2
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

      load_external_adapters

      config = Config.new(
        profile: @options[:profile],
        config_path: @options[:config_path],
        auth_mode: @options[:auth_mode],
        oci_cli: @options[:oci_cli]
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
        duration_ms: duration_ms,
        anyspec_version: Anyspec::VERSION,
        adapter_schema_version: ExternalAdapterLoader.schema_version,
        oci_cli_version: detect_oci_cli_version(config),
        external_adapters: @external_adapter_info
      }

      write_reports(results, summary, run_metadata)
      print_progress(results)

      base_exit_code = runner.exit_code
      process_exit_code = calculate_exit_code(base_exit_code)

      handle_github_actions(results, summary, run_metadata, base_exit_code)

      print_summary(summary, base_exit_code)

      process_exit_code
    rescue Anyspec::Error => e
      $stderr.puts "Error: #{e.message}"
      2
    rescue StandardError => e
      $stderr.puts "Unexpected error: #{e.message}"
      $stderr.puts e.backtrace.first(5).join("\n") if ENV['DEBUG']
      2
    end

    def calculate_exit_code(base_exit_code)
      return base_exit_code unless @options[:fail_on]

      case @options[:fail_on]
      when 'fail'
        base_exit_code == 1 ? 1 : (base_exit_code == 2 ? 2 : 0)
      when 'error'
        base_exit_code == 2 ? 2 : 0
      when 'never'
        0
      else
        base_exit_code
      end
    end

    def handle_github_actions(results, summary, run_metadata, base_exit_code)
      return unless Reporters::GitHubActionsReporter.github_actions?

      ga_reporter = Reporters::GitHubActionsReporter.new(results, summary, run_metadata: run_metadata)
      ga_reporter.write_step_summary
      ga_reporter.emit_workflow_commands
      ga_reporter.write_github_output(base_exit_code)
    end

    def run_validate
      spec_path = @argv.shift
      unless spec_path
        $stderr.puts "Error: spec file or directory required"
        return 1
      end

      unless File.exist?(spec_path)
        $stderr.puts "Error: #{spec_path} not found"
        return 1
      end

      load_external_adapters

      validator = Validator.new
      valid = validator.validate(spec_path)

      if valid
        puts "=== Validation Results ==="
        puts "All specs valid: #{validator.loaded_specs.size} spec(s) validated"
        validator.warnings.each do |warning|
          puts "[WARNING] #{warning.message}"
        end
        0
      else
        puts "=== Validation Results ==="
        puts "Validation FAILED with #{validator.errors.size} error(s)"
        puts ""
        validator.error_messages.each do |msg|
          puts "[ERROR] #{msg}"
        end
        2
      end
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

    def load_external_adapters
      adapter_loader = ExternalAdapterLoader.new(adapters_dir: @options[:adapters_dir])
      adapter_loader.load_all
      @external_adapter_info = AdapterRegistry.external_adapter_info

      if @external_adapter_info[:loaded_files].any?
        puts "Loaded external adapters from: #{@external_adapter_info[:loaded_files].join(', ')}"
        @external_adapter_info[:overridden_builtins].each do |override|
          puts "  Note: Built-in '#{override[:type]}' overridden by #{override[:source_file]}"
        end
      end
    end

    def detect_oci_cli_version(config)
      stdout, _stderr, status = Open3.capture3(config.oci_cli_path, '--version')
      return nil unless status.success?

      stdout.strip.sub(/^oci\s+/i, '')
    rescue StandardError
      nil
    end

    def print_help
      puts <<~HELP
        Usage: anyspec <command> [options]

        Commands:
          check <spec.yml|dir>     Run checks against OCI resources
          validate <spec.yml|dir>  Validate spec files offline (no OCI access required)
          collect <script> <inputs.json>  Collect a DSL snapshot as JSON on stdout
          validate-dsl <script>    Validate DSL syntax and commands offline
          version                  Show version
          help                     Show this help

        Options:
          --out-dir DIR       Output directory for results (default: artifacts)
          --profile NAME      OCI config profile name (default: DEFAULT)
          --config PATH       Path to OCI config file (default: ~/.oci/config)
          --auth-mode MODE    OCI auth: config_file (default), instance_principal, resource_principal
          --oci-cli PATH      Path to OCI CLI executable (default: oci, or OCI_CLI env var)
          --adapters-dir DIR  Directory with external adapter definitions (canonical source)
                              Multiple directories via platform path separator (: on Unix, ; on Windows)
          --fail-on MODE      When to exit non-zero (default: both fail and error exit non-zero)
                              fail:  Exit 1 on drift, exit 2 on errors only
                              error: Exit 2 on errors only (drift exits 0)
                              never: Always exit 0 (still writes reports and outputs)
          -h, --help          Show this help
          -v, --version       Show version

        Environment Variables:
          OCI_CLI                  Path to OCI CLI executable
          OCI_CLI_CONFIG_FILE      Path to OCI config file
          OCI_AUTH_MODE            Override auth mode (config_file, instance_principal, resource_principal)
          OCI_REGION               Region for instance/resource principal auth
          ANYSPEC_ADAPTERS_DIR     External adapter definitions directory (same as --adapters-dir)

        External Adapters:
          Search order (higher priority wins on type-name conflicts):
          1. --adapters-dir / ANYSPEC_ADAPTERS_DIR (canonical source for version control)
          2. adapters/ directory beside the executable
          3. .anyspec/adapters/ in current directory (personal/trial use)
          4. ~/.anyspec/adapters/ in home directory (personal/trial use)

        GitHub Actions Integration:
          When GITHUB_ACTIONS=true is detected:
          - Writes Markdown report to $GITHUB_STEP_SUMMARY
          - Emits ::error and ::notice workflow commands with file annotations
          - Writes pass/fail/error/exit_code to $GITHUB_OUTPUT

        Exit Codes:
          0  All checks passed (check) / All specs valid (validate)
          1  At least one check failed (drift detected)
          2  Error occurred (fetch/auth error, validation error, or config problem)

        Examples:
          anyspec check examples/oci-guardrails.yml
          anyspec check examples/ --out-dir ./reports
          anyspec check spec.yml --profile PRODUCTION
          anyspec check spec.yml --auth-mode instance_principal
          anyspec check spec.yml --adapters-dir ./adapters
          anyspec check spec.yml --fail-on never
          anyspec validate examples/
          anyspec validate spec.yml
      HELP
    end
  end
end
