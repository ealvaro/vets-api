# frozen_string_literal: true

module UserAudit
  module Appenders
    class UserActionAppender < Base
      private

      def append_log
        user_action = UserAction.create!(
          user_action_event:,
          acting_user_verification:,
          subject_user_verification:,
          status:,
          acting_ip_address:,
          acting_user_agent:,
          acting_device_id:,
          acting_visit_id:
        )

        log_success('UserAction created', event_id: user_action_event.id,
                                          event_description: user_action_event.details,
                                          status:,
                                          user_action: user_action.id)
      end
    end
  end
end
