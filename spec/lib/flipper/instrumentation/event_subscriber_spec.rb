# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Flipper::Instrumentation::EventSubscriber do
  let(:subscriber) { described_class.new }

  def emit_feature_operation(payload)
    subscriber.call('feature_operation.flipper', Time.zone.now, Time.zone.now, SecureRandom.uuid, payload)
  end

  context 'logs changes to toggle values' do
    it 'logs feature calls with result after operation for disable' do
      emit_feature_operation(feature_name: 'this_is_only_a_test', operation: :disable, gate_name: 'boolean')

      last_event = FeatureToggleEvent.last
      expect(last_event.feature_name).to eq('this_is_only_a_test')
      expect(last_event.operation).to eq('disable')
      expect(last_event.gate_name).to eq('boolean')
    end

    it 'logs feature calls with result after operation for disable_percentage_of_actors' do
      emit_feature_operation(feature_name: 'this_is_only_a_test', operation: :disable,
                             gate_name: 'percentage_of_actors')

      last_event = FeatureToggleEvent.last
      expect(last_event.feature_name).to eq('this_is_only_a_test')
      expect(last_event.operation).to eq('disable')
      expect(last_event.gate_name).to eq('percentage_of_actors')
    end

    it 'logs feature calls with result after operation for disable_percentage_of_time' do
      emit_feature_operation(feature_name: 'this_is_only_a_test', operation: :disable, gate_name: 'percentage_of_time')

      last_event = FeatureToggleEvent.last
      expect(last_event.feature_name).to eq('this_is_only_a_test')
      expect(last_event.operation).to eq('disable')
      expect(last_event.gate_name).to eq('percentage_of_time')
    end

    it 'logs feature calls with result after operation for enable_percentage_of_actors' do
      emit_feature_operation(feature_name: 'this_is_only_a_test', operation: :enable,
                             gate_name: 'percentage_of_actors')

      last_event = FeatureToggleEvent.last
      expect(last_event.feature_name).to eq('this_is_only_a_test')
      expect(last_event.operation).to eq('enable')
      expect(last_event.gate_name).to eq('percentage_of_actors')
    end

    it 'logs feature calls with result after operation for enable_percentage_of_time' do
      emit_feature_operation(feature_name: 'this_is_only_a_test', operation: :enable, gate_name: 'percentage_of_time')

      last_event = FeatureToggleEvent.last
      expect(last_event.feature_name).to eq('this_is_only_a_test')
      expect(last_event.operation).to eq('enable')
      expect(last_event.gate_name).to eq('percentage_of_time')
    end

    it 'logs feature calls with result after operation for actor gates' do
      emit_feature_operation(feature_name: 'this_is_only_a_test', operation: :enable, gate_name: 'actor')
      last_event = FeatureToggleEvent.last
      expect(last_event.feature_name).to eq('this_is_only_a_test')
      expect(last_event.operation).to eq('enable')
      expect(last_event.gate_name).to eq('actor')

      emit_feature_operation(feature_name: 'this_is_only_a_test', operation: :disable, gate_name: 'actor')
      last_event = FeatureToggleEvent.last
      expect(last_event.feature_name).to eq('this_is_only_a_test')
      expect(last_event.operation).to eq('disable')
      expect(last_event.gate_name).to eq('actor')
    end
  end

  context 'does not log evaluation of toggle values' do
    it 'does not log enabled checks' do
      expect do
        emit_feature_operation(feature_name: 'this_is_only_a_test', operation: :enabled?, gate_name: 'boolean')
      end.not_to change(FeatureToggleEvent, :count)
    end
  end
end
