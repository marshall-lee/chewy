module Chewy
  class Type
    module UpdateOrImport
      extend ActiveSupport::Concern

      module ClassMethods
        def update_or_import(*args)
          import_options = args.extract_options!
          bulk_options = import_options.reject { |k, v| ![:refresh, :suffix].include?(k) }.reverse_merge!(refresh: true)

          index.create!(bulk_options.slice(:suffix)) unless index.exists?
          build_root unless self.root_object

          ActiveSupport::Notifications.instrument 'import_objects.chewy', type: self do |payload|
            adapter.import(*args, import_options) do |action_objects|
              update_actions = { update: action_objects[:index] }
              indexed_objects = self.root_object.parent_id && fetch_indexed_objects(action_objects.values.flatten)

              body = bulk_body(update_actions, indexed_objects, import_options.slice(:only))

              errors = bulk(bulk_options.merge(body: body)) if body.any?

              p errors[:update]

              # body = bulk_body(action_objects, indexed_objects)
              # errors = bulk(bulk_options.merge(body: body)) if body.any?

              fill_payload_import payload, action_objects
              fill_payload_errors payload, errors if errors.present?
              !errors.present?
            end
          end
        end

      private

        def update_bulk_entry(object, *args)
          options = args.extract_options!
          indexed_objects = args.shift
          entry = {}

          if self.root_object.id
            entry[:_id] = self.root_object.compose_id(object)
          else
            entry[:_id] = object.id if object.respond_to?(:id)
            entry[:_id] ||= object[:id] || object['id'] if object.is_a?(Hash)
            entry[:_id] = entry[:_id].to_s if defined?(BSON) && entry[:_id].is_a?(BSON::ObjectId)
          end
          entry.delete(:_id) if entry[:_id].blank?

          if self.root_object.parent_id
            entry[:parent] = self.root_object.compose_parent(object)
            existing_object = entry[:_id].present? && indexed_objects && indexed_objects[entry[:_id].to_s]
          end

          entry[:data] = { doc: object_data(object, options.slice(:only)) }

          if existing_object && entry[:parent].to_s != existing_object[:parent]
            [{ delete: entry.except(:data).merge(parent: existing_object[:parent]) }, { update: entry }]
          else
            [{ update: entry }]
          end
        end
      end
    end
  end
end
