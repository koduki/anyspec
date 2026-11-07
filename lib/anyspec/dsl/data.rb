# frozen_string_literal: true

module Anyspec
  module DSL
    module Data
      module_function

      def path(value, path, optional: false)
        parts = path.is_a?(Array) ? path : path.to_s.split('.')
        parts.reduce(value) do |current, key|
          if current.is_a?(Hash) && current.key?(key.to_s)
            current[key.to_s]
          elsif current.is_a?(Array) && key.to_s.match?(/\A\d+\z/) && key.to_i < current.size
            current[key.to_i]
          elsif optional
            return nil
          else
            raise Error, "missing path #{parts.inspect}"
          end
        end
      end

      def array(value)
        raise Error, 'expected array' unless value.is_a?(Array)
        value
      end

      def object(value)
        raise Error, 'expected object' unless value.is_a?(Hash)
        value
      end

      def index(value, key)
        array(value).each_with_object({}) do |item, result|
          id = path(item, key)
          raise Error, 'index key must be a nonempty string' unless id.is_a?(String) && !id.empty?
          raise Error, "duplicate index key #{id}" if result.key?(id)
          result[id] = item
        end
      end

      def merge(left, right)
        object(left)
        object(right)
        collision = left.keys & right.keys
        raise Error, "map key collision #{collision.first}" unless collision.empty?
        left.merge(right)
      end

      def partial?(actual, expected)
        case expected
        when Hash
          actual.is_a?(Hash) && expected.all? { |key, value| actual.key?(key) && partial?(actual[key], value) }
        when Array
          actual.is_a?(Array) && expected.all? { |value| actual.any? { |item| partial?(item, value) } }
        else
          actual == expected
        end
      end

      # Array order is semantic by default. Only explicitly declared paths are sorted.
      # '*' matches one path segment, '**' matches arbitrary descendants.
      def normalize(value, options = {}, path = [])
        drop = options.fetch('drop', [])
        case value
        when Hash
          value.keys.sort.each_with_object({}) do |key, result|
            next if drop.include?(key)
            result[key] = normalize(value[key], options, path + [key])
          end
        when Array
          values = value.map { |item| normalize(item, options, path + ['*']) }
          rule = options.fetch('arrays', {}).find do |pattern, _|
            glob = pattern.split('.')
            glob.first == '**' ? path.last(glob.size - 1) == glob.drop(1) : glob.size == path.size && glob.zip(path).all? { |a, b| a == '*' || a == b }
          end
          return values unless rule
          key = rule.last
          values.sort_by do |item|
            sort_value = key == '$' ? JSON.generate(item) : self.path(item, key)
            [sort_value, JSON.generate(item)]
          end
        else
          value
        end
      end

      def transform(value, path, &block)
        parts = path.is_a?(Array) ? path : path.to_s.split('.')
        return block.call(value) if parts.empty?
        key, *rest = parts
        if key == '*'
          case value
          when Hash then value.transform_values { |child| transform(child, rest, &block) }
          when Array then value.map { |child| transform(child, rest, &block) }
          when NilClass then nil
          else raise Error, 'wildcard transform requires a container'
          end
        elsif value.is_a?(Hash)
          value.key?(key) ? value.merge(key => transform(value[key], rest, &block)) : value
        elsif value.nil?
          nil
        else
          raise Error, "invalid transform path #{key}"
        end
      end

      def collect(value, path)
        parts = path.is_a?(Array) ? path : path.to_s.split('.')
        return [value] if parts.empty?
        key, *rest = parts
        if key == '*'
          children = value.is_a?(Hash) ? value.values : array(value)
          children.flat_map { |item| collect(item, rest) }
        elsif value.is_a?(Hash) && value.key?(key)
          collect(value[key], rest)
        elsif value.nil? || value.is_a?(Hash)
          []
        else
          raise Error, "invalid traversal at #{key}"
        end
      end
    end
  end
end
