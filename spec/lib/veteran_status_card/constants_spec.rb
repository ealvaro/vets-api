# frozen_string_literal: true

require 'rails_helper'
require 'veteran_status_card/constants'

RSpec.describe VeteranStatusCard::Constants do
  describe 'DISCHARGE_STATUS_RESPONSE' do
    subject { described_class::DISCHARGE_STATUS_RESPONSE }

    let(:message) { subject[:message] }
    let(:first_text) { message.find { |m| m[:type] == 'text' } }
    let(:link) { message.find { |m| m[:type] == 'link' } }

    it 'has the correct title' do
      expect(subject[:title]).to eq("You're not eligible for a Veteran Status Card")
    end

    it 'has warning status' do
      expect(subject[:status]).to eq('warning')
    end

    it 'first text matches approved copy' do
      expect(first_text[:value]).to eq(
        "Your recorded discharge status doesn't meet the requirements for " \
        'this card. Only honorable and general discharges qualify.'
      )
    end

    it 'includes a link component for discharge upgrade' do
      expect(link).not_to be_nil
      expect(link[:value]).to eq('Learn how to apply for a discharge upgrade or correction')
      expect(link[:url]).to eq('https://www.va.gov/discharge-upgrade-instructions/')
    end

    it 'link appears after first text' do
      expect(message.index(link)).to eq(message.index(first_text) + 1)
    end

    it 'includes a phone component with tty' do
      phone = message.find { |m| m[:type] == 'phone' }
      expect(phone).not_to be_nil
      expect(phone[:tty]).to be true
    end
  end

  describe 'UNKNOWN_ELIGIBILITY_RESPONSE' do
    subject { described_class::UNKNOWN_ELIGIBILITY_RESPONSE }

    let(:message) { subject[:message] }

    it 'has the correct title' do
      expect(subject[:title]).to eq("We don't know if you're eligible for this card")
    end

    it 'has warning status' do
      expect(subject[:status]).to eq('warning')
    end

    it 'body explains the missing information' do
      text = message.find { |m| m[:type] == 'text' }
      expect(text[:value]).to eq('Your record is missing information about your service history or discharge status.')
    end

    it 'includes a phone component with tty' do
      phone = message.find { |m| m[:type] == 'phone' }
      expect(phone).not_to be_nil
      expect(phone[:tty]).to be true
    end
  end

  describe 'CURRENTLY_SERVING_RESPONSE' do
    subject { described_class::CURRENTLY_SERVING_RESPONSE }

    let(:message) { subject[:message] }

    it 'has the correct title' do
      expect(subject[:title]).to eq("You can't get a Veteran Status Card while you're on active duty")
    end

    it 'has warning status' do
      expect(subject[:status]).to eq('warning')
    end

    it 'body has the correct text' do
      text = message.find { |m| m[:type] == 'text' }
      expect(text[:value]).to eq(
        'If you think this is incorrect based on your service history, call us. ' \
        "We're here Monday through Friday, 8:00 a.m. to 8:00 p.m. ET."
      )
    end

    it 'includes a phone component with tty' do
      phone = message.find { |m| m[:type] == 'phone' }
      expect(phone).not_to be_nil
      expect(phone[:tty]).to be true
    end
  end

  describe 'SOMETHING_WENT_WRONG_RESPONSE' do
    subject { described_class::SOMETHING_WENT_WRONG_RESPONSE }

    let(:message) { subject[:message] }

    it 'has the correct title' do
      expect(subject[:title]).to eq('Something went wrong')
    end

    it 'has error status' do
      expect(subject[:status]).to eq('error')
    end

    it 'body has the correct text' do
      text = message.find { |m| m[:type] == 'text' }
      expect(text[:value]).to eq("We're sorry. Something went wrong on our end. Try again later.")
    end

    it 'does not include a phone component' do
      expect(message.none? { |m| m[:type] == 'phone' }).to be true
    end
  end

  describe 'PERSON_NOT_FOUND_RESPONSE' do
    subject { described_class::PERSON_NOT_FOUND_RESPONSE }

    let(:message) { subject[:message] }

    it 'has the correct title' do
      expect(subject[:title]).to eq("We don't know if you're eligible for this card")
    end

    it 'has warning status' do
      expect(subject[:status]).to eq('warning')
    end

    it 'body explains records are missing' do
      text = message.find { |m| m[:type] == 'text' }
      expect(text[:value]).to eq('Your records are missing from the system.')
    end

    it 'includes a phone component with tty' do
      phone = message.find { |m| m[:type] == 'phone' }
      expect(phone).not_to be_nil
      expect(phone[:tty]).to be true
    end
  end
end
