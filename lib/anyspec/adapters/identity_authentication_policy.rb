# frozen_string_literal: true

require 'oci'

module Anyspec
  module Adapters
    class IdentityAuthenticationPolicy < Base
      ADAPTER_TYPE = 'identity_authentication_policy'

      def fetch(spec)
        compartment_id = spec['compartment_id']
        raise Anyspec::Error, "compartment_id is required for #{ADAPTER_TYPE}" unless compartment_id

        client = OCI::Identity::IdentityClient.new(config: config.oci_client_config)
        response = client.get_authentication_policy(compartment_id)

        extract_policy(response.data)
      end

      private

      def extract_policy(policy)
        result = {
          'compartment_id' => policy.compartment_id
        }

        if policy.password_policy
          result['password_policy'] = extract_password_policy(policy.password_policy)
        end

        if policy.network_policy
          result['network_policy'] = extract_network_policy(policy.network_policy)
        end

        result
      end

      def extract_password_policy(pp)
        {
          'minimum_password_length' => pp.minimum_password_length,
          'is_uppercase_characters_required' => pp.is_uppercase_characters_required,
          'is_lowercase_characters_required' => pp.is_lowercase_characters_required,
          'is_numeric_characters_required' => pp.is_numeric_characters_required,
          'is_special_characters_required' => pp.is_special_characters_required,
          'is_username_containment_allowed' => pp.is_username_containment_allowed
        }
      end

      def extract_network_policy(np)
        {
          'network_source_ids' => np.network_source_ids
        }
      end
    end

    AdapterRegistry.register(IdentityAuthenticationPolicy::ADAPTER_TYPE, IdentityAuthenticationPolicy)
  end
end
