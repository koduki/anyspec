# frozen_string_literal: true

module Anyspec
  module Adapters
    class IdentityAuthenticationPolicy < Base
      ADAPTER_TYPE = 'identity_authentication_policy'

      def fetch(spec)
        compartment_id = spec['compartment_id']
        raise Anyspec::Error, "compartment_id is required for #{ADAPTER_TYPE}" unless compartment_id

        args = ['iam', 'authentication-policy', 'get', '--compartment-id', compartment_id]
        data = run_oci_cli(args)
        normalized = normalize_oci_response(data)

        extract_policy(normalized)
      end

      private

      def extract_policy(policy_data)
        result = {
          'compartment_id' => policy_data['compartment_id']
        }

        if policy_data['password_policy']
          result['password_policy'] = extract_password_policy(policy_data['password_policy'])
        end

        if policy_data['network_policy']
          result['network_policy'] = extract_network_policy(policy_data['network_policy'])
        end

        result
      end

      def extract_password_policy(pp)
        {
          'minimum_password_length' => pp['minimum_password_length'],
          'is_uppercase_characters_required' => pp['is_uppercase_characters_required'],
          'is_lowercase_characters_required' => pp['is_lowercase_characters_required'],
          'is_numeric_characters_required' => pp['is_numeric_characters_required'],
          'is_special_characters_required' => pp['is_special_characters_required'],
          'is_username_containment_allowed' => pp['is_username_containment_allowed']
        }
      end

      def extract_network_policy(np)
        {
          'network_source_ids' => np['network_source_ids']
        }
      end
    end

    AdapterRegistry.register(IdentityAuthenticationPolicy::ADAPTER_TYPE, IdentityAuthenticationPolicy)
  end
end
