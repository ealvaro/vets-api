# frozen_string_literal: true

require 'rails_helper'

RSpec.describe MHV::UserAccount::Errors::MHVClientError do
  describe '#as_json' do
    it 'returns structured error with body data' do
      err = described_class.new('some error', { 'message' => 'bad request', 'errorCode' => 'E001' })
      expect(err.as_json).to eq([{ title: 'some error', detail: 'bad request', code: 'E001' }])
    end

    it 'does not raise when body is nil' do
      err = described_class.new('some error', nil)
      expect { err.as_json }.not_to raise_error
      expect(err.as_json).to eq([{ title: 'some error', detail: nil, code: nil }])
    end

    it 'does not raise when body is a non-Hash string' do
      err = described_class.new('some error', '<html>503 Service Unavailable</html>')
      expect { err.as_json }.not_to raise_error
      expect(err.as_json).to eq([{ title: 'some error', detail: nil, code: nil }])
    end
  end
end
