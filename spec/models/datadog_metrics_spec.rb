# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DatadogMetrics do
  describe 'ALLOWLIST' do
    subject(:allowlist) { described_class::ALLOWLIST }

    it 'is frozen' do
      expect(allowlist).to be_frozen
    end

    it 'contains no duplicates' do
      expect(allowlist.uniq).to eq(allowlist)
    end

    it 'uses the mr. prefix for all entries' do
      expect(allowlist).to all(start_with('mr.'))
    end

    describe 'list calls' do
      %w[
        mr.labs_and_tests_list
        mr.imaging_results_list
        mr.care_summaries_and_notes_list
        mr.vaccines_list
        mr.allergies_list
        mr.health_conditions_list
        mr.vitals_list
      ].each do |metric|
        it "includes #{metric}" do
          expect(allowlist).to include(metric)
        end
      end
    end

    describe 'detail calls' do
      %w[
        mr.labs_and_tests_details
        mr.imaging_results_details
        mr.radiology_images_list
        mr.care_summaries_and_notes_details
        mr.vaccines_details
        mr.allergies_details
        mr.health_conditions_details
        mr.vitals_details
      ].each do |metric|
        it "includes #{metric}" do
          expect(allowlist).to include(metric)
        end
      end
    end

    describe 'download calls' do
      %w[
        mr.download_blue_button
        mr.download_ccd
        mr.download_sei
        mr.generate_blue_button
        mr.fetch_blue_button_data
      ].each do |metric|
        it "includes #{metric}" do
          expect(allowlist).to include(metric)
        end
      end
    end
  end
end
