# frozen_string_literal: true

module Anyspec
  class Config
    AUTH_MODES = %w[config_file instance_principal resource_principal].freeze
    DEFAULT_OCI_CLI = 'oci'

    attr_reader :profile, :auth_mode, :config_path, :region, :oci_cli_path, :allow_oci_writes

    def initialize(profile: 'DEFAULT', config_path: nil, auth_mode: nil, region: nil, oci_cli: nil, allow_oci_writes: false)
      @profile = profile
      @auth_mode = determine_auth_mode(auth_mode)
      @config_path = determine_config_path(config_path)
      @region = region || ENV['OCI_REGION']
      @oci_cli_path = determine_oci_cli_path(oci_cli)
      @allow_oci_writes = allow_oci_writes
    end

    private

    def determine_auth_mode(explicit_mode)
      return explicit_mode if explicit_mode && AUTH_MODES.include?(explicit_mode)

      env_mode = ENV['OCI_AUTH_MODE']
      return env_mode if env_mode && AUTH_MODES.include?(env_mode)

      'config_file'
    end

    def determine_config_path(explicit_path)
      return explicit_path if explicit_path && !explicit_path.empty?

      if ENV['OCI_CLI_CONFIG_FILE']
        return ENV['OCI_CLI_CONFIG_FILE']
      end

      nil
    end

    def determine_oci_cli_path(explicit_path)
      return explicit_path if explicit_path && !explicit_path.empty?

      ENV.fetch('OCI_CLI', DEFAULT_OCI_CLI)
    end
  end
end
