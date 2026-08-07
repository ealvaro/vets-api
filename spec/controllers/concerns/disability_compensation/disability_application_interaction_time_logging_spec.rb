# frozen_string_literal: true

require 'rails_helper'

# rubocop:disable Rails/ApplicationController
unless defined?(TestLoggingController)
  class TestLoggingController < ActionController::Base
    include DisabilityCompensation::DisabilityApplicationInteractionTimeLogging

    def test_action
      render json: { test: true }
    end
  end
end
# rubocop:enable Rails/ApplicationController

describe DisabilityCompensation::DisabilityApplicationInteractionTimeLogging do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { build(:user, :loa3, :legacy_icn) }
  let(:controller) { TestLoggingController.new }

  before do
    controller.instance_variable_set(:@current_user, user)
    controller.request = ActionController::TestRequest.create({})
    allow(controller).to receive(:action_name).and_return('test_action')
    allow(controller.request).to receive(:request_id).and_return('test-request-id')
  end

  describe '#active_delta_seconds' do
    it 'returns nil when previous_activity_at is blank' do
      result = controller.send(:active_delta_seconds, nil, Time.current)
      expect(result).to be_nil
    end

    it 'returns nil when previous_activity_at is an empty string' do
      result = controller.send(:active_delta_seconds, '', Time.current)
      expect(result).to be_nil
    end

    it 'returns nil when delta is negative (future timestamp)' do
      future_time = 1.hour.from_now
      current_time = Time.current
      result = controller.send(:active_delta_seconds, future_time, current_time)
      expect(result).to be_nil
    end

    it 'returns the full delta even when it exceeds ACTIVE_IDLE_GAP_SECONDS' do
      freeze_time do
        old_time = 15.minutes.ago
        current_time = Time.current
        result = controller.send(:active_delta_seconds, old_time, current_time)
        expect(result).to be_a(Integer)
        expect(result).to eq(15.minutes.to_i)
      end
    end

    it 'returns rounded integer seconds for deltas within idle gap' do
      previous_time = 2.minutes.ago
      current_time = Time.current
      result = controller.send(:active_delta_seconds, previous_time, current_time)
      expect(result).to be_a(Integer)
      expect(result).to be_within(5).of(120)
    end

    it 'returns the delta for timestamps at or beyond ACTIVE_IDLE_GAP_SECONDS boundary' do
      gap_seconds = DisabilityCompensation::DisabilityApplicationInteractionTimeLogging::ACTIVE_IDLE_GAP_SECONDS
      previous_time = gap_seconds.seconds.ago
      current_time = Time.current
      result = controller.send(:active_delta_seconds, previous_time, current_time)
      expect(result).to be_a(Integer)
      expect(result).to be_within(5).of(gap_seconds)
    end

    it 'returns delta for timestamps just under ACTIVE_IDLE_GAP_SECONDS' do
      gap_seconds = DisabilityCompensation::DisabilityApplicationInteractionTimeLogging::ACTIVE_IDLE_GAP_SECONDS
      previous_time = (gap_seconds - 10).seconds.ago
      current_time = Time.current
      result = controller.send(:active_delta_seconds, previous_time, current_time)
      expect(result).to be_a(Integer)
      expect(result).to be > 0
      expect(result).to be < gap_seconds
    end

    it 'handles equal timestamps (0 delta)' do
      same_time = Time.current
      result = controller.send(:active_delta_seconds, same_time, same_time)
      expect(result).to eq(0)
    end
  end

  describe '#log_ipf_active_time_event' do
    let(:ipf_id) { 123 }
    let(:event_type) { 'show' }
    let(:created_at) { 2.hours.ago }
    let(:updated_at) { 5.minutes.ago }

    before do
      allow(Rails.logger).to receive(:info).and_call_original
      allow(Flipper).to receive(:enabled?).and_return(true)
    end

    it 'emits a log event with required fields' do
      expect(Rails.logger).to receive(:info).with(
        'Form526 interaction',
        hash_including(
          event_type:,
          form_id: FormProfiles::VA526ez::FORM_ID,
          in_progress_form_id: ipf_id,
          user_uuid: user.uuid,
          terminal: false,
          request_id: kind_of(String),
          controller: 'TestLoggingController',
          action: 'test_action',
          active_idle_gap_exceeded: nil
        )
      )

      controller.send(:log_ipf_active_time_event,
                      event_type:,
                      in_progress_form_id: ipf_id,
                      terminal: false)
    end

    it 'formats occurred_at as ISO8601 with millisecond precision' do
      expect(Rails.logger).to receive(:info) do |message, payload|
        if message == 'Form526 interaction'
          expect(payload[:occurred_at]).to match(/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z/)
        end
      end

      controller.send(:log_ipf_active_time_event,
                      event_type:,
                      in_progress_form_id: ipf_id,
                      terminal: false)
    end

    it 'calculates active_delta_seconds when previous_activity_at is provided' do
      expect(Rails.logger).to receive(:info).with(
        'Form526 interaction',
        hash_including(active_delta_seconds: a_value_within(5).of(5.minutes.to_i))
      )

      controller.send(:log_ipf_active_time_event,
                      event_type:,
                      in_progress_form_id: ipf_id,
                      terminal: false,
                      context: { previous_activity_at: updated_at })
    end

    it 'sets active_delta_seconds to nil when previous_activity_at is nil' do
      expect(Rails.logger).to receive(:info).with(
        'Form526 interaction',
        hash_including(active_delta_seconds: nil)
      )

      controller.send(:log_ipf_active_time_event,
                      event_type:,
                      in_progress_form_id: ipf_id,
                      terminal: false,
                      context: { previous_activity_at: nil })
    end

    it 'logs active_idle_gap_exceeded: true when previous_activity_at exceeds the threshold' do
      expect(Rails.logger).to receive(:info).with(
        'Form526 interaction',
        hash_including(active_idle_gap_exceeded: true)
      )

      controller.send(:log_ipf_active_time_event,
                      event_type:,
                      in_progress_form_id: ipf_id,
                      terminal: false,
                      context: { previous_activity_at: 15.minutes.ago })
    end

    it 'logs active_idle_gap_exceeded: nil when previous_activity_at is within the threshold' do
      expect(Rails.logger).to receive(:info).with(
        'Form526 interaction',
        hash_including(active_idle_gap_exceeded: nil)
      )

      controller.send(:log_ipf_active_time_event,
                      event_type:,
                      in_progress_form_id: ipf_id,
                      terminal: false,
                      context: { previous_activity_at: 5.minutes.ago })
    end

    it 'includes submission_id when provided' do
      submission_id = 456
      expect(Rails.logger).to receive(:info).with(
        'Form526 interaction',
        hash_including(submission_id:)
      )

      controller.send(:log_ipf_active_time_event,
                      event_type:,
                      in_progress_form_id: ipf_id,
                      terminal: true,
                      context: { submission_id: })
    end

    it 'handles nil user by logging nil user_uuid' do
      controller.instance_variable_set(:@current_user, nil)
      expect(Rails.logger).to receive(:info).with(
        'Form526 interaction',
        hash_including(user_uuid: nil)
      )

      controller.send(:log_ipf_active_time_event,
                      event_type:,
                      in_progress_form_id: ipf_id,
                      terminal: false)
    end

    it 'logs nil for optional fields when not provided' do
      expect(Rails.logger).to receive(:info).with(
        'Form526 interaction',
        hash_including(
          active_delta_seconds: nil,
          active_idle_gap_exceeded: nil,
          submission_id: nil
        )
      )

      controller.send(:log_ipf_active_time_event,
                      event_type:,
                      in_progress_form_id: ipf_id,
                      terminal: false)
    end
  end

  describe 'engagement event payload structure' do
    it 'includes all required fields for a complete payload' do
      ipf_id = 789
      submission_id = 999
      updated_at = 10.minutes.ago
      captured_payload = nil

      allow(Rails.logger).to receive(:info) do |_message, payload|
        captured_payload = payload
      end

      controller.send(:log_ipf_active_time_event,
                      event_type: 'update',
                      in_progress_form_id: ipf_id,
                      terminal: false,
                      context: {
                        submission_id:,
                        previous_activity_at: updated_at
                      })

      # Verify all expected keys are present
      expect(captured_payload).to include(
        :event_type,
        :occurred_at,
        :request_id,
        :controller,
        :action,
        :form_id,
        :in_progress_form_id,
        :user_uuid,
        :terminal,
        :active_delta_seconds,
        :active_idle_gap_exceeded
      )

      # Verify specific values
      expect(captured_payload[:event_type]).to eq('update')
      expect(captured_payload[:form_id]).to eq(FormProfiles::VA526ez::FORM_ID)
      expect(captured_payload[:in_progress_form_id]).to eq(ipf_id)
      expect(captured_payload[:submission_id]).to eq(submission_id)
      expect(captured_payload[:user_uuid]).to eq(user.uuid)
      expect(captured_payload[:terminal]).to be(false)
    end
  end
end
