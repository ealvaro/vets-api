# frozen_string_literal: true

module AccreditedRepresentativePortal
  module SavedClaim
    class BenefitsIntake < ::SavedClaim
      # Do not change or remove any form IDs here as it will cause a data
      # mismatch in the saved_claims table.

      OTHER_FORM_IDS = %w[
        21-0779
        21-4192
        21-509
        21-8940
        21P-0516-1
        21P-0517-1
        21P-0518-1
        21P-0519C-1
        21P-0519S-1
        21P-530a
        21P-8049
        21-8951-2
        21-674b
        21-2680
        21-0788
        21-4193
        21P-4718a
        21-4140
        21P-4706c
        21-8960
        21-0304
        21-651
        21P-4185
        21P-535
        21-4170
        21P-524
        21P-601
        21P-4706B
        21P-4171
        21P-8924
        20-10208
        21-527
        21P-527EZ
        21-534
        20-0995
        20-0996
        10182
        20-10207
        28-1900
        26-1880
      ].freeze

      class << self
        DEFAULT_STATUS_WARNING_THRESHOLD = 10.days

        ##
        # Types of Benefits Intake API claims differ only by the value of a
        # couple attributes. `.define_claim_type` is a narrow & rigid interface
        # for defining new claim types. This interface discourages bespoke
        # customization and encourages a thoughtful pause in the case that some
        # new requirement presents friction for it.
        #
        # `form_id` can be found on much of the object graph: `saved_claims`,
        # `persistent_attachments`, and `form_submissions`. It is generally
        # overworked as both a way to indicate the actual form involved as well
        # as a way to distinguish what processing the form undergoes. We need a
        # way to deal with this overworking.
        #
        # Concretely, we have `FORM_ID` to distinguish which background job will
        # poll Benefits Intake API for status updates, and `PROPER_FORM_ID` to
        # set the datapoint in Benefits Intake API of which actual form we're
        # uploading. We could potentially forego `PROPER_FORM_ID` in favor of
        # the caller knowing how to map from `FORM_ID`, but the situation is
        # perhaps delicate enough that all callers should have their attention
        # drawn to the fact that `PROPER_FORM_ID` is the alternative for dealing
        # with this overworking problem.
        #
        def define_claim_type(form_id:, proper_form_id:, business_line:,
                              stamping_form_class:, feature_flag: nil)
          Class.new(self) do
            const_set(:FORM_ID, form_id)
            const_set(:PROPER_FORM_ID, proper_form_id)
            const_set(:BUSINESS_LINE, business_line)
            const_set(:STAMPING_FORM_CLASS, stamping_form_class)
            const_set(:FEATURE_FLAG, feature_flag) if feature_flag
            const_set(:STATUS_WARNING_THRESHOLD, DEFAULT_STATUS_WARNING_THRESHOLD)

            validates! :form_id, inclusion: [form_id]
            after_initialize { self.form_id = form_id }
          end
        end

        def pending_submission_warning_threshold
          Settings.accredited_representative_portal.pending_submission_warning_threshold&.days ||
            DEFAULT_STATUS_WARNING_THRESHOLD
        end
      end

      module BusinessLines
        CENTRAL_MAIL_PORTAL = 'CMP'
      end

      def proper_form_id
        self.class::PROPER_FORM_ID
      end

      FORM_TYPES = [
        (DependencyClaim =
           define_claim_type(
             form_id: '21-686C_BENEFITS-INTAKE',
             proper_form_id: '21-686c',
             business_line: BusinessLines::CENTRAL_MAIL_PORTAL,
             stamping_form_class: SimpleFormsApi::VBA21686C
           )
        ),
        (DisabilityClaim =
           define_claim_type(
             form_id: '21-526EZ_BENEFITS-INTAKE',
             proper_form_id: '21-526EZ',
             business_line: BusinessLines::CENTRAL_MAIL_PORTAL,
             stamping_form_class: SimpleFormsApi::VBA21526EZ
           )
        ),
        OTHER_FORM_IDS.map do |form_id|
          const_set(
            "Form#{form_id.gsub(/-/, '').camelize}",
            define_claim_type(
              form_id: "#{form_id.upcase}_BENEFITS-INTAKE",
              proper_form_id: form_id,
              business_line: BusinessLines::CENTRAL_MAIL_PORTAL,
              stamping_form_class: nil,
              feature_flag: 'accredited_representative_portal_submit_any_file'
            )
          )
        end
      ].flatten.freeze

      ##
      # Needed to interoperate with the form schema validations performed by the
      # parent class.
      #
      FORM = 'BENEFITS-INTAKE'

      attachment_association_options = {
        inverse_of: :saved_claim,
        dependent: :destroy
      }

      with_options(attachment_association_options) do
        has_one(
          :form_attachment,
          -> { where(type: 'PersistentAttachments::VAForm') },
          class_name: 'PersistentAttachment',
          required: true
        )

        has_many(
          :persistent_attachments,
          lambda {
            where(type: [
                    'PersistentAttachments::VAFormDocumentation',
                    'AccreditedRepresentativePortal::PersistentAttachments::SeparationHealthAssessment'
                  ])
          }
        )

        has_one(
          :separation_health_assessment,
          -> { where(type: 'AccreditedRepresentativePortal::PersistentAttachments::SeparationHealthAssessment') },
          class_name: 'PersistentAttachment'
        )
      end

      has_one :saved_claim_claimant_representative,
              class_name: 'AccreditedRepresentativePortal::SavedClaimClaimantRepresentative',
              foreign_key: :saved_claim_id

      delegate :power_of_attorney_holder_poa_code, to: :saved_claim_claimant_representative, allow_nil: true
      delegate :to_pdf, to: :form_attachment

      def latest_submission_attempt
        @latest_submission_attempt ||=
          form_submissions.order(created_at: :desc).first&.latest_attempt
      end

      def pending_submission_attempt_stale?
        return false unless latest_submission_attempt&.aasm_state == 'pending'

        latest_submission_attempt.updated_at <= self.class::STATUS_WARNING_THRESHOLD.ago
      end

      def display_form_id
        proper_form_id || form_id
      end

      def self.form_class_from_proper_form_id(proper_form_id)
        FORM_TYPES.find do |klass|
          klass::PROPER_FORM_ID.casecmp?(proper_form_id)
        end
      end
    end
  end
end
