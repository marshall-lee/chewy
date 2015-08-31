module Chewy
  module Fields
    class Base
      attr_reader :name, :options, :value

      def initialize(name, options = {})
        @name, @options, @nested = name.to_sym, options.deep_symbolize_keys, {}
        @value = @options.delete(:value)
      end

      def multi_field?
        nested.any? && !object_field?
      end

      def object_field?
        (nested.any? && options[:type].blank?) || ['object', 'nested'].include?(options[:type].to_s)
      end

      def root_field?
        false
      end

      def compose(object, *args)
        options = args.extract_options!
        parent_objects = args

        result = if value && value.is_a?(Proc)
          value.arity.zero? ? object.instance_exec(&value) :
            value.call(object, *parent_objects.first(value.arity - 1))
        elsif object.is_a?(Hash)
          object[name] || object[name.to_s]
        else
          object.send(name)
        end

        result = if result.respond_to?(:to_ary)
          result.to_ary.map { |result| nested_compose(result, object, *parent_objects, options) }
        else
          nested_compose(result, object, *parent_objects, options)
        end if nested.any? && !multi_field?

        {name => result.as_json(root: false)}
      end

      def nested(field = nil)
        if field
          @nested[field.name] = field
        else
          @nested
        end
      end

      def mappings_hash
        mapping = nested.any? ? {
          (multi_field? ? :fields : :properties) => nested.values.map(&:mappings_hash).inject(:merge)
        } : {}
        mapping.reverse_merge!(options)
        mapping.reverse_merge!(type: (nested.any? ? 'object' : 'string')) unless root_field?
        {name => mapping}
      end

    private

      def nested_compose(value, *args)
        options = args.extract_options!
        parent_objects = args
        onlys = if options && options[:only]
          options[:only].each_with_object({}) do |only, result|
            if only.is_a? Symbol
              result[only] = true
            else
              result.merge! only
            end
          end
        end
        nested.map do |name, field|
          next unless value
          new_options = nil
          if onlys
            next unless onlys.include? name
            if onlys[name].is_a? Array
              new_options = {}
              new_options[:only] = onlys[name]
            end
          end
          field.compose(value, *parent_objects, new_options)
        end.compact.inject(:merge)
      end
    end
  end
end
