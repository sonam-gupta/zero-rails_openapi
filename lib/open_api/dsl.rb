require 'active_support/ordered_options'
require 'oas_objs/param_obj'
require 'oas_objs/response_obj'

module OpenApi
  module DSL
    def self.included(base)
      base.extend ClassMethods
    end

    # TODO: Doc-Block Comments
    module ClassMethods
      def controller_description desc = '', external_doc_url = '', &block
        @_api_infos, @_ctrl_infos = [{ }] * 2
        # current `tag`, this means that tags is currently divided by controllers.
        tag = @_ctrl_infos[:tag] = { name: controller_path.camelize }
        tag[:description]  = desc if desc.present?
        tag[:externalDocs] = { description: 'ref', url: external_doc_url } if external_doc_url.present?

        schemas = @_ctrl_infos[:components_schemas] = CtrlInfoObj.new
        schemas.instance_eval &block if block_given?
      end
      alias_method :ctrl_desc, :controller_description
      alias_method :apis_desc, :controller_description

      def open_api method, summary = '', &block
        # select the routing info corresponding to the current method from the routing list.
        action_path = "#{controller_path}##{method}"
        routes_info = ctrl_routes_list.select { |api| api[:action_path].match? /^#{action_path}$/ }.first
        puts "[zero-rails_openapi] Routing mapping failed: #{controller_path}##{method}" or return if routes_info.nil?

        # structural { path: { http_method:{ } } }, for Paths Object.
        # it will be merged into :paths
        path = @_api_infos[routes_info[:path]] ||= { }
        current_api = path[routes_info[:http_verb]] =
            ApiInfoObj.new(action_path).merge!({ summary: summary, operationId: method, tags: [controller_path.camelize] })
        current_api.instance_eval &block if block_given?
        current_api.instance_eval &@apis_blocks[method] if @apis_blocks&.[](method).is_a?(Proc)
      end

      # For DRY
      def open_api_block method, &block
        (@apis_blocks ||= { }).merge! method.to_sym => block
      end

      def ctrl_routes_list
        @routes_list ||= Generator.generate_routes_list
        @routes_list[controller_path]
      end
    end


    class CtrlInfoObj < ActiveSupport::OrderedOptions

    end

    class ApiInfoObj < ActiveSupport::OrderedOptions
      attr_accessor :action_path
      def initialize(action_path)
        self.action_path = action_path
      end

      def this_api_is_invalid! explain = ''
        self[:deprecated] = true
      end

      def desc desc, inputs_descs = { }
        @inputs_descs = inputs_descs
        self[:description] = desc
      end

      def param param_type, name, type, required, schema_hash = { }
        schema_hash[:desc] = @inputs_descs[name] if @inputs_descs[name].present?
        (self[:parameters] ||= [ ]) << ParamObj.new(name, param_type, type, required).merge!(schema_hash).process
      end

      [:header,  :path,  :query,  :cookie,
       :header!, :path!, :query!, :cookie!].each do |param_type|
        define_method param_type do |name, type, schema_hash = { }|
          param "#{param_type}".delete('!'), name, type, (param_type.to_s.match?(/!/) ? :req : :opt), schema_hash
        end
      end

      def security

      end

      def server url, desc
        (self[:servers] ||= [ ]) << { url: url, description: desc }
      end

      def response code, desc, media_type = nil, schema_hash = { }
        (self[:responses] ||= { }).merge! ResponseObj.new(code, desc, media_type, schema_hash).process
      end

      def default_response desc, media_type = nil, schema_hash = { }
        response :default, desc, media_type, schema_hash
      end


      { # alias_methods mapping
          this_api_is_invalid!: %i[this_api_is_expired! this_api_is_unused! this_api_is_under_repair!],
          response:             %i[resp                 error_response                               ],
          default_response:     %i[dft_resp                                                          ],
          error_response:       %i[other_response       oth_resp            error         err_resp   ],
      }.each do |original_name, aliases|
        aliases.each do |alias_name|
          alias_method alias_name, original_name
        end
      end
    end
  end
end