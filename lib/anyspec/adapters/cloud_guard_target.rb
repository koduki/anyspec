# frozen_string_literal: true

require 'oci'

module Anyspec
  module Adapters
    class CloudGuardTarget < Base
      ADAPTER_TYPE = 'cloud_guard_target'

      def fetch(spec)
        compartment_id = spec['compartment_id']
        raise Anyspec::Error, "compartment_id is required for #{ADAPTER_TYPE}" unless compartment_id

        client = create_client(OCI::CloudGuard::CloudGuardClient)

        if spec['target_id']
          response = client.get_target(spec['target_id'])
          extract_target(response.data)
        elsif spec['name']
          target = find_target_by_name(client, compartment_id, spec['name'])
          raise Anyspec::Error, "Target not found with name: #{spec['name']}" unless target

          extract_target(target)
        else
          raise Anyspec::Error, "Either target_id or name is required for #{ADAPTER_TYPE}"
        end
      end

      private

      def find_target_by_name(client, compartment_id, name)
        response = client.list_targets(compartment_id, display_name: name)
        response.data.find { |t| t.display_name == name }
      end

      def extract_target(target)
        {
          'id' => target.id,
          'display_name' => target.display_name,
          'compartment_id' => target.compartment_id,
          'target_resource_type' => target.target_resource_type,
          'target_resource_id' => target.target_resource_id,
          'lifecycle_state' => target.lifecycle_state
        }
      end
    end

    AdapterRegistry.register(CloudGuardTarget::ADAPTER_TYPE, CloudGuardTarget)
  end
end
