# frozen_string_literal: true

module Anyspec
  module Adapters
    class CloudGuardConfiguration < Base
      ADAPTER_TYPE = 'cloud_guard_configuration'

      def fetch(spec)
        compartment_id = spec['compartment_id']
        raise Anyspec::Error, "compartment_id is required for #{ADAPTER_TYPE}" unless compartment_id

        args = ['cloud-guard', 'configuration', 'get', '--compartment-id', compartment_id]
        data = run_oci_cli(args)
        normalized = normalize_oci_response(data)

        extract_configuration(normalized)
      end

      private

      def extract_configuration(config_data)
        {
          'status' => config_data['status'],
          'reporting_region' => config_data['reporting_region'],
          'self_manage_resources' => config_data['self_manage_resources']
        }
      end
    end

    AdapterRegistry.register(CloudGuardConfiguration::ADAPTER_TYPE, CloudGuardConfiguration)
  end
end
