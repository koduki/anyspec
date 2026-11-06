# frozen_string_literal: true

module Anyspec
  class AdapterRegistry
    class << self
      def registry
        @registry ||= {}
      end

      def register(type, adapter_class)
        registry[type.to_s] = adapter_class
      end

      def get(type)
        adapter_class = registry[type.to_s]
        raise UnknownAdapterError, "Unknown adapter type: '#{type}'. Available types: #{available_types.join(', ')}" unless adapter_class

        adapter_class
      end

      def available_types
        registry.keys.sort
      end

      def registered?(type)
        registry.key?(type.to_s)
      end
    end
  end
end
