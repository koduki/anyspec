# frozen_string_literal: true

require 'oci'

module Anyspec
  module Adapters
    class CloudGuardConfiguration < Base
      ADAPTER_TYPE = 'cloud_guard_configuration'

      def fetch(spec)
        compartment_id = spec['compartment_id']
        raise Anyspec::Error, "compartment_id is required for #{ADAPTER_TYPE}" unless compartment_id

        client = create_client(OCI::CloudGuard::CloudGuardClient)
        response = client.get_configuration(compartment_id)

        extract_configuration(response.data)
      end

      private

      def extract_configuration(config_obj)
        {
          'status' => config_obj.status,
          'reporting_region' => config_obj.reporting_region,
          'self_manage_resources' => config_obj.self_manage_resources
        }
      end
    end

    AdapterRegistry.register(CloudGuardConfiguration::ADAPTER_TYPE, CloudGuardConfiguration)
  end
end
