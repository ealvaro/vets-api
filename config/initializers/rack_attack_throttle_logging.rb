# frozen_string_literal: true

require 'rack_attack/throttle_logger'

# Subscribe once at boot. This block only *registers* the subscription; it does
# not touch Flipper (which isn't ready during initialization). The Flipper gate
# lives in ThrottleLogger.log, evaluated at request time when a throttle fires.
#
# rack-attack emits `throttle.rack_attack` only when a request exceeds a limit
# (i.e. on the actual 429), so this fires per-429, not per-request.
ActiveSupport::Notifications.subscribe('throttle.rack_attack') do |_name, _start, _finish, _id, payload|
  RackAttack::ThrottleLogger.log(payload[:request])
end
