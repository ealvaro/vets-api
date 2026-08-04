# frozen_string_literal: true

require 'form21p530a/find_cemeteries_service'

module V0
  class Form21p530aFindCemeteriesController < ApplicationController
    service_tag 'state-tribal-interment-allowance'
    skip_before_action :authenticate, unless: :auth_required?
    before_action :load_user, unless: :auth_required?
    before_action :check_feature_enabled

    STATS_KEY = 'api.form21p530a.find_cemeteries'

    # GET /v0/form21p530a/cemeteries
    def index
      cemeteries = Form21p530a::FindCemeteriesService.new.response
      render json: Form21p530aCemeterySerializer.new(cemeteries), status: :ok
    rescue => e
      StatsD.increment("#{STATS_KEY}.failure")
      Rails.logger.error('Form 21P-530a cemetery lookup failed', error_class: e.class.name, class: self.class.name)
      raise
    end

    private

    def check_feature_enabled
      routing_error unless Flipper.enabled?(:form_530a_cemetery_prefill, current_user)
    end

    def auth_required?
      Flipper.enabled?(:aquia_bio_auth_required, current_user)
    end
  end
end
