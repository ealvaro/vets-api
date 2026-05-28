# frozen_string_literal: true

require 'rails_helper'

RSpec.describe VRE::Ch31CaseDetails::Response do
  subject(:response) { described_class.new(raw_response.status, raw_response) }

  let(:json) { File.read('modules/vre/spec/fixtures/ch31_case_details.json') }
  let(:body) { JSON.parse(json).deep_transform_keys!(&:underscore) }
  let(:raw_response) { instance_double(Faraday::Env, status: 200, body:) }

  describe '#initialize' do
    it 'sets attributes from raw response' do
      expect(response.attributes).to eq(body)
    end

    it 'sets is_initial_evaluation_step_code_of_conduct_completed' do
      expect(response.is_initial_evaluation_step_code_of_conduct_completed)
        .to eq(body['is_initial_evaluation_step_code_of_conduct_completed'])
    end

    it 'sets has_veteran_opted_for_eva' do
      expect(response.has_veteran_opted_for_eva).to eq(body['has_veteran_opted_for_eva'])
    end
  end
end
