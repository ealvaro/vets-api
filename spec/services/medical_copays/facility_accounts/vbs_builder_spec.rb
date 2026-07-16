# frozen_string_literal: true

require 'rails_helper'

RSpec.describe MedicalCopays::FacilityAccounts::VBSBuilder do
  subject(:builder) { described_class.new(vbs_service: instance_double(MedicalCopays::VBS::Service)) }

  describe '#get_station_id' do
    it 'reads the station id from the statement facility number' do
      statement = { 'pSFacilityNum' => '757' }

      expect(builder.send(:get_station_id, statement)).to eq('757')
    end

    it 'truncates a division-suffixed facility number to the parent station' do
      statement = { 'pSFacilityNum' => '640A0' }

      expect(builder.send(:get_station_id, statement)).to eq('640')
    end
  end
end
