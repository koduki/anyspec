# frozen_string_literal: true

module Anyspec
  class AdapterRegistry
    PRIORITY_BUILTIN = 0
    PRIORITY_EXTERNAL = 10

    RegistryEntry = Struct.new(:adapter_class, :priority, :source_file, :definition, keyword_init: true)

    class << self
      def registry
        @registry ||= {}
      end

      def external_definitions
        @external_definitions ||= {}
      end

      def loaded_definition_files
        @loaded_definition_files ||= []
      end

      def overridden_builtins
        @overridden_builtins ||= []
      end

      def register(type, adapter_class, priority: :builtin, source_file: nil, definition: nil)
        type_str = type.to_s
        priority_value = resolve_priority(priority)

        existing = registry[type_str]
        if existing
          if priority_value > existing.priority
            if existing.priority == PRIORITY_BUILTIN
              overridden_builtins << { type: type_str, source_file: source_file }
            end
          else
            return existing.adapter_class
          end
        end

        registry[type_str] = RegistryEntry.new(
          adapter_class: adapter_class,
          priority: priority_value,
          source_file: source_file,
          definition: definition
        )

        adapter_class
      end

      def register_external_definition(type, definition, source_file:)
        type_str = type.to_s
        external_definitions[type_str] = definition

        register(
          type_str,
          definition['dsl'] ? Adapters::Dsl : Adapters::GenericCli,
          priority: :external,
          source_file: source_file,
          definition: definition
        )
      end

      def get(type)
        entry = registry[type.to_s]
        raise UnknownAdapterError, "Unknown adapter type: '#{type}'. Available types: #{available_types.join(', ')}" unless entry

        entry.adapter_class
      end

      def get_definition(type)
        external_definitions[type.to_s]
      end

      def available_types
        registry.keys.sort
      end

      def registered?(type)
        registry.key?(type.to_s)
      end

      def builtin?(type)
        entry = registry[type.to_s]
        return false unless entry

        entry.priority == PRIORITY_BUILTIN
      end

      def external?(type)
        entry = registry[type.to_s]
        return false unless entry

        entry.priority == PRIORITY_EXTERNAL
      end

      def entry_for(type)
        registry[type.to_s]
      end

      def external_adapter_info
        {
          loaded_files: loaded_definition_files.dup,
          external_types: external_definitions.keys.sort,
          overridden_builtins: overridden_builtins.dup
        }
      end

      def reset!
        @registry = {}
        @external_definitions = {}
        @loaded_definition_files = []
        @overridden_builtins = []
      end

      private

      def resolve_priority(priority)
        case priority
        when :builtin, 'builtin'
          PRIORITY_BUILTIN
        when :external, 'external'
          PRIORITY_EXTERNAL
        when Integer
          priority
        else
          PRIORITY_BUILTIN
        end
      end
    end
  end
end
