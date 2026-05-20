# frozen_string_literal: true

module MedicalCopays
  module LighthouseIntegration
    module Exceptions
      class MissingOrganizationIdError < StandardError; end
      class MissingOrganizationRefError < StandardError; end
      class MissingCityError < StandardError; end
      class MissingAccountError < StandardError; end
      class ServiceError < StandardError; end
    end
  end
end
