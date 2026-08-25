# frozen_string_literal: true

require 'rails_helper'
require 'va_profile/demographics/service'

describe VAProfile::Demographics::Service,  feature: :personal_info,
                                            team_owner: :vfs_authenticated_experience_backend,
                                            type: :service do
  subject { described_class.new(user) }

  let(:user) { build(:user, :loa3, idme_uuid:, icn:) }
  let(:idme_uuid) { 'b2fab2b5-6af0-45e1-a9e2-394347af91ef' }
  let(:icn) { '123498767V234859' }

  describe '#identity_path' do
    it 'returns an ICN based identity path' do
      path = subject.identity_path
      expect(path).to eq('2.16.840.1.113883.4.349/123498767V234859%5ENI%5E200M%5EUSVHA')
    end
  end

  describe '#get_demographics' do
    context 'when successful' do
      it 'returns a status of 200' do
        VCR.use_cassette('va_profile/demographics/demographics', VCR::MATCH_EVERYTHING) do
          response = subject.get_demographics

          expect(response).to be_ok
          expect(response.demographics).to be_a(VAProfile::Models::Demographic)
        end
      end

      it 'returns a users preferred name' do
        VCR.use_cassette('va_profile/demographics/demographics', VCR::MATCH_EVERYTHING) do
          response = subject.get_demographics
          preferred_name = response.demographics.preferred_name

          expect(preferred_name.text).to eq('SAM')
        end
      end

      it 'returns a users gender-identity' do
        VCR.use_cassette('va_profile/demographics/demographics', VCR::MATCH_EVERYTHING) do
          response = subject.get_demographics
          gender_identity = response.demographics.gender_identity

          expect(gender_identity.code).to eq('F')
          expect(gender_identity.name).to eq('Female')
        end
      end
    end

    context 'when not successful' do
      context 'with a 400 error' do
        it 'returns nil demographic' do
          VCR.use_cassette('va_profile/demographics/demographics_error_400', VCR::MATCH_EVERYTHING) do
            response = subject.get_demographics

            expect(response).not_to be_ok
            expect(response.demographics.preferred_name).to be_nil
            expect(response.demographics.gender_identity).to be_nil
          end
        end
      end

      it 'logs exception' do
        VCR.use_cassette('va_profile/demographics/demographics_error_404', VCR::MATCH_EVERYTHING) do
          expect(Rails.logger).to receive(:error).with(
            instance_of(String),
            { icn_present: true, va_profile: :demographics_not_found }
          )

          response = subject.get_demographics
          expect(response).not_to be_ok
          expect(response.demographics.preferred_name).to be_nil
          expect(response.demographics.gender_identity).to be_nil
        end
      end
    end

    context 'when service returns a 503 error code' do
      it 'raises a BackendServiceException error' do
        VCR.use_cassette('va_profile/demographics/demographics_error_503', VCR::MATCH_EVERYTHING) do
          expect { subject.get_demographics }.to raise_error do |e|
            expect(e).to be_a(Common::Exceptions::BackendServiceException)
            expect(e.status_code).to eq(502)
            expect(e.errors.first.code).to eq('VET360_502')
          end
        end
      end
    end

    context 'when the user has no ICN' do
      before { allow(user).to receive(:icn).and_return(nil) }

      it 'returns an unauthorized response and logs the missing ICN' do
        allow(StatsD).to receive(:increment).and_call_original
        allow(Rails.logger).to receive(:warn).and_call_original

        response = subject.get_demographics

        expect(response).not_to be_ok
        expect(StatsD).to have_received(:increment)
          .with('va_profile.demographics.missing_icn', tags: ['service:demographics'])
        expect(Rails.logger).to have_received(:warn).with(
          hash_including(event: 'va_profile.demographics.missing_icn', service: 'demographics')
        )
      end
    end
  end
end
