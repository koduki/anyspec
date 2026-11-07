# frozen_string_literal: true

module Anyspec
  module DSL
    module OCI
      class PaginationError < RuntimeError; end

      class Pagination
        MAX_SCIM_COUNT = 1000
        MAX_PAGES = 1000
        MAX_TOTAL_RESULTS = 100_000
        MAX_MEMBERS_PER_REQUEST = 10_000

        def initialize(executor:)
          @executor = executor
        end

        def scim_paginate(base_cmd, location:, attributes: nil)
          all_resources = []
          seen_ids = Set.new
          start_index = 1
          page_count = 0
          initial_total = nil
          count = MAX_SCIM_COUNT

          loop do
            page_count += 1
            if page_count > MAX_PAGES
              raise PaginationError.new("Exceeded maximum page count (#{MAX_PAGES})", location)
            end

            cmd = base_cmd.dup
            cmd << '--start-index' << start_index.to_s
            cmd << '--count' << count.to_s
            cmd << '--attributes' << attributes if attributes

            response = @executor.execute(cmd, location: location)
            
            resources = response['Resources'] || response['resources'] || []
            total_results = response['totalResults'] || response['total-results'] || 0
            items_per_page = response['itemsPerPage'] || response['items-per-page'] || resources.length
            response_start = response['startIndex'] || response['start-index'] || start_index

            if initial_total.nil?
              initial_total = total_results
              if initial_total > MAX_TOTAL_RESULTS
                raise PaginationError.new(
                  "Total results (#{initial_total}) exceeds maximum (#{MAX_TOTAL_RESULTS})",
                  location
                )
              end
            elsif total_results != initial_total
              raise PaginationError.new(
                "totalResults changed during pagination: #{initial_total} -> #{total_results}",
                location
              )
            end

            if response_start != start_index
              raise PaginationError.new(
                "startIndex mismatch: expected #{start_index}, got #{response_start}",
                location
              )
            end

            if resources.empty? && all_resources.length < initial_total
              raise PaginationError.new(
                "Empty page returned but expected more results (got #{all_resources.length}/#{initial_total})",
                location
              )
            end

            resources.each do |resource|
              id = resource['id']
              if id && seen_ids.include?(id)
                raise PaginationError.new("Duplicate resource id: #{id}", location)
              end
              seen_ids.add(id) if id
              all_resources << resource
            end

            break if resources.empty?
            break if all_resources.length >= initial_total
            break if items_per_page < count

            start_index += items_per_page
          end

          if all_resources.length != initial_total
            raise PaginationError.new(
              "Final count mismatch: got #{all_resources.length}, expected #{initial_total}",
              location
            )
          end

          all_resources
        end

        def scim_paginate_simple(base_cmd, location:)
          response = @executor.execute(base_cmd, location: location)
          response['Resources'] || response['resources'] || [response].compact
        end

        def iam_paginate(base_cmd, location:)
          all_items = []
          cmd = base_cmd.dup
          
          unless cmd.include?('--all')
            cmd << '--all'
          end

          response = @executor.execute(cmd, location: location)
          
          if response.is_a?(Array)
            all_items.concat(response)
          elsif response.is_a?(Hash) && response['data']
            all_items.concat(Array(response['data']))
          else
            all_items << response
          end

          all_items
        end

        def group_members_paginate(group_id:, endpoint:, location:)
          all_members = []
          seen_ids = Set.new
          start_index = 1
          count = MAX_SCIM_COUNT
          page_count = 0

          loop do
            page_count += 1
            if page_count > MAX_PAGES
              raise PaginationError.new("Exceeded maximum page count for members", location)
            end

            cmd = [
              'oci', 'identity-domains', 'group', 'get',
              '--endpoint', endpoint,
              '--group-id', group_id,
              '--attributes', "members[startIndex=#{start_index}&count=#{count}]"
            ]

            response = @executor.execute(cmd, location: location)
            members = response['members'] || []

            break if members.empty?

            members.each do |member|
              id = member['value']
              next if id && seen_ids.include?(id)
              seen_ids.add(id) if id
              all_members << member
            end

            break if members.length < count
            
            start_index += count
            
            if start_index > MAX_MEMBERS_PER_REQUEST
              raise PaginationError.new(
                "Group has too many members (>#{MAX_MEMBERS_PER_REQUEST})",
                location
              )
            end
          end

          all_members
        end

        def raw_request_paginate(endpoint:, path:, location:)
          all_resources = []
          seen_ids = Set.new
          start_index = 1
          count = 100
          page_count = 0
          initial_total = nil

          loop do
            page_count += 1
            if page_count > MAX_PAGES
              raise PaginationError.new("Exceeded maximum page count for raw request", location)
            end

            separator = path.include?('?') ? '&' : '?'
            full_uri = "#{endpoint}#{path}#{separator}startIndex=#{start_index}&count=#{count}"

            cmd = [
              'oci', 'raw-request',
              '--http-method', 'GET',
              '--target-uri', full_uri
            ]

            response = @executor.execute(cmd, location: location)
            
            body = response['data']&.is_a?(Hash) ? response['data'] : response
            
            if body.is_a?(String)
              begin
                body = JSON.parse(body)
              rescue JSON::ParserError => e
                raise PaginationError.new("Invalid JSON in raw-request response: #{e.message}", location)
              end
            end

            resources = body['Resources'] || body['resources'] || []
            total_results = body['totalResults'] || body['total-results'] || 0

            if initial_total.nil?
              initial_total = total_results
            elsif total_results != initial_total
              raise PaginationError.new(
                "totalResults changed during pagination: #{initial_total} -> #{total_results}",
                location
              )
            end

            resources.each do |resource|
              id = resource['id']
              if id && seen_ids.include?(id)
                raise PaginationError.new("Duplicate resource id in raw request: #{id}", location)
              end
              seen_ids.add(id) if id
              all_resources << resource
            end

            break if resources.empty?
            break if all_resources.length >= initial_total

            start_index += count
          end

          all_resources
        end
      end
    end
  end
end
