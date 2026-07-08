# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Vass::IanaToWindowsTimeZone do
  describe '.windows_id_for!' do
    it 'returns Windows id for a mapped US Eastern IANA zone' do
      expect(described_class.windows_id_for!('America/New_York')).to eq('Eastern Standard Time')
    end

    it 'returns Windows id using canonical resolution for alias zones' do
      expect(described_class.windows_id_for!('America/Nassau')).to eq('Eastern Standard Time')
    end

    it 'raises InvalidVeteranTimeZoneError when blank' do
      expect do
        described_class.windows_id_for!('   ')
      end.to raise_error(Vass::Errors::InvalidVeteranTimeZoneError, 'Veteran time zone is required')
    end

    it 'raises InvalidVeteranTimeZoneError when IANA is unknown' do
      expect do
        described_class.windows_id_for!('Not/A_Real_Zone')
      end.to raise_error(Vass::Errors::InvalidVeteranTimeZoneError, 'Unknown veteran time zone')
    end

    it 'raises InvalidVeteranTimeZoneError when IANA is valid but unmapped' do
      expect do
        described_class.windows_id_for!('Pacific/Kiritimati')
      end.to raise_error(Vass::Errors::InvalidVeteranTimeZoneError, 'Unsupported veteran time zone')
    end

    it 'attaches the machine-readable reason to the raised error' do
      expect { described_class.windows_id_for!('   ') }
        .to raise_error(Vass::Errors::InvalidVeteranTimeZoneError) { |e| expect(e.reason).to eq('blank') }
    end

    it 'attaches the unknown_iana reason for an unrecognized zone' do
      expect { described_class.windows_id_for!('Not/A_Real_Zone') }
        .to raise_error(Vass::Errors::InvalidVeteranTimeZoneError) { |e| expect(e.reason).to eq('unknown_iana') }
    end

    it 'attaches the unmapped reason for a valid-but-unmapped zone' do
      expect { described_class.windows_id_for!('Pacific/Kiritimati') }
        .to raise_error(Vass::Errors::InvalidVeteranTimeZoneError) { |e| expect(e.reason).to eq('unmapped') }
    end

    it 'attaches the scrubbed offending zone to the raised error metadata' do
      expect { described_class.windows_id_for!('Not/A_Real_Zone') }
        .to raise_error(Vass::Errors::InvalidVeteranTimeZoneError) do |e|
          expect(e.log_metadata).to include(iana: 'Not/A_Real_Zone')
        end
    end
  end
end
