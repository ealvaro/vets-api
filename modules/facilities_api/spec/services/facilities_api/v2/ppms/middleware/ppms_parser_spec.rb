# frozen_string_literal: true

require 'rails_helper'
require 'common/client/middleware/response/raise_custom_error'

RSpec.describe FacilitiesApi::V2::PPMS::Middleware::PPMSParser do
  # Mirror the response middleware stack from
  # FacilitiesApi::V2::PPMS::Configuration so we exercise how a blank PPMS error
  # code is turned into an i18n key (RaiseCustomError builds "PPMS#{code}").
  def raise_for(status, body)
    stubs = Faraday::Adapter::Test::Stubs.new
    conn = Faraday.new do |c|
      c.response :raise_custom_error, error_prefix: 'PPMS'
      c.use described_class
      c.adapter :test, stubs
    end
    stubs.get('/x') { [status, { 'Content-Type' => 'application/json' }, body] }
    conn.get('/x')
  rescue => e
    e
  end

  # PPMS returns errors as {"error":{"code":"","message":"..."}} -- a blank code.
  def blank_code_body(message = 'An error has occurred.')
    { error: { code: '', message: } }.to_json
  end

  describe 'error code selection for a blank upstream code' do
    it 'preserves a 404 so it renders as Not Found rather than a 502' do
      error = raise_for(404, blank_code_body('Not found'))

      expect(error).to be_a(Common::Exceptions::BackendServiceException)
      expect(error.original_status).to eq(404)
      expect(error.errors.first.code).to eq('PPMS_404')
      expect(error.errors.first.status).to eq('404')
    end

    it 'preserves a 429 so it renders as Too Many Requests rather than a 502' do
      error = raise_for(429, blank_code_body('Rate limit exceeded'))

      expect(error).to be_a(Common::Exceptions::BackendServiceException)
      expect(error.original_status).to eq(429)
      expect(error.errors.first.code).to eq('PPMS_429')
      expect(error.errors.first.status).to eq('429')
    end

    it 'falls back to PPMS_502 for other server errors (e.g. 500)' do
      error = raise_for(500, blank_code_body)

      expect(error).to be_a(Common::Exceptions::BackendServiceException)
      expect(error.errors.first.code).to eq('PPMS_502')
      expect(error.errors.first.status).to eq('502')
    end

    it 'falls back to PPMS_502 for other client errors (e.g. 400)' do
      error = raise_for(400, blank_code_body('Bad request'))

      expect(error).to be_a(Common::Exceptions::BackendServiceException)
      expect(error.errors.first.code).to eq('PPMS_502')
      expect(error.errors.first.status).to eq('502')
    end
  end
end
