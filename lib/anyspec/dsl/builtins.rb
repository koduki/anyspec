# frozen_string_literal: true

require 'json'
require 'uri'
require 'set'

module Anyspec
  module DSL
    class BuiltinError < RuntimeError; end

    class Builtins
      def initialize
        @functions = {}
        register_core_builtins
      end

      def register(name, &block)
        @functions[name.to_s] = block
      end

      def registered?(name)
        @functions.key?(name.to_s)
      end

      def call(name, args, interpreter, location)
        func = @functions[name.to_s]
        raise BuiltinError.new("Unknown builtin: #{name}", location) unless func
        func.call(args, interpreter, location)
      rescue StandardError => e
        if e.is_a?(RuntimeError) || e.is_a?(BuiltinError)
          raise
        else
          raise BuiltinError.new("#{name}: #{e.message}", location)
        end
      end

      private

      def register_core_builtins
        register_path_builtins
        register_array_builtins
        register_set_builtins
        register_object_builtins
        register_string_builtins
        register_graph_builtins
        register_utility_builtins
      end

      def register_path_builtins
        register('get') do |args, interp, loc|
          obj, path = args
          get_path(obj, path, strict: true, location: loc)
        end

        register('get_opt') do |args, interp, loc|
          obj, path, default = args
          get_path(obj, path, strict: false, default: default, location: loc)
        end

        register('has') do |args, interp, loc|
          obj, path = args
          !get_path(obj, path, strict: false, location: loc).nil?
        end

        register('is_empty') do |args, interp, loc|
          val = args[0]
          val.nil? || (val.respond_to?(:empty?) && val.empty?)
        end

        register('is_null') do |args, interp, loc|
          args[0].nil?
        end

        register('is_array') do |args, interp, loc|
          args[0].is_a?(Array)
        end
      end

      def register_array_builtins
        register('filter') do |args, interp, loc|
          arr, field, value = args
          raise_unless_array(arr, 'filter', loc)
          arr.select { |item| get_path(item, field, strict: false) == value }
        end

        register('filter_not') do |args, interp, loc|
          arr, field, value = args
          raise_unless_array(arr, 'filter_not', loc)
          arr.reject { |item| get_path(item, field, strict: false) == value }
        end

        register('filter_in') do |args, interp, loc|
          arr, field, values = args
          raise_unless_array(arr, 'filter_in', loc)
          raise_unless_array(values, 'filter_in (values)', loc)
          value_set = values.to_set
          arr.select { |item| value_set.include?(get_path(item, field, strict: false)) }
        end

        register('filter_contains') do |args, interp, loc|
          arr, field, substring = args
          raise_unless_array(arr, 'filter_contains', loc)
          arr.select do |item|
            val = get_path(item, field, strict: false)
            val.is_a?(String) && val.include?(substring.to_s)
          end
        end

        register('map') do |args, interp, loc|
          arr, field = args
          raise_unless_array(arr, 'map', loc)
          arr.map { |item| get_path(item, field, strict: false) }
        end

        register('flatten') do |args, interp, loc|
          arr = args[0]
          depth = args[1] || 1
          raise_unless_array(arr, 'flatten', loc)
          arr.flatten(depth)
        end

        register('unique') do |args, interp, loc|
          arr = args[0]
          raise_unless_array(arr, 'unique', loc)
          arr.uniq
        end

        register('unique_by') do |args, interp, loc|
          arr, field = args
          raise_unless_array(arr, 'unique_by', loc)
          arr.uniq { |item| get_path(item, field, strict: false) }
        end

        register('sort') do |args, interp, loc|
          arr = args[0]
          raise_unless_array(arr, 'sort', loc)
          arr.sort_by.with_index { |item, idx| [item.to_s, idx] }
        end

        register('sort_by') do |args, interp, loc|
          arr, field = args
          raise_unless_array(arr, 'sort_by', loc)
          arr.sort_by.with_index do |item, idx|
            val = get_path(item, field, strict: false)
            [val.nil? ? '' : val, idx]
          end
        end

        register('first') do |args, interp, loc|
          arr = args[0]
          raise_unless_array(arr, 'first', loc)
          arr.first
        end

        register('last') do |args, interp, loc|
          arr = args[0]
          raise_unless_array(arr, 'last', loc)
          arr.last
        end

        register('count') do |args, interp, loc|
          arr = args[0]
          raise_unless_array(arr, 'count', loc)
          arr.length
        end

        register('concat') do |args, interp, loc|
          result = []
          args.each do |arr|
            raise_unless_array(arr, 'concat', loc)
            result.concat(arr)
          end
          result
        end

        register('compact') do |args, interp, loc|
          arr = args[0]
          raise_unless_array(arr, 'compact', loc)
          arr.compact
        end
      end

      def register_set_builtins
        register('index_by') do |args, interp, loc|
          arr, field = args
          raise_unless_array(arr, 'index_by', loc)
          result = {}
          arr.each do |item|
            key = get_path(item, field, strict: false)&.to_s
            if result.key?(key)
              raise BuiltinError.new("index_by: duplicate key '#{key}'", loc)
            end
            result[key] = item
          end
          result
        end

        register('keys') do |args, interp, loc|
          obj = args[0]
          raise_unless_hash(obj, 'keys', loc)
          obj.keys
        end

        register('values') do |args, interp, loc|
          obj = args[0]
          raise_unless_hash(obj, 'values', loc)
          obj.values
        end

        register('union') do |args, interp, loc|
          a, b = args
          raise_unless_array(a, 'union (first)', loc)
          raise_unless_array(b, 'union (second)', loc)
          (a + b).uniq
        end

        register('difference') do |args, interp, loc|
          a, b = args
          raise_unless_array(a, 'difference (first)', loc)
          raise_unless_array(b, 'difference (second)', loc)
          a - b
        end

        register('intersection') do |args, interp, loc|
          a, b = args
          raise_unless_array(a, 'intersection (first)', loc)
          raise_unless_array(b, 'intersection (second)', loc)
          a & b
        end

        register('contains') do |args, interp, loc|
          arr, value = args
          raise_unless_array(arr, 'contains', loc)
          arr.include?(value)
        end

        register('contains_any') do |args, interp, loc|
          arr, values = args
          raise_unless_array(arr, 'contains_any', loc)
          raise_unless_array(values, 'contains_any (values)', loc)
          (arr & values).any?
        end

        register('merge') do |args, interp, loc|
          a, b = args
          raise_unless_hash(a, 'merge (first)', loc)
          raise_unless_hash(b, 'merge (second)', loc)
          conflicts = a.keys & b.keys
          if conflicts.any?
            raise BuiltinError.new("merge: key conflict on #{conflicts.inspect}", loc)
          end
          a.merge(b)
        end

        register('merge_all') do |args, interp, loc|
          hashes = args[0]
          raise_unless_array(hashes, 'merge_all', loc)
          result = {}
          hashes.each do |h|
            raise_unless_hash(h, 'merge_all (element)', loc)
            conflicts = result.keys & h.keys
            if conflicts.any?
              raise BuiltinError.new("merge_all: key conflict on #{conflicts.inspect}", loc)
            end
            result.merge!(h)
          end
          result
        end
      end

      def register_object_builtins
        register('sort_keys') do |args, interp, loc|
          obj = args[0]
          sort_keys_recursive(obj)
        end

        register('omit') do |args, interp, loc|
          obj, *paths = args
          raise_unless_hash(obj, 'omit', loc)
          omit_paths(obj, paths)
        end

        register('pick') do |args, interp, loc|
          obj, *keys = args
          raise_unless_hash(obj, 'pick', loc)
          keys.to_h { |k| [k, obj[k]] }
        end

        register('build') do |args, interp, loc|
          path, value = args
          build_nested(path, value)
        end

        register('set_at') do |args, interp, loc|
          obj, path, value = args
          raise_unless_hash(obj, 'set_at', loc)
          deep_set(obj.dup, path, value)
        end

        register('eq') do |args, interp, loc|
          a, b = args
          a == b
        end

        register('not_eq') do |args, interp, loc|
          a, b = args
          a != b
        end

        register('not') do |args, interp, loc|
          !args[0]
        end
      end

      def register_string_builtins
        register('json_decode') do |args, interp, loc|
          str = args[0]
          begin
            JSON.parse(str)
          rescue JSON::ParserError => e
            raise BuiltinError.new("json_decode failed: #{e.message}", loc)
          end
        end

        register('json_encode') do |args, interp, loc|
          obj = args[0]
          JSON.generate(obj)
        end

        register('capture') do |args, interp, loc|
          str, pattern = args
          match = str.to_s.match(Regexp.new(pattern))
          return nil unless match
          if match.names.any?
            match.names.to_h { |n| [n, match[n]] }
          else
            match.captures
          end
        end

        register('split') do |args, interp, loc|
          str, delimiter = args
          str.to_s.split(delimiter)
        end

        register('join') do |args, interp, loc|
          arr, delimiter = args
          raise_unless_array(arr, 'join', loc)
          arr.join(delimiter || ',')
        end

        register('starts_with') do |args, interp, loc|
          str, prefix = args
          str.to_s.start_with?(prefix.to_s)
        end

        register('ends_with') do |args, interp, loc|
          str, suffix = args
          str.to_s.end_with?(suffix.to_s)
        end

        register('replace') do |args, interp, loc|
          str, from, to = args
          str.to_s.gsub(from.to_s, to.to_s)
        end

        register('uri_encode') do |args, interp, loc|
          str = args[0]
          URI.encode_www_form_component(str.to_s)
        end

        register('scim_escape') do |args, interp, loc|
          str = args[0]
          str.to_s.gsub('\\', '\\\\').gsub('"', '\\"')
        end
      end

      def register_graph_builtins
        register('traverse') do |args, interp, loc|
          start_ids, lookup, get_children, max_depth = args
          max_depth ||= 100
          
          raise_unless_array(start_ids, 'traverse (start_ids)', loc)
          raise_unless_hash(lookup, 'traverse (lookup)', loc)
          
          visited = Set.new
          result = []
          
          traverse_recursive(start_ids, lookup, get_children, visited, result, 0, max_depth, loc)
          result
        end

        register('resolve_refs') do |args, interp, loc|
          ids, lookup = args
          raise_unless_array(ids, 'resolve_refs (ids)', loc)
          raise_unless_hash(lookup, 'resolve_refs (lookup)', loc)
          
          found = []
          missing = []
          
          ids.each do |id|
            if lookup.key?(id)
              found << lookup[id]
            else
              missing << id
            end
          end
          
          { 'found' => found, 'missing' => missing }
        end
      end

      def register_utility_builtins
        register('warn') do |args, interp, loc|
          message = args[0]
          interp.add_warning(message, loc)
          nil
        end

        register('assert') do |args, interp, loc|
          condition, message = args
          unless condition
            raise BuiltinError.new("Assertion failed: #{message || 'no message'}", loc)
          end
          true
        end

        register('debug') do |args, interp, loc|
          value = args[0]
          $stderr.puts "[DEBUG] #{loc}: #{value.inspect}"
          value
        end

        register('identity') do |args, interp, loc|
          interp.env.get('_')
        rescue KeyError
          nil
        end

        register('let') do |args, interp, loc|
          name, value = args
          interp.env.set(name, value)
          value
        end

        register('if_then') do |args, interp, loc|
          condition, then_value, else_value = args
          condition ? then_value : else_value
        end

        register('default') do |args, interp, loc|
          value, default = args
          value.nil? ? default : value
        end

        register('error') do |args, interp, loc|
          message = args[0]
          raise BuiltinError.new(message, loc)
        end

        register('typeof') do |args, interp, loc|
          val = args[0]
          case val
          when NilClass then 'null'
          when TrueClass, FalseClass then 'boolean'
          when Integer, Float then 'number'
          when String then 'string'
          when Array then 'array'
          when Hash then 'object'
          else val.class.name.downcase
          end
        end

        register('coalesce') do |args, interp, loc|
          args.find { |v| !v.nil? }
        end
      end

      def get_path(obj, path, strict: true, default: nil, location: nil)
        return obj if path.nil? || path.empty?
        
        parts = path.to_s.split('.')
        current = obj
        
        parts.each do |part|
          case current
          when Hash
            key = current.key?(part) ? part : part.tr('_', '-')
            current = current[key]
          when Array
            if part =~ /^\d+$/
              current = current[part.to_i]
            else
              return default unless strict
              raise BuiltinError.new("Cannot access '#{part}' on array", location)
            end
          when NilClass
            return default unless strict
            raise BuiltinError.new("Cannot access '#{part}' on null (path: #{path})", location)
          else
            return default unless strict
            raise BuiltinError.new("Cannot access '#{part}' on #{current.class}", location)
          end
        end
        
        current.nil? ? default : current
      end

      def raise_unless_array(val, name, loc)
        return if val.is_a?(Array)
        raise BuiltinError.new("#{name} requires array, got #{val.class}", loc)
      end

      def raise_unless_hash(val, name, loc)
        return if val.is_a?(Hash)
        raise BuiltinError.new("#{name} requires object, got #{val.class}", loc)
      end

      def sort_keys_recursive(obj)
        case obj
        when Hash
          obj.keys.sort.to_h { |k| [k, sort_keys_recursive(obj[k])] }
        when Array
          obj.map { |v| sort_keys_recursive(v) }
        else
          obj
        end
      end

      def omit_paths(obj, paths)
        result = obj.dup
        paths.each do |path|
          parts = path.to_s.split('.')
          omit_nested(result, parts)
        end
        result
      end

      def omit_nested(obj, parts)
        return unless obj.is_a?(Hash) && parts.any?
        
        key = parts.first
        if parts.length == 1
          obj.delete(key)
          obj.delete(key.tr('_', '-'))
        else
          child = obj[key] || obj[key.tr('_', '-')]
          omit_nested(child, parts[1..]) if child.is_a?(Hash)
        end
      end

      def build_nested(path, value)
        parts = path.to_s.split(/\.|\[|\]/).reject(&:empty?)
        return value if parts.empty?
        
        result = {}
        current = result
        
        parts[0..-2].each_with_index do |part, idx|
          next_part = parts[idx + 1]
          next_is_array = next_part&.match?(/^\d+$/)
          
          if part.match?(/^\d+$/)
            current = current[part.to_i] ||= (next_is_array ? [] : {})
          else
            current = current[part] ||= (next_is_array ? [] : {})
          end
        end
        
        last_part = parts.last
        if last_part.match?(/^\d+$/)
          current[last_part.to_i] = value
        else
          current[last_part] = value
        end
        
        result
      end

      def deep_set(obj, path, value)
        parts = path.to_s.split('.')
        return value if parts.empty?
        
        current = obj
        parts[0..-2].each do |part|
          current[part] ||= {}
          current = current[part]
        end
        current[parts.last] = value
        obj
      end

      def traverse_recursive(ids, lookup, get_children_field, visited, result, depth, max_depth, loc)
        return if depth > max_depth
        
        ids.each do |id|
          next if visited.include?(id)
          visited.add(id)
          
          item = lookup[id]
          next unless item
          
          result << item
          
          children = get_path(item, get_children_field, strict: false)
          next unless children.is_a?(Array)
          
          child_ids = children.map { |c| c.is_a?(Hash) ? c['value'] : c }.compact
          traverse_recursive(child_ids, lookup, get_children_field, visited, result, depth + 1, max_depth, loc)
        end
      end
    end
  end
end
