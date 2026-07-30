# frozen_string_literal: true

require 'rails_helper'

RSpec.describe IvcChampva::DocsOnlyResubmissionService do
  subject(:service) { described_class.new(current_user:) }

  let(:current_user) { instance_double(User) }
  let(:controller) { IvcChampva::V1::UploadsController.new }
  let(:parsed_form_data) { { 'claim_id' => 'claim-uuid' } }

  before do
    allow(IvcChampva::V1::UploadsController).to receive(:new).and_return(controller)
    allow(controller).to receive(:ensure_docs_only_resubmission_enabled)
    allow(controller).to receive(:validate_docs_only_resubmission!)
    allow(controller).to receive(:hydrate_docs_only_resubmission_data)
    allow(IvcChampva::MetadataValidator).to receive(:validate_docs_only_resubmission)
    allow(controller).to receive(:process_docs_only_resubmission)
      .and_return({ json: {}, status: 200 })
    allow(Rails.logger).to receive(:error)
  end

  it 'runs docs-only processing and returns its response' do
    expect(service.call(parsed_form_data)).to eq({ json: {}, status: 200 })
    expect(controller.instance_variable_get(:@current_user)).to eq(current_user)
    expect(controller).to have_received(:ensure_docs_only_resubmission_enabled).with(parsed_form_data)
    expect(controller).to have_received(:validate_docs_only_resubmission!).with(parsed_form_data)
    expect(controller).to have_received(:hydrate_docs_only_resubmission_data).with(parsed_form_data)
    expect(IvcChampva::MetadataValidator).to have_received(:validate_docs_only_resubmission)
      .with(parsed_form_data)
    expect(controller).to have_received(:process_docs_only_resubmission).with(parsed_form_data)
  end

  it 'returns an unprocessable response for validation errors' do
    allow(controller).to receive(:validate_docs_only_resubmission!)
      .and_raise(ArgumentError, 'supporting documents are required')

    expect(service.call(parsed_form_data)).to eq(
      json: { error_message: 'supporting documents are required' },
      status: 422
    )
    expect(Rails.logger).to have_received(:error)
      .with('Validation error in CHAMPVA docs-only resubmission: supporting documents are required')
  end

  it 'returns an internal server error response for unexpected errors' do
    allow(controller).to receive(:process_docs_only_resubmission)
      .and_raise(StandardError, 'upload failed')

    expect(service.call(parsed_form_data)).to eq(
      json: { error_message: 'Error: upload failed' },
      status: 500
    )
    expect(Rails.logger).to have_received(:error).with('Docs-only resubmission error: upload failed')
  end
end
