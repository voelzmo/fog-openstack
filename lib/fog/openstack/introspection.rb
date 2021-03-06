require 'yaml'

module Fog
  module Introspection
    class OpenStack < Fog::Service
      SUPPORTED_VERSIONS = /v1/

      requires :openstack_auth_url
      recognizes :openstack_auth_token, :openstack_management_url,
                 :persistent, :openstack_service_type, :openstack_service_name,
                 :openstack_tenant, :openstack_tenant_id,
                 :openstack_api_key, :openstack_username, :openstack_identity_endpoint,
                 :current_user, :current_tenant, :openstack_region,
                 :openstack_endpoint_type,
                 :openstack_project_name, :openstack_project_id,
                 :openstack_project_domain, :openstack_user_domain, :openstack_domain_name,
                 :openstack_project_domain_id, :openstack_user_domain_id, :openstack_domain_id

      ## REQUESTS
      #
      request_path 'fog/openstack/requests/introspection'

      # Introspection requests
      request :create_introspection
      request :get_introspection
      request :abort_introspection
      request :get_introspection_details

      # Rules requests
      request :create_rules
      request :list_rules
      request :delete_rules_all
      request :get_rules
      request :delete_rules

      ## MODELS
      #
      model_path 'fog/openstack/models/introspection'
      model       :rules
      collection  :rules_collection

      class Mock
        def self.data
          @data ||= Hash.new do |hash, key|
            # Introspection data is *huge* we load it from a yaml file
            file = "../../../../tests/fixtures/introspection.yaml"
            hash[key] = YAML.load(File.read(File.expand_path(file, __FILE__)))
          end
        end

        def self.reset
          @data = nil
        end

        include Fog::OpenStack::Core

        def initialize(options = {})
          @auth_token = Fog::Mock.random_base64(64)
          @auth_token_expiration = (Time.now.utc + 86_400).iso8601

          initialize_identity options
        end

        def data
          self.class.data[@openstack_username]
        end

        def reset_data
          self.class.data.delete(@openstack_username)
        end
      end

      class Real
        include Fog::OpenStack::Core

        def initialize(options = {})
          initialize_identity options

          @openstack_service_type  = options[:openstack_service_type] || ['introspection']
          @openstack_service_name  = options[:openstack_service_name]

          @connection_options = options[:connection_options] || {}

          authenticate

          unless @path.match(SUPPORTED_VERSIONS)
            @path = "/" + Fog::OpenStack.get_supported_version(
              SUPPORTED_VERSIONS,
              @openstack_management_uri,
              @auth_token,
              @connection_options
            )
          end

          @persistent = options[:persistent] || false
          @connection = Fog::Core::Connection.new("#{@scheme}://#{@host}:#{@port}", @persistent, @connection_options)
        end

        def request(params)
          response = @connection.request(
            params.merge(
              :headers => {
                'Content-Type' => 'application/json',
                'X-Auth-Token' => @auth_token
              }.merge!(params[:headers] || {}),
              :path    => "#{@path}/#{params[:path]}"
            )
          )
        rescue Excon::Errors::Unauthorized    => error
          if error.response.body != "Bad username or password" # token expiration
            @openstack_must_reauthenticate = true
            authenticate
            retry
          else # bad credentials
            raise error
          end
        rescue Excon::Errors::HTTPStatusError => error
          raise case error
                when Excon::Errors::NotFound
                  Fog::Introspection::OpenStack::NotFound.slurp(error)
                else
                  error
                end
        else
          unless response.body.empty?
            response.body = Fog::JSON.decode(response.body)
          end
          response
        end
      end
    end
  end
end
