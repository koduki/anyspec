# frozen_string_literal: true

require 'oci'

module Anyspec
  module Adapters
    class AuditConfiguration < Base
      ADAPTER_TYPE = 'audit_configuration'

      def fetch(spec)
        compartment_id = spec['compartment_id']
        raise Anyspec::Error, "compartment_id is required for #{ADAPTER_TYPE}" unless compartment_id

        client = create_client(OCI::Audit::AuditClient)
        response = client.get_configuration(compartment_id)

        extract_configuration(response.data)
      end

      private

      def extract_configuration(config_obj)
        {
          'retention_period_days' => config_obj.retention_period_days
        }
      end
    end

    AdapterRegistry.register(AuditConfiguration::ADAPTER_TYPE, AuditConfiguration)
  end
end
