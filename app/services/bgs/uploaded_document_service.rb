# frozen_string_literal: true

require 'logging/helper/data_scrubber'

module BGS
  class UploadedDocumentService
    attr_reader :participant_id, :ssn, :common_name, :email, :icn, :user_account

    def initialize(user)
      @participant_id = user.participant_id
      @common_name = user.common_name
      @email = user.email
      @icn = user.icn
      @user_account = user.user_account
    end

    def get_documents
      service.uploaded_document.find_by_participant_id(participant_id) || [] # rubocop:disable Rails/DynamicFindBy
    rescue => e
      Rails.logger.error(scrub_pii(e.message), { user_account:, team: Constants::ERROR_REPORTING_TEAM })

      []
    end

    private

    def service
      @service ||= BGS::Services.new(external_uid: icn, external_key:)
    end

    def external_key
      @external_key ||= begin
        key = common_name.presence || email
        key.first(Constants::EXTERNAL_KEY_MAX_LENGTH)
      end
    end

    def scrub_pii(message)
      Logging::Helper::DataScrubber.scrub(message)
    end
  end
end
