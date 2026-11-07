# frozen_string_literal: true

require 'anyspec/dsl/ast'
require 'anyspec/dsl/lexer'
require 'anyspec/dsl/parser'
require 'anyspec/dsl/interpreter'
require 'anyspec/dsl/builtins'
require 'anyspec/dsl/oci/builtins'
require 'anyspec/dsl/oci/executor'
require 'anyspec/dsl/oci/pagination'
require 'anyspec/dsl/runner'
require 'json'

module DSLTestHelper
  GEM_ROOT = File.expand_path('../..', __dir__)
  FIXTURES_PATH = File.join(GEM_ROOT, 'spec/fixtures/oci')
  SCRIPTS_PATH = File.join(GEM_ROOT, 'scripts')

  def self.fixture_path(name)
    File.join(FIXTURES_PATH, "#{name}.json")
  end

  def self.load_fixture(name)
    JSON.parse(File.read(fixture_path(name)))
  end

  def self.run_dsl(source, env: {}, executor: nil)
    lexer = Anyspec::DSL::Lexer.new(source, file: '<test>')
    tokens = lexer.tokenize
    parser = Anyspec::DSL::Parser.new(tokens, file: '<test>')
    program = parser.parse

    builtins = Anyspec::DSL::Builtins.new
    config = Anyspec::Config.new

    executor ||= Anyspec::DSL::OCI::Executor.new(config: config)
    pagination = Anyspec::DSL::OCI::Pagination.new(executor: executor)
    oci_builtins = Anyspec::DSL::OCI::OciBuiltins.new(executor: executor, pagination: pagination)
    oci_builtins.register_all(builtins)

    interpreter = Anyspec::DSL::Interpreter.new(builtins: builtins)
    env.each { |k, v| interpreter.env.set(k.to_s, v) }
    result = interpreter.evaluate(program)

    DSLResult.new(result, interpreter.warnings)
  end

  class DSLResult
    attr_reader :value, :warnings

    def initialize(value, warnings)
      @value = value
      @warnings = warnings
    end

    def [](key)
      @value[key]
    end

    def to_h
      @value
    end

    def method_missing(method, *args, &block)
      @value.send(method, *args, &block)
    end

    def respond_to_missing?(method, include_private = false)
      @value.respond_to?(method, include_private)
    end
  end

  def self.run_collector_script(executor:, tenancy_id: 'ocid1.tenancy.oc1..aaaaaaaatesttenancy')
    script_path = File.join(SCRIPTS_PATH, 'oci_identity_domains.flow')
    source = File.read(script_path)

    run_dsl(source, env: { 'TENANCY_OCID' => tenancy_id }, executor: executor)
  end

  class CollectorMockExecutor
    attr_reader :calls

    def initialize(fixtures: {}, custom_responses: {})
      @fixtures = fixtures
      @custom_responses = custom_responses
      @calls = []
    end

    def execute(argv, location: nil)
      @calls << { argv: argv, location: location }

      response = find_response(argv)
      if response.nil?
        raise Anyspec::DSL::OCI::CLIError.new("Mock: no response for #{argv.inspect}", location)
      end

      response.is_a?(Proc) ? response.call(argv) : response
    end

    private

    def find_response(argv)
      cmd_str = argv.join(' ')

      @custom_responses.each do |pattern, response|
        case pattern
        when Regexp
          return response if cmd_str.match?(pattern)
        when String
          return response if cmd_str.include?(pattern)
        when Array
          return response if pattern.all? { |p| cmd_str.include?(p.to_s) }
        end
      end

      route_to_fixture(argv)
    end

    def route_to_fixture(argv)
      cmd_str = argv.join(' ')

      if cmd_str.include?('iam compartment list')
        @fixtures[:compartments] || DSLTestHelper.load_fixture('compartments')
      elsif cmd_str.include?('iam domain list')
        @fixtures[:domains] || DSLTestHelper.load_fixture('domains')
      elsif cmd_str.include?('identity-domains policies list') || cmd_str.include?('identity-domains policy list')
        @fixtures[:policies] || DSLTestHelper.load_fixture('policies_all')
      elsif cmd_str.include?('identity-domains rules list') || cmd_str.include?('identity-domains rule list')
        @fixtures[:rules] || DSLTestHelper.load_fixture('rules_all')
      elsif cmd_str.include?('identity-domains conditions list') || cmd_str.include?('identity-domains condition list')
        @fixtures[:conditions] || DSLTestHelper.load_fixture('conditions_all')
      elsif cmd_str.include?('identity-domains network-perimeters list') || cmd_str.include?('identity-domains network-perimeter list')
        @fixtures[:network_perimeters] || DSLTestHelper.load_fixture('network_perimeters_all')
      elsif cmd_str.include?('identity-domains identity-providers list') || cmd_str.include?('identity-domains identity-provider list')
        @fixtures[:identity_providers] || DSLTestHelper.load_fixture('identity_providers_all')
      elsif cmd_str.include?('identity-domains social-identity-providers list') || cmd_str.include?('identity-domains social-identity-provider list')
        @fixtures[:social_providers] || DSLTestHelper.load_fixture('social_providers_all')
      elsif cmd_str.include?('identity-domains password-policies list') || cmd_str.include?('identity-domains password-policy list')
        @fixtures[:password_policies] || DSLTestHelper.load_fixture('password_policies_all')
      elsif cmd_str.include?('identity-domains authentication-factor-settings list') || cmd_str.include?('identity-domains authentication-factor-setting list')
        @fixtures[:auth_factor_settings] || DSLTestHelper.load_fixture('auth_factor_settings')
      elsif cmd_str.include?('identity-domains kmsi-settings list') || cmd_str.include?('identity-domains kmsi-setting list')
        @fixtures[:kmsi_settings] || DSLTestHelper.load_fixture('kmsi_settings')
      elsif cmd_str.include?('identity-domains apps list') || cmd_str.include?('identity-domains app list')
        @fixtures[:apps] || DSLTestHelper.load_fixture('apps_all')
      elsif cmd_str.include?('identity-domains app-roles list') || cmd_str.include?('identity-domains app-role list')
        @fixtures[:admin_roles] || DSLTestHelper.load_fixture('admin_roles_all')
      elsif cmd_str.include?('identity-domains grants list') || cmd_str.include?('identity-domains grant list')
        @fixtures[:grants] || DSLTestHelper.load_fixture('grants_admin_role')
      elsif cmd_str.include?('identity-domains groups list') || cmd_str.include?('identity-domains group list')
        if cmd_str.include?('displayName eq')
          @fixtures[:admin_groups] || DSLTestHelper.load_fixture('groups_all')
        else
          @fixtures[:groups] || DSLTestHelper.load_fixture('groups_all')
        end
      elsif cmd_str.include?('identity-domains group get')
        @fixtures[:group_detail] || DSLTestHelper.load_fixture('group_admin')
      elsif cmd_str.include?('identity-domains group-members list') || cmd_str.include?('identity-domains my-group list')
        @fixtures[:group_members] || DSLTestHelper.load_fixture('group_members')
      elsif cmd_str.include?('identity-domains user get')
        @fixtures[:user_detail] || DSLTestHelper.load_fixture('user_admin')
      elsif cmd_str.include?('raw-request') && cmd_str.include?('ConditionGroups')
        @fixtures[:condition_groups] || DSLTestHelper.load_fixture('condition_groups_raw')
      elsif cmd_str.include?('raw-request') && cmd_str.include?('SsoSettings')
        @fixtures[:sso_settings] || DSLTestHelper.load_fixture('sso_settings_raw')
      elsif cmd_str.include?('raw-request')
        { 'data' => '{"Resources":[],"totalResults":0}', 'headers' => {}, 'status' => '200 OK' }
      else
        nil
      end
    end
  end

  class WarningCapture
    attr_reader :warnings

    def initialize
      @warnings = []
    end

    def capture(message)
      @warnings << message
    end
  end
end
