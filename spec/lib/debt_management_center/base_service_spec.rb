# frozen_string_literal: true

require 'rails_helper'
require 'debt_management_center/debts_service'

RSpec.describe DebtManagementCenter::BaseService do
  # DebtsService is used as the concrete subclass because BaseService is abstract;
  # every DMC service inherits the same #handle_client_error.
  subject(:service) { DebtManagementCenter::DebtsService.new(nil) }

  before { allow(Rails.logger).to receive(:error) }

  def raised_exception(status)
    error = Common::Client::Errors::ClientError.new(
      "the server responded with status #{status}", status, 'upstream body'
    )
    service.send(:handle_client_error, error)
  rescue Common::Exceptions::BackendServiceException => e
    e
  end

  describe '#handle_client_error' do
    # Every status observed reaching DMC in production, plus the connection-level
    # failure that carries no status at all. Before these mappings existed each of
    # these fell through to VA900 and rendered 400, attributing an upstream outage
    # to the client.
    {
      400 => { code: 'DMC400', status: 400 },
      404 => { code: 'DMC404', status: 502 },
      500 => { code: 'DMC500', status: 502 },
      502 => { code: 'DMC502', status: 502 },
      503 => { code: 'DMC503', status: 503 },
      504 => { code: 'DMC504', status: 504 },
      nil => { code: 'DMC',    status: 503 }
    }.each do |upstream_status, expected|
      context "when the upstream responds with #{upstream_status || 'no status'}" do
        it "renders #{expected[:code]} as HTTP #{expected[:status]}" do
          exception = raised_exception(upstream_status)

          expect(exception).to be_a(Common::Exceptions::BackendServiceException)
          expect(exception.errors.first.code).to eq(expected[:code])
          expect(exception.status_code).to eq(expected[:status])
          expect(exception).not_to be_va900
        end
      end
    end
  end
end
