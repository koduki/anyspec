# frozen_string_literal: true

require 'oci'

module Anyspec
  class Config
    attr_reader :profile, :oci_config

    def initialize(profile: 'DEFAULT', config_path: nil)
      @profile = profile
      @config_path = config_path || File.join(Dir.home, '.oci', 'config')
      @oci_config = load_oci_config
    end

    def oci_client_config
      @oci_config
    end

    private

    def load_oci_config
      OCI::ConfigFileLoader.load_config(
        config_file_location: @config_path,
        profile_name: @profile
      )
    rescue StandardError => e
      raise Anyspec::Error, "Failed to load OCI config: #{e.message}"
    end
  end
end
