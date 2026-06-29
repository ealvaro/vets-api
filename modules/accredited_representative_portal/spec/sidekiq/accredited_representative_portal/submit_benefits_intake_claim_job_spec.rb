# frozen_string_literal: true

require 'rails_helper'
require AccreditedRepresentativePortal::Engine.root / 'spec/spec_helper'

RSpec.describe AccreditedRepresentativePortal::SubmitBenefitsIntakeClaimJob do
  fixture_path =
    'form_data/saved_claim/benefits_intake/dependent_claimant.json'

  dependent_claimant_form =
    load_fixture(fixture_path) do |fixture|
      JSON.parse(fixture)
    end

  subject(:perform) { described_class.new.perform(saved_claim.id) }

  let(:form_attachment) { create(:persistent_attachment_va_form, form_id: '21-686c') }
  let(:documentation)   { create(:persistent_attachment_va_form_documentation, form_id: '21-686c') }

  let(:saved_claim) do
    AccreditedRepresentativePortal::SavedClaim::BenefitsIntake::DependencyClaim.create!(
      form: dependent_claimant_form.to_json,
      form_attachment:,
      persistent_attachments: [documentation]
    )
  end
  let(:saved_claim_claimant_representative) do
    create(:saved_claim_claimant_representative, saved_claim:)
  end

  let(:vcr_options) do
    ##
    # It seems as though request bodies and headers are dynamic given static
    # inputs, which is why we exclude them from VCR matching.
    #
    {
      match_requests_on: %i[method uri],

      ##
      # This job is behaving incorrectly if it does not perform all of the
      # requests to Benefits Intake API that were recorded in the cassette.
      # Those are:
      #   - `POST /uploads` (gets an <upload_location>)
      #   - `POST /uploads/validate_document` (validates 1st document)
      #   - `POST /uploads/validate_document` (validates 2nd document)
      #   - `PUT <upload_location>` (submits the document)
      #
      allow_unused_http_interactions: false
    }
  end

  before do
    ##
    # This works around some test configuration weirdness. Without this, the
    # locations used for reading and writing differ, likely due to a difference
    # in which Shrine plugins have been plugged in at various points.
    #
    allow_any_instance_of(Shrine::UploadedFile).to(
      receive(:storage).and_return(Shrine.storages[:store])
    )
    saved_claim.saved_claim_claimant_representative = saved_claim_claimant_representative
    saved_claim.save
  end

  after do
    # Clean up mocks to prevent test pollution in parallel runs
    RSpec::Mocks.space.reset_all
  end

  context 'accredited_representative_portal_lighthouse_api_key is not set' do
    before do
      allow(Flipper).to receive(:enabled?).with(
        :accredited_representative_portal_lighthouse_api_key
      ).and_return(false)
    end

    it 'performs using BenefitsIntakeService::Service' do
      use_cassette('performs', vcr_options) do
        expect_any_instance_of(BenefitsIntakeService::Service).to(
          receive(:upload_doc).and_call_original
        )

        expect { perform }.to change {
          FormSubmissionAttempt.where.not(benefits_intake_uuid: nil).count
        }.by(1)
      end
    end

    context 'submission has additional documentation' do
      around { |example| Timecop.freeze { example.run } }

      let(:stamper) { double }

      it 'stamps the footer of the additional docs' do
        timestamp = DateTime.now.utc.strftime('%H:%M:%S  %Y-%m-%d %I:%M %p')

        use_cassette('performs', vcr_options) do
          # mock stamping of provided VA form
          allow(SimpleFormsApi::PdfStamper).to receive(:new).and_return(stamper)
          allow(stamper).to receive(:stamp_pdf)

          expect_any_instance_of(PDFUtilities::DatestampPdf).to receive(:run).with(
            text: "Submitted via VA.gov at #{timestamp} UTC. Signed in and submitted " \
                  'with an identity-verified account.',
            text_only: true, x: 5, y: 5
          ).and_call_original

          perform
        end
      end
    end
  end

  describe 'StatsD metrics' do
    let(:form_id) { saved_claim.proper_form_id }
    let(:expected_tags) do
      [
        "form_id:#{form_id}",
        'org:067',
        'service:accredited-representative-portal'
      ]
    end

    before do
      allow(StatsD).to receive(:increment)
      allow(Flipper).to receive(:enabled?).with(
        :accredited_representative_portal_lighthouse_api_key
      ).and_return(false)
    end

    context 'on success' do
      it 'increments ATTEMPT then SUCCESS' do
        use_cassette('performs', vcr_options) do
          perform
        end

        expect(StatsD).to have_received(:increment)
          .with(described_class::ATTEMPT_METRIC_SUBMIT, tags: expected_tags)
        expect(StatsD).to have_received(:increment)
          .with(described_class::SUCCESS_METRIC_SUBMIT, tags: expected_tags)
      end
    end

    context 'on ClientError' do
      before do
        allow_any_instance_of(BenefitsIntakeService::Service).to(
          receive(:get_location_and_uuid).and_raise(
            Common::Client::Errors::ClientError.new('500 Internal Server Error')
          )
        )
        allow(StatsD).to receive(:increment)
      end

      it 'increments ATTEMPT then ERROR with reason:unknown_error' do
        suppress(Common::Client::Errors::ClientError) { perform }

        expect(StatsD).to have_received(:increment)
          .with(described_class::ATTEMPT_METRIC_SUBMIT, tags: expected_tags)
        expect(StatsD).to have_received(:increment)
          .with(described_class::ERROR_METRIC_SUBMIT,
                tags: ['reason:unknown_error'].concat(expected_tags))
      end
    end

    context 'on generic error' do
      before do
        allow_any_instance_of(BenefitsIntakeService::Service).to(
          receive(:get_location_and_uuid).and_raise(StandardError.new('oh no'))
        )
      end

      it 'increments ATTEMPT then ERROR with reason:unknown_error' do
        suppress(StandardError) { perform }

        expect(StatsD).to have_received(:increment)
          .with(described_class::ATTEMPT_METRIC_SUBMIT, tags: expected_tags)
        expect(StatsD).to have_received(:increment)
          .with(described_class::ERROR_METRIC_SUBMIT,
                tags: ['reason:unknown_error'].concat(expected_tags))
      end
    end
  end

  context 'accredited_representative_portal_lighthouse_api_key is set' do
    before do
      allow(Flipper).to receive(:enabled?).with(
        :accredited_representative_portal_lighthouse_api_key
      ).and_return(true)

      # Mock the API key configuration that BenefitsIntakeService requires
      allow(Settings.accredited_representative_portal.lighthouse.benefits_intake).to(
        receive(:api_key).and_return('test-api-key')
      )
    end

    it 'performs using ARP BenefitsIntakeService' do
      use_cassette('performs', vcr_options) do
        expect_any_instance_of(AccreditedRepresentativePortal::BenefitsIntakeService).to(
          receive(:upload_doc).and_call_original
        )

        expect { perform }.to change {
          FormSubmissionAttempt.where.not(benefits_intake_uuid: nil).count
        }.by(1)
      end
    end

    context 'submission has additional documentation' do
      around { |example| Timecop.freeze { example.run } }

      let(:stamper) { double }

      it 'stamps the footer of the additional docs' do
        timestamp = DateTime.now.utc.strftime('%H:%M:%S  %Y-%m-%d %I:%M %p')

        use_cassette('performs', vcr_options) do
          # mock stamping of provided VA form
          allow(SimpleFormsApi::PdfStamper).to receive(:new).and_return(stamper)
          allow(stamper).to receive(:stamp_pdf)

          expect_any_instance_of(PDFUtilities::DatestampPdf).to receive(:run).with(
            text: "Submitted via VA.gov at #{timestamp} UTC. Signed in and submitted " \
                  'with an identity-verified account.',
            text_only: true, x: 5, y: 5
          ).and_call_original

          perform
        end
      end

      it 'resolves the stamping form class from the claim form_id' do
        claim_class = AccreditedRepresentativePortal::SavedClaim::BenefitsIntake::DependencyClaim

        claim = double('claim', form_id: '21-686C')

        allow(claim).to receive(:class).and_return(claim_class)

        job = described_class.new

        job.instance_variable_set(:@claim, claim)

        expect(job.send(:stamping_form_class)).to eq(SimpleFormsApi::VBA21686C)
      end
    end
  end

  context 'submit other forms upload' do
    let(:stamper) { double }
    let(:claim) { build(:saved_claim_other_forms) }

    it 'calls SimpleFormsApi::PdfStamper with correct parameters' do
      job = described_class.new

      job.instance_variable_set(:@claim, claim)
      allow(SimpleFormsApi::PdfStamper).to receive(:new).with(
        form: nil,
        form_number: '21-4170',
        stamped_template_path: 'stamped_template_path',
        current_loa: SignIn::Constants::Auth::LOA_THREE,
        timestamp: claim.created_at
      ).and_return stamper
      allow(claim).to receive(:to_pdf).and_return('stamped_template_path')
      expect(stamper).to receive(:stamp_pdf)
      job.stamp_pdf(claim)
    end
  end
end
