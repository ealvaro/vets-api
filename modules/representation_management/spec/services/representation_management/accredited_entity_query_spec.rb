# frozen_string_literal: true

require 'rails_helper'

ACCREDITED_FIRST_NAMES = %w[Michael James John David Robert Patricia Emily].freeze

ACCREDITED_LAST_NAMES = %w[Smith Johnson Jones Lee Williams Brown Rodriguez].freeze

RSpec.describe RepresentationManagement::AccreditedEntityQuery, type: :model do
  describe '#results' do
    it 'returns nothing for a blank query string' do
      expect(described_class.new('').results).to be_empty
    end
  end

  describe 'using more realistic names' do
    let!(:base_individuals) do
      (0..6).map do |i|
        create(:accredited_individual,
               :with_location,
               :with_active_accreditation,
               first_name: ACCREDITED_FIRST_NAMES[i % 7],
               last_name: ACCREDITED_LAST_NAMES[i])
      end
    end

    let!(:claims_agents) do
      (7..13).map do |i|
        create(:accredited_individual,
               :with_location,
               :claims_agent,
               first_name: ACCREDITED_FIRST_NAMES[i % 7],
               last_name: ACCREDITED_LAST_NAMES[(i + 1) % 7])
      end
    end

    let!(:attorneys) do
      (14..20).map do |i|
        create(:accredited_individual,
               :with_location,
               :attorney,
               first_name: ACCREDITED_FIRST_NAMES[i % 7],
               last_name: ACCREDITED_LAST_NAMES[(i + 2) % 7])
      end
    end

    let!(:organizations) do
      (0..6).map do |i|
        create(:accredited_organization,
               :with_location,
               name: "#{ACCREDITED_FIRST_NAMES[i % 7]} #{ACCREDITED_LAST_NAMES[(6 - i) % 7]} Firm")
      end +
        (7..13).map do |i|
          create(:accredited_organization,
                 :with_location,
                 name: "#{ACCREDITED_FIRST_NAMES[i % 7]} #{ACCREDITED_LAST_NAMES[(5 - i) % 7]} Firm")
        end
    end

    describe 'with trigram flipper enabled (now always on)' do
      it 'returns nothing for a blank query string' do
        expect(described_class.new('').results).to be_empty
      end

      it 'returns individuals and organizations in the sorted order' do
        results = described_class.new('James').results

        expect(results.size).to eq(5)
        expect(results[0]).to be_a(AccreditedOrganization)
        expect(results[0].name).to eq('James Williams Firm')
        expect(results[1]).to be_a(AccreditedOrganization)
        expect(results[1].name).to eq('James Brown Firm')
        expect(results[2]).to be_a(AccreditedIndividual)
        expect(results[2].full_name).to eq('James Lee')
        expect(results[3]).to be_a(AccreditedIndividual)
        expect(results[3].full_name).to eq('James Jones')
      end

      it 'sorts individuals by trigram distance' do
        results = described_class.new('James Jo').results
        individual_results = results.select { |result| result.is_a?(AccreditedIndividual) }

        expect(individual_results.map(&:full_name)).to eq(['James Jones', 'James Johnson', 'James Lee'])
      end

      it 'sorts organizations by trigram distance' do
        results = described_class.new('Michael R').results
        organization_results = results.select { |result| result.is_a?(AccreditedOrganization) }

        expect(organization_results.map(&:name)).to eq(['Michael Rodriguez Firm', 'Michael Brown Firm'])
      end

      it 'excludes organizations without a location' do
        create(:accredited_organization, name: 'Null Location Firm')
        create(:accredited_organization, :with_location, name: 'With Location Firm')

        results = described_class.new('With Location Firm').results

        expect(results.map(&:name)).to eq(['With Location Firm'])
      end

      it 'sorts individuals and organizations together by trigram distance' do
        results = described_class.new('John').results

        expect(results.size).to eq(10)
        expect(results.map(&:name)).to eq(['John Lee Firm',
                                           'John Williams Firm',
                                           'John Williams',
                                           'John Lee',
                                           'John Jones',
                                           'Robert Johnson Firm',
                                           'Patricia Johnson Firm',
                                           'Emily Johnson',
                                           'Michael Johnson',
                                           'James Johnson'])
      end

      it 'sorts last initial realistically' do
        results = described_class.new('John W').results

        expect(results.size).to eq(5)
        expect(results.map(&:name)).to eq(['John Williams Firm', 'John Williams', 'John Lee Firm', 'John Lee',
                                           'John Jones'])
      end

      it 'can return organizations as the first result' do
        results = described_class.new('Michael Rodriguez').results

        expect(results.first).to be_a(AccreditedOrganization)
        expect(results.first.name).to eq('Michael Rodriguez Firm')
      end

      it 'returns at most 10 results' do
        create_list(:accredited_individual, 20, :with_location, :with_active_accreditation,
                    first_name: 'Bob', last_name: '')

        results = described_class.new('Bob').results

        expect(results.size).to eq(10)
      end
    end
  end

  describe 'parity with original entity query trigram behavior' do
    before do
      (0..6).each do |i|
        create(:representative, :with_address, :vso,
               first_name: ACCREDITED_FIRST_NAMES[i % 7],
               last_name: ACCREDITED_LAST_NAMES[i],
               representative_id: format('%05d', i + 1))
      end

      (7..13).each do |i|
        create(:representative, :with_address, :claim_agents,
               first_name: ACCREDITED_FIRST_NAMES[i % 7],
               last_name: ACCREDITED_LAST_NAMES[(i + 1) % 7],
               representative_id: format('%05d', i + 1))
      end

      (14..20).each do |i|
        create(:representative, :with_address,
               first_name: ACCREDITED_FIRST_NAMES[i % 7],
               last_name: ACCREDITED_LAST_NAMES[(i + 2) % 7],
               representative_id: format('%05d', i + 1))
      end

      (0..6).each do |i|
        create(:organization, :with_address,
               name: "#{ACCREDITED_FIRST_NAMES[i % 7]} #{ACCREDITED_LAST_NAMES[(6 - i) % 7]} Firm",
               poa: format('%03d', i + 1))
      end

      (7..13).each do |i|
        create(:organization, :with_address,
               name: "#{ACCREDITED_FIRST_NAMES[i % 7]} #{ACCREDITED_LAST_NAMES[(5 - i) % 7]} Firm",
               poa: format('%03d', i + 1))
      end

      (0..6).each do |i|
        create(:accredited_individual, :with_location,
               :with_active_accreditation,
               first_name: ACCREDITED_FIRST_NAMES[i % 7],
               last_name: ACCREDITED_LAST_NAMES[i])
      end

      (7..13).each do |i|
        create(:accredited_individual, :with_location, :claims_agent,
               first_name: ACCREDITED_FIRST_NAMES[i % 7],
               last_name: ACCREDITED_LAST_NAMES[(i + 1) % 7])
      end

      (14..20).each do |i|
        create(:accredited_individual, :with_location, :attorney,
               first_name: ACCREDITED_FIRST_NAMES[i % 7],
               last_name: ACCREDITED_LAST_NAMES[(i + 2) % 7])
      end

      (0..6).each do |i|
        create(:accredited_organization, :with_location,
               name: "#{ACCREDITED_FIRST_NAMES[i % 7]} #{ACCREDITED_LAST_NAMES[(6 - i) % 7]} Firm")
      end

      (7..13).each do |i|
        create(:accredited_organization, :with_location,
               name: "#{ACCREDITED_FIRST_NAMES[i % 7]} #{ACCREDITED_LAST_NAMES[(5 - i) % 7]} Firm")
      end
    end

    it 'returns the same sorted names for equivalent data' do
      query = 'John'

      original_names = RepresentationManagement::OriginalEntityQuery.new(query).results.map(&:name)
      accredited_names = described_class.new(query).results.map(&:name)

      expect(accredited_names).to eq(original_names)
    end

    context 'when a representative has no active accreditations' do
      let!(:inactive_rep) do
        create(:accredited_individual, :with_location, individual_type: 'representative',
                                                       first_name: 'Zed', last_name: 'Zephyr')
      end

      it 'excludes representatives with no accreditations at all' do
        results = described_class.new('Zed Zephyr').results

        expect(results.map(&:id)).not_to include(inactive_rep.id)
      end

      it 'excludes representatives whose only accreditation is deactivated' do
        create(:accreditation, accredited_individual: inactive_rep, deactivated_at: Time.current)

        results = described_class.new('Zed Zephyr').results

        expect(results.map(&:id)).not_to include(inactive_rep.id)
      end

      it 'includes a representative once an accreditation is active' do
        create(:accreditation, accredited_individual: inactive_rep)

        results = described_class.new('Zed Zephyr').results

        expect(results.map(&:id)).to include(inactive_rep.id)
      end

      it 'still includes attorneys and claims agents without accreditations' do
        attorney = create(:accredited_individual, :with_location, :attorney, first_name: 'Zed', last_name: 'Attorney')
        claims_agent = create(:accredited_individual, :with_location, :claims_agent, first_name: 'Zed',
                                                                                     last_name: 'Agent')

        results = described_class.new('Zed').results

        expect(results.map(&:id)).to include(attorney.id, claims_agent.id)
      end
    end

    context 'when the most recent ingestion log is the trexler file (legacy) dataset' do
      # Regression: the search must always read the Accredited* tables and never
      # fall back to the legacy Veteran::Service tables based on the ingestion
      # log's dataset. Falling back returned legacy IDs (representative_id/poa)
      # that the PDF resolver's AccreditedIndividual/Organization.find_by(id:)
      # could not match, causing "Representative/Organization not found".
      before do
        create(:accreditation_data_ingestion_log, :trexler_file, :completed)
      end

      let!(:individual1) do
        create(:accredited_individual, :with_location, :with_active_accreditation,
               first_name: 'Bob', last_name: 'Smith')
      end
      let!(:individual2) do
        create(:accredited_individual, :with_location, :with_active_accreditation,
               first_name: 'Bob', last_name: 'Jones')
      end
      let!(:organization1) { create(:accredited_organization, :with_location, name: 'Bob Smith Firm') }
      let!(:organization2) { create(:accredited_organization, :with_location, name: 'Bob Jones Firm') }

      it 'still returns Accredited* records, not legacy records' do
        results = described_class.new('Bob').results

        expect(results).to all(be_a(AccreditedIndividual).or(be_a(AccreditedOrganization)))
        expect(results.map(&:id)).to contain_exactly(
          individual1.id, individual2.id, organization1.id, organization2.id
        )
      end
    end
  end
end
