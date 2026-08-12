# frozen_string_literal: true

require 'rails_helper'
require_relative '../support/shared_examples_for_base_form'
require 'simple_forms_api/overflow_4502'

RSpec.describe SimpleFormsApi::VBA214502 do
  describe '#notification_first_name' do
    let(:data) do
      {
        'full_name' => {
          'first' => 'Taylor',
          'middle' => 'A',
          'last' => 'Veteran'
        }
      }
    end

    it 'returns the first name to be used in notifications' do
      expect(described_class.new(data).notification_first_name).to eq 'Taylor'
    end
  end

  describe '#notification_email_address' do
    let(:data) do
      { 'email' => 'a@b.com' }
    end

    it 'returns the email address to be used in notifications' do
      expect(described_class.new(data).notification_email_address).to eq 'a@b.com'
    end
  end

  describe '#driver?' do
    it 'returns bool if veteran is driver' do
      data = {
        'veteran_will_operate_vehicle' => true
      }
      model = SimpleFormsApi::VBA214502.new(data)
      expect(model.driver?).to be(true)
      model.data['veteran_will_operate_vehicle'] = false
      expect(model.driver?).to be(false)

      model.data['veteran_will_operate_vehicle'] = 'true'
      expect(model.driver?).to be(true)

      model.data['veteran_will_operate_vehicle'] = 'false'
      expect(model.driver?).to be(false)

      model.data['veteran_will_operate_vehicle'] = ''
      expect(model.driver?).to be(false)

      model.data['veteran_will_operate_vehicle'] = nil
      expect(model.driver?).to be(false)
    end
  end

  describe '#track_user_identity' do
    let(:data) do
      {
        'veteran_will_operate_vehicle' => true
      }
    end

    it 'Logs if veteran is driver' do
      allow(SemanticLogger::Logger).to receive(:new).and_return(Rails.logger)
      allow(Rails.logger).to receive(:info)
      identity = 'driver'
      confirmation_number = '123abc'
      model = SimpleFormsApi::VBA214502.new({ 'veteran_will_operate_vehicle' => true })
      model.track_user_identity('123abc')
      expect(Rails.logger).to have_received(:info).with(
        'Simple forms api - 21-4502 submission user identity',
        identity:,
        confirmation_number:
      )
    end

    it 'Logs if veteran is passenger' do
      allow(SemanticLogger::Logger).to receive(:new).and_return(Rails.logger)
      allow(Rails.logger).to receive(:info)
      identity = 'passenger'
      confirmation_number = '123abc'
      model = SimpleFormsApi::VBA214502.new({ 'veteran_will_operate_vehicle' => false })
      model.track_user_identity('123abc')
      expect(Rails.logger).to have_received(:info).with(
        'Simple forms api - 21-4502 submission user identity',
        identity:,
        confirmation_number:
      )
    end
  end

  describe '#pdf_email' do
    it 'returns email if its 30 characters or under' do
      model = SimpleFormsApi::VBA214502.new({ 'email' => 'example.email.1234@example.com' })
      expect(model.pdf_email).to eq('example.email.1234@example.com')
    end

    it "returns 'see additional page' if email over 30 characters" do
      model = SimpleFormsApi::VBA214502.new({ 'email' => 'example.email.12345@example.com' })
      expect(model.pdf_email).to eq('see additional page')
    end
  end

  describe '#email_overflow?' do
    it 'returns boolean based off of email cutoff length' do
      model = SimpleFormsApi::VBA214502.new({ 'email' => 'short' })
      expect(model.email_overflow?).to be(false)
      model.data = { 'email' => 'example.email.12345@example.com' }
      expect(model.email_overflow?).to be(true)
      model.data = {}
      expect(model.email_overflow?).to be(false)
    end
  end

  describe '#overflow_pdf' do
    def pdf_text(path)
      PDF::Reader.new(path).pages.map(&:text).join("\n")
    end
    before { @generated_paths = [] }

    after do
      @generated_paths.each { |p| FileUtils.rm_f(p) if p.present? && File.exist?(p) }
    end

    it 'If email is 30 characters or less and no "veteran_will_operate_vehicle" present. no overflow' do
      model = SimpleFormsApi::VBA214502.new({ 'email' => 'example.email.1234@example.com' })
      expect(model.overflow_pdf).to be_nil
    end

    it 'If email is > 30 characters, email appears on the overflow page.' do
      model = SimpleFormsApi::VBA214502.new({ 'email' => 'example.email.12345@example.com' })
      path = model.overflow_pdf
      @generated_paths << path
      content = pdf_text(path)
      expect(content).to include('example.email.12345@example.com')
      expect(content).not_to include('drive')
      expect(content).not_to include('passenger')
    end

    it 'when veteran_will_operate_vehicle true, overflow generates with message' do
      model = SimpleFormsApi::VBA214502.new({ 'veteran_will_operate_vehicle' => true })
      path = model.overflow_pdf
      @generated_paths << path
      content = pdf_text(path)
      expect(content).not_to  include('example.email.12345@example.com')
      expect(content).not_to  include('EMAIL')
      expect(content).to include('drive')
      expect(content).not_to include('passenger')
    end

    it 'when veteran_will_operate_vehicle is false, oveflow generate with message' do
      model = SimpleFormsApi::VBA214502.new({ 'veteran_will_operate_vehicle' => false })
      path = model.overflow_pdf
      @generated_paths << path
      content = pdf_text(path)
      expect(content).not_to include('example.email.12345@example.com')
      expect(content).not_to include('EMAIL')
      expect(content).not_to include('drive')
      expect(content).to include('passenger')
    end
  end
end
