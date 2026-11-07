# frozen_string_literal: true

module Anyspec
  module DSL
    class Runtime
      # Arity is checked throughout the AST before the first external operation.
      ARITY = {
        'value' => 1..1, 'array' => 0..100, 'object' => 0..100, 'get' => 1..1, 'get?' => 1..1,
        'collect' => 1..1, 'pluck' => 1..1, 'pluck?' => 1..1, 'flatten' => 0..0, 'compact' => 0..0,
        'where' => 2..2, 'where-in' => 2..2, 'where-not-in' => 2..2, 'where-contains' => 2..2,
        'index' => 1..1, 'keys' => 0..0, 'values' => 0..0, 'union' => 1..100, 'difference' => 1..1,
        'intersection' => 1..1, 'merge' => 1..1, 'unique' => 0..0, 'put' => 2..2,
        'parse-json' => 0..0, 'decode-json' => 0..0, 'decode-field' => 1..1, 'decode-at' => 1..1, 'scan' => 1..1,
        'normalize' => 0..1, 'emit' => 1..100, 'warn' => 2..2, 'warn-empty' => 2..2,
        'warn-missing' => 2..2, 'warn-duplicates' => 2..2, 'context' => 1..1,
        'oci' => 1..1, 'iam-list' => 3..3, 'scim-list' => 2..3, 'scim-get' => 3..3, 'scim-get?' => 3..3,
        'scim-groups' => 2..2, 'scim-eq' => 2..2, 'scim-and' => 1..100,
        'links' => 2..2, 'references' => 1..1, 'check-references' => 1..1, 'reference-ids' => 1..1
      }.freeze
      attr_reader :warnings

      def initialize(transport: nil, max_steps: 1_000_000)
        @transport, @max_steps = transport, max_steps
      end

      def run(source, variables: {}, file: '(dsl)')
        @file, @variables = file, variables.dup
        @warnings, @output, @steps, @context = [], {}, 0, nil
        nodes = Parser.new(source, file: file).parse
        validate(nodes)
        execute(nodes)
        @warnings.sort_by! { |w| [w['context'].to_s, w['code'].to_s, w['message'].to_s] }
        @output['warnings'] = warnings
        @output['warning_count'] = warnings.size
        Data.normalize(@output)
      end

      def validate(nodes, file: nil)
        @file = file || @file || '(dsl)'
        nodes.each do |node|
          node.pipeline.each do |stage|
            range = ARITY[stage.first.value]
            fail_at(stage.first, "unknown command #{stage.first.value}") unless range
            fail_at(stage.first, 'wrong number of arguments') unless range.cover?(stage.size - 1)
          end
          validate(node.body) if node.body
        end
      end

      private

      def execute(nodes)
        nodes.each do |node|
          value = evaluate(node.pipeline)
          case node.kind
          when :assign
            raise Error, 'input is a read-only variable' if node.name == 'input'
            @variables[node.name] = value
          when :for
            raise Error, 'input is a read-only variable' if node.name == 'input'
            present, old = @variables.key?(node.name), @variables[node.name]
            Data.array(value).each do |item|
              @variables[node.name] = item
              execute(node.body)
            end
            present ? @variables[node.name] = old : @variables.delete(node.name)
          end
        end
      end

      def evaluate(pipeline)
        pipeline.reduce(nil) do |input, stage|
          @steps += 1
          fail_at(stage.first, 'execution step limit exceeded') if @steps > @max_steps
          begin
            args = stage.drop(1).map { |token| resolve(token) }
            command(stage.first.value, input, args)
          rescue Error, ArgumentError, TypeError, KeyError, JSON::ParserError, RegexpError => e
            raise if e.is_a?(Error) && e.message.start_with?("#{@file}:")
            fail_at(stage.first, e.message)
          end
        end
      end

      def resolve(token)
        return token.value unless token.kind == :variable
        name, *path = token.value.split('.')
        fail_at(token, "undefined variable #{name}") unless @variables.key?(name)
        Data.path(@variables[name], path)
      end

      def command(name, input, args)
        case name
        when 'value' then args.first
        when 'array' then args
        when 'object'
          raise Error, 'object requires key/value pairs' unless args.size.even?
          args.each_slice(2).each_with_object({}) do |(key, value), result|
            raise Error, 'object keys must be unique strings' unless key.is_a?(String) && !result.key?(key)
            result[key] = value
          end
        when 'get', 'get?' then Data.path(input, args.first, optional: name.end_with?('?'))
        when 'collect' then Data.collect(input, args.first)
        when 'pluck', 'pluck?' then Data.array(input).map { |item| Data.path(item, args.first, optional: name.end_with?('?')) }
        when 'flatten' then Data.array(input).flatten(1)
        when 'compact' then Data.array(input).compact
        when 'where', 'where-in', 'where-not-in', 'where-contains'
          Data.array(input).select do |item|
            value = Data.path(item, args[0], optional: true)
            case name
            when 'where' then value == args[1]
            when 'where-in' then Data.array(args[1]).include?(value)
            when 'where-not-in' then !Data.array(args[1]).include?(value)
            when 'where-contains' then value.is_a?(Array) && value.any? { |entry| Data.partial?(entry, args[1]) }
            end
          end
        when 'index' then Data.index(input, args.first)
        when 'keys' then Data.object(input).keys
        when 'values' then Data.object(input).values
        when 'unique' then Data.array(input).uniq
        when 'union' then ([Data.array(input)] + args.map { |v| Data.array(v) }).flatten(1).uniq
        when 'difference' then Data.array(input) - Data.array(args.first)
        when 'intersection' then Data.array(input) & Data.array(args.first)
        when 'merge' then Data.merge(input, args.first)
        when 'put'
          raise Error, 'put key must be a string' unless args.first.is_a?(String)
          Data.object(input).merge(args.first => args.last)
        when 'parse-json' then JSON.parse(input)
        when 'decode-json' then decode(input)
        when 'decode-field'
          Data.array(input).map do |item|
            obj = Data.object(item)
            obj.key?(args.first) ? obj.merge(args.first => decode(obj[args.first])) : obj
          end
        when 'decode-at' then Data.transform(input, args.first) { |value| decode(value) }
        when 'scan'
          regex = Regexp.new(args.first)
          Timeout.timeout(1) { strings(input).flat_map { |str| str.scan(regex).map { |v| v.is_a?(Array) ? v.first : v } }.uniq }
        when 'normalize' then Data.normalize(input, args.first || {})
        when 'emit' then emit(input, args)
        when 'context' then @context = args.first
        when 'warn'
          warning(args[0], args[1]); input
        when 'warn-empty'
          warning(args[0], args[1]) if Data.array(input).empty?
          input
        when 'warn-missing'
          (Data.array(input) - Data.object(args.first).keys).uniq.each { |id| warning('MISSING_REFERENCE', "#{args.last}/#{id}") }
          input
        when 'warn-duplicates'
          Data.array(input).group_by { |v| Data.path(v, args.first) }.each do |key, rows|
            warning('DUPLICATE_PRIORITY', "#{args.last}: #{key}") if rows.size > 1
          end
          input
        when 'iam-list' then transport.iam_list(*args)
        when 'oci' then transport.call(args.first)
        when 'scim-list' then transport.list(*args)
        when 'scim-get' then transport.get(*args)
        when 'scim-get?'
          result = transport.get(*args, optional: true)
          warning('MISSING_REFERENCE', "#{args[1]}/#{args[2]}") unless result
          result
        when 'scim-groups' then transport.groups(*args, method(:warning))
        when 'scim-eq'
          raise Error, 'invalid SCIM attribute' unless args[0].is_a?(String) && args[0].match?(/\A[a-zA-Z][\w.:]*\z/)
          raise Error, 'SCIM comparison requires string, boolean or number' unless [String, TrueClass, FalseClass, Integer, Float].any? { |type| args[1].is_a?(type) }
          "#{args[0]} eq #{JSON.generate(args[1])}"
        when 'scim-and' then args.map { |arg| "(#{arg})" }.join(' and ')
        when 'links' then links(input, args[0], args[1])
        when 'references' then references(input, args.first)
        when 'reference-ids' then Data.array(input).select { |r| r['collection'] == args.first }.map { |r| r.fetch('id') }.uniq
        when 'check-references'
          Data.array(input).each do |ref|
            collection = Data.object(args.first).fetch(ref['collection'], {})
            warning('MISSING_REFERENCE', "#{ref['source']} -> #{ref['collection']}/#{ref['id']}") unless collection.key?(ref['id'])
          end
          input
        end
      rescue Timeout::Error
        raise Error, 'regular expression time limit exceeded'
      end

      def transport
        @transport || raise(Error, 'no collection transport configured')
      end

      def decode(value)
        case value
        when Array then value.map { |v| decode(v) }
        when String
          value.lstrip.start_with?('[', '{', '"') ? JSON.parse(value) : value
        else value
        end
      end

      def strings(value)
        case value
        when Hash then value.values.flat_map { |v| strings(v) }
        when Array then value.flat_map { |v| strings(v) }
        when String then [value]
        else []
        end
      end

      # Read references as data; never follow a URI supplied by an API response.
      def links(value, collections, excluded, path = [])
        case value
        when Hash
          result = []
          if value['$ref'].is_a?(String)
            match = value['$ref'].match(%r{/admin/v1/([^/]+)/([^/?#]+)\z})
            if match && collections.include?(match[1])
              result << { 'collection' => match[1], 'id' => URI.decode_www_form_component(match[2]), 'source' => path.join('.') }
            end
          end
          result + value.flat_map { |key, child| excluded.include?(key) ? [] : links(child, collections, excluded, path + [key]) }
        when Array
          value.each_with_index.flat_map { |child, i| links(child, collections, excluded, path + [i.to_s]) }
        else []
        end
      end

      def references(input, rules)
        Data.array(rules).flat_map do |rule|
          Data.collect(input, rule.fetch('path')).filter_map do |ref|
            next if ref.nil?
            collection = rule['collection']
            if rule['types']
              type = Data.path(ref, rule.fetch('type_path', 'type'), optional: true)
              collection = rule['types'][type]
              unless collection
                warning('UNRESOLVED_REFERENCE_TYPE', "#{rule['path']}: #{type}")
                next
              end
            end
            id = rule['id_path'] ? Data.path(ref, rule['id_path']) : ref
            raise Error, "invalid reference at #{rule['path']}" unless id.is_a?(String) && !id.empty?
            { 'collection' => collection, 'id' => id, 'source' => rule['path'] }
          end
        end.uniq
      end

      def emit(input, path)
        raise Error, 'output path must contain nonempty strings' unless path.all? { |v| v.is_a?(String) && !v.empty? }
        raise Error, 'diagnostics use a reserved output path' if %w[warnings warning_count].include?(path.first)
        parent = path[0...-1].reduce(@output) do |hash, key|
          Data.object(hash)
          hash[key] ||= {}
          Data.object(hash[key])
        end
        raise Error, "output collision at #{path.join('.')}" if parent.key?(path.last)
        parent[path.last] = input
        input
      end

      def warning(code, message)
        entry = { 'code' => code, 'message' => message, 'context' => @context }
        @warnings << entry unless @warnings.include?(entry)
      end

      def fail_at(token, message)
        raise Error, "#{@file}:#{token.line}:#{token.column}: #{message}"
      end
    end
  end
end
