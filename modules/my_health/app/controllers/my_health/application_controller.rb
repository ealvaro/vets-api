# frozen_string_literal: true

module MyHealth
  class ApplicationController < ::ApplicationController
    include MyHealth::FacilityLoggingConcern
  end
end
