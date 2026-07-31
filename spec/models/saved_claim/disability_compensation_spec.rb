# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SavedClaim::DisabilityCompensation, type: :model do
  describe '#form_matches_schema' do
    let(:claim) { described_class.new(form: '{}') }
    let(:schema) { { 'type' => 'object' } }

    before do
      allow(Rails.logger).to receive(:error)
      allow(VetsJsonSchema::SCHEMAS).to receive(:[]).with('21-526EZ').and_return(schema)
    end

    it 'does not run hardened validation when the flipper is disabled' do
      allow_any_instance_of(SavedClaim).to receive(:form_matches_schema).and_return(true)
      allow(Flipper).to receive(:enabled?).with(:disability_526_schema_hardening_logging).and_return(false)

      expect(claim).not_to receive(:validate_schema)
      expect(claim).not_to receive(:validate_form)

      expect(claim.send(:form_matches_schema)).to be true
    end

    it 'does not run hardened validation when the base validation returned false' do
      allow_any_instance_of(SavedClaim).to receive(:form_matches_schema).and_return(false)
      allow(Flipper).to receive(:enabled?).with(:disability_526_schema_hardening_logging).and_return(true)

      expect(claim).not_to receive(:validate_schema)
      expect(claim).not_to receive(:validate_form)

      expect(claim.send(:form_matches_schema)).to be false
    end

    it 'runs hardened validation when the flipper is enabled and base validation returned true' do
      allow_any_instance_of(SavedClaim).to receive(:form_matches_schema).and_return(true)
      allow(Flipper).to receive(:enabled?).with(:disability_526_schema_hardening_logging).and_return(true)

      schema_errors = [{ fragment: '/required', message: 'is required' }]
      validation_errors = [
        {
          fragment: '/foo',
          message: 'is invalid',
          errors: [[{ fragment: '/nested', message: 'nested is invalid' }]]
        }
      ]

      expect(claim).to receive(:validate_schema).with(schema).and_return(schema_errors)
      expect(claim).to receive(:validate_form).with(schema).and_return(validation_errors)

      expect(claim.send(:form_matches_schema)).to be true

      expect(Rails.logger).to have_received(:error).with(
        'SavedClaim::DisabilityCompensation HARDENED schema failed validation.',
        { errors: schema_errors, form_id: claim.form_id, guid: claim.guid }
      )
      expect(Rails.logger).to have_received(:error).with(
        'SavedClaim::DisabilityCompensation form did not pass HARDENED validation',
        { errors: validation_errors, form_id: claim.form_id, guid: claim.guid }
      )
    end
  end
end
