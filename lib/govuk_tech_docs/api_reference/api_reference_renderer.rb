require 'erb'
require 'json'

module GovukTechDocs
  module ApiReference
    class Renderer
      def initialize(app, document)
        @app = app
        @document = document

        # Load template files
        @template_api_full = get_renderer('api_reference_full.html.erb')
        @template_path = get_renderer('path.html.erb')
        @template_schema = get_renderer('schema.html.erb')
        @template_operation = get_renderer('operation.html.erb')
        @template_parameters = get_renderer('parameters.html.erb')
        @template_responses = get_renderer('responses.html.erb')
      end

      def api_full(info, server)
        paths = ''
        paths_data = @document.paths
        paths_data.each do |path_data|
          # For some reason paths.each returns an array of arrays [title, object]
          # instead of an array of objects
          text = path_data[0]
          paths += path(text)
        end
        schemas = ''
        schemas_data = @document.components.schemas
        schemas_data.each do |schema_data|
          text = schema_data[0]
          schemas += schema(text)
        end
        @template_api_full.result(binding)
      end

      def path(text)
        path = @document.paths[text]
        id = text.parameterize
        operations = operations(path, id)
        @template_path.result(binding)
      end

      def schema(text)
        schemas = ''
        schemas_data = @document.components.schemas
        schemas_data.each do |schema_data|

          allOf = schema_data[1]["allOf"]

          properties = []

          if !allOf.blank?
            schema_data[1]["allOf"].each do |schema_nested|
              # pry(schema_nested.properties)
              properties.concat(schema_nested.properties)
            end
          end

          puts properties

          if schema_data[0] == text
            title = schema_data[0]
            schema = schema_data[1]
            return @template_schema.result(binding)
          end
        end
      end

      def schemas_from_path(text)
        path = @document.paths[text]
        operations = get_operations(path)
        # Get all referenced schemas
        schemas = []
        operations.compact.each do |key, operation|
          responses = operation.responses
          responses.each do |key,response|
            if response.content['application/json']
              schema = response.content['application/json'].schema
              schema_name = get_schema_name(schema.node_context.source_location.to_s)
              if !schema_name.nil?
                schemas.push schema_name
              end
              schemas.concat(schemas_from_schema(schema))
            end
          end
        end
        # Render all referenced schemas
        output = ''
        schemas.uniq.each do |schema_name|
          output += schema(schema_name)
        end
        if !output.empty?
          output.prepend('<h2 id="schemas">Schemas</h2>')
        end
        output
      end

      def schemas_from_schema(schema)
        schemas = []
        properties = schema.properties
        properties.each do |key, property|
          # Must be a schema be referenced by another schema
          # And not a property of a schema
          if property.node_context.referenced_by.to_s.include? '#/components/schemas' and !property.node_context.source_location.to_s.include? '/properties/'
            schema_name = get_schema_name(property.node_context.source_location.to_s)
          end
          if !schema_name.nil?
            schemas.push schema_name
          end
          # Check sub-properties for references
          schemas.concat(schemas_from_schema(property))
        end
        schemas
      end

      def operations(path, path_id)
        output = ''
        operations = get_operations(path)
        operations.compact.each do |key, operation|
          id = "#{path_id}-#{key.parameterize}"
          parameters = parameters(operation, id)
          responses = responses(operation, id)
          output += @template_operation.result(binding)
        end
        output
      end

      def parameters(operation, operation_id)
        parameters = operation.parameters
        id = "#{operation_id}-parameters"
        output = @template_parameters.result(binding)
        output
      end

      def responses(operation, operation_id)
        responses = operation.responses
        id = "#{operation_id}-responses"
        output = @template_responses.result(binding)
        output
      end

      def markdown(text)
        if text
          Tilt['markdown'].new(context: @app) { text }.render
        end
      end

      def json_output(schema)
        properties =  schema_properties(schema)
        JSON.pretty_generate(properties)
      end

      def schema_properties(schema_data)
        properties = schema_data.properties
        properties_hash = Hash.new
        properties.each do |key, item|
          if item.type == 'object' || item.type == 'array'
            properties_hash[key] = schema_properties(item)
          else
            if item.example.nil?
              value = item.type
            else
              value = item.example
            end
            properties_hash[key] = value
            # if $ref return referenced
          end
        end
        properties_hash
      end

    private

      def get_renderer(file)
        template_path = File.join(File.dirname(__FILE__), 'templates/' + file)
        template = File.open(template_path, 'r').read
        ERB.new(template)
      end

      def get_operations(path)
        operations = {}
        operations['get'] = path.get if defined? path.get
        operations['put'] = path.put if defined? path.put
        operations['post'] = path.post if defined? path.post
        operations['delete'] = path.delete if defined? path.delete
        operations['patch'] = path.patch if defined? path.patch
        operations
      end

      def get_schema_name(text)
        unless text.is_a?(String)
          return nil
        end
        # Schema dictates that it's always components['schemas']
        text.gsub(/#\/components\/schemas\//, '')
      end

      def get_schema_link(schema)
        schema_name = get_schema_name schema.node_context.source_location.to_s
        if !schema_name.nil?
          id = "schema-#{schema_name.parameterize}"
          output = "<a href='\##{id}'>#{schema_name}</a>"
          output
        end
      end
    end
  end
end

