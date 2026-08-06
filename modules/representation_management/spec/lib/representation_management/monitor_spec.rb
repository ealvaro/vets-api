# frozen_string_literal: true

require 'rails_helper'

RSpec.describe RepresentationManagement::Monitor do
  subject(:monitor) { described_class.new }

  before do
    allow(StatsD).to receive(:increment)
    allow(Rails.logger).to receive(:error)
  end

  describe '#track_validation_errors' do
    let(:base_args) do
      {
        message: 'validation failed',
        action: 'create',
        controller: 'RepresentationManagement::V0::PdfGenerator2122Controller',
        form_id: '21-22'
      }
    end

    it 'submits one event per unique normalized validation error type with form_id tagging' do
      errors = {
        veteran_first_name: ["can't be blank"],
        veteran_last_name: ['too long (maximum is 12 characters)'],
        veteran_social_security_number: ['is invalid'],
        representative_id: ['Representative not found'],
        consent_limits: ['ALCOHOLISM_X is not a valid limitation of consent']
      }

      monitor.track_validation_errors(**base_args, errors:)

      expect(StatsD).to have_received(:increment).exactly(5).times

      expect(StatsD).to have_received(:increment).with(
        'representation_management.validation_error',
        hash_including(
          tags: include(
            'action:create',
            'controller:RepresentationManagement::V0::PdfGenerator2122Controller',
            'form_id:21-22',
            'validation_error_type:required_field_missing',
            'validation_error_field:veteran_first_name'
          )
        )
      )

      expect(Rails.logger).to have_received(:error).with(
        'validation failed',
        hash_including(
          statsd: 'representation_management.validation_error',
          context: hash_including(
            form_id: '21-22',
            errors: a_kind_of(Hash)
          )
        )
      ).at_least(:once)

      expect(StatsD).to have_received(:increment).with(
        'representation_management.validation_error',
        hash_including(
          tags: include(
            'action:create',
            'controller:RepresentationManagement::V0::PdfGenerator2122Controller',
            'form_id:21-22',
            'validation_error_type:length_too_long',
            'validation_error_field:veteran_last_name'
          )
        )
      )

      expect(StatsD).to have_received(:increment).with(
        'representation_management.validation_error',
        hash_including(
          tags: include(
            'action:create',
            'controller:RepresentationManagement::V0::PdfGenerator2122Controller',
            'form_id:21-22',
            'validation_error_type:format_invalid',
            'validation_error_field:veteran_social_security_number'
          )
        )
      )

      expect(StatsD).to have_received(:increment).with(
        'representation_management.validation_error',
        hash_including(
          tags: include(
            'action:create',
            'controller:RepresentationManagement::V0::PdfGenerator2122Controller',
            'form_id:21-22',
            'validation_error_type:lookup_not_found',
            'validation_error_field:representative_id'
          )
        )
      )

      expect(StatsD).to have_received(:increment).with(
        'representation_management.validation_error',
        hash_including(
          tags: include(
            'action:create',
            'controller:RepresentationManagement::V0::PdfGenerator2122Controller',
            'form_id:21-22',
            'validation_error_type:invalid_consent_limit',
            'validation_error_field:consent_limits'
          )
        )
      )
    end

    it 'logs unknown when no error messages are present' do
      monitor.track_validation_errors(**base_args, errors: {})

      expect(StatsD).to have_received(:increment).once
      expect(StatsD).to have_received(:increment).with(
        'representation_management.validation_error',
        hash_including(
          tags: include('validation_error_type:unknown_validation_error')
        )
      )
    end

    it 'logs unknown for unrecognized error messages' do
      monitor.track_validation_errors(**base_args, errors: { base: ['unexpected validation message'] })

      expect(StatsD).to have_received(:increment).once
      expect(StatsD).to have_received(:increment).with(
        'representation_management.validation_error',
        hash_including(
          tags: include(
            'validation_error_type:unknown_validation_error',
            'validation_error_field:base'
          )
        )
      )
    end

    it 'logs one event for a shared error type with all matching fields tagged' do
      errors = {
        veteran_first_name: ["can't be blank"],
        veteran_last_name: ["can't be blank"],
        claimant_first_name: ["can't be blank"]
      }

      monitor.track_validation_errors(**base_args, errors:)

      expect(StatsD).to have_received(:increment).once
      expect(StatsD).to have_received(:increment).with(
        'representation_management.validation_error',
        hash_including(
          tags: include(
            'validation_error_type:required_field_missing',
            'validation_error_field:veteran_first_name',
            'validation_error_field:veteran_last_name',
            'validation_error_field:claimant_first_name'
          )
        )
      )
    end
  end
end
