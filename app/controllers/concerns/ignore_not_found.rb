# frozen_string_literal: true

module IgnoreNotFound
  def skip_reportable_types
    ApplicationController::SKIP_REPORTABLE_TYPES + [Common::Exceptions::RecordNotFound]
  end
end
