# frozen_string_literal: true

require 'rails_helper'

RSpec.describe MedicalCopays::VBS::Service do
  subject { described_class.build(user:) }

  def stub_get_copays(response)
    allow_any_instance_of(MedicalCopays::VBS::Service).to receive(:get_copays).and_return(response)
  end

  let(:user) do
    build(:user, :loa3,
          vha_facility_ids: %w[757 358],
          vha_facility_hash: { '757' => %w[36546], '358' => %w[36546] })
  end
  let(:today_date) { Time.zone.today.strftime('%m%d%Y') }

  describe 'attributes' do
    it 'responds to request' do
      expect(subject.respond_to?(:request)).to be(true)
    end

    it 'responds to request_data' do
      expect(subject.respond_to?(:request_data)).to be(true)
    end
  end

  describe '.build' do
    it 'returns an instance of Service' do
      expect(subject).to be_an_instance_of(MedicalCopays::VBS::Service)
    end
  end

  describe '#get_copays' do
    before do
      allow(Flipper).to receive(:enabled?).with(:medical_copays_zero_debt).and_return(false)
      allow(Flipper).to receive(:enabled?).with(:medical_copays_six_mo_window).and_return(false)
    end

    context 'with a cached response' do
      it 'logs that a cached response was returned' do
        allow_any_instance_of(MedicalCopays::VBS::Service)
          .to receive(:get_user_cached_response)
          .and_return(Faraday::Response.new(status: 200, body: []))

        expect { subject.get_copays }
          .to trigger_statsd_increment('api.mcp.vbs.init_cached_copays.fired')
          .and trigger_statsd_increment('api.mcp.vbs.init_cached_copays.cached_response_returned')
      end
    end

    context 'with an empty copay response' do
      before do
        empty_response = Faraday::Response.new(status: 200, body: [])
        allow(subject.request).to receive(:post).with(
          "#{Settings.mcp.vbs_v2.base_path}/GetStatementsByEDIPIAndVistaAccountNumber",
          anything
        ).and_return(empty_response)
      end

      it 'logs that an empty response was cached' do
        expect { subject.get_copays }
          .to trigger_statsd_increment('api.mcp.vbs.init_cached_copays.fired')
          .and trigger_statsd_increment('api.mcp.vbs.init_cached_copays.empty_response_cached')
      end
    end

    it 'raises a custom error when request data is invalid' do
      allow_any_instance_of(MedicalCopays::VBS::RequestData).to receive(:valid?).and_return(false)

      expect { subject.get_copays }.to raise_error(MedicalCopays::VBS::InvalidVBSRequestError)
        .and trigger_statsd_increment('api.mcp.vbs.failure')
    end

    it 'returns a response hash' do
      url = '/vbsapi/GetStatementsByEDIPIAndVistaAccountNumber'
      data = { edipi: '123456789', vistaAccountNumbers: [36_546] }
      response = Faraday::Response.new(status: 200, body:
        [
          {
            'foo_bar' => 'bar',
            'pS_STATEMENT_DATE' => today_date
          }
        ])

      allow_any_instance_of(MedicalCopays::VBS::RequestData).to receive(:valid?).and_return(true)
      allow_any_instance_of(MedicalCopays::VBS::RequestData).to receive(:to_hash).and_return(data)
      allow_any_instance_of(MedicalCopays::Request).to receive(:post).with(url, data).and_return(response)

      VCR.use_cassette('user/get_facilities_empty', match_requests_on: %i[method uri]) do
        expect(subject.get_copays).to eq({ status: 200, data:
          [
            {
              'fooBar' => 'bar',
              'pSStatementDate' => today_date
            }
          ] })
      end
    end

    context 'with medical_copays_zero_debt flipper enabled' do
      before do
        allow(Flipper).to receive(:enabled?).with(:medical_copays_zero_debt).and_return(true)
      end

      it 'includes zero balance statements if available' do
        url = '/vbsapi/GetStatementsByEDIPIAndVistaAccountNumber'
        data = { edipi: '123456789', vistaAccountNumbers: [36_546] }
        response = Faraday::Response.new(
          status: 200, body: [
            {
              'foo_bar' => 'bar',
              'pS_STATEMENT_DATE' => today_date
            }
          ]
        )
        zero_balance_response = [
          {
            'bar_baz' => 'baz',
            'pS_STATEMENT_DATE' => today_date
          }
        ]

        allow_any_instance_of(MedicalCopays::VBS::RequestData).to receive(:valid?).and_return(true)
        allow_any_instance_of(MedicalCopays::VBS::RequestData).to receive(:to_hash).and_return(data)
        allow_any_instance_of(MedicalCopays::Request).to receive(:post).with(url, data).and_return(response)
        allow_any_instance_of(MedicalCopays::ZeroBalanceStatements).to receive(:list).and_return(zero_balance_response)
        allow_any_instance_of(MedicalCopays::VBS::Service).to receive(:get_user_cached_response).and_return(nil)

        VCR.use_cassette('user/get_facilities_empty', match_requests_on: %i[method uri]) do
          expect(subject.get_copays).to eq(
            {
              status: 200,
              data: [
                {
                  'fooBar' => 'bar',
                  'pSStatementDate' => today_date
                },
                {
                  'barBaz' => 'baz',
                  'pSStatementDate' => today_date
                }
              ]
            }
          )
        end
      end
    end

    context 'with debts_copay_logging flipper enabled' do
      before do
        allow(Flipper).to receive(:enabled?).with(:debts_copay_logging).and_return(true)
        allow(Flipper).to receive(:enabled?).with(:medical_copays_zero_debt).and_return(true)
        allow(Flipper).to receive(:enabled?).with(:medical_copays_six_mo_window).and_return(true)
      end

      it 'logs that a response was cached' do
        allow_any_instance_of(MedicalCopays::VBS::RequestData).to receive(:valid?).and_return(true)
        allow_any_instance_of(MedicalCopays::VBS::RequestData).to receive(:to_hash).and_return(
          { edipi: '123456789', vistaAccountNumbers: [36_546] }
        )
        allow_any_instance_of(MedicalCopays::Request).to receive(:post)
          .and_return(Faraday::Response.new(status: 200, body: []))

        allow(Rails.logger).to receive(:info)

        VCR.use_cassette('user/get_facilities_empty', match_requests_on: %i[method uri]) do
          subject.get_copays
        end

        expect(Rails.logger).to have_received(:info).with(
          a_string_including('MedicalCopays::VBS::Service#get_copays request data: ')
        )
      end

      it 'logs the response status and statement count without the body' do
        allow_any_instance_of(MedicalCopays::VBS::RequestData).to receive(:valid?).and_return(true)
        allow_any_instance_of(MedicalCopays::VBS::RequestData).to receive(:to_hash).and_return(
          { edipi: '123456789', vistaAccountNumbers: [36_546] }
        )
        allow_any_instance_of(MedicalCopays::Request).to receive(:post)
          .and_return(Faraday::Response.new(status: 200, body: []))

        allow(Rails.logger).to receive(:info)

        VCR.use_cassette('user/get_facilities_empty', match_requests_on: %i[method uri]) do
          subject.get_copays
        end

        expect(Rails.logger).to have_received(:info).with(
          a_string_including('MedicalCopays::VBS::Service#get_copays returned, status: 200, count: 0')
        )
      end
    end
  end

  describe '#get_cached_copay_response' do
    before do
      allow(Flipper).to receive(:enabled?).with(:debts_copay_logging).and_return(true)
    end

    context 'with a cached response' do
      before do
        allow_any_instance_of(MedicalCopays::VBS::Service).to receive(:get_user_cached_response)
          .and_return(Faraday::Response.new(status: 200, body: []))
      end

      it 'logs a cache hit' do
        allow(Rails.logger).to receive(:info)

        subject.get_cached_copay_response

        expect(Rails.logger).to have_received(:info).with(a_string_including('cache hit'))
      end

      context 'when debts_copay_logging is disabled' do
        before do
          allow(Flipper).to receive(:enabled?).with(:debts_copay_logging).and_return(false)
        end

        it 'does not log a cache hit' do
          allow(Rails.logger).to receive(:info)

          subject.get_cached_copay_response

          expect(Rails.logger).not_to have_received(:info).with(a_string_including('cache hit'))
        end
      end
    end

    context 'without a cached response' do
      before do
        allow_any_instance_of(MedicalCopays::VBS::Service).to receive(:get_user_cached_response).and_return(nil)
        allow(subject.request).to receive(:post).and_return(Faraday::Response.new(status: 200, body: []))
      end

      it 'logs a cache miss' do
        allow(Rails.logger).to receive(:info)

        subject.get_cached_copay_response

        expect(Rails.logger).to have_received(:info).with(a_string_including('cache miss'))
      end

      context 'when debts_copay_logging is disabled' do
        before do
          allow(Flipper).to receive(:enabled?).with(:debts_copay_logging).and_return(false)
        end

        it 'does not log a cache miss' do
          allow(Rails.logger).to receive(:info)

          subject.get_cached_copay_response

          expect(Rails.logger).not_to have_received(:info).with(a_string_including('cache miss'))
        end
      end
    end

    context 'when the backend request raises' do
      before do
        allow_any_instance_of(MedicalCopays::VBS::Service).to receive(:get_user_cached_response).and_return(nil)
        allow(subject.request).to receive(:post).and_raise(StandardError.new('backend down'))
      end

      it 'logs the error and raises ServiceError' do
        expect(Rails.logger).to receive(:error)
          .with(a_string_including('get_cached_copay_response error: StandardError'))

        expect { subject.get_cached_copay_response }
          .to raise_error(MedicalCopays::VBS::Service::ServiceError)
          .and trigger_statsd_increment('api.mcp.vbs.summary.failure')
      end
    end
  end

  describe '#get_copay_by_id' do
    it 'filters multiple statements to return a single one' do
      response = {
        status: 200,
        data: [
          {
            'id' => '2f1569ff-64cf-4300-8dd1-5ec3caded615',
            'pSStatementDate' => today_date
          },
          {
            'id' => 'b9cdcc61-2e5a-47c3-b314-4449606e65c7',
            'pSStatementDate' => today_date
          }
        ]
      }

      stub_get_copays(response)

      expect(subject.get_copay_by_id('b9cdcc61-2e5a-47c3-b314-4449606e65c7')).to eq({ status: 200, data:
      {
        'id' => 'b9cdcc61-2e5a-47c3-b314-4449606e65c7',
        'pSStatementDate' => today_date
      } })
    end

    it 'return error message when service error' do
      response = { data: { message: 'Bad request' }, status: 400 }
      stub_get_copays(response)

      expect(subject.get_copay_by_id('b9cdcc61-2e5a-47c3-b314-4449606e65c7')).to eq(response)
    end

    it 'raises an error if no statement with that id' do
      stub_get_copays({ status: 200, data: [] })

      expect { subject.get_copay_by_id('b9cdcc61-2e5a-47c3-b314-4449606e65c7') }.to raise_error(
        MedicalCopays::VBS::Service::StatementNotFound
      )
    end

    it 'logs when no statement matches the id' do
      stub_get_copays({ status: 200, data: [] })

      expect(Rails.logger).to receive(:error).with(a_string_including('statement not found'))

      expect { subject.get_copay_by_id('b9cdcc61-2e5a-47c3-b314-4449606e65c7') }.to raise_error(
        MedicalCopays::VBS::Service::StatementNotFound
      )
    end

    it 'logs when a statement is found, behind the debts_copay_logging flag' do
      allow(Flipper).to receive(:enabled?).with(:debts_copay_logging).and_return(true)
      stub_get_copays(
        { status: 200, data: [{ 'id' => 'b9cdcc61-2e5a-47c3-b314-4449606e65c7', 'pSStatementDate' => today_date }] }
      )

      allow(Rails.logger).to receive(:info)

      subject.get_copay_by_id('b9cdcc61-2e5a-47c3-b314-4449606e65c7')

      expect(Rails.logger).to have_received(:info).with(a_string_including('statement found'))
    end
  end

  describe '#get_pdf_statement_by_id' do
    statement_id = '123456789'
    let(:pdf_url) { "/vbsapi/GetPDFStatementById/#{statement_id}" }

    before do
      allow(Flipper).to receive(:enabled?).with(:debts_copay_logging).and_return(false)
    end

    def stub_pdf_response(raw_body)
      response = Faraday::Response.new(response_body: { 'statement' => Base64.encode64(raw_body) }, status: 200)
      allow_any_instance_of(MedicalCopays::Request).to receive(:get).with(pdf_url).and_return(response)
    end

    it 'raises an error when request data is invalid' do
      allow_any_instance_of(MedicalCopays::VBS::RequestData).to receive(:valid?).and_return(false)

      expect do
        subject.get_pdf_statement_by_id(statement_id)
      end.to raise_error(VCR::Errors::UnhandledHTTPRequestError)
    end

    it 'returns the decoded statement and increments the total counter' do
      stub_pdf_response('%PDF-1.4 fake')

      expect { expect(subject.get_pdf_statement_by_id(statement_id)).to eq('%PDF-1.4 fake') }
        .to trigger_statsd_increment(described_class::STATSD_PRE_RETRIEVAL)
    end

    context 'with a valid PDF body' do
      before { stub_pdf_response('%PDF-1.4 fake') }

      it 'increments the success counter' do
        expect { subject.get_pdf_statement_by_id(statement_id) }
          .to trigger_statsd_increment(described_class::STATSD_RETRIEVAL_SUCCESS)
      end
    end

    context 'with a non-PDF body on a 200 response' do
      before { stub_pdf_response('not a pdf') }

      it 'increments the invalid_body counter and logs an error' do
        expect(Rails.logger).to receive(:error).with(a_string_including('invalid PDF body on 200 response'))

        expect { subject.get_pdf_statement_by_id(statement_id) }
          .to trigger_statsd_increment(described_class::STATSD_RETRIEVAL_INVALID)
      end

      it 'still returns the decoded body' do
        expect(subject.get_pdf_statement_by_id(statement_id)).to eq('not a pdf')
      end
    end

    context 'when the request raises' do
      before do
        allow_any_instance_of(MedicalCopays::Request).to receive(:get).with(pdf_url)
                                                                      .and_raise(StandardError.new('boom'))
      end

      it 'logs the error, increments the failure counter, and re-raises' do
        expect(Rails.logger).to receive(:error)
          .with(a_string_including('get_pdf_statement_by_id error: StandardError'))

        expect { subject.get_pdf_statement_by_id(statement_id) }
          .to raise_error(StandardError, 'boom')
          .and trigger_statsd_increment(described_class::STATSD_RETRIEVAL_FAILURE)
      end
    end

    context 'when the backend error carries PII in its body' do
      let(:pii) { 'SSN 123-45-6789' }
      let(:backend_error) do
        Common::Exceptions::BackendServiceException.new(
          nil, { detail: pii, source: pii }, 502, { 'detail' => pii, 'source' => pii }
        )
      end

      before do
        allow_any_instance_of(MedicalCopays::Request).to receive(:get).with(pdf_url).and_raise(backend_error)
      end

      it 'logs only the safe fields and never the PII from the response body' do
        allow(Rails.logger).to receive(:error)

        expect { subject.get_pdf_statement_by_id(statement_id) }
          .to raise_error(Common::Exceptions::BackendServiceException)

        expect(Rails.logger).to have_received(:error).with(a_string_including('status: 502'))
        expect(Rails.logger).not_to have_received(:error).with(a_string_including(pii))
      end
    end

    context 'with debts_copay_logging enabled' do
      before do
        allow(Flipper).to receive(:enabled?).with(:debts_copay_logging).and_return(true)
        stub_pdf_response('%PDF-1.4 fake')
      end

      it 'logs the request and success lines' do
        allow(Rails.logger).to receive(:info)

        subject.get_pdf_statement_by_id(statement_id)

        expect(Rails.logger).to have_received(:info)
          .with(a_string_including("requested, statement_id: #{statement_id}"))
        expect(Rails.logger).to have_received(:info)
          .with(a_string_including("success, statement_id: #{statement_id}, bytes:"))
      end
    end
  end
end
