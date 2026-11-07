# frozen_string_literal: true

require 'uri'
require 'set'

module Anyspec
  module DSL
    # OCI-specific effects are isolated from the language and pure builtins.
    class OCI
      COLLECTIONS = %w[Policies Rules ConditionGroups Conditions NetworkPerimeters IdentityProviders PasswordPolicies AuthenticationFactorSettings SsoSettings KmsiSettings Apps AppRoles Grants Groups Users].freeze
      SETTINGS = %w[AuthenticationFactorSettings SsoSettings KmsiSettings].freeze
      IAM_COMMANDS = {
        %w[iam compartment list] => %w[--compartment-id --compartment-id-in-subtree --access-level --lifecycle-state],
        %w[iam domain list] => %w[--compartment-id],
        %w[iam region-subscription list] => %w[--tenancy-id]
      }.freeze

      def initialize(config, runner: ProcessRunner.new, max_pages: 1000, page_size: 100, max_resources: 100_000)
        @config, @runner = config, runner
        @max_pages, @page_size, @max_resources = max_pages, page_size, max_resources
        @cache = {}
        @endpoints = Set.new
      end

      def call(args)
        args = Data.array(args)
        raise Error, 'OCI arguments must be strings' unless args.all? { |v| v.is_a?(String) }
        allowed = IAM_COMMANDS[args.first(3)]
        raise Error, 'OCI command is not an allowed read operation' unless allowed
        flags = args.drop(3)
        seen = []
        until flags.empty?
          flag = flags.shift
          raise Error, "unsupported or duplicate OCI option #{flag}" unless allowed.include?(flag) && !seen.include?(flag)
          seen << flag
          val = flags.shift
          raise Error, "missing or unsafe value for #{flag}" if val.nil? || val.start_with?('--', 'file://')
        end
        result = memo(['iam', args]) do
          response = execute(args + ['--all'])
          raise Error, 'OCI list response missing data array' unless response.is_a?(Hash) && response['data'].is_a?(Array)
          Data.index(response['data'], 'id') unless args.first(3) == %w[iam region-subscription list]
          response['data']
        end
        if args.first(3) == %w[iam domain list]
          result.each do |domain|
            %w[url home-region-url].each do |key|
              @endpoints << origin(domain[key]) if domain[key]
            end
          end
        end
        result
      end

      # Raw IAM GET preserves a successful [] response; the normal CLI renderer can
      # suppress stdout for empty lists, which cannot safely be treated as success.
      def iam_list(endpoint, resource, params)
        allowed = { 'compartments' => %w[compartmentId compartmentIdInSubtree accessLevel],
                    'domains' => %w[compartmentId] }
        raise Error, 'unsupported IAM resource' unless allowed.key?(resource)
        Data.object(params)
        raise Error, 'unsupported IAM query parameter' unless (params.keys - allowed[resource]).empty?
        raise Error, 'IAM compartmentId is required' unless params['compartmentId'].is_a?(String) && !params['compartmentId'].empty?
        base = origin(endpoint)
        result = memo(['iam-list', base, resource, params]) do
          rows, ids, tokens, page = [], Set.new, Set.new, nil
          @max_pages.times do
            query = params.merge('limit' => @page_size)
            query['page'] = page if page
            uri = "#{base}/20160918/#{resource}?#{URI.encode_www_form(query)}"
            response = raw_get(uri)
            body = response['data']
            raise Error, 'IAM response data must be an array' unless body.is_a?(Array)
            body.each do |item|
              id = item.is_a?(Hash) && item['id']
              raise Error, 'IAM resource missing id' unless id.is_a?(String) && !id.empty?
              raise Error, "duplicate IAM id #{id}" unless ids.add?(id)
              rows << item
            end
            raise Error, 'IAM resource limit exceeded' if rows.size > @max_resources
            headers = response['headers']
            raise Error, 'IAM response missing headers object' unless headers.is_a?(Hash)
            page = headers.find { |key, _| key.downcase == 'opc-next-page' }&.last
            break if page.nil? || page == ''
            raise Error, 'invalid IAM page token' unless page.is_a?(String)
            raise Error, 'IAM paging made no progress' if body.empty?
            raise Error, 'repeated IAM page token' unless tokens.add?(page)
          end
          raise Error, 'IAM page limit exceeded' if page && page != ''
          rows
        end
        if resource == 'domains'
          result.each do |domain|
            %w[url homeRegionUrl].each { |key| @endpoints << origin(domain[key]) if domain[key] }
          end
        end
        result
      end

      def list(endpoint, collection, filter = nil)
        check_collection!(collection)
        if %w[Users Groups].include?(collection) && (filter.nil? || filter.empty?)
          raise Error, 'unfiltered Users/Groups collection is forbidden'
        end
        memo(['list', endpoint, collection, filter]) do
          params = { 'attributeSets' => 'default' }
          # Explicit request attributes: do not request all attributes (credentials/large memberships).
          params['attributes'] = 'rules' if collection == 'Policies'
          params['attributes'] = 'identityProviders' if collection == 'Apps'
          params['attributes'] = 'members' if collection == 'Groups'
          params['filter'] = filter if filter
          resources, seen, total = [], Set.new, nil
          @max_pages.times do
            start = resources.size + 1
            unless SETTINGS.include?(collection)
              params.merge!('startIndex' => start, 'count' => @page_size, 'sortBy' => 'id', 'sortOrder' => 'ascending')
            end
            body = request(endpoint, collection, nil, params)
            raise Error, 'invalid SCIM list response' unless body.is_a?(Hash)
            count = body['totalResults']
            raise Error, 'SCIM totalResults must be a nonnegative integer' unless count.is_a?(Integer) && count >= 0
            raise Error, 'SCIM totalResults changed while paging' if total && total != count
            total = count
            raise Error, 'SCIM resource limit exceeded' if total > @max_resources
            page = body.fetch('Resources') { total.zero? ? [] : nil }
            raise Error, 'SCIM Resources must be an array' unless page.is_a?(Array)
            if body.key?('startIndex') && body['startIndex'] != start
              raise Error, 'SCIM startIndex mismatch'
            end
            if !SETTINGS.include?(collection) && total > page.size && !body.key?('startIndex')
              raise Error, 'SCIM missing startIndex on partial response'
            end
            if total > page.size && !body.key?('itemsPerPage')
              raise Error, 'SCIM missing itemsPerPage on partial response'
            end
            if body.key?('itemsPerPage') && body['itemsPerPage'] != page.size
              raise Error, 'SCIM itemsPerPage mismatch'
            end
            page.each do |item|
              id = item.is_a?(Hash) && item['id']
              raise Error, 'SCIM resource missing id' unless id.is_a?(String) && !id.empty?
              raise Error, "duplicate SCIM id #{id}" unless seen.add?(id)
              resources << item
            end
            raise Error, 'SCIM results exceed totalResults' if resources.size > total
            break if resources.size == total
            raise Error, 'SCIM paging made no progress' if page.empty?
            raise Error, 'settings endpoint returned incomplete results' if SETTINGS.include?(collection)
          end
          raise Error, 'SCIM page limit exceeded' unless resources.size == total
          resources
        end
      end

      def get(endpoint, collection, id, optional: false)
        check_collection!(collection)
        raise Error, 'SCIM id must be a nonempty string' unless id.is_a?(String) && !id.empty?
        memo(['get', endpoint, collection, id, optional]) do
          params = { 'attributeSets' => 'default' }
          params['attributes'] = 'members' if collection == 'Groups'
          value = request(endpoint, collection, id, params, optional: optional)
          unless value.nil? && optional
            raise Error, 'SCIM get id mismatch' unless value.is_a?(Hash) && value['id'] == id
          end
          value
        end
      end

      # Bounded graph expansion; no language-level recursion and no full group scan.
      def groups(endpoint, ids, warning)
        queue, visited, result = Data.array(ids).dup, Set.new, []
        until queue.empty?
          id = queue.shift
          next unless visited.add?(id)
          raise Error, 'group traversal limit exceeded' if visited.size > @max_resources
          group = get(endpoint, 'Groups', id, optional: true)
          unless group
            warning.call('MISSING_REFERENCE', "Groups/#{id}")
            next
          end
          result << group
          Data.array(group.fetch('members', [])).each do |member|
            case member['type']
            when 'Group'
              queue << member.fetch('value')
            when 'User'
              # Users are fetched by the DSL after the closure is complete.
            else
              warning.call('UNRESOLVED_MEMBER_TYPE', "Groups/#{id}: #{member['type']}")
            end
          end
        end
        result
      end

      private

      def memo(key)
        if @cache.key?(key)
          value = @cache[key]
          raise value if value.is_a?(Exception)
          return value
        end
        @cache[key] = yield
      rescue Error => e
        @cache[key] = e
        raise
      end

      def execute(args)
        argv = [@config.oci_cli_path] + args + ['--output', 'json']
        argv += ['--profile', @config.profile] if @config.profile
        argv += ['--config-file', @config.config_path] if @config.config_path
        argv += ['--auth', @config.auth_mode] unless @config.auth_mode == 'config_file'
        argv += ['--region', @config.region] if @config.region
        @runner.call(argv)
      end

      def origin(endpoint)
        uri = URI.parse(endpoint.to_s)
        unless uri.is_a?(URI::HTTPS) && uri.host && !uri.userinfo && !uri.query && !uri.fragment && ['', '/'].include?(uri.path) && uri.port == 443
          raise Error, 'domain endpoint must be an HTTPS origin on port 443'
        end
        "https://#{uri.host.downcase}"
      rescue URI::InvalidURIError
        raise Error, 'invalid domain endpoint'
      end

      def request(endpoint, collection, id, params, optional: false)
        base = origin(endpoint)
        raise Error, 'SCIM endpoint was not discovered by OCI domain list' unless @endpoints.include?(base)
        uri = "#{base}/admin/v1/#{collection}"
        uri += "/#{URI.encode_www_form_component(id)}" if id
        uri += "?#{URI.encode_www_form(params)}" unless params.empty?
        response = raw_get(uri, optional: optional)
        return nil if response.nil?
        raise Error, 'SCIM response missing data' unless response['data'].is_a?(Hash)
        response['data']
      end

      def raw_get(uri, optional: false)
        response = execute(['raw-request', '--http-method', 'GET', '--target-uri', uri])
        raise Error, 'invalid raw-request response' unless response.is_a?(Hash)
        status = response['status'].to_s
        return nil if optional && status.match?(/\A404(?:\s|\z)/)
        raise Error, "OCI HTTP failure: #{status[/\A\d{3}/] || 'missing status'}" unless status.match?(/\A200(?:\s|\z)/)
        response
      end

      def check_collection!(collection)
        raise Error, "unsupported SCIM collection #{collection}" unless COLLECTIONS.include?(collection)
      end
    end
  end
end
