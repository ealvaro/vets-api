# frozen_string_literal: true

require 'rails_helper'

FIRST_NAMES = %w[Michael
                 James
                 John
                 David
                 Robert
                 Patricia
                 Emily].freeze

LAST_NAMES = %w[Smith
                Johnson
                Jones
                Lee
                Williams
                Brown
                Rodriguez].freeze

RSpec.describe RepresentationManagement::OriginalEntityQuery, type: :model do
  describe '#results' do
    it 'returns nothing for a blank query string' do
      expect(described_class.new('').results).to be_empty
    end
  end

  describe 'using more realistic names' do
    let!(:vso_individuals) do
      (0..6).map do |i|
        create(:representative, :with_address, :vso, first_name: FIRST_NAMES[i % 7],
                                                     last_name: LAST_NAMES[i],
                                                     representative_id: format('%05d', i + 1))
      end
    end
    let!(:claim_agents) do
      (7..13).map do |i|
        create(:representative, :with_address, :claim_agents, first_name: FIRST_NAMES[i % 7],
                                                              last_name: LAST_NAMES[(i + 1) % 7],
                                                              representative_id: format('%05d', i + 1))
      end
    end
    let!(:attorneys) do
      (14..20).map do |i|
        create(:representative, :with_address, first_name: FIRST_NAMES[i % 7],
                                               last_name: LAST_NAMES[(i + 2) % 7],
                                               representative_id: format('%05d', i + 1))
      end
    end
    let!(:organizations) do
      (0..6).map do |i|
        create(:organization, :with_address, name: "#{FIRST_NAMES[i % 7]} #{LAST_NAMES[(6 - i) % 7]} Firm",
                                             poa: format('%03d', i + 1))
      end +
        (7..13).map do |i|
          create(:organization, :with_address, name: "#{FIRST_NAMES[i % 7]} #{LAST_NAMES[(5 - i) % 7]} Firm",
                                               poa: format('%03d', i + 1))
        end
    end

    it 'returns nothing for a blank query string' do
      expect(described_class.new('').results).to be_empty
    end

    it 'returns individuals and organizations in the sorted order' do
      results = described_class.new('James').results

      expect(results.size).to eq(5)
      expect(results[0]).to be_a(Veteran::Service::Organization)
      expect(results[0].name).to eq('James Williams Firm')
      expect(results[1]).to be_a(Veteran::Service::Organization)
      expect(results[1].name).to eq('James Brown Firm')
      expect(results[2]).to be_a(Veteran::Service::Representative)
      expect(results[2].full_name).to eq('James Lee')
      expect(results[3]).to be_a(Veteran::Service::Representative)
      expect(results[3].full_name).to eq('James Jones')
    end

    it 'sorts individuals by trigram distance' do
      results = described_class.new('James Jo').results
      individual_results = results.select { |result| result.is_a?(Veteran::Service::Representative) }

      expect(individual_results.map(&:full_name)).to eq(['James Jones', 'James Johnson', 'James Lee'])
    end

    it 'sorts organizations by trigram distance' do
      results = described_class.new('Michael R').results
      organization_results = results.select { |result| result.is_a?(Veteran::Service::Organization) }

      expect(organization_results.map(&:name)).to eq(['Michael Rodriguez Firm', 'Michael Brown Firm'])
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

      expect(results.first).to be_a(Veteran::Service::Organization)
      expect(results.first.name).to eq('Michael Rodriguez Firm')
    end

    it 'returns at most 10 results' do
      20.times do |index|
        create(:representative, :with_address, full_name: 'Bob', representative_id: index.to_s)
      end

      results = described_class.new('Bob').results

      expect(results.size).to eq(10)
    end
  end
end
