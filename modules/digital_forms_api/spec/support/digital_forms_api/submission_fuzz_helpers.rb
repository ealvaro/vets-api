# frozen_string_literal: true

module DigitalFormsApi
  module SubmissionFuzzHelpers
    DEFAULT_PARTICIPANT_ID = '12345'

    # Reproducible seed — replay any failure with DF_FUZZ_SEED=<value>
    def fuzz_seed
      @fuzz_seed ||= ENV.fetch('DF_FUZZ_SEED', Random.new_seed).to_i
    end

    def fuzz_rng
      @fuzz_rng ||= Random.new(fuzz_seed)
    end

    # ------------------------------------------------------------------ #
    # Iteration & Stubs
    # ------------------------------------------------------------------ #

    # Run N fuzz iterations, yielding each generated body, veteranId, and denial reason.
    # Uses :fuzz_submission_body and :fuzz_veteran_id factories for data generation.
    # @param rng [Random]
    # @param count [Integer] number of iterations
    # @param veteran_id_style [Symbol] :valid, :malformed, :wrong_type, :mismatch, or :random
    # @param matching_participant_id [String, nil]
    # @yieldparam body [Hash] the generated submission body
    # @yieldparam veteran_id [Object] the veteranId from the body
    # @yieldparam denial [String, nil] the expected denial reason
    def fuzz_iterations(rng, count: 25, veteran_id_style: :random, matching_participant_id: DEFAULT_PARTICIPANT_ID)
      count.times do
        style = resolve_veteran_id_style(rng, veteran_id_style)
        veteran_id = build_fuzz_veteran_id(rng, style, matching_participant_id)
        body = build(:fuzz_submission_body, rng:, matching_participant_id:, veteran_id:)
        denial = expected_denial_reason(veteran_id, matching_participant_id)
        yield body, veteran_id, denial
      end
    end

    # Build a stub submission response (OpenStruct mimicking Faraday::Env)
    def stub_submission(body)
      OpenStruct.new(body:)
    end

    # Build a valid template response hash
    def stub_template(version: '1.0')
      {
        'formTemplate' => {
          'formTemplate' => {
            '21-686c' => {
              'formId' => '21-686c',
              'version' => version
            }
          }
        }
      }
    end

    # Stub the Submissions service retrieve call, and optionally the Templates service
    # when no denial is expected (i.e. the request should be authorized).
    # @param body [Hash] the submission response body
    # @param denial [String, nil] the expected denial reason
    def stub_fuzz_services(body, denial: nil)
      allow_any_instance_of(DigitalFormsApi::Service::Submissions)
        .to receive(:retrieve).and_return(stub_submission(body))
      return if denial

      allow_any_instance_of(DigitalFormsApi::Service::Templates)
        .to receive(:template).and_return(stub_template)
    end

    # Return the expected denial reason (or nil for authorized) given the inputs
    # Mirrors SubmissionsController#denial_reason_for_veteran_id
    def expected_denial_reason(veteran_id, user_participant_id)
      return 'missing_participant_id' if user_participant_id.blank?
      return 'malformed_veteran_id' unless veteran_id.is_a?(Hash)
      return 'identifier_type_mismatch' unless veteran_id['identifierType'] == 'PARTICIPANTID'
      return 'participant_id_mismatch' unless veteran_id['value'] == user_participant_id

      nil
    end

    private

    # Resolve :random style into a concrete veteran ID style
    # @param rng [Random]
    # @param style [Symbol]
    # @return [Symbol]
    def resolve_veteran_id_style(rng, style)
      return style unless style == :random

      %i[valid malformed wrong_type mismatch].sample(random: rng)
    end

    # Build a veteran ID hash via the :fuzz_veteran_id factory
    # @param rng [Random]
    # @param style [Symbol] :valid, :malformed, :wrong_type, or :mismatch
    # @param matching_participant_id [String, nil]
    # @return [Hash, Object] the veteran ID (may be non-Hash for :malformed)
    def build_fuzz_veteran_id(rng, style, matching_participant_id)
      if style == :valid
        build(:fuzz_veteran_id, rng:, matching_participant_id:)
      else
        build(:fuzz_veteran_id, style, rng:, matching_participant_id:)
      end
    end
  end
end
