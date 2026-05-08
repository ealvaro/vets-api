# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SavedClaim::CoeClaim, type: :model do
  include_context 'coe claim form validation'

  def mutate_form
    h = valid_form_hash.deep_dup
    yield h
    h.to_json
  end

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

    it 'calls validate_coe_rebuild_form for v2 forms when the form is a string' do
      claim = described_class.new(form: valid_form_hash.to_json)
      allow(claim).to receive(:form_is_string).and_return(true)
      expect(claim).to receive(:validate_coe_rebuild_form).and_call_original
      claim.send(:form_matches_schema)
    end
  end

  describe 'COE v2 field validation' do
    context 'with a complete valid payload' do
      it 'passes validation' do
        expect(claim.validate).to be true
        expect(claim.errors).to be_empty
      end
    end

    describe '#rebuild_form_version?' do
      it 'safely returns false when parsed_form is malformed' do
        claim = described_class.new(form: valid_form_hash.to_json)
        allow(claim).to receive(:parsed_form).and_raise(JSON::ParserError)

        expect(claim.send(:rebuild_form_version?)).to be false
      end
    end

    it 'validates a structurally complete v2 claim without adding field errors' do
      valid = described_class.new(form: valid_form_hash.merge('version' => 2).to_json)
      expect(valid.validate).to be true
      expect(valid.errors).to be_empty
    end

    it 'rejects a structurally bad v2 payload with field errors' do
      invalid = described_class.new(form: valid_form_hash.merge('version' => 2).except('fullName').to_json)
      expect(invalid.validate).to be false
      expect(invalid.errors).not_to be_empty
      expect(error_attributes(invalid)).to include('/fullName')
    end

    it 'logs when validation fails' do
      allow(Rails.logger).to receive(:error)
      expect(claim.validate).to be true
      expect(Rails.logger).not_to have_received(:error)

      invalid = described_class.new(form: valid_form_hash.except('fullName').to_json)
      invalid.validate
      expect(Rails.logger).to have_received(:error).with(
        'SavedClaim form did not pass validation',
        hash_including(:errors)
      )
    end

    context 'when a required top-level field is missing' do
      let(:form_json) { mutate_form { |h| h.delete('fullName') } }

      it 'records a required error' do
        claim.validate
        expect(error_attributes(claim)).to include('/fullName')
      end
    end

    context 'when privacyAgreementAccepted is not true' do
      let(:form_json) { mutate_form { |h| h['privacyAgreementAccepted'] = false } }

      it 'rejects the payload' do
        claim.validate
        expect(error_attributes(claim)).to include('/privacyAgreementAccepted')
      end
    end

    context 'when fullName is not an object' do
      let(:form_json) { mutate_form { |h| h['fullName'] = 'oops' } }

      it 'records a type error' do
        claim.validate
        expect(error_attributes(claim)).to include('/fullName')
      end
    end

    context 'when veteran is not an object' do
      let(:form_json) { mutate_form { |h| h['veteran'] = [] } }

      it 'records a type error' do
        claim.validate
        expect(error_attributes(claim)).to include('/veteran')
      end
    end

    context 'when militaryHistory periodsOfService is not an array' do
      let(:form_json) { mutate_form { |h| h['militaryHistory']['periodsOfService'] = {} } }

      it 'records a type error' do
        claim.validate
        expect(error_attributes(claim)).to include('/militaryHistory/periodsOfService')
      end
    end

    context 'when militaryHistory periodsOfService is empty' do
      let(:form_json) { mutate_form { |h| h['militaryHistory']['periodsOfService'] = [] } }

      it 'requires at least one period' do
        claim.validate
        expect(error_attributes(claim)).to include('/militaryHistory/periodsOfService')
      end
    end

    context 'when fullName first is too long' do
      let(:form_json) { mutate_form { |h| h['fullName']['first'] = 'x' * 31 } }

      it 'records a length error' do
        claim.validate
        expect(error_attributes(claim)).to include('/fullName/first')
      end
    end
  end
end
