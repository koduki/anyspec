# frozen_string_literal: true

require 'oci'
require 'securerandom'

module Anyspec
  class Config
    AUTH_MODES = %w[config_file instance_principal resource_principal].freeze

    attr_reader :profile, :oci_config, :auth_mode

    def initialize(profile: 'DEFAULT', config_path: nil, auth_mode: nil)
      @profile = profile
      @config_path = config_path || File.join(Dir.home, '.oci', 'config')
      @auth_mode = determine_auth_mode(auth_mode)
      @oci_config = load_oci_config
    end

    def oci_client_config
      @oci_config
    end

    def region
      return @oci_config.region if @oci_config.respond_to?(:region)

      nil
    end

    def signer
      @signer
    end

    private

    def determine_auth_mode(explicit_mode)
      return explicit_mode if explicit_mode && AUTH_MODES.include?(explicit_mode)

      env_mode = ENV['OCI_AUTH_MODE']
      return env_mode if env_mode && AUTH_MODES.include?(env_mode)

      'config_file'
    end

    def load_oci_config
      case @auth_mode
      when 'instance_principal'
        load_instance_principal_config
      when 'resource_principal'
        load_resource_principal_config
      else
        load_config_file
      end
    rescue StandardError => e
      raise Anyspec::Error, "Failed to load OCI config (#{@auth_mode}): #{e.message}"
    end

    def load_config_file
      OCI::ConfigFileLoader.load_config(
        config_file_location: @config_path,
        profile_name: @profile
      )
    end

    def load_instance_principal_config
      @signer = OCI::Auth::Signers::InstancePrincipalsSecurityTokenSigner.new
      region = @signer.region || ENV['OCI_REGION']

      config = OCI::Config.new
      config.region = region
      config
    end

    def load_resource_principal_config
      @signer = OCI::Auth::Signers::get_resource_principals_signer
      region = ENV['OCI_RESOURCE_PRINCIPAL_REGION'] || ENV['OCI_REGION']

      config = OCI::Config.new
      config.region = region
      config
    end
  end
end
