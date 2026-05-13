# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SignIn::OpenidConfigurationController, type: :controller do
  describe 'GET show' do
    subject { get(:show) }

    let(:expected_status) { :ok }
    let(:expected_response) { SignIn::OpenidConfigurationPresenter.new.perform }

    it 'returns ok status' do
      expect(subject).to have_http_status(expected_status)
    end

    it 'renders the openid configuration' do
      expect(JSON.parse(subject.body)).to eq(expected_response.as_json)
    end
  end
end
