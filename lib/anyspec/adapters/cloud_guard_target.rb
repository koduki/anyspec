# frozen_string_literal: true

module Anyspec
  module Adapters
    class CloudGuardTarget < Base
      ADAPTER_TYPE = 'cloud_guard_target'

      def fetch(spec)
        compartment_id = spec['compartment_id']
        raise Anyspec::Error, "compartment_id is required for #{ADAPTER_TYPE}" unless compartment_id

        if spec['target_id']
          fetch_by_id(spec['target_id'])
        elsif spec['name']
          fetch_by_name(compartment_id, spec['name'])
        else
          raise Anyspec::Error, "Either target_id or name is required for #{ADAPTER_TYPE}"
        end
      end

      private

      def fetch_by_id(target_id)
        args = ['cloud-guard', 'target', 'get', '--target-id', target_id]
        data = run_oci_cli(args)
        normalized = normalize_oci_response(data)
        extract_target(normalized)
      end

      def fetch_by_name(compartment_id, name)
        args = ['cloud-guard', 'target', 'list', '--compartment-id', compartment_id, '--display-name', name]
        data = run_oci_cli(args)

        items = extract_items_from_list(data)

        target = items.find { |t| find_display_name(t) == name }
        raise Anyspec::Error, "Target not found with name: #{name}" unless target

        normalized = normalize_oci_response(target)
        extract_target(normalized)
      end

      def extract_items_from_list(data)
        return data if data.is_a?(Array)
        return data['items'] if data.is_a?(Hash) && data['items']

        [data]
      end

      def find_display_name(item)
        item['display-name'] || item['displayName'] || item['display_name']
      end

      def extract_target(target_data)
        {
          'id' => target_data['id'],
          'display_name' => target_data['display_name'],
          'compartment_id' => target_data['compartment_id'],
          'target_resource_type' => target_data['target_resource_type'],
          'target_resource_id' => target_data['target_resource_id'],
          'lifecycle_state' => target_data['lifecycle_state']
        }
      end
    end

    AdapterRegistry.register(CloudGuardTarget::ADAPTER_TYPE, CloudGuardTarget)
  end
end
