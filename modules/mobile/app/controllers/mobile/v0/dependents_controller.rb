# frozen_string_literal: true

module Mobile
  module V0
    class DependentsController < ApplicationController
      def index
        dependents_response = dependent_service.get_dependents
        persons = dependents_response[:persons].map { |person| Dependent.new(id: SecureRandom.uuid, **person) }

        render json: DependentSerializer.new(persons)
      rescue => e
        raise Common::Exceptions::BackendServiceException.new(nil, detail: e.message)
      end

      def dependent_service
        @dependent_service ||= BGS::DependentService.new(current_user)
      end
    end
  end
end
