# frozen_string_literal: true

require 'rails_helper'

# rubocop:disable RSpec/DescribeClass
RSpec.describe 'HTTPI initializer' do
  describe 'HTTPI.log' do
    it 'is explicitly false, not nil' do
      # HTTPI.log? returns true when @log is nil (@log != false).
      # The initializer must set false, not just leave it unset.
      expect(HTTPI.instance_variable_get(:@log)).to be false
    end

    it 'does not log requests' do
      expect(HTTPI.log?).to be false
    end
  end

  describe 'BGS.configuration.log' do
    it 'is explicitly false, not nil' do
      # When nil is passed to Savon.client(log: nil), it overrides Savon's
      # log: false default and sets HTTPI.log = nil, re-enabling logging globally.
      # BGS.configuration.log must be false (not nil) to prevent that.
      expect(BGS.configuration.log).to be false
    end

    it 'does not re-enable HTTPI logging when a BGS Savon client is created' do
      original = HTTPI.instance_variable_get(:@log)

      begin
        HTTPI.log = nil # simulate pre-fix state
        wsdl = Rails.root.join('config', 'health_care_application', 'wsdl', 'voa.wsdl').to_s
        Savon.client(log: BGS.configuration.log, wsdl:)
        expect(HTTPI.log?).to be false
      ensure
        HTTPI.instance_variable_set(:@log, original)
      end
    end
  end
end
# rubocop:enable RSpec/DescribeClass
