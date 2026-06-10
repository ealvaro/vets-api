# frozen_string_literal: true

require 'rails_helper'
require 'mhv/aal/activity_page'

RSpec.describe AAL::ActivityPage do
  let(:api_response_body) do
    {
      'content' => [
        {
          'activityId' => 1,
          'userProfileId' => 100,
          'action' => 'LOGIN',
          'status' => 'true',
          'performerType' => 'SELF',
          'activityType' => 'LOGIN_LOGOUT',
          'detailValue' => 'User logged in',
          'completionTime' => '2026-03-04T14:30:00Z'
        },
        {
          'activityId' => 2,
          'userProfileId' => 100,
          'action' => 'VIEW_ALLERGY',
          'status' => 'true',
          'performerType' => 'SELF',
          'activityType' => 'ALLERGY',
          'detailValue' => nil,
          'completionTime' => '2026-03-04T14:35:00Z'
        }
      ],
      'pageable' => {
        'sort' => { 'sorted' => true, 'unsorted' => false, 'empty' => false },
        'pageNumber' => 0,
        'pageSize' => 20,
        'offset' => 0,
        'paged' => true,
        'unpaged' => false
      },
      'totalElements' => 42,
      'totalPages' => 3,
      'last' => false,
      'first' => true,
      'numberOfElements' => 2,
      'size' => 20,
      'number' => 0,
      'empty' => false
    }
  end

  describe '#initialize' do
    it 'parses activities from the content array' do
      page = described_class.new(api_response_body)

      expect(page.activities.size).to eq(2)
      expect(page.activities.first).to be_a(AAL::Activity)
      expect(page.activities.first.action).to eq('LOGIN')
      expect(page.activities.last.action).to eq('VIEW_ALLERGY')
    end

    it 'extracts pagination metadata' do
      page = described_class.new(api_response_body)

      expect(page.page_number).to eq(0)
      expect(page.page_size).to eq(20)
      expect(page.total_elements).to eq(42)
      expect(page.total_pages).to eq(3)
      expect(page.first_page).to be(true)
      expect(page.last_page).to be(false)
      expect(page.number_of_elements).to eq(2)
      expect(page.empty_page).to be(false)
    end
  end

  describe '#pagination' do
    it 'returns a hash of pagination metadata' do
      page = described_class.new(api_response_body)

      expect(page.pagination).to eq({
                                      page_number: 0,
                                      page_size: 20,
                                      total_elements: 42,
                                      total_pages: 3,
                                      first_page: true,
                                      last_page: false,
                                      number_of_elements: 2,
                                      empty_page: false
                                    })
    end
  end

  describe 'with empty response' do
    let(:empty_body) do
      {
        'content' => [],
        'pageable' => { 'pageNumber' => 0, 'pageSize' => 20 },
        'totalElements' => 0,
        'totalPages' => 0,
        'last' => true,
        'first' => true,
        'numberOfElements' => 0,
        'size' => 20,
        'number' => 0,
        'empty' => true
      }
    end

    it 'handles empty content gracefully' do
      page = described_class.new(empty_body)

      expect(page.activities).to eq([])
      expect(page.total_elements).to eq(0)
      expect(page.empty_page).to be(true)
    end
  end

  describe 'with missing pageable' do
    let(:minimal_body) do
      { 'content' => [], 'number' => 2, 'size' => 10, 'totalElements' => 50, 'totalPages' => 5 }
    end

    it 'falls back to top-level fields for pagination' do
      page = described_class.new(minimal_body)

      expect(page.page_number).to eq(2)
      expect(page.page_size).to eq(10)
    end
  end
end
