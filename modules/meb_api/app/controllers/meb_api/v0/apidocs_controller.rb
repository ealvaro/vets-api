# frozen_string_literal: true

module MebApi
  module V0
    class ApidocsController < ApplicationController
      service_tag 'education-benefits'
      skip_before_action(:authenticate)

      def index
        base_path = MebApi::Engine.root.join('app/docs/dgi/v0')
        swagger = YAML.safe_load(File.read(base_path.join('dgi_v0.yaml')))
        resolved_swagger = resolve_refs(swagger, base_path)
        render json: resolved_swagger
      end

      private

      def resolve_refs(obj, base_path, visited = {})
        @root_swagger ||= obj if obj.is_a?(Hash)

        case obj
        when Hash
          obj['$ref'] ? resolve_ref(obj, base_path, visited) : resolve_hash_values(obj, base_path, visited)
        when Array
          obj.map { |item| resolve_refs(item, base_path, visited) }
        else
          obj
        end
      end

      def resolve_ref(obj, base_path, visited)
        ref_path = obj['$ref']
        return {} if visited[ref_path] # Prevent circular refs

        next_visited = visited.merge(ref_path => true)
        referenced_doc, next_base_path = load_referenced_doc(ref_path, base_path)
        target = navigate_json_pointer(ref_path, referenced_doc)

        target.nil? ? obj : resolve_refs(target, next_base_path, next_visited)
      end

      def resolve_hash_values(obj, base_path, visited)
        obj.transform_values { |v| resolve_refs(v, base_path, visited) }
      end

      def load_referenced_doc(ref_path, base_path)
        file_path, = ref_path.split('#', 2)

        if file_path.blank?
          [@root_swagger, base_path]
        else
          docs_root = MebApi::Engine.root.join('app/docs/dgi/v0').cleanpath
          full_path = base_path.join(file_path).cleanpath

          unless full_path.to_s.start_with?(docs_root.to_s + File::SEPARATOR)
            raise ActionController::BadRequest, 'Invalid $ref path'
          end

          @loaded_docs ||= {}
          doc = @loaded_docs[full_path.to_s] ||= YAML.safe_load(File.read(full_path))
          [doc, full_path.dirname]
        end
      end

      def navigate_json_pointer(ref_path, referenced_doc)
        _, json_pointer = ref_path.split('#', 2)
        return nil if referenced_doc.nil? || json_pointer.nil?

        json_pointer.split('/').reject(&:empty?).reduce(referenced_doc) do |doc, key|
          doc.is_a?(Hash) ? doc[key] : nil
        end
      end
    end
  end
end
