# frozen_string_literal: true

require 'oci'

module Anyspec
  module Adapters
    class ObjectStorageBucket < Base
      ADAPTER_TYPE = 'object_storage_bucket'

      def fetch(spec)
        namespace = spec['namespace']
        bucket_name = spec['bucket_name'] || spec['name']

        raise Anyspec::Error, "namespace is required for #{ADAPTER_TYPE}" unless namespace
        raise Anyspec::Error, "bucket_name or name is required for #{ADAPTER_TYPE}" unless bucket_name

        client = create_client(OCI::ObjectStorage::ObjectStorageClient)
        response = client.get_bucket(namespace, bucket_name)

        extract_bucket(response.data)
      end

      private

      def extract_bucket(bucket)
        {
          'name' => bucket.name,
          'namespace' => bucket.namespace,
          'compartment_id' => bucket.compartment_id,
          'public_access_type' => bucket.public_access_type,
          'storage_tier' => bucket.storage_tier,
          'versioning' => bucket.versioning,
          'is_read_only' => bucket.is_read_only,
          'auto_tiering' => bucket.auto_tiering,
          'object_events_enabled' => bucket.object_events_enabled,
          'replication_enabled' => bucket.replication_enabled
        }
      end
    end

    AdapterRegistry.register(ObjectStorageBucket::ADAPTER_TYPE, ObjectStorageBucket)
  end
end
