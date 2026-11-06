# frozen_string_literal: true

module Anyspec
  module Adapters
    class AuditConfiguration < Base
      ADAPTER_TYPE = 'audit_configuration'

      def fetch(spec)
        compartment_id = spec['compartment_id']
        raise Anyspec::Error, "compartment_id is required for #{ADAPTER_TYPE}" unless compartment_id

        args = ['audit', 'config', 'get', '--compartment-id', compartment_id]
        data = run_oci_cli(args)
        normalized = normalize_oci_response(data)

        extract_configuration(normalized)
      end

      private

      def extract_configuration(config_data)
        {
          'retention_period_days' => config_data['retention_period_days']
        }
      end
    end

    AdapterRegistry.register(AuditConfiguration::ADAPTER_TYPE, AuditConfiguration)
  end
end
