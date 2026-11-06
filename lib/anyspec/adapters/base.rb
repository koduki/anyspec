# frozen_string_literal: true

module Anyspec
  module Adapters
    class Base
      attr_reader :config

      def initialize(config)
        @config = config
      end

      def fetch(_spec)
        raise NotImplementedError, "#{self.class}#fetch must be implemented"
      end

      protected

      def create_client(client_class)
        if config.signer
          client_class.new(config: config.oci_client_config, signer: config.signer)
        else
          client_class.new(config: config.oci_client_config)
        end
      end

      def symbolize_keys(hash)
        return hash unless hash.is_a?(Hash)

        hash.transform_keys(&:to_s)
      end

      def extract_fields(obj, field_map = {})
        result = {}
        field_map.each do |key, method_or_lambda|
          value = if method_or_lambda.is_a?(Proc)
                    method_or_lambda.call(obj)
                  elsif obj.respond_to?(method_or_lambda)
                    obj.send(method_or_lambda)
                  else
                    nil
                  end
          result[key.to_s] = value
        end
        result
      end
    end
  end
end
