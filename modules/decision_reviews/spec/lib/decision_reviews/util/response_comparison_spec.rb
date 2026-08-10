# frozen_string_literal: true

require './modules/decision_reviews/spec/dr_spec_helper'
require 'decision_reviews/util/response_comparison'

RSpec.describe DecisionReviews::Util::ResponseComparison do
  subject(:comparison) { described_class.new(expected:, actual:, **options) }

  let(:options) { {} }
  let(:migraine) do
    {
      'subjectText' => 'Migraine',
      'decisionDate' => '2020-02-01',
      'chain' => [{ 'id' => nil, 'decisionDate' => '2020-02-01' }]
    }
  end
  let(:ptsd) { { 'subjectText' => 'PTSD', 'decisionDate' => '2020-05-01' } }

  def record(type:, attributes:)
    { 'id' => nil, 'type' => type, 'attributes' => attributes }
  end

  describe 'with no options' do
    let(:expected) { { 'data' => [record(type: 'a', attributes: migraine)] } }

    context 'when the bodies are identical' do
      let(:actual) { expected.deep_dup }

      it 'is equivalent' do
        expect(comparison.equivalent?).to be true
        expect(comparison.ordering_differs?).to be false
        expect(comparison.differing_keys).to eq []
      end
    end

    context 'when any value differs' do
      let(:actual) { { 'data' => [record(type: 'a', attributes: migraine.merge('subjectText' => 'PTSD'))] } }

      it 'is not equivalent' do
        expect(comparison.equivalent?).to be false
      end
    end

    context 'when only a key one side does not have differs' do
      let(:actual) { { 'data' => [record(type: 'a', attributes: migraine.merge('timely' => false))] } }

      it 'is not equivalent, and names the key' do
        expect(comparison.equivalent?).to be false
        expect(comparison.differing_keys).to eq ['timely']
      end
    end
  end

  describe 'ignored_keys' do
    let(:expected) { { 'data' => [record(type: 'contestableIssue', attributes: migraine)] } }
    let(:actual) { { 'data' => [record(type: 'appealableIssue', attributes: migraine)] } }

    context 'when the differing key is not ignored' do
      it 'is not equivalent' do
        expect(comparison.equivalent?).to be false
      end
    end

    context 'when the differing key is ignored' do
      let(:options) { { ignored_keys: %w[type] } }

      it 'is equivalent' do
        expect(comparison.equivalent?).to be true
      end

      it 'excludes the ignored key from differing_keys' do
        expect(comparison.differing_keys).not_to include 'type'
      end
    end

    context 'when the ignored key appears nested inside a record' do
      let(:expected) { { 'data' => [{ 'attributes' => { 'type' => 'one', 'shared' => 1 } }] } }
      let(:actual) { { 'data' => [{ 'attributes' => { 'type' => 'two', 'shared' => 1 } }] } }
      let(:options) { { ignored_keys: %w[type] } }

      # Ignored keys are dropped at every depth, not just the top of each record.
      it 'is equivalent' do
        expect(comparison.equivalent?).to be true
      end
    end

    context 'when a key other than the ignored one differs' do
      let(:actual) { { 'data' => [record(type: 'appealableIssue', attributes: migraine.merge('extra' => 1))] } }
      let(:options) { { ignored_keys: %w[type] } }

      it 'is not equivalent' do
        expect(comparison.equivalent?).to be false
      end
    end
  end

  describe 'ignore_order' do
    let(:expected) do
      { 'data' => [record(type: 'a', attributes: migraine), record(type: 'a', attributes: ptsd)] }
    end
    let(:actual) do
      { 'data' => [record(type: 'a', attributes: ptsd), record(type: 'a', attributes: migraine)] }
    end

    context 'when order is significant' do
      it 'is not equivalent, but reports the difference as an ordering one' do
        expect(comparison.equivalent?).to be false
        expect(comparison.ordering_differs?).to be true
      end
    end

    context 'when order is ignored' do
      let(:options) { { ignore_order: true } }

      it 'is equivalent, and still reports the reordering' do
        expect(comparison.equivalent?).to be true
        expect(comparison.ordering_differs?).to be true
      end
    end

    context 'when the records genuinely differ' do
      let(:actual) { { 'data' => [record(type: 'a', attributes: ptsd)] } }
      let(:options) { { ignore_order: true } }

      it 'is not equivalent, and is not an ordering difference' do
        expect(comparison.equivalent?).to be false
        expect(comparison.ordering_differs?).to be false
      end
    end

    context 'when an array nested inside a record is reordered' do
      let(:expected) { { 'data' => [{ 'chain' => [{ 'n' => 1 }, { 'n' => 2 }] }] } }
      let(:actual) { { 'data' => [{ 'chain' => [{ 'n' => 2 }, { 'n' => 1 }] }] } }
      let(:options) { { ignore_order: true } }

      # ignore_order applies to the collection, not to arrays nested inside a record.
      it 'is not equivalent' do
        expect(comparison.equivalent?).to be false
      end
    end
  end

  describe 'collection_key' do
    let(:expected) { { 'items' => [record(type: 'a', attributes: migraine)] } }
    let(:actual) { { 'items' => [record(type: 'b', attributes: migraine)] } }
    let(:options) { { ignored_keys: %w[type], collection_key: 'items' } }

    it 'compares the named member' do
      expect(comparison.equivalent?).to be true
      expect(comparison.expected_count).to be 1
      expect(comparison.actual_count).to be 1
    end
  end

  describe 'members other than the collection' do
    let(:expected) { { 'data' => [record(type: 'a', attributes: migraine)] } }

    context 'when one side has a member the other lacks' do
      let(:actual) { expected.deep_dup.merge('meta' => { 'total' => 1 }) }

      it 'is not equivalent, even though the records agree' do
        expect(comparison.equivalent?).to be false
      end
    end

    context 'when a shared member differs in value' do
      let(:expected) { { 'data' => [], 'meta' => { 'total' => 1 } } }
      let(:actual) { { 'data' => [], 'meta' => { 'total' => 2 } } }

      it 'is not equivalent' do
        expect(comparison.equivalent?).to be false
      end
    end

    context 'when a shared member agrees' do
      let(:expected) { { 'data' => [], 'meta' => { 'total' => 0 } } }
      let(:actual) { { 'data' => [], 'meta' => { 'total' => 0 } } }

      it 'is equivalent' do
        expect(comparison.equivalent?).to be true
      end
    end
  end

  describe 'malformed bodies' do
    context 'when the collection member is missing or not an array' do
      let(:expected) { {} }
      let(:actual) { { 'data' => nil } }

      it 'counts no records rather than raising' do
        expect(comparison.expected_count).to be 0
        expect(comparison.actual_count).to be 0
      end

      it 'is not equivalent, because the bodies are shaped differently' do
        expect(comparison.equivalent?).to be false
      end
    end

    context 'when neither body is a hash' do
      let(:expected) { 'oops' }
      let(:actual) { 'oops' }

      it 'falls back to comparing them directly' do
        expect(comparison.equivalent?).to be true
      end
    end
  end

  describe '#to_h' do
    let(:expected) do
      { 'data' => [record(type: 'a', attributes: migraine.merge('timely' => false)),
                   record(type: 'a', attributes: ptsd)] }
    end
    let(:actual) { { 'data' => [record(type: 'b', attributes: migraine)] } }
    let(:options) { { ignored_keys: %w[type], ignore_order: true } }

    it 'reports counts, differing key names, and the ordering flag' do
      expect(comparison.to_h).to eq(
        expected_count: 2,
        actual_count: 1,
        differing_keys: ['timely'],
        ordering_differs: false
      )
    end

    # The whole point of the class: its output can be logged without redaction.
    it 'exposes no value from either body' do
      report = comparison.to_h.to_s
      %w[Migraine PTSD 2020-02-01 2020-05-01].each do |value|
        expect(report).not_to include value
      end
    end
  end
end
