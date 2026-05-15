# frozen_string_literal: true

require 'rails_helper'

RSpec.describe V0::ClaimLettersController, type: :controller do
  let(:user) { build(:user, :loa3) }
  let(:document_id) { '{27832B64-2D88-4DEE-9F6F-DF80E4CAAA87}' }
  let(:filename) { 'ClaimLetter-2022-9-22.pdf' }
  let(:list_letters_res) { get_fixture('claim_letter/claim_letter_list') }

  before do
    sign_in_as(user)
  end

  context 'VBMS claim letter provider' do
    before do
      allow(Flipper).to receive(:enabled?)
        .with(:cst_claim_letters_use_lighthouse_api_provider, anything)
        .and_return(false)
    end

    describe '#index' do
      it 'lists document id and letter details for claim letters' do
        get(:index)
        letters = JSON.parse(response.body)
        expected_important_keys = %w[document_id doc_type received_at]

        expect(letters.length).to be > 0
        # We can reference the keys of the first letters since
        # they _should_ all have the same keys.
        expect(letters.first.keys).to include(*expected_important_keys)
      end
    end

    describe '#index when "cst_include_ddl_boa_letters" is enabled
    and "cst_include_ddl_5103_letters" and "cst_include_ddl_sqd_letters" are disabled' do
      before do
        allow(Flipper).to receive(:enabled?)
          .with(:cst_include_ddl_boa_letters, anything)
          .and_return(true)
        allow(Flipper).to receive(:enabled?)
          .with(:cst_include_ddl_5103_letters, anything)
          .and_return(false)
        allow(Flipper).to receive(:enabled?)
          .with(:cst_include_ddl_sqd_letters, anything)
          .and_return(false)
      end

      it 'lists correct documents' do
        get(:index)
        letters = JSON.parse(response.body)
        allowed_letters = letters.select { |d| %w[27 184].include?(d['doc_type']) }

        expect(allowed_letters.length).to eql(letters.length)
      end
    end

    describe '#index when "cst_include_ddl_5103_letters" is enabled
    and "cst_include_ddl_boa_letters" and "cst_include_ddl_sqd_letters" are disabled' do
      before do
        allow(Flipper).to receive(:enabled?)
          .with(:cst_include_ddl_5103_letters, anything)
          .and_return(true)
        allow(Flipper).to receive(:enabled?)
          .with(:cst_include_ddl_boa_letters, anything)
          .and_return(false)
        allow(Flipper).to receive(:enabled?)
          .with(:cst_include_ddl_sqd_letters, anything)
          .and_return(false)
      end

      it 'lists correct documents' do
        get(:index)
        letters = JSON.parse(response.body)
        allowed_letters = letters.select { |d| %w[704 706 858 184].include?(d['doc_type']) }

        expect(allowed_letters.length).to eql(letters.length)
      end
    end

    describe '#index when "cst_include_ddl_sqd_letters" is enabled
    and "cst_include_ddl_boa_letters" and "cst_include_ddl_5103_letters" are disabled' do
      before do
        allow(Flipper).to receive(:enabled?)
          .with(:cst_include_ddl_5103_letters, anything)
          .and_return(false)
        allow(Flipper).to receive(:enabled?)
          .with(:cst_include_ddl_boa_letters, anything)
          .and_return(false)
        allow(Flipper).to receive(:enabled?)
          .with(:cst_include_ddl_sqd_letters, anything)
          .and_return(true)
      end

      it 'lists correct documents' do
        get(:index)
        letters = JSON.parse(response.body)
        allowed_letters = letters.select { |d| %w[184 34 408 700 859 864 942 1605].include?(d['doc_type']) }

        expect(allowed_letters.length).to eql(letters.length)
      end
    end

    describe '#index when "cst_include_ddl_5103_letters", "cst_include_ddl_boa_letters",
    and "cst_include_ddl_sqd_letters" feature flags are disabled' do
      before do
        allow(Flipper).to receive(:enabled?)
          .with(:cst_include_ddl_5103_letters, anything)
          .and_return(false)
        allow(Flipper).to receive(:enabled?)
          .with(:cst_include_ddl_boa_letters, anything)
          .and_return(false)
        allow(Flipper).to receive(:enabled?)
          .with(:cst_include_ddl_sqd_letters, anything)
          .and_return(false)
      end

      it 'lists correct documents' do
        get(:index)
        letters = JSON.parse(response.body)
        allowed_letters = letters.select { |d| d['doc_type'] == '184' }

        expect(allowed_letters.length).to eql(letters.length)
      end
    end

    describe '#index when "cst_include_ddl_5103_letters", "cst_include_ddl_boa_letters",
    and "cst_include_ddl_sqd_letters" feature flags are all enabled' do
      before do
        allow(Flipper).to receive(:enabled?)
          .with(:cst_include_ddl_5103_letters, anything)
          .and_return(true)
        allow(Flipper).to receive(:enabled?)
          .with(:cst_include_ddl_boa_letters, anything)
          .and_return(true)
        allow(Flipper).to receive(:enabled?)
          .with(:cst_include_ddl_sqd_letters, anything)
          .and_return(true)
      end

      it 'lists correct documents' do
        all_allowed_doctypes = %w[27 34 184 408 700 704 706 858 859 864 942 1605]
        get(:index)
        letters = JSON.parse(response.body)
        allowed_letters = letters.select { |d| all_allowed_doctypes.include?(d['doc_type']) }

        expect(allowed_letters.length).to eql(letters.length)
      end
    end

    describe '#show' do
      it 'responds with a pdf with a dated filename' do
        get(:show, params: { document_id: })

        expect(response.header['Content-Type']).to eq('application/pdf')
        expect(response.header['Content-Disposition']).to include("filename=\"#{filename}\"")
      end

      it 'returns a 404 with a not found message if document id does not exist' do
        get(:show, params: { document_id: '{0}' })
        err = JSON.parse(response.body)['errors'].first

        expect(err['status']).to eql('404')
        expect(err['title'].downcase).to include('not found')
      end

      it 'has a dated filename' do
        get(:show, params: { document_id: })

        expect(response.header['Content-Disposition']).to include("filename=\"#{filename}\"")
      end
    end

    context 'DDL Logging' do
      let(:monitor) { instance_double(Logging::Monitor) }

      before do
        allow(Flipper).to receive(:enabled?)
          .with(:cst_include_ddl_5103_letters, anything)
          .and_return(true)
        allow(Flipper).to receive(:enabled?)
          .with(:cst_include_ddl_boa_letters, anything)
          .and_return(true)
        allow(Flipper).to receive(:enabled?)
          .with(:cst_include_ddl_sqd_letters, anything)
          .and_return(true)
        allow(Logging::Monitor).to receive(:new).and_return(monitor)
        allow(monitor).to receive(:track_request)
      end

      it 'logs metadata of document types via monitor' do
        get(:index)
        expect(monitor)
          .to have_received(:track_request)
          .with(:info, 'DDL Document Types Metadata', 'claim_letters.doctypes_metadata',
                message_type: 'ddl.doctypes_metadata', document_type_metadata: contain_exactly(
                  { doc_type: '27',
                    type_description: 'Board decision' },
                  { doc_type: '864',
                    type_description: 'Copy of request for medical records sent to a non-VA provider' },
                  { doc_type: '859',
                    type_description: 'Request for specific evidence or information' },
                  { doc_type: '700',
                    type_description: 'Request for specific evidence or information' },
                  { doc_type: '408',
                    type_description: 'Notification: Exam with VHA has been scheduled' },
                  { doc_type: '34',
                    type_description: 'Request for specific evidence or information' },
                  { doc_type: '858',
                    type_description: 'List of evidence we may need ("5103 notice")' },
                  { doc_type: '1605',
                    type_description: 'Copy of request for non-medical records sent to a non-VA organization' },
                  { doc_type: '942',
                    type_description: 'Final notification: Request for specific evidence or information' },
                  { doc_type: '706',
                    type_description: 'List of evidence we may need ("5103 notice")' },
                  { doc_type: '184',
                    type_description: 'Claim decision (or other notification, like Intent to File)' },
                  { doc_type: '184',
                    type_description: 'Claim decision (or other notification, like Intent to File)' },
                  { doc_type: '184',
                    type_description: 'Claim decision (or other notification, like Intent to File)' },
                  { doc_type: '704',
                    type_description: 'List of evidence we may need ("5103 notice")' },
                  { doc_type: '184',
                    type_description: 'Claim decision (or other notification, like Intent to File)' },
                  { doc_type: '184',
                    type_description: 'Claim decision (or other notification, like Intent to File)' }
                ))
      end
    end

    context 'when VBMS returns a 500 internal server error' do
      before do
        allow_any_instance_of(ClaimStatusTool::ClaimLetterDownloader)
          .to receive(:get_letters)
          .and_raise(Common::Exceptions::ExternalServerInternalServerError)
        allow_any_instance_of(ClaimStatusTool::ClaimLetterDownloader)
          .to receive(:get_letter)
          .and_raise(Common::Exceptions::ExternalServerInternalServerError)
      end

      it 'returns a 502 bad gateway for index' do
        get(:index)

        expect(response).to have_http_status(:bad_gateway)
        error = JSON.parse(response.body)['errors'].first
        expect(error['title']).to eq('Bad Gateway')
        expect(error['detail']).to include('Upstream service')
        expect(error['status']).to eq('502')
      end

      it 'returns a 502 bad gateway for show' do
        get(:show, params: { document_id: })

        expect(response).to have_http_status(:bad_gateway)
        error = JSON.parse(response.body)['errors'].first
        expect(error['title']).to eq('Bad Gateway')
        expect(error['detail']).to include('VBMS')
        expect(error['status']).to eq('502')
      end
    end

    context 'stale or empty letters logging' do
      before do
        allow(Rails.logger).to receive(:info)
      end

      context 'when cst_claim_letters_log_stale_or_empty is disabled' do
        before do
          allow(Flipper).to receive(:enabled?)
            .with(:cst_claim_letters_log_stale_or_empty, anything)
            .and_return(false)
        end

        it 'does not log stale or empty letters' do
          get(:index)
          expect(Rails.logger).not_to have_received(:info)
            .with('Claim letters stale or empty for user',
                  hash_including(message_type: 'cst.claim_letters.stale_or_empty'))
        end
      end

      context 'when cst_claim_letters_log_stale_or_empty is enabled' do
        before do
          allow(Flipper).to receive(:enabled?)
            .with(:cst_claim_letters_log_stale_or_empty, anything)
            .and_return(true)
          allow_any_instance_of(ClaimStatusTool::ClaimLetterDownloader)
            .to receive(:get_letters)
            .and_return([
                          { doc_type: '184', received_at: '2022-09-22' },
                          { doc_type: '184', received_at: '2022-08-31' }
                        ])
        end

        it 'logs when all 184 letters are older than 1 day' do
          get(:index)
          expect(Rails.logger).to have_received(:info)
            .with('Claim letters stale or empty for user',
                  hash_including(message_type: 'cst.claim_letters.stale_or_empty',
                                 reason: 'all_stale'))
        end

        it 'does not include icn in the log payload' do
          allow_any_instance_of(ClaimStatusTool::ClaimLetterDownloader)
            .to receive(:get_letters).and_return([{ doc_type: '184', received_at: 2.days.ago.to_s }])

          get(:index)
          expect(Rails.logger).to have_received(:info)
            .with('Claim letters stale or empty for user',
                  hash_not_including(:icn))
        end

        it 'logs when there are no 184 letters' do
          allow_any_instance_of(ClaimStatusTool::ClaimLetterDownloader)
            .to receive(:get_letters).and_return([{ doc_type: '27', received_at: '2022-05-30' }])

          get(:index)
          expect(Rails.logger).to have_received(:info)
            .with('Claim letters stale or empty for user',
                  hash_including(message_type: 'cst.claim_letters.stale_or_empty',
                                 reason: 'no_letters',
                                 letter_count: 0))
        end

        it 'does not log when a 184 letter is newer than 1 day' do
          allow_any_instance_of(ClaimStatusTool::ClaimLetterDownloader)
            .to receive(:get_letters).and_return([{ doc_type: '184', received_at: 1.hour.ago.to_s }])

          get(:index)
          expect(Rails.logger).not_to have_received(:info)
            .with('Claim letters stale or empty for user', anything)
        end
      end
    end

    context 'letter count logging' do
      before do
        allow(Rails.logger).to receive(:info)
      end

      it 'logs the count of claim letters returned' do
        get(:index)
        expect(Rails.logger).to have_received(:info)
          .with('Claim letters count',
                hash_including(message_type: 'cst.claim_letters.count',
                               letter_count: be_a(Integer),
                               api_provider: be_a(String)))
      end

      it 'does not include PII in the log payload' do
        get(:index)
        expect(Rails.logger).to have_received(:info)
          .with('Claim letters count',
                hash_not_including(:icn, :user_uuid, :user_account_uuid))
      end
    end
  end

  # VBMS to Lighthouse migration. Retain these tests to ensure the LighthouseClaimLettersProvider
  # behaves as expected, including filtering, transformation, and sorting of claim letters,
  # as well as proper handling of allowed document types and file generation.
  context 'lighthouse claim letters provider' do
    before do
      allow(Flipper).to receive(:enabled?)
        .with(:cst_claim_letters_use_lighthouse_api_provider, anything)
        .and_return(true)

      # Mock the provider creation to use actual initialization logic
      allow(LighthouseClaimLettersProvider).to receive(:new) do |current_user|
        mock_lighthouse_provider(current_user)
      end
    end

    describe '#index' do
      it 'lists document id and letter details for claim letters' do
        get(:index)
        letters = JSON.parse(response.body)
        expected_important_keys = %w[document_id doc_type received_at]

        expect(letters.length).to be > 0
        # We can reference the keys of the first letters since
        # they _should_ all have the same keys.
        expect(letters.first.keys).to include(*expected_important_keys)
      end
    end

    describe '#index when "cst_include_ddl_boa_letters" is enabled
    and "cst_include_ddl_5103_letters" and "cst_include_ddl_sqd_letters" are disabled' do
      before do
        allow(Flipper).to receive(:enabled?)
          .with(:cst_include_ddl_boa_letters, anything)
          .and_return(true)
        allow(Flipper).to receive(:enabled?)
          .with(:cst_include_ddl_5103_letters, anything)
          .and_return(false)
        allow(Flipper).to receive(:enabled?)
          .with(:cst_include_ddl_sqd_letters, anything)
          .and_return(false)
      end

      it 'lists correct documents' do
        get(:index)
        letters = JSON.parse(response.body)
        allowed_letters = letters.select { |d| %w[27 184].include?(d['doc_type']) }

        expect(allowed_letters.length).to eql(letters.length)
      end
    end

    describe '#index when "cst_include_ddl_5103_letters" is enabled
    and "cst_include_ddl_boa_letters" and "cst_include_ddl_sqd_letters" are disabled' do
      before do
        allow(Flipper).to receive(:enabled?)
          .with(:cst_include_ddl_5103_letters, anything)
          .and_return(true)
        allow(Flipper).to receive(:enabled?)
          .with(:cst_include_ddl_boa_letters, anything)
          .and_return(false)
        allow(Flipper).to receive(:enabled?)
          .with(:cst_include_ddl_sqd_letters, anything)
          .and_return(false)
      end

      it 'lists correct documents' do
        get(:index)
        letters = JSON.parse(response.body)
        allowed_letters = letters.select { |d| %w[704 706 858 184].include?(d['doc_type']) }

        expect(allowed_letters.length).to eql(letters.length)
      end
    end

    describe '#index when "cst_include_ddl_sqd_letters" is enabled
    and "cst_include_ddl_boa_letters" and "cst_include_ddl_5103_letters" are disabled' do
      before do
        allow(Flipper).to receive(:enabled?)
          .with(:cst_include_ddl_5103_letters, anything)
          .and_return(false)
        allow(Flipper).to receive(:enabled?)
          .with(:cst_include_ddl_boa_letters, anything)
          .and_return(false)
        allow(Flipper).to receive(:enabled?)
          .with(:cst_include_ddl_sqd_letters, anything)
          .and_return(true)
      end

      it 'lists correct documents' do
        get(:index)
        letters = JSON.parse(response.body)
        allowed_letters = letters.select { |d| %w[184 34 408 700 859 864 942 1605].include?(d['doc_type']) }

        expect(allowed_letters.length).to eql(letters.length)
      end
    end

    describe '#index when "cst_include_ddl_5103_letters", "cst_include_ddl_boa_letters",
    and "cst_include_ddl_sqd_letters" feature flags are disabled' do
      before do
        allow(Flipper).to receive(:enabled?)
          .with(:cst_include_ddl_5103_letters, anything)
          .and_return(false)
        allow(Flipper).to receive(:enabled?)
          .with(:cst_include_ddl_boa_letters, anything)
          .and_return(false)
        allow(Flipper).to receive(:enabled?)
          .with(:cst_include_ddl_sqd_letters, anything)
          .and_return(false)
      end

      it 'lists correct documents' do
        get(:index)
        letters = JSON.parse(response.body)
        allowed_letters = letters.select { |d| d['doc_type'] == '184' }

        expect(allowed_letters.length).to eql(letters.length)
      end
    end

    describe '#index when "cst_include_ddl_5103_letters", "cst_include_ddl_boa_letters",
    and "cst_include_ddl_sqd_letters" feature flags are all enabled' do
      before do
        allow(Flipper).to receive(:enabled?)
          .with(:cst_include_ddl_5103_letters, anything)
          .and_return(true)
        allow(Flipper).to receive(:enabled?)
          .with(:cst_include_ddl_boa_letters, anything)
          .and_return(true)
        allow(Flipper).to receive(:enabled?)
          .with(:cst_include_ddl_sqd_letters, anything)
          .and_return(true)
      end

      it 'lists correct documents' do
        all_allowed_doctypes = %w[27 34 184 408 700 704 706 858 859 864 942 1605]
        get(:index)
        letters = JSON.parse(response.body)
        allowed_letters = letters.select { |d| all_allowed_doctypes.include?(d['doc_type']) }

        expect(allowed_letters.length).to eql(letters.length)
      end
    end

    describe '#show' do
      it 'responds with a pdf with a dated filename' do
        get(:show, params: { document_id: })

        expect(response.header['Content-Type']).to eq('application/pdf')
        expect(response.header['Content-Disposition']).to include("filename=\"#{filename}\"")
      end

      it 'returns a 404 with a not found message if document id does not exist' do
        get(:show, params: { document_id: '{0}' })
        err = JSON.parse(response.body)['errors'].first

        expect(err['status']).to eql('404')
        expect(err['title'].downcase).to include('not found')
      end

      it 'has a dated filename' do
        get(:show, params: { document_id: })

        expect(response.header['Content-Disposition']).to include("filename=\"#{filename}\"")
      end
    end

    context 'DDL Logging' do
      let(:monitor) { instance_double(Logging::Monitor) }

      before do
        allow(Flipper).to receive(:enabled?)
          .with(:cst_include_ddl_5103_letters, anything)
          .and_return(true)
        allow(Flipper).to receive(:enabled?)
          .with(:cst_include_ddl_boa_letters, anything)
          .and_return(true)
        allow(Flipper).to receive(:enabled?)
          .with(:cst_include_ddl_sqd_letters, anything)
          .and_return(true)
        allow(Logging::Monitor).to receive(:new).and_return(monitor)
        allow(monitor).to receive(:track_request)
      end

      it 'logs metadata of document types via monitor' do
        get(:index)
        expect(monitor)
          .to have_received(:track_request)
          .with(:info, 'DDL Document Types Metadata', 'claim_letters.doctypes_metadata',
                message_type: 'ddl.doctypes_metadata', document_type_metadata: contain_exactly(
                  { doc_type: '27',
                    type_description: 'Board decision' },
                  { doc_type: '864',
                    type_description: 'Copy of request for medical records sent to a non-VA provider' },
                  { doc_type: '859',
                    type_description: 'Request for specific evidence or information' },
                  { doc_type: '700',
                    type_description: 'Request for specific evidence or information' },
                  { doc_type: '408',
                    type_description: 'Notification: Exam with VHA has been scheduled' },
                  { doc_type: '34',
                    type_description: 'Request for specific evidence or information' },
                  { doc_type: '858',
                    type_description: 'List of evidence we may need ("5103 notice")' },
                  { doc_type: '1605',
                    type_description: 'Copy of request for non-medical records sent to a non-VA organization' },
                  { doc_type: '942',
                    type_description: 'Final notification: Request for specific evidence or information' },
                  { doc_type: '706',
                    type_description: 'List of evidence we may need ("5103 notice")' },
                  { doc_type: '184',
                    type_description: 'Claim decision (or other notification, like Intent to File)' },
                  { doc_type: '184',
                    type_description: 'Claim decision (or other notification, like Intent to File)' },
                  { doc_type: '184',
                    type_description: 'Claim decision (or other notification, like Intent to File)' },
                  { doc_type: '704',
                    type_description: 'List of evidence we may need ("5103 notice")' },
                  { doc_type: '184',
                    type_description: 'Claim decision (or other notification, like Intent to File)' },
                  { doc_type: '184',
                    type_description: 'Claim decision (or other notification, like Intent to File)' }
                ))
      end
    end

    context 'when Lighthouse returns a 500 internal server error' do
      before do
        mock_provider = instance_double(LighthouseClaimLettersProvider)
        allow(LighthouseClaimLettersProvider).to receive(:new).and_return(mock_provider)
        allow(mock_provider).to receive(:get_letters)
          .and_raise(Common::Exceptions::ExternalServerInternalServerError)
        allow(mock_provider).to receive(:get_letter)
          .and_raise(Common::Exceptions::ExternalServerInternalServerError)
      end

      it 'returns a 502 bad gateway for index instead of a 500' do
        get(:index)

        expect(response).to have_http_status(:bad_gateway)
        error = JSON.parse(response.body)['errors'].first
        expect(error['title']).to eq('Bad Gateway')
        expect(error['detail']).to include('Upstream service')
        expect(error['status']).to eq('502')
      end

      it 'returns a 502 bad gateway for show instead of a 500' do
        get(:show, params: { document_id: })

        expect(response).to have_http_status(:bad_gateway)
        error = JSON.parse(response.body)['errors'].first
        expect(error['title']).to eq('Bad Gateway')
        expect(error['detail']).to include('Upstream service')
        expect(error['status']).to eq('502')
      end
    end

    context 'when an unexpected application error occurs' do
      let(:monitor) { instance_double(Logging::Monitor) }

      before do
        mock_provider = instance_double(LighthouseClaimLettersProvider)
        allow(LighthouseClaimLettersProvider).to receive(:new).and_return(mock_provider)
        allow(mock_provider).to receive(:get_letters).and_raise(StandardError, 'boom')
        allow(mock_provider).to receive(:get_letter).and_raise(StandardError, 'boom')

        allow(Logging::Monitor).to receive(:new).and_return(monitor)
        allow(monitor).to receive(:track_request)
      end

      it 'logs as an application error for index' do
        get(:index)

        expect(response).to have_http_status(:internal_server_error)
        expect(monitor).to have_received(:track_request)
          .with(:error, 'boom', 'claim_letters.application_error.index', action: 'index')
        expect(monitor).not_to have_received(:track_request)
          .with(:error, anything, /vbms_lighthouse_claim_letters_provider_error/, anything)
      end

      it 'logs as an application error for show' do
        get(:show, params: { document_id: })

        expect(response).to have_http_status(:internal_server_error)
        expect(monitor).to have_received(:track_request)
          .with(:error, 'boom', 'claim_letters.application_error.show', action: 'show')
        expect(monitor).not_to have_received(:track_request)
          .with(:error, anything, /vbms_lighthouse_claim_letters_provider_error/, anything)
      end
    end

    context 'when a non-500 BaseError is raised' do
      before do
        mock_provider = instance_double(LighthouseClaimLettersProvider)
        allow(LighthouseClaimLettersProvider).to receive(:new).and_return(mock_provider)
        allow(mock_provider).to receive(:get_letters)
          .and_raise(Common::Exceptions::Forbidden.new)
      end

      it 'passes through with the original status for index' do
        get(:index)

        expect(response).to have_http_status(:forbidden)
      end
    end

    context 'when VAProfile VeteranStatus raises VAProfileError' do
      let(:monitor) { instance_double(Logging::Monitor) }

      before do
        mock_provider = instance_double(LighthouseClaimLettersProvider)
        allow(LighthouseClaimLettersProvider).to receive(:new).and_return(mock_provider)
        allow(mock_provider).to receive(:get_letters)
          .and_raise(VAProfile::VeteranStatus::VAProfileError.new(status: 400))
        allow(mock_provider).to receive(:get_letter)
          .and_raise(VAProfile::VeteranStatus::VAProfileError.new(status: 400))

        allow(Logging::Monitor).to receive(:new).and_return(monitor)
        allow(monitor).to receive(:track_request)
      end

      it 'returns a 502 bad gateway for index' do
        get(:index)

        expect(response).to have_http_status(:bad_gateway)
        error = JSON.parse(response.body)['errors'].first
        expect(error['title']).to eq('Bad Gateway')
        expect(error['status']).to eq('502')
      end

      it 'returns a 502 bad gateway for show' do
        get(:show, params: { document_id: })

        expect(response).to have_http_status(:bad_gateway)
        error = JSON.parse(response.body)['errors'].first
        expect(error['title']).to eq('Bad Gateway')
        expect(error['status']).to eq('502')
      end

      it 'logs the VAProfile error for index' do
        get(:index)

        expect(monitor).to have_received(:track_request)
          .with(:warn,
                'VAProfile VeteranStatus error during claim letters request',
                'claim_letters.va_profile_error.index',
                action: 'index',
                va_profile_status: 400)
      end

      it 'logs the VAProfile error for show' do
        get(:show, params: { document_id: })

        expect(monitor).to have_received(:track_request)
          .with(:warn,
                'VAProfile VeteranStatus error during claim letters request',
                'claim_letters.va_profile_error.show',
                action: 'show',
                va_profile_status: 400)
      end
    end
  end

  def mock_lighthouse_provider(current_user)
    mock_provider = instance_double(LighthouseClaimLettersProvider)

    allow_get_letters(mock_provider, current_user)
    allow_get_letter(mock_provider, current_user)

    mock_provider
  end

  # Setup get_letters to filter based on allowed doctypes for this user
  def allow_get_letters(mock_provider, current_user)
    allow(mock_provider).to receive(:get_letters) do
      # Get allowed doctypes for the current user based on feature flags
      allowed_doctypes = ClaimLetters::DoctypeService.allowed_for_user(current_user)

      # Filter and transform test data
      filtered_data = ClaimLetterTestData::TEST_DATA
                      .select { |doc| allowed_doctypes.include?(doc.doc_type) }
                      .select do |doc|
        # Apply BOA filtering
        if doc.doc_type == '27' && doc.received_at
          doc.received_at < 2.days.ago
        else
          true
        end
      end

      transformed_data = filtered_data.map do |doc|
        data = doc.marshal_dump
        data[:type_description] = ClaimLetters::Utils::LetterTransformer.decorate_description(data[:doc_type])
        data
      end

      transformed_data
        .sort_by { |doc| doc[:received_at] || Time.zone.local(1900, 1, 1) }
        .reverse
    end
  end

  # Setup get_letter to respect allowed doctypes
  def allow_get_letter(mock_provider, current_user)
    allow(mock_provider).to receive(:get_letter) do |doc_id, &block|
      doc = ClaimLetterTestData::TEST_DATA.find { |d| d.document_id == doc_id }
      allowed_doctypes = ClaimLetters::DoctypeService.allowed_for_user(current_user)

      raise Common::Exceptions::RecordNotFound, doc_id if doc.nil? || allowed_doctypes.exclude?(doc.doc_type)

      test_pdf_content = File.read(ClaimLetterTestData::TEST_FILE_PATH)
      filename = ClaimLetters::Utils::LetterTransformer.filename_with_date(doc.received_at)

      block.call(test_pdf_content, 'application/pdf', 'attachment', filename)
    end
  end
end
