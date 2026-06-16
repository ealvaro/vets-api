# frozen_string_literal: true

module Mobile
  module V0
    module Claims
      class Proxy
        STATSD_UPLOAD_LATENCY = 'mobile.api.claims.upload.latency'

        def initialize(user)
          @user = user
        end

        def get_appeal(id)
          appeals = appeals_service.get_appeals(@user).body['data']
          appeal = appeals.filter { |entry| entry['id'] == id }[0]
          raise Common::Exceptions::RecordNotFound, id unless appeal

          serializable_resource = OpenStruct.new(appeal['attributes'])
          serializable_resource[:id] = appeal['id']
          serializable_resource[:type] = appeal['type']
          serializable_resource
        rescue => e
          raise if e.is_a?(Common::Exceptions::RecordNotFound)

          handle_middleware_error(e)
        end

        def get_all_appeals
          lambda {
            begin
              { list: appeals_service.get_appeals(@user).body['data'], errors: nil }
            rescue => e
              { list: nil, errors: Mobile::V0::Adapters::ClaimsOverviewErrors.new.parse(e, 'appeals') }
            end
          }
        end

        private

        def appeals_service
          @appeals_service ||= Caseflow::Service.new
        end

        # Upstream exception classes (e.g. Common::Exceptions::BackendServiceException) expose
        # `errors`, while EVSS-style errors expose `details`. Either may also lack `body`. Probe
        # for whichever is available rather than assuming `details`.
        def handle_middleware_error(error)
          details = if error.respond_to?(:details)
                      error.details
                    elsif error.respond_to?(:errors)
                      error.errors.as_json
                    else
                      error.message
                    end
          body = error.respond_to?(:body) ? error.body : nil
          raise Common::Exceptions::BackendServiceException.new('MOBL_502_upstream_error', { details: },
                                                                upstream_status(error), body)
        end

        # Preferred order:
        # 1. error.original_status (BackendServiceException upstream HTTP code)
        # 2. error.status (Faraday-style error upstream HTTP code)
        # 3. 500 (generic fallback)
        def upstream_status(error)
          if error.respond_to?(:original_status) && error.original_status
            error.original_status
          elsif error.respond_to?(:status) && error.status
            error.status
          else
            500
          end
        end
      end
    end
  end
end
