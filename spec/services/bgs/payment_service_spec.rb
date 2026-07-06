# frozen_string_literal: true

require 'rails_helper'

RSpec.describe BGS::PaymentService do
  let(:user) { create(:evss_user, :loa3) }
  let(:person) { BGS::People::Response.new(bgs_response) }
  let(:bgs_response) do
    {
      file_nbr: file_number,
      ssn_nbr: ssn_number,
      ptcpnt_id: participant_id
    }
  end
  let(:file_number) { '796043735' }
  let(:ssn_number) { '796043735' }
  let(:participant_id) { '600061742' }

  describe '#payment_history' do
    it 'returns a user\'s payment history given the user\'s participant id and file number' do
      VCR.use_cassette('bgs/payment_service/payment_history') do
        service = BGS::PaymentService.new(user)
        response = service.payment_history(person)
        expect(response).to include(:payments)
      end
    end

    it 'EXCLUDES payments sent to people other than the logged-in user' do
      VCR.use_cassette('bgs/payment_service/payment_history') do
        service = BGS::PaymentService.new(user)
        response = service.payment_history(person)
        beneficiary_ids = response[:payments][:payment].map { |pay| pay[:beneficiary_participant_id] }
        recipient_ids = response[:payments][:payment].map { |pay| pay[:recipient_participant_id] }
        expect(beneficiary_ids).to eq(recipient_ids)
        payee_types = response[:payments][:payment].map { |pay| pay[:payee_type] }
        expect(payee_types).not_to include('Third Party/Vendor')
      end
    end

    it 'prepends CH33 to the hardship payment type' do
      VCR.use_cassette('bgs/payment_service/payment_history') do
        service = BGS::PaymentService.new(user)
        response = service.payment_history(person)
        expect(response[:payments][:payment].last[:payment_type]).to eq('CH 33 Hardship (Manual) C&P')
      end
    end

    it 'returns a single payment response as an array' do
      payment = {
        payment_type: 'Compensation & Pension - Recurring',
        payee_type: 'Veteran',
        beneficiary_participant_id: participant_id,
        recipient_participant_id: participant_id
      }
      response = { payments: { payment: } }
      payment_information = double('payment information')
      service = BGS::PaymentService.new(user)

      allow(service).to receive(:service).and_return(double(payment_information:))
      expect(payment_information).to receive(:retrieve_payment_summary_with_bdn)
        .with(participant_id, file_number, '00', ssn_number)
        .and_return(response)

      expect(service.payment_history(person)[:payments][:payment]).to eq([payment])
    end

    it 'returns a multi-payment response as an array' do
      payments = [
        {
          payment_type: 'Compensation & Pension - Recurring',
          payee_type: 'Veteran',
          beneficiary_participant_id: participant_id,
          recipient_participant_id: participant_id
        },
        {
          payment_type: 'Post-9/11 GI Bill',
          payee_type: 'Veteran',
          beneficiary_participant_id: participant_id,
          recipient_participant_id: participant_id
        }
      ]
      response = { payments: { payment: payments } }
      payment_information = double('payment information')
      service = BGS::PaymentService.new(user)

      allow(service).to receive(:service).and_return(double(payment_information:))
      expect(payment_information).to receive(:retrieve_payment_summary_with_bdn)
        .with(participant_id, file_number, '00', ssn_number)
        .and_return(response)

      expect(service.payment_history(person)[:payments][:payment]).to eq(payments)
    end

    context 'if there are no results for the user' do
      let(:file_number) { '000000000' }
      let(:participant_id) { '000000000' }

      it 'returns an empty result' do
        VCR.use_cassette('bgs/payment_service/no_payment_history') do
          response = BGS::PaymentService.new(user).payment_history(person)
          expect(response).to include({ payments: { payment: [] } })
        end
      end
    end

    context 'error' do
      let(:file_number) { '000000000' }
      let(:participant_id) { '000000000' }

      it 'logs an error' do
        response = BGS::PaymentService.new(user)
        expect_any_instance_of(BGS::PaymentInformationService)
          .to receive(:retrieve_payment_summary_with_bdn).and_raise(StandardError)
        expect(Rails.logger).to receive(:error)
        response.payment_history(person)
      end
    end
  end
end
