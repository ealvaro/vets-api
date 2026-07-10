# frozen_string_literal: true

require 'rails_helper'
require 'lighthouse/letters_generator/service'
require 'lighthouse/letters_generator/service_error'

FAKE_RESPONSES_PATH = 'spec/lib/lighthouse/letters_generator/fakeResponses'

RSpec.describe Lighthouse::LettersGenerator::Service do
  before do
    @stubs = Faraday::Adapter::Test::Stubs.new
    conn = Faraday.new { |b| b.adapter(:test, @stubs) }
    allow_any_instance_of(Lighthouse::LettersGenerator::Configuration).to receive(:connection).and_return(conn)
  end

  context 'type validation' do
    it 'returns true if the type is present in the allow list' do
      service = Lighthouse::LettersGenerator::Service.new

      is_valid = service.valid_type?('BENEFIT_summary')
      expect(is_valid).to be(true)
    end

    it 'returns false if the type is not present in the allow list' do
      service = Lighthouse::LettersGenerator::Service.new

      is_valid = service.valid_type?('SUMMARY_of_BENEFITS')
      expect(is_valid).to be(false)
    end

    context 'when fmp_benefits_authorization_letter feature flag is enabled' do
      it 'returns true for foreign_medical_program letter type' do
        allow(Flipper).to receive(:enabled?).and_return(false)
        allow(Flipper).to receive(:enabled?).with(:fmp_benefits_authorization_letter).and_return(true)
        service = Lighthouse::LettersGenerator::Service.new

        is_valid = service.valid_type?('foreign_medical_program')
        expect(is_valid).to be(true)
      end

      it 'checks actor-aware flag for foreign_medical_program letter type' do
        user = build(:user)
        allow(Flipper).to receive(:enabled?).and_return(false)
        allow(Flipper).to receive(:enabled?).with(:fmp_benefits_authorization_letter, user).and_return(true)
        service = Lighthouse::LettersGenerator::Service.new

        is_valid = service.valid_type?('foreign_medical_program', user)
        expect(is_valid).to be(true)
      end
    end

    context 'when fmp_benefits_authorization_letter feature flag is disabled' do
      it 'returns false for foreign_medical_program letter type' do
        allow(Flipper).to receive(:enabled?).and_return(false)
        allow(Flipper).to receive(:enabled?).with(:fmp_benefits_authorization_letter).and_return(false)
        service = Lighthouse::LettersGenerator::Service.new

        is_valid = service.valid_type?('foreign_medical_program')
        expect(is_valid).to be(false)
      end

      it 'checks actor-aware flag for foreign_medical_program letter type' do
        user = build(:user)
        allow(Flipper).to receive(:enabled?).and_return(false)
        allow(Flipper).to receive(:enabled?).with(:fmp_benefits_authorization_letter, user).and_return(false)
        service = Lighthouse::LettersGenerator::Service.new

        is_valid = service.valid_type?('foreign_medical_program', user)
        expect(is_valid).to be(false)
      end
    end
  end

  context 'a request' do
    it 'always gets the lighthouse token via get_access_token' do
      expect_any_instance_of(Lighthouse::LettersGenerator::Configuration)
        .to receive(:get_access_token)
        .twice
        .and_return('faketoken')

      fake_response_json = File.read("#{FAKE_RESPONSES_PATH}/fakeResponse.json")
      fake_response_body = JSON.parse(fake_response_json)

      @stubs.get('/eligible-letters?icn=DOLLYPARTON') do
        [200, {}, fake_response_body]
      end

      client = Lighthouse::LettersGenerator::Service.new

      client.get_eligible_letter_types('DOLLYPARTON')
      client.get_eligible_letter_types('DOLLYPARTON')
    end

    it 'returns a 504 on timeout' do
      expect_any_instance_of(Lighthouse::LettersGenerator::Configuration)
        .to receive(:get_access_token)
        .and_return('faketoken')

      @stubs.get('/eligible-letters?icn=TIMEOUT_ICN') do
        raise Faraday::TimeoutError.new('waiting waiting', { status: 504 })
      end

      client = Lighthouse::LettersGenerator::Service.new

      expect { client.get_eligible_letter_types('TIMEOUT_ICN') }.to raise_error do |error|
        expect(error).to be_an_instance_of(Common::Exceptions::GatewayTimeout)
      end
    end
  end

  describe '#get_letter' do
    it 'returns a full json representation of a letter without letter options' do
      expect_any_instance_of(Lighthouse::LettersGenerator::Configuration)
        .to receive(:get_access_token)
        .once
        .and_return('faketoken')

      fake_response_json = File.read("#{FAKE_RESPONSES_PATH}/fakeProofOfServiceLetterResponse.json")
      fake_response_body = JSON.parse(fake_response_json)

      @stubs.get('/letter-contents/proof_of_service?icn=DOLLYPARTON') do
        [200, {}, fake_response_body]
      end

      client = Lighthouse::LettersGenerator::Service.new

      response = client.get_letter('DOLLYPARTON', 'proof_of_service')

      expect(response).to have_key('letterDescription')
      expect(response).to have_key('letterContent')
      expect(response['letterContent'].length).to eq(3)
      response['letterContent'].each do |content|
        expect(content.keys).to match_array(%w[contentKey contentTitle content])
      end
    end

    it 'returns a full json representation of a letter with options' do
      expect_any_instance_of(Lighthouse::LettersGenerator::Configuration)
        .to receive(:get_access_token)
        .once
        .and_return('faketoken')

      fake_response_json = File.read("#{FAKE_RESPONSES_PATH}/fakeProofOfServiceLetterResponse.json")
      fake_response_body = JSON.parse(fake_response_json)
      query_params = 'icn=DOLLYPARTON&serviceConnectedDisabilities=true'

      @stubs.get("/letter-contents/proof_of_service?#{query_params}") do
        [200, {}, fake_response_body]
      end

      client = Lighthouse::LettersGenerator::Service.new

      response = client.get_letter('DOLLYPARTON', 'proof_of_service', { serviceConnectedDisabilities: true })
      expect(response).to have_key('letterDescription')
      expect(response).to have_key('letterContent')
      expect(response['letterContent'].length).to eq(3)
      response['letterContent'].each do |content|
        expect(content.keys).to match_array(%w[contentKey contentTitle content])
      end
    end

    context 'Error handling' do
      it 'handles an error that returns a detailed response' do
        ## This test covers classes of client errors in lighthouse that
        ## have a detailed response, exemplified in fakeBadRequest.json.
        ## Status codes include: 400, 404, 406, 433, 500
        ## Link: https://developer.va.gov/explore/verification/docs/va_letter_generator

        expect_any_instance_of(Lighthouse::LettersGenerator::Configuration)
          .to receive(:get_access_token)
          .once
          .and_return('faketoken')

        fake_response_json = File.read("#{FAKE_RESPONSES_PATH}/fakeBadRequest.json")
        fake_response_body = JSON.parse(fake_response_json)
        @stubs.get('/letter-contents/proof_of_service?icn=BADREQUEST') do
          raise Faraday::BadRequestError.new('YIKES', { status: 400, body: fake_response_body })
        end

        client = Lighthouse::LettersGenerator::Service.new

        expect { client.get_letter('BADREQUEST', 'proof_of_service') }.to raise_error do |error|
          expect(error).to be_an_instance_of(Common::Exceptions::BadRequest)
        end
      end

      it 'handles an error that returns a simplified response' do
        ## This test covers classes of client errors in lighthouse that
        ## have a detailed response, exemplified in fakeBadRequest.json.
        ## Status codes include: 401, 403, 413, 429
        ## Link: https://developer.va.gov/explore/verification/docs/va_letter_generator

        expect_any_instance_of(Lighthouse::LettersGenerator::Configuration)
          .to receive(:get_access_token)
          .once
          .and_return('faketoken')

        fake_response_json = File.read("#{FAKE_RESPONSES_PATH}/fakeUnauthorized.json")
        fake_response_body = JSON.parse(fake_response_json)
        @stubs.get('/letter-contents/proof_of_service?icn=BadActor') do
          raise Faraday::UnauthorizedError.new("don't go in there", { status: 401, body: fake_response_body })
        end

        client = Lighthouse::LettersGenerator::Service.new

        expect { client.get_letter('BadActor', 'proof_of_service') }.to raise_error do |error|
          expect(error).to be_an_instance_of(Common::Exceptions::Unauthorized)
        end
      end
    end
  end

  describe '#get_eligible_letter_types' do
    it 'returns a list of eligible letter types' do
      allow(Flipper).to receive(:enabled?).and_call_original
      allow(Flipper).to receive(:enabled?).with(:letters_hide_dependent_benefits_summary_letter).and_return(false)

      expect_any_instance_of(Lighthouse::LettersGenerator::Configuration)
        .to receive(:get_access_token)
        .once
        .and_return('faketoken')

      fake_response_json = File.read("#{FAKE_RESPONSES_PATH}/fakeResponse.json")
      fake_response_body = JSON.parse(fake_response_json)

      @stubs.get('/eligible-letters?icn=DOLLYPARTON') do
        [200, {}, fake_response_body]
      end

      client = Lighthouse::LettersGenerator::Service.new

      response = client.get_eligible_letter_types('DOLLYPARTON')

      expect(response[:letters][0]).to have_key(:letterType)
      expect(response[:letters][0]).to have_key(:name)
      expect(response).to have_key(:letter_destination)
    end

    context 'with actor-aware FMP filtering' do
      let(:user) { build(:user) }
      let(:eligible_letters_response) do
        {
          'letters' => [
            { 'letterType' => 'PROOF_OF_SERVICE', 'letterName' => 'Proof of service letter' },
            { 'letterType' => 'FOREIGN_MEDICAL_PROGRAM', 'letterName' => 'Foreign medical program enrollment letter' }
          ],
          'letterDestination' => { 'name' => 'DOLLY PARTON' }
        }
      end

      it 'includes foreign_medical_program when fmp_benefits_authorization_letter is enabled for the user' do
        allow(Flipper).to receive(:enabled?).and_return(false)
        allow(Flipper).to receive(:enabled?).with(:fmp_benefits_authorization_letter, user).and_return(true)

        expect_any_instance_of(Lighthouse::LettersGenerator::Configuration)
          .to receive(:get_access_token)
          .once
          .and_return('faketoken')

        @stubs.get('/eligible-letters?icn=DOLLYPARTON') do
          [200, {}, eligible_letters_response]
        end

        client = Lighthouse::LettersGenerator::Service.new

        response = client.get_eligible_letter_types('DOLLYPARTON', user)
        letter_types = response[:letters].pluck(:letterType)

        expect(letter_types).to include('foreign_medical_program')
      end

      it 'excludes foreign_medical_program when fmp_benefits_authorization_letter is disabled for the user' do
        allow(Flipper).to receive(:enabled?).and_return(false)
        allow(Flipper).to receive(:enabled?).with(:fmp_benefits_authorization_letter, user).and_return(false)

        expect_any_instance_of(Lighthouse::LettersGenerator::Configuration)
          .to receive(:get_access_token)
          .once
          .and_return('faketoken')

        @stubs.get('/eligible-letters?icn=DOLLYPARTON') do
          [200, {}, eligible_letters_response]
        end

        client = Lighthouse::LettersGenerator::Service.new

        response = client.get_eligible_letter_types('DOLLYPARTON', user)
        letter_types = response[:letters].pluck(:letterType)

        expect(letter_types).not_to include('foreign_medical_program')
      end
    end

    describe 'cst_letters_content_updates flag' do
      let(:user) { build(:user) }
      let(:eligible_letters_response) do
        {
          'letters' => [
            { 'letterType' => 'SERVICE_VERIFICATION', 'letterName' => 'Service verification letter from LH' },
            { 'letterType' => 'BENEFIT_SUMMARY', 'letterName' => 'Benefits summary letter from LH' },
            { 'letterType' => 'PROOF_OF_SERVICE', 'letterName' => 'Proof of service letter from LH' }
          ],
          'letterDestination' => { 'name' => 'DOLLY PARTON' }
        }
      end

      before do
        @stubs.get('/eligible-letters?icn=DOLLYPARTON') do
          [200, {}, eligible_letters_response]
        end
      end

      context 'when cst_letters_content_updates is disabled' do
        before do
          allow(Flipper).to receive(:enabled?).and_call_original
          allow(Flipper).to receive(:enabled?).with(:cst_letters_content_updates, user).and_return(false)
        end

        it 'returns the existing lighthouse shape' do
          expect_any_instance_of(Lighthouse::LettersGenerator::Configuration)
            .to receive(:get_access_token)
            .once
            .and_return('faketoken')

          client = Lighthouse::LettersGenerator::Service.new
          response = client.get_eligible_letter_types('DOLLYPARTON', user)

          expect(response[:letters]).to eq(
            [
              { letterType: 'service_verification', name: 'Service verification letter from LH' },
              { letterType: 'benefit_summary', name: 'Benefits summary letter from LH' },
              { letterType: 'proof_of_service', name: 'Proof of service letter from LH' }
            ]
          )
        end
      end

      context 'when cst_letters_content_updates is enabled' do
        before do
          allow(Flipper).to receive(:enabled?).and_call_original
          allow(Flipper).to receive(:enabled?).with(:cst_letters_content_updates, user).and_return(true)
        end

        context 'when cst_letters_description_content_format is enabled' do
          before do
            allow(Flipper).to receive(:enabled?).with(:cst_letters_description_content_format).and_return(true)
          end

          it 'applies names, descriptions in content format, and ordering' do
            expect_any_instance_of(Lighthouse::LettersGenerator::Configuration)
              .to receive(:get_access_token)
              .once
              .and_return('faketoken')

            client = Lighthouse::LettersGenerator::Service.new
            response = client.get_eligible_letter_types('DOLLYPARTON', user)

            expect(response[:letters].map { |l| l[:letterType] }).to eq(
              %w[benefit_summary proof_of_service service_verification]
            )

            benefit_summary = response[:letters].first
            service_verification = response[:letters].last

            expect(benefit_summary[:name]).to eq('Benefits and service summary')
            expect(benefit_summary[:description]['content'].first['text']).to start_with(
              'This letter confirms your service history'
            )
            expect(
              benefit_summary[:description]['content'].find { |b| b['type'] == 'list' }['items']
            ).to include('Applying for housing assistance')
            expect(benefit_summary[:description]['subtitle']).to eq('Choose topics to include')

            expect(service_verification[:name]).to eq('Service verification')
            expect(service_verification[:description]).to be_present
            expect(service_verification[:description]['content']).to be_an(Array)
            expect(service_verification[:description]['content'].first['text']).to start_with(
              'This letter lists every period of service on record '
            )
          end
        end

        context 'when cst_letters_description_content_format is disabled' do
          before do
            allow(Flipper).to receive(:enabled?).with(:cst_letters_description_content_format).and_return(false)
          end

          it 'applies names, descriptions in legacy format, and ordering' do
            expect_any_instance_of(Lighthouse::LettersGenerator::Configuration)
              .to receive(:get_access_token)
              .once
              .and_return('faketoken')

            client = Lighthouse::LettersGenerator::Service.new
            response = client.get_eligible_letter_types('DOLLYPARTON', user)

            benefit_summary = response[:letters].first
            service_verification = response[:letters].last

            expect(benefit_summary[:name]).to eq('Benefits and service summary')
            expect(benefit_summary[:description]['paragraphs']).to be_an(Array)
            expect(benefit_summary[:description]['paragraphs'].first).to start_with(
              'This letter confirms your service history'
            )
            expect(benefit_summary[:description]['lists']).to be_an(Array)
            expect(benefit_summary[:description]['lists'].first['items']).to include('Applying for housing assistance')
            expect(benefit_summary[:description]['subtitle']).to eq('Choose topics to include')

            expect(service_verification[:name]).to eq('Service verification')
            expect(service_verification[:description]).to be_present
            expect(service_verification[:description]['paragraphs']).to be_an(Array)
            expect(service_verification[:description]['paragraphs'].first).to start_with(
              'This letter lists every period of service on record '
            )
          end
        end
      end

      context 'when cst_letters_content_updates is enabled but apply_content_updates is false' do
        before do
          allow(Flipper).to receive(:enabled?).and_call_original
          allow(Flipper).to receive(:enabled?).with(:cst_letters_content_updates, user).and_return(true)
        end

        it 'returns the legacy lighthouse content regardless of the flag' do
          expect_any_instance_of(Lighthouse::LettersGenerator::Configuration)
            .to receive(:get_access_token)
            .once
            .and_return('faketoken')

          client = Lighthouse::LettersGenerator::Service.new
          response = client.get_eligible_letter_types('DOLLYPARTON', user, apply_content_updates: false)

          expect(response[:letters]).to eq(
            [
              { letterType: 'service_verification', name: 'Service verification letter from LH' },
              { letterType: 'benefit_summary', name: 'Benefits summary letter from LH' },
              { letterType: 'proof_of_service', name: 'Proof of service letter from LH' }
            ]
          )
        end
      end

      context 'consolidation of medicare_partd to minimum_essential_coverage when both flags are enabled' do
        let(:user) { build(:user) }
        let(:consolidation_response) do
          {
            'letters' => [
              { 'letterType' => 'MEDICARE_PARTD', 'letterName' => 'Medicare Part D letter' },
              { 'letterType' => 'BENEFIT_SUMMARY', 'letterName' => 'Benefits and service summary' }
            ],
            'letterDestination' => { 'name' => 'DOLLY PARTON' }
          }
        end

        before do
          @test_stubs = Faraday::Adapter::Test::Stubs.new
          test_conn = Faraday.new { |b| b.adapter(:test, @test_stubs) }
          allow_any_instance_of(Lighthouse::LettersGenerator::Configuration)
            .to receive(:connection).and_return(test_conn)

          allow(Flipper).to receive(:enabled?).and_call_original
          allow(Flipper).to receive(:enabled?).with(:cst_letters_content_updates, user).and_return(true)
          allow(Flipper).to receive(:enabled?).with(:cst_letters_description_content_format).and_return(true)

          @test_stubs.get('/eligible-letters?icn=DOLLYPARTON') do
            [200, {}, consolidation_response]
          end
        end

        it 'relabels medicare_partd to minimum_essential_coverage' do
          expect_any_instance_of(Lighthouse::LettersGenerator::Configuration)
            .to receive(:get_access_token).once.and_return('faketoken')

          client = Lighthouse::LettersGenerator::Service.new
          response = client.get_eligible_letter_types('DOLLYPARTON', user)

          letter_types = response[:letters].map { |l| l[:letterType] }
          expect(letter_types).to include('minimum_essential_coverage')
          expect(letter_types).not_to include('medicare_partd')
        end

        it 'uses minimum_essential_coverage name and description in content format' do
          expect_any_instance_of(Lighthouse::LettersGenerator::Configuration)
            .to receive(:get_access_token).once.and_return('faketoken')

          client = Lighthouse::LettersGenerator::Service.new
          response = client.get_eligible_letter_types('DOLLYPARTON', user)

          mec_letter = response[:letters].find { |l| l[:letterType] == 'minimum_essential_coverage' }
          expect(mec_letter[:name]).to eq('Creditable coverage for health care and prescription drugs')
          expect(mec_letter[:description]).not_to be_nil
          expect(mec_letter[:description].keys).to include('content')
        end
      end

      context 'when both flags are enabled but use_content_format is false' do
        let(:user) { build(:user) }
        let(:consolidation_response) do
          {
            'letters' => [
              { 'letterType' => 'MEDICARE_PARTD', 'letterName' => 'Medicare Part D letter' },
              { 'letterType' => 'MINIMUM_ESSENTIAL_COVERAGE', 'letterName' => 'Minimum essential coverage letter' },
              { 'letterType' => 'BENEFIT_SUMMARY', 'letterName' => 'Benefits and service verification' }
            ],
            'letterDestination' => { 'name' => 'DOLLY PARTON' }
          }
        end

        before do
          @test_stubs = Faraday::Adapter::Test::Stubs.new
          test_conn = Faraday.new { |b| b.adapter(:test, @test_stubs) }
          allow_any_instance_of(Lighthouse::LettersGenerator::Configuration)
            .to receive(:connection).and_return(test_conn)

          allow(Flipper).to receive(:enabled?).and_call_original
          allow(Flipper).to receive(:enabled?).with(:cst_letters_content_updates, user).and_return(true)
          allow(Flipper).to receive(:enabled?).with(:cst_letters_description_content_format).and_return(true)
          allow(Flipper).to receive(:enabled?).with(:letters_hide_service_verification_letter).and_return(false)

          @test_stubs.get('/eligible-letters?icn=DOLLYPARTON') do
            [200, {}, consolidation_response]
          end
        end

        it 'gates description shape, consolidation, and consolidated name together' do
          expect_any_instance_of(Lighthouse::LettersGenerator::Configuration)
            .to receive(:get_access_token).once.and_return('faketoken')

          client = Lighthouse::LettersGenerator::Service.new
          response = client.get_eligible_letter_types('DOLLYPARTON', user, use_content_format: false)

          letter_types = response[:letters].map { |l| l[:letterType] }
          # Both health letters flow through as distinct entries — no relabel, no dedup.
          expect(letter_types).to include('medicare_partd', 'minimum_essential_coverage')

          partd_letter = response[:letters].find { |l| l[:letterType] == 'medicare_partd' }
          mec_letter = response[:letters].find { |l| l[:letterType] == 'minimum_essential_coverage' }

          # Names: upstream/override names, NOT the consolidated CONSOLIDATED_COVERAGE_NAME.
          expect(partd_letter[:name]).to eq('Creditable prescription drug coverage')
          expect(mec_letter[:name]).not_to eq('Creditable coverage for health care and prescription drugs')
          expect(mec_letter[:name]).to eq('Proof of minimum essential coverage')

          # Description shape: legacy paragraphs/lists, never the typed content array.
          expect(partd_letter[:description].keys).to include('paragraphs')
          expect(partd_letter[:description].keys).not_to include('content')
          expect(mec_letter[:description].keys).to include('paragraphs')
          expect(mec_letter[:description].keys).not_to include('content')
        end
      end

      context 'no consolidation when cst_letters_description_content_format is disabled' do
        let(:user) { build(:user) }
        let(:consolidation_response) do
          {
            'letters' => [
              { 'letterType' => 'MEDICARE_PARTD', 'letterName' => 'Medicare Part D letter' },
              { 'letterType' => 'BENEFIT_SUMMARY', 'letterName' => 'Benefits and service summary' }
            ],
            'letterDestination' => { 'name' => 'DOLLY PARTON' }
          }
        end

        before do
          @test_stubs = Faraday::Adapter::Test::Stubs.new
          test_conn = Faraday.new { |b| b.adapter(:test, @test_stubs) }
          allow_any_instance_of(Lighthouse::LettersGenerator::Configuration)
            .to receive(:connection).and_return(test_conn)

          allow(Flipper).to receive(:enabled?).and_call_original
          allow(Flipper).to receive(:enabled?).with(:cst_letters_content_updates, user).and_return(true)
          allow(Flipper).to receive(:enabled?).with(:cst_letters_description_content_format).and_return(false)

          @test_stubs.get('/eligible-letters?icn=DOLLYPARTON') do
            [200, {}, consolidation_response]
          end
        end

        it 'does not relabel medicare_partd and returns legacy description format' do
          expect_any_instance_of(Lighthouse::LettersGenerator::Configuration)
            .to receive(:get_access_token).once.and_return('faketoken')

          client = Lighthouse::LettersGenerator::Service.new
          response = client.get_eligible_letter_types('DOLLYPARTON', user)

          letter_types = response[:letters].map { |l| l[:letterType] }
          expect(letter_types).to include('medicare_partd')
          expect(letter_types).not_to include('minimum_essential_coverage')

          partd_letter = response[:letters].find { |l| l[:letterType] == 'medicare_partd' }
          expect(partd_letter[:description].keys).to include('paragraphs')
        end
      end

      context 'deduplication when both medicare_partd and minimum_essential_coverage are returned' do
        let(:user) { build(:user) }
        let(:both_letters_response) do
          {
            'letters' => [
              { 'letterType' => 'MEDICARE_PARTD', 'letterName' => 'Medicare Part D letter' },
              { 'letterType' => 'MINIMUM_ESSENTIAL_COVERAGE', 'letterName' => 'Minimum essential coverage letter' },
              { 'letterType' => 'BENEFIT_SUMMARY', 'letterName' => 'Benefits and service summary' }
            ],
            'letterDestination' => { 'name' => 'DOLLY PARTON' }
          }
        end

        before do
          @test_stubs = Faraday::Adapter::Test::Stubs.new
          test_conn = Faraday.new { |b| b.adapter(:test, @test_stubs) }
          allow_any_instance_of(Lighthouse::LettersGenerator::Configuration)
            .to receive(:connection).and_return(test_conn)

          allow(Flipper).to receive(:enabled?).and_call_original
          allow(Flipper).to receive(:enabled?).with(:cst_letters_content_updates, user).and_return(true)
          allow(Flipper).to receive(:enabled?).with(:cst_letters_description_content_format).and_return(true)

          @test_stubs.get('/eligible-letters?icn=DOLLYPARTON') do
            [200, {}, both_letters_response]
          end
        end

        it 'includes only one minimum_essential_coverage entry' do
          expect_any_instance_of(Lighthouse::LettersGenerator::Configuration)
            .to receive(:get_access_token)
            .once
            .and_return('faketoken')

          client = Lighthouse::LettersGenerator::Service.new
          response = client.get_eligible_letter_types('DOLLYPARTON', user)

          mec_count = response[:letters].count { |l| l[:letterType] == 'minimum_essential_coverage' }
          expect(mec_count).to eq(1)
        end
      end
    end

    context 'Error handling' do
      it 'handles an error that returns a detailed response' do
        ## This test covers classes of client errors in lighthouse that
        ## have a detailed response, exemplified in fakeBadRequest.json.
        ## Status codes include: 400, 404, 406, 433, 500
        ## Link: https://developer.va.gov/explore/verification/docs/va_letter_generator

        expect_any_instance_of(Lighthouse::LettersGenerator::Configuration)
          .to receive(:get_access_token)
          .once
          .and_return('faketoken')

        fake_response_json = File.read("#{FAKE_RESPONSES_PATH}/fakeBadRequest.json")
        fake_response_body = JSON.parse(fake_response_json)
        @stubs.get('/eligible-letters?icn=BADREQUEST') do
          raise Faraday::BadRequestError.new('YIKES', { status: 400, body: fake_response_body })
        end

        client = Lighthouse::LettersGenerator::Service.new

        expect { client.get_eligible_letter_types('BADREQUEST') }.to raise_error do |error|
          expect(error).to be_an_instance_of(Common::Exceptions::BadRequest)
        end
      end

      it 'handles an error that returns a simplified response' do
        ## This test covers classes of client errors in lighthouse that
        ## have a detailed response, exemplified in fakeBadRequest.json.
        ## Status codes include: 401, 403, 413, 429
        ## Link: https://developer.va.gov/explore/verification/docs/va_letter_generator

        expect_any_instance_of(Lighthouse::LettersGenerator::Configuration)
          .to receive(:get_access_token)
          .once
          .and_return('faketoken')

        fake_response_json = File.read("#{FAKE_RESPONSES_PATH}/fakeUnauthorized.json")
        fake_response_body = JSON.parse(fake_response_json)
        @stubs.get('/eligible-letters?icn=BadActor') do
          raise Faraday::UnauthorizedError.new("don't go in there", { status: 401, body: fake_response_body })
        end

        client = Lighthouse::LettersGenerator::Service.new

        expect { client.get_eligible_letter_types('BadActor') }.to raise_error do |error|
          expect(error).to be_an_instance_of(Common::Exceptions::Unauthorized)
        end
      end
    end
  end

  describe '#get_benefit_information' do
    it 'returns a list of benefit information' do
      expect_any_instance_of(Lighthouse::LettersGenerator::Configuration)
        .to receive(:get_access_token)
        .once
        .and_return('faketoken')

      fake_response_json = File.read("#{FAKE_RESPONSES_PATH}/fakeResponse.json")
      fake_response_body = JSON.parse(fake_response_json)

      @stubs.get('/eligible-letters?icn=DOLLYPARTON') do
        [200, {}, fake_response_body]
      end

      client = Lighthouse::LettersGenerator::Service.new

      response = client.get_benefit_information('DOLLYPARTON')

      expect(response).to have_key(:benefitInformation)
      expect(response[:benefitInformation]).not_to be_nil
    end

    it 'handles a missing monthlyAwardAmount' do
      expect_any_instance_of(Lighthouse::LettersGenerator::Configuration)
        .to receive(:get_access_token)
        .once
        .and_return('faketoken')

      fake_response_json = File.read("#{FAKE_RESPONSES_PATH}/fakeResponse_no_award.json")
      fake_response_body = JSON.parse(fake_response_json)

      @stubs.get('/eligible-letters?icn=DOLLYPARTON') do
        [200, {}, fake_response_body]
      end

      client = Lighthouse::LettersGenerator::Service.new

      response = client.get_benefit_information('DOLLYPARTON')

      expect(response).to have_key(:benefitInformation)
      expect(response[:benefitInformation]).not_to be_nil
      expect(response[:benefitInformation][:monthlyAwardAmount]).to be(0)
    end

    context 'Transformation' do
      it 'performs transformation on benefit info' do
        expect_any_instance_of(Lighthouse::LettersGenerator::Configuration)
          .to receive(:get_access_token)
          .once
          .and_return('faketoken')

        fake_response_json = File.read("#{FAKE_RESPONSES_PATH}/fakeResponse.json")
        fake_response_body = JSON.parse(fake_response_json)

        @stubs.get('/eligible-letters?icn=DOLLYPARTON') do
          [200, {}, fake_response_body]
        end

        client = Lighthouse::LettersGenerator::Service.new
        response = client.get_benefit_information('DOLLYPARTON')

        expect(response).to have_key(:benefitInformation)
        expect(response[:benefitInformation]).not_to be_nil
        # Ensures the tranform works
        expect(response[:benefitInformation]).to have_key(:awardEffectiveDate)
        # Ensures the non-transformable data is present
        expect(response[:benefitInformation]).to have_key(:serviceConnectedPercentage)
        # Ensure (has)chapter35EligibilityDateTime is not present
        expect(response[:benefitInformation]).not_to have_key(:chapter35EligibilityDateTime)
        # Ensure enteredDateTime has been transformed to enteredDate
        expect(response[:militaryService][0]).to have_key(:enteredDate)
        expect(response[:militaryService][0]).not_to have_key(:enteredDateTime)
        # Ensure releasedDateTime has been transformed to releasedDate
        expect(response[:militaryService][0]).to have_key(:releasedDate)
        expect(response[:militaryService][0]).not_to have_key(:releasedDateTime)
      end
    end
  end

  describe '#download_letter' do
    it 'returns a letter pdf without letter options' do
      expect_any_instance_of(Lighthouse::LettersGenerator::Configuration)
        .to receive(:get_access_token)
        .once
        .and_return('faketoken')

      fake_response_json = File.read("#{FAKE_RESPONSES_PATH}/fakeResponse.json")
      fake_response_body = JSON.parse(fake_response_json)

      @stubs.get('/letters/BENEFIT_SUMMARY/letter?icn=DOLLYPARTON') do
        [200, {}, fake_response_body]
      end

      client = Lighthouse::LettersGenerator::Service.new
      icns = { icn: 'DOLLYPARTON' }
      response = client.download_letter(icns, 'BENEFIT_SUMMARY')

      @stubs.verify_stubbed_calls
      expect(response).not_to be_nil
    end

    it 'returns a letter pdf with letter options' do
      expect_any_instance_of(Lighthouse::LettersGenerator::Configuration)
        .to receive(:get_access_token)
        .once
        .and_return('faketoken')

      fake_response_json = File.read("#{FAKE_RESPONSES_PATH}/fakeResponse.json")
      fake_response_body = JSON.parse(fake_response_json)
      download_path = '/letters/BENEFIT_SUMMARY/letter'
      query_params = 'icn=DOLLYPARTON?serviceConnectedDisabilities=true&chapter35Eligibility=true'

      @stubs.get("#{download_path}?#{query_params}") do
        [200, {}, fake_response_body]
      end

      letter_options = fake_response_body['benefitInformation']

      client = Lighthouse::LettersGenerator::Service.new
      icns = { icn: 'DOLLYPARTON' }
      response = client.download_letter(icns, 'BENEFIT_SUMMARY', letter_options)

      @stubs.verify_stubbed_calls
      expect(response).not_to be_nil
    end

    context 'error handling' do
      it 'handles an error returned from Lighthouse' do
        expect_any_instance_of(Lighthouse::LettersGenerator::Configuration)
          .to receive(:get_access_token)
          .and_return('faketoken')

        fake_response_json = File.read("#{FAKE_RESPONSES_PATH}/fakeBadRequest.json")
        fake_response_body = JSON.parse(fake_response_json)
        @stubs.get('/letters/BENEFIT_SUMMARY/letter?icn=BADREQUEST') do
          raise Faraday::BadRequestError.new('YIKES', { status: 400, body: fake_response_body })
        end

        client = Lighthouse::LettersGenerator::Service.new
        icns = { icn: 'BADREQUEST' }

        expect { client.download_letter(icns, 'BENEFIT_SUMMARY') }.to raise_error do |error|
          expect(error).to be_an_instance_of(Common::Exceptions::BadRequest)
        end
      end
    end
  end

  describe 'letters_hide_dependent_benefits_summary_letter flag' do
    let(:user) { build(:user) }
    let(:eligible_letters_response) do
      {
        'letters' => [
          { 'letterType' => 'BENEFIT_SUMMARY', 'letterName' => 'Benefit summary letter' },
          { 'letterType' => 'BENEFIT_SUMMARY_DEPENDENT', 'letterName' => 'Dependent Benefit Summary Letter' },
          { 'letterType' => 'PROOF_OF_SERVICE', 'letterName' => 'Proof of service letter' }
        ],
        'letterDestination' => { 'name' => 'DOLLY PARTON' }
      }
    end

    before do
      expect_any_instance_of(Lighthouse::LettersGenerator::Configuration)
        .to receive(:get_access_token)
        .once
        .and_return('faketoken')

      @stubs.get('/eligible-letters?icn=DOLLYPARTON') do
        [200, {}, eligible_letters_response]
      end
    end

    context 'when letters_hide_dependent_benefits_summary_letter is disabled' do
      before do
        allow(Flipper).to receive(:enabled?).and_call_original
        allow(Flipper).to receive(:enabled?).with(:letters_hide_dependent_benefits_summary_letter).and_return(false)
      end

      it 'includes dependent benefits summary letter' do
        client = Lighthouse::LettersGenerator::Service.new
        response = client.get_eligible_letter_types('DOLLYPARTON', user)

        letter_types = response[:letters].pluck(:letterType)
        expect(letter_types).to include('benefit_summary_dependent')
      end
    end

    context 'when letters_hide_dependent_benefits_summary_letter is enabled' do
      before do
        allow(Flipper).to receive(:enabled?).and_call_original
        allow(Flipper).to receive(:enabled?).with(:letters_hide_dependent_benefits_summary_letter).and_return(true)
      end

      it 'excludes dependent benefits summary letter' do
        client = Lighthouse::LettersGenerator::Service.new
        response = client.get_eligible_letter_types('DOLLYPARTON', user)

        letter_types = response[:letters].pluck(:letterType)
        expect(letter_types).not_to include('benefit_summary_dependent')
        expect(letter_types).to include('benefit_summary', 'proof_of_service')
      end
    end
  end

  describe 'letter ordering and sorting' do
    let(:user) { build(:user) }
    let(:eligible_letters_response) do
      {
        'letters' => [
          { 'letterType' => 'BENEFIT_SUMMARY_DEPENDENT', 'letterName' => 'Dependent Benefit Summary Letter' },
          { 'letterType' => 'PROOF_OF_SERVICE', 'letterName' => 'Proof of service card' },
          { 'letterType' => 'BENEFIT_SUMMARY', 'letterName' => 'Benefits and service summary' }
        ],
        'letterDestination' => { 'name' => 'TEST USER' }
      }
    end

    before do
      expect_any_instance_of(Lighthouse::LettersGenerator::Configuration)
        .to receive(:get_access_token)
        .once
        .and_return('faketoken')

      @stubs.get('/eligible-letters?icn=TESTUSER') do
        [200, {}, eligible_letters_response]
      end
    end

    context 'when cst_letters_content_updates is disabled' do
      before do
        allow(Flipper).to receive(:enabled?).and_call_original
        allow(Flipper).to receive(:enabled?).with(:cst_letters_content_updates, user).and_return(false)
        allow(Flipper).to receive(:enabled?).with(:letters_hide_dependent_benefits_summary_letter).and_return(false)
      end

      it 'returns letters in the original order from Lighthouse' do
        client = Lighthouse::LettersGenerator::Service.new
        response = client.get_eligible_letter_types('TESTUSER', user)

        letter_types = response[:letters].map { |l| l[:letterType] }
        expect(letter_types).to eq(%w[benefit_summary_dependent proof_of_service benefit_summary])
      end
    end

    context 'when cst_letters_content_updates is enabled' do
      before do
        allow(Flipper).to receive(:enabled?).and_call_original
        allow(Flipper).to receive(:enabled?).with(:cst_letters_content_updates, user).and_return(true)
        allow(Flipper).to receive(:enabled?).with(:letters_hide_dependent_benefits_summary_letter).and_return(false)
        allow(Flipper).to receive(:enabled?).with(:fmp_benefits_authorization_letter, user).and_return(true)
      end

      it 'sorts letters according to LETTER_ORDER with remaining letters appended' do
        client = Lighthouse::LettersGenerator::Service.new
        response = client.get_eligible_letter_types('TESTUSER', user)

        letter_types = response[:letters].map { |l| l[:letterType] }
        # benefit_summary should come first (defined in LETTER_ORDER)
        # proof_of_service should come second (defined in LETTER_ORDER)
        # benefit_summary_dependent should come last (not in LETTER_ORDER)
        expect(letter_types).to eq(%w[benefit_summary proof_of_service benefit_summary_dependent])
      end
    end
  end

  describe 'edge cases in letter transformation' do
    let(:user) { build(:user) }
    let(:eligible_letters_response) do
      {
        'letters' => [
          { 'letterType' => 'BENEFIT_SUMMARY', 'letterName' => nil }
        ],
        'letterDestination' => { 'name' => 'TEST USER' }
      }
    end

    before do
      expect_any_instance_of(Lighthouse::LettersGenerator::Configuration)
        .to receive(:get_access_token)
        .once
        .and_return('faketoken')

      @stubs.get('/eligible-letters?icn=TESTUSER') do
        [200, {}, eligible_letters_response]
      end
    end

    context 'when cst_letters_content_updates is disabled' do
      before do
        allow(Flipper).to receive(:enabled?).and_call_original
        allow(Flipper).to receive(:enabled?).with(:cst_letters_content_updates, user).and_return(false)
      end

      it 'handles letters with missing letterName gracefully' do
        client = Lighthouse::LettersGenerator::Service.new
        response = client.get_eligible_letter_types('TESTUSER', user)

        expect(response[:letters].first[:name]).to be_nil
      end
    end
  end
end
