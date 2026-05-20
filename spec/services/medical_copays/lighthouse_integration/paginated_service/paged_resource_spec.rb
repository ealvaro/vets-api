# frozen_string_literal: true

require 'rails_helper'
require 'lighthouse/healthcare_cost_and_coverage/charge_item/service'

RSpec.describe MedicalCopays::LighthouseIntegration::PaginatedService::PagedResource do
  describe '::PagedResource' do
    let(:list_service_class) do
      Class.new do
        def list(*); end
      end
    end
    let(:list_service) { instance_double(list_service_class) }
    let(:paged_resource) do
      Class.new do
        include MedicalCopays::LighthouseIntegration::PaginatedService::PagedResource
      end.new
    end

    describe '#fetch_paged_resources' do
      it 'returns empty entries when the first page has no bundle entries' do
        allow(list_service).to receive(:list).with(count: 10, page: 1, foo: :bar).and_return('entry' => [])

        result = paged_resource.fetch_paged_resources(
          service: list_service,
          max_pages: 5,
          count: 10,
          page_params: { foo: :bar }
        )

        expect(result['entries']).to eq([])
      end

      it 'aggregates entries across bundle responses while next links exist' do
        allow(list_service).to receive(:list).with(count: 10, page: 1).and_return(
          'entry' => [{ 'resource' => { 'id' => 'a' } }],
          'link' => [{ 'relation' => 'next', 'url' => 'https://example/next' }]
        )
        allow(list_service).to receive(:list).with(count: 10, page: 2).and_return(
          'entry' => [{ 'resource' => { 'id' => 'b' } }],
          'link' => []
        )

        result = paged_resource.fetch_paged_resources(service: list_service, max_pages: 5, count: 10)

        expect(result['entries'].map { |e| e.dig('resource', 'id') }).to eq(%w[a b])
        expect(list_service).to have_received(:list).twice
      end

      it 'stops after max_pages even when every bundle still has a next link' do
        perpetual_next = {
          'entry' => [{ 'resource' => { 'id' => 'per-page' } }],
          'link' => [{ 'relation' => 'next', 'url' => 'https://example/next' }]
        }
        allow(list_service).to receive(:list).and_return(perpetual_next)

        result = paged_resource.fetch_paged_resources(service: list_service, max_pages: 3, count: 10)

        expect(list_service).to have_received(:list).exactly(3).times
        expect(result['entries'].length).to eq(3)
      end

      it 'filters entries when include_entry block is given' do
        allow(list_service).to receive(:list).with(count: 10, page: 1).and_return(
          'entry' => [
            { 'resource' => { 'id' => 'keep' } },
            { 'resource' => { 'id' => 'skip' } }
          ],
          'link' => []
        )

        result = paged_resource.fetch_paged_resources(service: list_service, max_pages: 5, count: 10) do |entry|
          entry.dig('resource', 'id') == 'keep'
        end

        expect(result['entries'].length).to eq(1)
        expect(result['entries'].first.dig('resource', 'id')).to eq('keep')
      end
    end
  end

  describe '::ChargeItemService' do
    let(:icn) { '123456789V123456' }
    let(:lighthouse_client) { instance_double(Lighthouse::HealthcareCostAndCoverage::ChargeItem::Service) }
    let(:hccc_charge_item) { Lighthouse::HealthcareCostAndCoverage::ChargeItem::Service }
    let(:charge_item_service_class) do
      MedicalCopays::LighthouseIntegration::PaginatedService::ChargeItemService
    end

    before do
      allow(hccc_charge_item).to receive(:new).with(icn).and_return(lighthouse_client)
    end

    describe '#fetch_paginated_charge_items' do
      it 'returns an empty hash when ids are empty' do
        expect(charge_item_service_class.new(icn).fetch_paginated_charge_items([])).to eq({})
      end

      it 'collects matching ChargeItems across bundle responses until next link is absent' do
        allow(lighthouse_client).to receive(:list).with(
          count: charge_item_service_class::CHARGE_ITEM_FETCH_LIMIT,
          page: 1
        ).and_return(
          'entry' => [{ 'resource' => { 'id' => 'noise', 'status' => 'x' } }],
          'link' => [{ 'relation' => 'next', 'url' => 'https://example/next' }]
        )
        allow(lighthouse_client).to receive(:list).with(
          count: charge_item_service_class::CHARGE_ITEM_FETCH_LIMIT,
          page: 2
        ).and_return(
          'entry' => [{ 'resource' => { 'id' => 'want-this', 'status' => 'billable' } }],
          'link' => []
        )

        result = charge_item_service_class.new(icn).fetch_paginated_charge_items(['want-this'])

        expect(result).to eq('want-this' => { 'id' => 'want-this', 'status' => 'billable' })
        expect(lighthouse_client).to have_received(:list).twice
      end

      it 'returns an empty hash when list raises' do
        allow(lighthouse_client).to receive(:list).and_raise(StandardError.new('API error'))
        allow(Rails.logger).to receive(:warn)

        expect(charge_item_service_class.new(icn).fetch_paginated_charge_items(['x'])).to eq({})
      end
    end
  end
end
