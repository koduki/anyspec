# frozen_string_literal: true

module Anyspec
  module Adapters
    class Dsl < Base
      def initialize(config)
        super
        @snapshots = {}
      end

      def fetch(spec)
        definition = AdapterRegistry.get_definition(spec.fetch('type'))
        raise Anyspec::Error, 'DSL definition not found' unless definition
        inputs = definition.fetch('inputs').each_with_object({}) do |key, result|
          raise Anyspec::Error, "missing DSL input #{key}" unless spec.key?(key) && !spec[key].nil?
          result[key] = spec[key]
        end
        key = [spec['type'], JSON.generate(inputs)]
        unless @snapshots.key?(key)
          begin
            runtime = DSL::Runtime.new(transport: DSL::OCI.new(config))
            @snapshots[key] = runtime.run(definition.fetch('_source'), variables: { 'input' => inputs }, file: definition.fetch('_file'))
            runtime.warnings.each { |w| warn "Warning [#{w['code']}] #{w['context']}: #{w['message']}" }
          rescue StandardError => e
            @snapshots[key] = e
          end
        end
        value = @snapshots[key]
        raise value if value.is_a?(Exception)
        # Callers cannot poison the shared snapshot.
        JSON.parse(JSON.generate(value))
      end
    end
  end
end
