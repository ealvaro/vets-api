# frozen_string_literal: true

module Flipper
  module UI
    # Rack middleware that normalizes actor values to lowercase for features whose actor_type
    # is 'user' (the default). User-type actors use email addresses or UUIDs as flipper_ids,
    # both of which are case-insensitive (RFC 5321 / RFC 4122). Features with actor_type
    # 'cookie_id' are left unchanged because cookie-based identifiers are arbitrary,
    # case-sensitive strings.
    class ActorsValueNormalizer
      ACTORS_PATH_PATTERN = %r{/flipper/features/(?<feature>[^/]+)/actors\z}

      def initialize(app)
        @app = app
      end

      def call(env)
        if env['REQUEST_METHOD'] == 'POST' && (match = env['PATH_INFO']&.match(ACTORS_PATH_PATTERN))
          feature_name = match[:feature]
          if user_actor_type?(feature_name)
            request = Rack::Request.new(env)
            form_params = request.POST
            if form_params['value'].is_a?(String)
              normalized = form_params['value'].split(',').map { |v| v.strip.downcase }.join(',')
              env['rack.request.form_hash'] = form_params.merge('value' => normalized)
            end
          end
        end

        @app.call(env)
      end

      private

      def user_actor_type?(feature_name)
        feature_config = FLIPPER_FEATURE_CONFIG.dig('features', feature_name)
        # Default to 'user' when feature is not in config or actor_type is unset,
        # matching the application default described in features.yml.
        actor_type = feature_config&.fetch('actor_type', 'user') || 'user'
        actor_type != FLIPPER_ACTOR_STRING
      end
    end
  end
end
