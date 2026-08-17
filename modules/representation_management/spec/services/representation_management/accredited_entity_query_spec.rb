# frozen_string_literal: true

require 'rails_helper'

RSpec.describe RepresentationManagement::AccreditedEntityQuery, type: :model do
  let!(:individual1) do
    create(:accredited_individual, :with_location, :with_active_accreditation, first_name: 'Bob', last_name: 'Law')
  end
  let!(:individual2) do
    create(:accredited_individual, :with_location, :with_active_accreditation, first_name: 'Bob', last_name: 'Smith')
  end
  let!(:individual3) { create(:accredited_individual, :with_location, :attorney, first_name: 'aaaabc', last_name: '') }
  let!(:individual4) do
    create(:accredited_individual, :with_location, :claims_agent, first_name: 'aaaab', last_name: '')
  end
  let!(:individual5) do
    create(:accredited_individual, :with_location, :with_active_accreditation, first_name: 'aaaabcde', last_name: '')
  end
  let!(:individual6) do
    create(:accredited_individual, :with_location, :with_active_accreditation, first_name: 'aaaa', last_name: '')
  end
  let!(:individual7) do
    create(:accredited_individual, :with_location, :with_active_accreditation, first_name: 'aaaabcd', last_name: '')
  end

  let!(:organization1) { create(:accredited_organization, name: 'Bob Law Firm') }
  let!(:organization2) { create(:accredited_organization, name: 'Bob Smith Firm') }
  let!(:organization3) { create(:accredited_organization, name: 'aaaabcdefgh') }
  let!(:organization4) { create(:accredited_organization, name: 'aaaabcdefg') }
  let!(:organization5) { create(:accredited_organization, name: 'aaaabcdefghij') }
  let!(:organization6) { create(:accredited_organization, name: 'aaaabcdef') }
  let!(:organization7) { create(:accredited_organization, name: 'aaaabcdefghi') }

  describe '#results' do
    it 'returns nothing for a blank query string' do
      expect(described_class.new('').results).to be_empty
    end

    it 'returns individuals and organizations in the sorted order' do
      results = described_class.new('Bob').results

      expect(results.size).to eq(4)
      expect(results.first).to be_a(AccreditedIndividual)
      expect(results.first.full_name).to eq('Bob Law')
      expect(results.second).to be_a(AccreditedIndividual)
      expect(results.second.full_name).to eq('Bob Smith')
      expect(results.third).to be_a(AccreditedOrganization)
      expect(results.third.name).to eq('Bob Law Firm')
      expect(results.last).to be_a(AccreditedOrganization)
      expect(results.last.name).to eq('Bob Smith Firm')
    end

    it 'sorts individuals by levenshtein distance' do
      results = described_class.new('aaaa').results
      individual_results = results.select { |result| result.is_a?(AccreditedIndividual) }

      expect(individual_results.map(&:full_name)).to eq(%w[aaaa aaaab aaaabc aaaabcd aaaabcde])
    end

    it 'sorts organizations by levenshtein distance' do
      results = described_class.new('aaaa').results
      organization_results = results.select { |result| result.is_a?(AccreditedOrganization) }

      expect(organization_results.map(&:name)).to eq(%w[aaaabcdef aaaabcdefg aaaabcdefgh aaaabcdefghi aaaabcdefghij])
    end

    it 'sorts individuals and organizations together by levenshtein distance' do
      results = described_class.new('aaaa').results

      expect(results.size).to eq(10)
      expect(results.map(&:id)).to eq([individual6.id,
                                       individual4.id,
                                       individual3.id,
                                       individual7.id,
                                       individual5.id,
                                       organization6.id,
                                       organization4.id,
                                       organization3.id,
                                       organization7.id,
                                       organization5.id])
    end

    it 'can return organizations as the first result' do
      results = described_class.new('Bob Law Firm').results

      expect(results.first).to be_a(AccreditedOrganization)
      expect(results.first.name).to eq('Bob Law Firm')
    end

    it 'returns at most 10 results' do
      create_list(:accredited_individual, 20, :with_location, :with_active_accreditation, first_name: 'Bob',
                                                                                          last_name: '')

      results = described_class.new('Bob').results

      expect(results.size).to eq(10)
    end

    it "returns 9 results with a query of 'aaaab' and the standard threshold" do
      results = described_class.new('aaaab').results

      expect(results.size).to eq(9)
    end

    it "returns more than 9 results with a query of 'aaaab' and a threshold of 0.5" do
      stub_const('RepresentationManagement::AccreditedEntityQuery::WORD_SIMILARITY_THRESHOLD', 0.5)
      results = described_class.new('aaaab').results

      expect(results.size).to be > 9
    end

    it "returns less than 9 results with a query of 'aaaab' and a threshold of 0.9" do
      stub_const('RepresentationManagement::AccreditedEntityQuery::WORD_SIMILARITY_THRESHOLD', 0.9)
      results = described_class.new('aaaab').results

      expect(results.size).to be < 9
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
