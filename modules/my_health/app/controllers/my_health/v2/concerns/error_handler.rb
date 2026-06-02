# frozen_string_literal: true

module MyHealth
  module V2
    module Concerns
      ##
      # Thin wrapper around the shared MedicalRecords::ErrorHandler concern.
      #
      # All error-handling logic lives in +app/controllers/concerns/medical_records/error_handler.rb+.
      # This module exists solely to preserve the existing +include MyHealth::V2::Concerns::ErrorHandler+
      # statements across all V2 controllers with zero diff.
      #
      # The monitor prefix defaults to +'mhv-medical-records'+ (set by the shared concern).
      # V2 controllers inherit that default automatically.
      #
      module ErrorHandler
        extend ActiveSupport::Concern

        included do
          include ::MedicalRecords::ErrorHandler
        end
      end
    end
  end
end
