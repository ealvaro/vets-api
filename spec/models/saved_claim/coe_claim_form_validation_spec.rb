# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SavedClaim::CoeClaim, type: :model do
  describe 'COE inbound form validation (CoeClaimFormValidation) — part 1' do
    include_context 'coe claim form validation'

    describe '#form_matches_schema' do
      it 'returns early when form is not a string for v2+ forms' do
        claim = described_class.new(form: valid_form_hash.merge('version' => 2).to_json)
        allow(claim).to receive(:form_is_string).and_return(false)
        expect(claim).not_to receive(:validate_coe_rebuild_form)
        claim.send(:form_matches_schema)
      end

      it 'does not run validate_coe_rebuild_form for v1 forms' do
        claim = described_class.new(form: valid_form_hash.merge('version' => 1).to_json)
        allow(claim).to receive(:form_is_string).and_return(true)
        expect(claim).not_to receive(:validate_coe_rebuild_form)
        claim.send(:form_matches_schema)
      end
    end

    describe '#rebuild_form_version?' do
      it 'safely returns false when parsed_form is malformed' do
        claim = described_class.new(form: valid_form_hash.to_json)
        allow(claim).to receive(:parsed_form).and_raise(JSON::ParserError)

        expect(claim.send(:rebuild_form_version?)).to be false
      end
    end
  end
end
