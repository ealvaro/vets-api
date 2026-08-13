# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SavedClaim::DisabilityCompensation::Form526AllClaim, type: :model do
  let(:claim) { described_class.new(form: '{}') }
  let(:default_schema) { { 'type' => 'object', 'properties' => {} } }
  let(:strict_schema) { { 'type' => 'object', 'required' => ['field'] } }

  before do
    allow(VetsJsonSchema::SCHEMAS).to receive(:[]).with('21-526EZ-ALLCLAIMS').and_return(default_schema)
    allow(VetsJsonSchema::SCHEMAS).to receive(:[]).with('21-526EZ-ALLCLAIMS-STRICT').and_return(strict_schema)
  end

  describe '#form_schema' do
    it 'returns the default schema when the enforce flag is disabled' do
      allow(Flipper).to receive(:enabled?).with(:disability_526_schema_hardening_enforce).and_return(false)

      expect(claim.form_schema).to eq(default_schema)
    end

    it 'returns the strict schema when the enforce flag is enabled' do
      allow(Flipper).to receive(:enabled?).with(:disability_526_schema_hardening_enforce).and_return(true)

      expect(claim.form_schema).to eq(strict_schema)
    end
  end

  describe '#form_matches_schema' do
    before { allow(Rails.logger).to receive(:error) }

    it 'returns nil when the base validation returns nil' do
      allow_any_instance_of(SavedClaim).to receive(:form_is_string).and_return(false)

      expect(claim).not_to receive(:validate_schema)
      expect(claim).not_to receive(:validate_form)

      expect(claim.form_matches_schema).to be_nil
    end

    it 'becomes invalid when strict validation fails and enforce is enabled, even if default validation would pass' do
      strict_validation_errors = [{ fragment: '/field', message: 'is required', errors: [] }]

      allow(Flipper).to receive(:enabled?).with(:disability_526_schema_hardening_logging).and_return(false)

      allow(Flipper).to receive(:enabled?).with(:disability_526_schema_hardening_enforce).and_return(false)
      expect(claim).to receive(:validate_schema).with(default_schema).and_return([]).once
      expect(claim).to receive(:validate_form).with(default_schema).and_return([]).once
      expect(claim.form_matches_schema).to be true

      allow(Flipper).to receive(:enabled?).with(:disability_526_schema_hardening_enforce).and_return(true)
      expect(claim).to receive(:validate_schema).with(strict_schema).and_return([]).once
      expect(claim).to receive(:validate_form).with(strict_schema).and_return(strict_validation_errors).once
      expect(claim.form_matches_schema).to be false
    end

    it 'does not run hardened validation when the logging flag is disabled' do
      allow_any_instance_of(SavedClaim).to receive(:form_matches_schema).and_return(true)
      allow(Flipper).to receive(:enabled?).with(:disability_526_schema_hardening_enforce).and_return(false)
      allow(Flipper).to receive(:enabled?).with(:disability_526_schema_hardening_logging).and_return(false)

      expect(claim).not_to receive(:validate_schema)
      expect(claim).not_to receive(:validate_form)

      expect(claim.form_matches_schema).to be true
    end

    it 'does not run hardened validation when the base validation returned false' do
      allow_any_instance_of(SavedClaim).to receive(:form_matches_schema).and_return(false)
      allow(Flipper).to receive(:enabled?).with(:disability_526_schema_hardening_enforce).and_return(false)
      allow(Flipper).to receive(:enabled?).with(:disability_526_schema_hardening_logging).and_return(true)

      expect(claim).not_to receive(:validate_schema)
      expect(claim).not_to receive(:validate_form)

      expect(claim.form_matches_schema).to be false
    end

    it 'runs hardened validation with the strict schema when the logging flag is enabled and base validation passed' do
      allow_any_instance_of(SavedClaim).to receive(:form_matches_schema).and_return(true)
      allow(Flipper).to receive(:enabled?).with(:disability_526_schema_hardening_enforce).and_return(false)
      allow(Flipper).to receive(:enabled?).with(:disability_526_schema_hardening_logging).and_return(true)

      schema_errors = [{ fragment: '/required', message: 'is required' }]
      validation_errors = [{ fragment: '/foo', message: 'is invalid', errors: [] }]

      expect(claim).to receive(:validate_schema).with(strict_schema).and_return(schema_errors)
      expect(claim).to receive(:validate_form).with(strict_schema).and_return(validation_errors)

      expect(claim.form_matches_schema).to be true

      expect(Rails.logger).to have_received(:error).with(
        'SavedClaim::DisabilityCompensation::Form526AllClaim HARDENED schema failed validation.',
        { errors: schema_errors, form_id: claim.form_id, guid: claim.guid }
      )
      expect(Rails.logger).to have_received(:error).with(
        'SavedClaim::DisabilityCompensation::Form526AllClaim form did not pass HARDENED validation',
        { errors: validation_errors, form_id: claim.form_id, guid: claim.guid }
      )
    end

    it 'does not log when hardened validation passes' do
      allow_any_instance_of(SavedClaim).to receive(:form_matches_schema).and_return(true)
      allow(Flipper).to receive(:enabled?).with(:disability_526_schema_hardening_enforce).and_return(false)
      allow(Flipper).to receive(:enabled?).with(:disability_526_schema_hardening_logging).and_return(true)

      allow(claim).to receive(:validate_schema).with(strict_schema).and_return([])
      allow(claim).to receive(:validate_form).with(strict_schema).and_return([])

      expect(claim.form_matches_schema).to be true
      expect(Rails.logger).not_to have_received(:error)
    end
  end
end
