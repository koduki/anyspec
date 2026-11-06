# frozen_string_literal: true

module Anyspec
  module Adapters
    class ObjectStorageBucket < Base
      ADAPTER_TYPE = 'object_storage_bucket'

      def fetch(spec)
        namespace = spec['namespace']
        bucket_name = spec['bucket_name'] || spec['name']

        raise Anyspec::Error, "namespace is required for #{ADAPTER_TYPE}" unless namespace
        raise Anyspec::Error, "bucket_name or name is required for #{ADAPTER_TYPE}" unless bucket_name

        args = ['os', 'bucket', 'get', '--namespace-name', namespace, '--bucket-name', bucket_name]
        data = run_oci_cli(args)
        normalized = normalize_oci_response(data)

        extract_bucket(normalized)
      end

      private

      def extract_bucket(bucket_data)
        {
          'name' => bucket_data['name'],
          'namespace' => bucket_data['namespace'],
          'compartment_id' => bucket_data['compartment_id'],
          'public_access_type' => bucket_data['public_access_type'],
          'storage_tier' => bucket_data['storage_tier'],
          'versioning' => bucket_data['versioning'],
          'is_read_only' => bucket_data['is_read_only'],
          'auto_tiering' => bucket_data['auto_tiering'],
          'object_events_enabled' => bucket_data['object_events_enabled'],
          'replication_enabled' => bucket_data['replication_enabled']
        }
      end
    end

    AdapterRegistry.register(ObjectStorageBucket::ADAPTER_TYPE, ObjectStorageBucket)
  end
end
