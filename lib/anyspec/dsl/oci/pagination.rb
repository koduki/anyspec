# frozen_string_literal: true

module Anyspec
  module DSL
    module OCI
      class PaginationError < RuntimeError; end

      class Pagination
        MAX_SCIM_COUNT = 1000
        MAX_PAGES = 1000
        MAX_TOTAL_RESULTS = 100_000
        MAX_GROUP_MEMBERS = 100_000

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
          response = @executor.execute(base_cmd, location: location, preserve_envelope: true)
          data = response.is_a?(Hash) && response.key?('data') ? response['data'] : response
          unless data.is_a?(Hash)
            raise PaginationError.new('SCIM response body must be an object', location)
          end
          resources = data['Resources'] || data['resources']
          return resources if resources.is_a?(Array)
          return [data] if data.key?('id')

          raise PaginationError.new('SCIM response has no Resources array', location)
        end

        def scim_all(base_cmd, location:)
          cmd = base_cmd.dup
          cmd << '--all' unless cmd.include?('--all')

          response = @executor.execute(cmd, location: location, preserve_envelope: true)

          unless response.is_a?(Hash)
            raise PaginationError.new('SCIM response must be an object', location)
          end
          data = response.key?('data') ? response['data'] : response
          unless data.is_a?(Hash)
            raise PaginationError.new('SCIM response body must be an object', location)
          end

          opc_total = response['opc-total-items']
          total_from_data = data['totalResults'] || data['total-results']
          expected_total = parse_total(opc_total, total_from_data, location)
          resources = data['Resources'] || data['resources']
          resources = [] if resources.nil? && expected_total == 0
          unless resources.is_a?(Array)
            raise PaginationError.new('SCIM response has no Resources array', location)
          end

          seen_ids = Set.new
          resources.each do |resource|
            id = resource['id']
            if id && seen_ids.include?(id)
              raise PaginationError.new("Duplicate resource id: #{id}", location)
            end
            seen_ids.add(id) if id
          end

          if expected_total && resources.length != expected_total
            raise PaginationError.new(
              "Count mismatch: got #{resources.length}, expected #{expected_total} (from opc-total-items or total-results)",
              location
            )
          end

          resources
        end

        private

        def parse_total(opc_total, data_total, location)
          value = opc_total.nil? ? data_total : opc_total
          return nil if value.nil?

          result = value.is_a?(Integer) ? value : Integer(value, 10)
          raise ArgumentError if result.negative?
          result
        rescue ArgumentError, TypeError
          raise PaginationError.new("Invalid SCIM total: #{value.inspect}", location)
        end

        public

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
            unless response.is_a?(Hash)
              raise PaginationError.new('Group response must be an object', location)
            end
            members = response['members'] || []
            unless members.is_a?(Array)
              raise PaginationError.new('Group members must be an array', location)
            end

            break if members.empty?

            members.each do |member|
              raise PaginationError.new('Group member must be an object', location) unless member.is_a?(Hash)
              id = member['value']
              if id && seen_ids.include?(id)
                raise PaginationError.new("Duplicate group member id: #{id}", location)
              end
              seen_ids.add(id) if id
              all_members << member
            end

            if all_members.length > MAX_GROUP_MEMBERS
              raise PaginationError.new("Group has too many members (>#{MAX_GROUP_MEMBERS})", location)
            end

            break if members.length < count
            
            start_index += members.length
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

            response = @executor.execute(cmd, location: location, preserve_envelope: true)
            body = raw_response_body(response, location: location)

            total_value = body.key?('totalResults') ? body['totalResults'] : body['total-results']
            total_results = parse_total(nil, total_value, location)
            raise PaginationError.new('raw-request response has no totalResults', location) if total_results.nil?
            if total_results > MAX_TOTAL_RESULTS
              raise PaginationError.new("Total results exceeds maximum (#{MAX_TOTAL_RESULTS})", location)
            end

            resources = body['Resources'] || body['resources']
            resources = [] if resources.nil? && total_results.zero?
            unless resources.is_a?(Array)
              raise PaginationError.new('raw-request response has no Resources array', location)
            end

            response_start = body['startIndex'] || body['start-index']
            if response_start && parse_total(nil, response_start, location) != start_index
              raise PaginationError.new("startIndex mismatch: expected #{start_index}, got #{response_start}", location)
            end
            response_count = body['itemsPerPage'] || body['items-per-page']
            if response_count && parse_total(nil, response_count, location) < resources.length
              raise PaginationError.new('itemsPerPage is smaller than the resource count', location)
            end

            if initial_total.nil?
              initial_total = total_results
            elsif total_results != initial_total
              raise PaginationError.new(
                "totalResults changed during pagination: #{initial_total} -> #{total_results}",
                location
              )
            end

            if resources.empty? && all_resources.length < initial_total
              raise PaginationError.new("Empty page before all results were received (#{all_resources.length}/#{initial_total})", location)
            end
            if all_resources.length + resources.length > initial_total
              raise PaginationError.new("raw-request returned more resources than totalResults #{initial_total}", location)
            end

            resources.each do |resource|
              raise PaginationError.new('raw-request resource must be an object', location) unless resource.is_a?(Hash)
              id = resource['id']
              if id && seen_ids.include?(id)
                raise PaginationError.new("Duplicate resource id in raw request: #{id}", location)
              end
              seen_ids.add(id) if id
              all_resources << resource
            end

            break if all_resources.length == initial_total

            start_index += resources.length
          end

          all_resources
        end

        def raw_response_body(response, location:)
          unless response.is_a?(Hash) && response.key?('status') && response.key?('data')
            raise PaginationError.new('raw-request response must include status and data', location)
          end
          status = response['status'].to_s
          unless status.match?(/\A2\d\d(?:\s|\z)/)
            raise CLIError.new("raw-request HTTP status: #{status}", location)
          end
          body = response['data']
          body = JSON.parse(body) if body.is_a?(String)
          raise PaginationError.new('raw-request body must be an object', location) unless body.is_a?(Hash)

          body
        rescue JSON::ParserError => e
          raise PaginationError.new("Invalid JSON in raw-request response: #{e.message}", location)
        end
      end
    end
  end
end
