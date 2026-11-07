# frozen_string_literal: true

require 'json'

module Anyspec
  module DSL
    module OCI
      class OciBuiltins
        ADMIN_ROLE_APP_ID = 'IDCSAppId'
        IPRANGE_PATTERN = /#inIPRange\("([^"]+)"\)/
        MAX_NESTED_GROUPS = 10_000
        MAX_NESTED_MEMBERS = 100_000

        def initialize(executor:, pagination:)
          @executor = executor
          @pagination = pagination
        end

        def register_all(builtins)
          register_compartment_builtins(builtins)
          register_domain_builtins(builtins)
          register_scim_builtins(builtins)
          register_attribute_value_builtins(builtins)
        end

        private

        def register_compartment_builtins(builtins)
          builtins.register('oci_list_compartments') do |args, interp, loc|
            tenancy_ocid = args[0]
            
            cmd = [
              'oci', 'iam', 'compartment', 'list',
              '--compartment-id', tenancy_ocid,
              '--compartment-id-in-subtree', 'true',
              '--access-level', 'ANY',
              '--include-root',
              '--all'
            ]

            begin
              @pagination.iam_paginate(cmd, location: loc)
            rescue CLIError => e
              if e.message.include?('include-root')
                cmd.delete('--include-root')
                result = @pagination.iam_paginate(cmd, location: loc)
                tenancy_as_root = { 'id' => tenancy_ocid, 'compartment-id' => tenancy_ocid, 'name' => 'root', 'lifecycle-state' => 'ACTIVE' }
                [tenancy_as_root] + result
              else
                raise
              end
            end
          end

          builtins.register('oci_list_domains') do |args, interp, loc|
            compartment_id = args[0]
            
            cmd = [
              'oci', 'iam', 'domain', 'list',
              '--compartment-id', compartment_id,
              '--all'
            ]

            @pagination.iam_paginate(cmd, location: loc)
          end
        end

        def register_domain_builtins(builtins)
          builtins.register('oci_domain_list') do |args, interp, loc|
            endpoint, resource_type, attributes = args
            
            resource_map = {
              'policies' => 'policy',
              'rules' => 'rule',
              'conditions' => 'condition',
              'network-perimeters' => 'network-perimeters',
              'identity-providers' => 'identity-providers',
              'social-identity-providers' => 'social-identity-provider',
              'password-policies' => 'password-policies',
              'apps' => 'apps',
              'app-roles' => 'app-roles',
              'grants' => 'grants',
              'groups' => 'groups',
              'users' => 'users'
            }

            cli_resource = resource_map[resource_type] || resource_type
            cmd = ['oci', 'identity-domains', cli_resource, 'list', '--endpoint', endpoint]

            if attributes
              cmd << '--attributes' << attributes
            end

            @pagination.scim_all(cmd, location: loc)
          end

          builtins.register('oci_domain_list_filtered') do |args, interp, loc|
            endpoint, resource_type, filter, attributes = args
            
            resource_map = {
              'app-roles' => 'app-roles',
              'grants' => 'grants',
              'groups' => 'groups'
            }

            cli_resource = resource_map[resource_type] || resource_type
            cmd = [
              'oci', 'identity-domains', cli_resource, 'list',
              '--endpoint', endpoint,
              '--filter', filter
            ]

            if attributes
              cmd << '--attributes' << attributes
            end

            @pagination.scim_all(cmd, location: loc)
          end

          builtins.register('oci_domain_get') do |args, interp, loc|
            endpoint, resource_type, resource_id = args

            resource_map = {
              'group' => 'group',
              'user' => 'user'
            }

            cli_resource = resource_map[resource_type] || resource_type
            cmd = [
              'oci', 'identity-domains', cli_resource, 'get',
              '--endpoint', endpoint,
              "--#{cli_resource}-id", resource_id
            ]

            # Group members are requested separately with attribute pagination.
            cmd.concat(['--attribute-sets', 'default']) if cli_resource == 'group'

            @executor.execute(cmd, location: loc)
          end

          builtins.register('oci_domain_singleton') do |args, interp, loc|
            endpoint, resource_type = args

            singleton_map = {
              'authentication-factor-settings' => 'authentication-factor-settings',
              'kmsi-settings' => 'kmsi-settings'
            }

            cli_resource = singleton_map[resource_type] || resource_type
            cmd = [
              'oci', 'identity-domains', cli_resource, 'list',
              '--endpoint', endpoint,
              '--all'
            ]

            @pagination.scim_paginate_simple(cmd, location: loc)
          end

          builtins.register('oci_raw_get') do |args, interp, loc|
            endpoint, path = args
            
            unless path.start_with?('/admin/v1/')
              raise RuntimeError.new("raw_get only allows /admin/v1/ paths, got: #{path}", loc)
            end

            if path.include?('ConditionGroups') || path.include?('SsoSettings')
              if path.include?('SsoSettings') && !path.include?('startIndex')
                full_uri = "#{endpoint}#{path}"
                cmd = ['oci', 'raw-request', '--http-method', 'GET', '--target-uri', full_uri]
                response = @executor.execute(cmd, location: loc, preserve_envelope: true)
                body = @pagination.raw_response_body(response, location: loc)
                resources = body['Resources'] || body['resources']
                if resources.is_a?(Array)
                  resources
                elsif body.key?('id')
                  [body]
                elsif (body['totalResults'] || body['total-results']) == 0
                  []
                else
                  raise PaginationError.new('SsoSettings response has no Resources array', loc)
                end
              else
                @pagination.raw_request_paginate(endpoint: endpoint, path: path, location: loc)
              end
            else
              raise RuntimeError.new("raw_get only supports ConditionGroups and SsoSettings", loc)
            end
          end

          builtins.register('oci_group_members') do |args, interp, loc|
            endpoint, group_id = args
            @pagination.group_members_paginate(
              group_id: group_id,
              endpoint: endpoint,
              location: loc
            )
          end

          builtins.register('oci_group_closure') do |args, interp, loc|
            endpoint, group_ids = args
            raise RuntimeError.new('oci_group_closure requires an array of group ids', loc) unless group_ids.is_a?(Array)

            pending = group_ids.compact.uniq
            queued = pending.to_set
            groups = []
            users = Set.new
            total_members = 0
            index = 0

            while index < pending.length
              raise RuntimeError.new("Too many nested groups (>#{MAX_NESTED_GROUPS})", loc) if pending.length > MAX_NESTED_GROUPS
              group_id = pending[index]
              index += 1
              cmd = ['oci', 'identity-domains', 'group', 'get', '--endpoint', endpoint,
                     '--group-id', group_id, '--attribute-sets', 'default']
              group = @executor.execute(cmd, location: loc)
              raise RuntimeError.new("Invalid group response: #{group_id}", loc) unless group.is_a?(Hash)

              members = @pagination.group_members_paginate(group_id: group_id, endpoint: endpoint, location: loc)
              total_members += members.length
              raise RuntimeError.new("Too many nested group members (>#{MAX_NESTED_MEMBERS})", loc) if total_members > MAX_NESTED_MEMBERS
              groups << group.merge('members' => members)

              members.each do |member|
                member_id = member['value']
                case member['type'].to_s.downcase
                when 'user'
                  member_id ? users.add(member_id) : interp.add_warning("Group #{group_id}: user member has no value", loc)
                when 'group'
                  if member_id
                    pending << member_id if queued.add?(member_id)
                  else
                    interp.add_warning("Group #{group_id}: group member has no value", loc)
                  end
                else
                  interp.add_warning("Group #{group_id}: unsupported member type #{member['type'].inspect}", loc)
                end
              end
            end
            { 'groups' => groups, 'user_ids' => users.to_a }
          end
        end

        def register_scim_builtins(builtins)
          builtins.register('scim_filter') do |args, interp, loc|
            field, op, value = args
            escaped_value = value.to_s.gsub('\\', '\\\\').gsub('"', '\\"')
            "#{field} #{op} \"#{escaped_value}\""
          end

          builtins.register('extract_data') do |args, interp, loc|
            response = args[0]
            response.is_a?(Hash) && response.key?('data') ? response['data'] : response
          end
        end

        def register_attribute_value_builtins(builtins)
          builtins.register('classify_attribute_value') do |args, interp, loc|
            value = args[0]
            if value.nil?
              next { 'type' => 'null', 'value' => nil }
            end
            
            str = value.to_s
            result = nil

            if str.start_with?('{') || str.start_with?('[')
              begin
                parsed = JSON.parse(str)
                result = { 'type' => 'json', 'value' => parsed }
              rescue JSON::ParserError
              end
            end

            if result.nil? && (match = str.match(IPRANGE_PATTERN))
              result = { 'type' => 'iprange_ref', 'value' => match[1] }
            end

            if result.nil? && str.match?(/#[a-zA-Z]+\(/)
              result = { 'type' => 'function_expr', 'value' => str }
            end

            result || { 'type' => 'string', 'value' => str }
          end

          builtins.register('extract_iprange_refs') do |args, interp, loc|
            value = args[0]
            next [] if value.nil?
            
            str = value.to_s
            refs = []
            
            str.scan(IPRANGE_PATTERN) do |match|
              refs << match[0]
            end
            
            refs.uniq
          end

          builtins.register('extract_condition_refs') do |args, interp, loc|
            condition = args[0]
            next { 'groups' => [], 'users' => [] } unless condition.is_a?(Hash)

            groups = []
            users = []

            attr_name = condition['attributeName'] || condition['attribute-name']
            attr_value = condition['attributeValue'] || condition['attribute-value']

            case attr_name
            when 'user.memberOf', 'user.groups'
              groups << attr_value if attr_value
            when 'user.id', 'user.ocid'
              users << attr_value if attr_value
            end

            { 'groups' => groups.compact.uniq, 'users' => users.compact.uniq }
          end

          builtins.register('find_admin_roles') do |args, interp, loc|
            app_roles = args[0]
            raise RuntimeError.new('find_admin_roles requires array', loc) unless app_roles.is_a?(Array)
            
            app_roles.select do |role|
              role['adminRole'] == true || role['admin-role'] == true
            end
          end

          builtins.register('validate_sequence') do |args, interp, loc|
            rules, policy_name = args
            next [] unless rules.is_a?(Array)

            sequences = rules.map { |r| r['sequence'] }.compact
            duplicates = sequences.group_by(&:itself).select { |_, v| v.length > 1 }.keys

            duplicates.map do |seq|
              "Policy '#{policy_name}' has duplicate rule sequence: #{seq}"
            end
          end

          builtins.register('check_ref_integrity') do |args, interp, loc|
            refs, lookup, ref_type = args
            raise RuntimeError.new('check_ref_integrity: refs must be array', loc) unless refs.is_a?(Array)
            raise RuntimeError.new('check_ref_integrity: lookup must be object', loc) unless lookup.is_a?(Hash)
            
            missing = []
            refs.each do |ref|
              ref_id = ref.is_a?(Hash) ? (ref['value'] || ref['id']) : ref
              next if ref_id.nil?
              missing << ref_id unless lookup.key?(ref_id.to_s)
            end
            
            missing.uniq.map { |id| "Missing #{ref_type} reference: #{id}" }
          end
        end
      end
    end
  end
end
