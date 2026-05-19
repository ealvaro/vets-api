# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CoeClaimFormValidation::VeteranContact do
  subject(:host) { veteran_contact_host.new }

  let(:veteran_contact_host) do
    Class.new do
      include ActiveModel::Model
      include ActiveModel::Validations
      include CoeClaimFormValidation::Helpers

      attr_accessor :parsed_form

      include CoeClaimFormValidation::VeteranContact
    end
  end

  let(:valid_veteran) do
    {
      'mailingAddress' => {
        'addressLine1' => '123 Main St',
        'city' => 'Springfield',
        'stateCode' => 'IL',
        'zipCode' => '62704'
      },
      'homePhone' => {
        'areaCode' => '800',
        'phoneNumber' => '5551212'
      },
      'email' => {
        'emailAddress' => 'vet@example.com'
      }
    }
  end

  describe '#validate_veteran_contact' do
    it 'returns early when veteran is not a hash' do
      host.parsed_form = { 'veteran' => 'nope' }
      host.send(:validate_veteran_contact)
      expect(host.errors).to be_empty
    end

    it 'validates a complete veteran contact block' do
      host.parsed_form = { 'veteran' => valid_veteran }
      host.send(:validate_veteran_contact)
      expect(host.errors).to be_empty
    end
  end

  describe '#validate_veteran_mailing_address' do
    it 'requires mailingAddress to be an object' do
      host.send(:validate_veteran_mailing_address, nil)
      expect(host.errors['/veteran/mailingAddress']).to include('is required')
    end

    it 'rejects mailingAddress when it is not an object' do
      host.send(:validate_veteran_mailing_address, 'nope')
      expect(host.errors['/veteran/mailingAddress']).to include('must be an object')
    end

    it 'validates optional address lines when present' do
      addr = valid_veteran['mailingAddress'].merge(
        'addressLine2' => 'Apt 2',
        'addressLine3' => 'Building B'
      )
      host.send(:validate_veteran_mailing_address, addr)
      expect(host.errors).to be_empty
    end

    it 'rejects addressLine3 when it is not a string' do
      addr = valid_veteran['mailingAddress'].merge('addressLine3' => 123)
      host.send(:validate_veteran_mailing_address, addr)
      expect(host.errors['/veteran/mailingAddress/addressLine3']).to include('must be a string')
    end

    it 'rejects addressLine3 when it exceeds the max length' do
      addr = valid_veteran['mailingAddress'].merge('addressLine3' => 'x' * 101)
      host.send(:validate_veteran_mailing_address, addr)
      expect(host.errors['/veteran/mailingAddress/addressLine3']).to include('must be 100 characters or less')
    end
  end

  describe '#validate_veteran_home_phone' do
    it 'requires homePhone to be an object' do
      host.send(:validate_veteran_home_phone, nil)
      expect(host.errors['/veteran/homePhone']).to include('is required')
    end

    it 'rejects homePhone when it is not an object' do
      host.send(:validate_veteran_home_phone, 'nope')
      expect(host.errors['/veteran/homePhone']).to include('must be an object')
    end
  end

  describe '#validate_veteran_email' do
    it 'requires email to be an object' do
      host.send(:validate_veteran_email, nil)
      expect(host.errors['/veteran/email']).to include('is required')
    end

    it 'rejects email when it is not an object' do
      host.send(:validate_veteran_email, 'nope')
      expect(host.errors['/veteran/email']).to include('must be an object')
    end

    it 'requires emailAddress when blank' do
      host.send(:validate_veteran_email, { 'emailAddress' => '' })
      expect(host.errors['/veteran/email/emailAddress']).to include('is required')
    end
  end
end
