# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SimpleFormsApi::Exceptions::ScrubbedUploadsSubmitError do
  describe '#message' do
    context 'with form 21-4138' do
      let(:ssn) { '321540987' }
      let(:dob) { '1980-01-15' }
      let(:postal_code) { '98117' }
      let(:phone) { '2065550101' }
      let(:email) { 'veteran@example.com' }

      let(:params) do
        {
          form_number: '21-4138',
          'id_number' => { 'ssn' => ssn },
          'date_of_birth' => dob,
          'veteran' => {
            'mailing_address' => { 'zip_code' => postal_code, 'country_code_iso3' => 'USA' },
            'mobile_phone' => { 'area_code' => '206', 'phone_number' => '5550101' },
            'email' => { 'email_address' => email }
          }
        }
      end

      def raise_and_rescue(original_message)
        raise described_class.new(params), original_message
      rescue described_class => e
        e
      end

      it 'removes SSN parts from the error message' do
        error = raise_and_rescue("failed: ssn=#{ssn} caused an error")
        expect(error.message).not_to include('321')
        expect(error.message).not_to include('540')
        expect(error.message).not_to include('0987')
      end

      it 'removes date of birth parts from the error message' do
        error = raise_and_rescue("failed: dob=#{dob}")
        expect(error.message).not_to include('1980')
        expect(error.message).not_to include(dob)
      end

      it 'removes postal code from the error message' do
        error = raise_and_rescue("zip #{postal_code} caused an issue")
        expect(error.message).not_to include(postal_code)
      end

      it 'removes email from the error message' do
        error = raise_and_rescue("email #{email} was invalid")
        expect(error.message).not_to include(email)
      end

      it 'preserves non-PII content in the error message' do
        error = raise_and_rescue('connection timeout after 30 seconds')
        expect(error.message).to include('connection timeout after')
      end

      it 'does not fall through to the fully-redacted else message' do
        error = raise_and_rescue("some error for #{params[:form_number]}")
        expect(error.message).not_to include('entire error message has been redacted')
      end
    end
  end
end
