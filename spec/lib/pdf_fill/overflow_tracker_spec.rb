# frozen_string_literal: true

require 'rails_helper'
require 'pdf_fill/overflow_tracker'
require 'pdf_fill/hash_converter'

class TestClaim < SavedClaim
  FORM = 'Form-XYZ'
end

class TestForm < PdfFill::Forms::FormBase
  KEY = {
    'store' => {
      limit: 20,
      key: 'store_name'
    },
    'owner' => {
      'first' => {
        limit: 10,
        key: 'first_name'
      },
      'last' => {
        limit: 10,
        key: 'last_name'
      }
    },
    'fruit' => {
      limit: 2,
      item_label: 'Available Fruit',
      'name' => {
        limit: 10,
        key: "fruit_name[#{PdfFill::HashConverter::ITERATOR}]"
      },
      'inStock' => {
        key: "in_stock[#{PdfFill::HashConverter::ITERATOR}]"
      },
      'nutrition' => {
        'sugar' => {
          limit: 3,
          key: "fruit_nutrition_sugar[#{PdfFill::HashConverter::ITERATOR}]"
        },
        'calories' => {
          limit: 3,
          key: "fruit_nutrition_calories[#{PdfFill::HashConverter::ITERATOR}]"
        }
      }
    }
  }.freeze

  def merge_fields
    @form_data
  end
end

Rspec.describe PdfFill::OverflowTracker do
  subject(:tracker) { described_class.new(claim) }

  let(:claim) { TestClaim.new(form: form.to_json) }
  let(:form) { {} }

  before do
    allow(StatsD).to receive(:increment)
    allow(Rails.logger).to receive(:error)
    allow(PdfFill::Filler::FORM_CLASSES).to receive(:[]).with(claim.form_id).and_return(TestForm)
  end

  describe '#initialize' do
    it 'sets claim' do
      expect(tracker.instance_variable_get(:@claim)).to eq(claim)
    end

    it 'grabs form class from claim form id' do
      expect(tracker.instance_variable_get(:@form_class)).to eq(TestForm)
    end

    it 'throws argument error if no associated form with claim' do
      allow(PdfFill::Filler::FORM_CLASSES).to receive(:[]).with(claim.form_id).and_return(nil)
      expect { tracker }.to raise_error(ArgumentError, 'No form class associated with claim')
    end
  end

  describe '#track_pdf_overflow' do
    before { allow(StatsD).to receive(:increment) }

    it 'returns false if filename argument nil' do
      expect(tracker.track_pdf_overflow(nil)).to be false
      expect(StatsD).not_to have_received(:increment)
    end

    it 'returns false if filename does not end with _final.pdf' do
      expect(tracker.track_pdf_overflow('form-xyz_1.pdf')).to be false
      expect(StatsD).not_to have_received(:increment)
    end

    it 'increments metric and returns true if filename ends with _final.pdf' do
      expect(tracker.track_pdf_overflow('form-xyz_1_final.pdf')).to be true
      expect(StatsD).to have_received(:increment).with(
        'saved_claim.pdf.overflow', tags: ["form_id:#{claim.form_id}", "doctype:#{claim.document_type}"]
      ).once
    end

    it 'logs error when failure encountered' do
      allow(claim).to receive(:id).and_return(1)
      allow(Rails.logger).to receive(:error)
      tracker.track_pdf_overflow(123)
      expect(Rails.logger).to have_received(:error).with(
        'FORM-XYZ: Failure in track_pdf_overflow', saved_claim_id: claim.id, error: instance_of(NoMethodError)
      )
    end
  end

  describe '#track_pdf_overflow_by_field' do
    let(:form) do
      {
        'store' => '#1 Grocery Store',
        'owner' => {
          'first' => 'Sandy',
          'last' => 'Squirrel'
        },
        'fruit' => [
          {
            'name' => 'apple',
            'inStock' => true,
            'nutrition' => {
              'sugar' => 500,
              'calories' => 500
            }
          },
          {
            'name' => 'banana',
            'inStock' => false,
            'nutrition' => {
              'sugar' => 300,
              'calories' => 300
            }
          }
        ]
      }
    end

    before { allow(TestForm).to receive(:new).and_call_original }

    def tags(key)
      { tags: ["form_id:#{claim.form_id}", key] }
    end

    def set_form
      yield if block_given?
      claim.form = claim.parsed_form.to_json
    end

    context 'when error encountered' do
      it 'logs error' do
        allow(claim).to receive(:id).and_return(1)
        hide_const('TestForm::KEY')
        tracker.track_pdf_overflow_by_field
        expect(Rails.logger).to have_received(:error).with(
          "#{claim.form_id}: Failure in track_pdf_overflow_by_field",
          saved_claim_id: claim.id,
          error: an_instance_of(NameError)
        )
      end
    end

    context 'when no field or array overflow' do
      it 'does not track any metrics' do
        tracker.track_pdf_overflow_by_field
        expect(StatsD).not_to have_received(:increment)
      end
    end

    context 'when overflow of top-level field' do
      it 'tracks metric for field' do
        set_form { claim.parsed_form['store'] = 'The Best Grocery Store' }
        tracker.track_pdf_overflow_by_field
        expect(StatsD).to have_received(:increment).with("#{described_class::STATSD_KEY_PREFIX}.field",
                                                         tags('field:store_name')).once
      end
    end

    context 'when overflow of nested field' do
      it 'tracks metric for field' do
        set_form { claim.parsed_form['owner']['first'] = 'Aristophanes' }
        tracker.track_pdf_overflow_by_field
        expect(StatsD).to have_received(:increment).with("#{described_class::STATSD_KEY_PREFIX}.field",
                                                         tags('field:first_name')).once
      end
    end

    context 'when overflow of top-level field inside array' do
      it 'strips iterator and tracks metric for field' do
        set_form { claim.parsed_form['fruit'].first['name'] = 'huckleberry' }
        tracker.track_pdf_overflow_by_field
        expect(StatsD).to have_received(:increment).with("#{described_class::STATSD_KEY_PREFIX}.field",
                                                         tags('field:fruit_name')).once
      end
    end

    context 'when overflow of nested field inside array' do
      it 'tracks metric for field' do
        set_form { claim.parsed_form['fruit'].first['nutrition']['sugar'] = 1000 }
        tracker.track_pdf_overflow_by_field
        expect(StatsD).to have_received(:increment).with("#{described_class::STATSD_KEY_PREFIX}.field",
                                                         tags('field:fruit_nutrition_sugar')).once
      end
    end

    context 'when overflow of same field across different items in array' do
      it 'tracks metric for each occurence of field overflow' do
        set_form do
          claim.parsed_form['fruit'].first['name'] = 'huckleberry'
          claim.parsed_form['fruit'].second['name'] = 'honeydew melon'
        end
        tracker.track_pdf_overflow_by_field
        expect(StatsD).to have_received(:increment).with("#{described_class::STATSD_KEY_PREFIX}.field",
                                                         tags('field:fruit_name')).twice
      end
    end

    context 'when overflow of array' do
      it 'parametrizes item label and tracks metric for array' do
        new_fruit = {
          'name' => 'cantelope',
          'inStock' => true,
          'nutrition' => {
            'sugar' => 200,
            'calories' => 200
          }
        }
        set_form { claim.parsed_form['fruit'] << new_fruit }
        tracker.track_pdf_overflow_by_field
        expect(StatsD).to have_received(:increment).with("#{described_class::STATSD_KEY_PREFIX}.array",
                                                         tags('array:available_fruit')).once
      end
    end

    context 'when kitchen sink' do
      it 'tracks metrics across the board' do
        new_fruit = {
          'name' => 'huckleberry',
          'inStock' => true,
          'nutrition' => {
            'sugar' => 200,
            'calories' => 2000
          }
        }
        set_form do
          claim.parsed_form['fruit'].first['nutrition']['calories'] = 3000
          claim.parsed_form.deep_merge!(
            {
              'store' => 'The Most Wonderful Grocery',
              'owner' => { 'last' => 'Squarepants' },
              'fruit' => [*claim.parsed_form['fruit'], new_fruit]
            }
          )
        end
        tracker.track_pdf_overflow_by_field
        expect(StatsD).to have_received(:increment).with("#{described_class::STATSD_KEY_PREFIX}.field",
                                                         tags('field:store_name')).once
        expect(StatsD).to have_received(:increment).with("#{described_class::STATSD_KEY_PREFIX}.field",
                                                         tags('field:last_name')).once
        expect(StatsD).to have_received(:increment).with("#{described_class::STATSD_KEY_PREFIX}.array",
                                                         tags('array:available_fruit')).once
        expect(StatsD).to have_received(:increment).with("#{described_class::STATSD_KEY_PREFIX}.field",
                                                         tags('field:fruit_name')).once
        expect(StatsD).to have_received(:increment).with("#{described_class::STATSD_KEY_PREFIX}.field",
                                                         tags('field:fruit_nutrition_calories')).twice
      end
    end

    context 'when necessary key missing from field config' do
      it 'tracks unknown metric' do
        bad_key = TestForm::KEY.deep_dup
        bad_key['store'].delete(:key)
        stub_const('TestForm::KEY', bad_key)
        set_form { claim.parsed_form['store'] = 'The Supermarket to End All Supermarkets' }
        tracker.track_pdf_overflow_by_field
        expect(StatsD).to have_received(:increment).with("#{described_class::STATSD_KEY_PREFIX}.field",
                                                         tags('field:unknown')).once
      end
    end

    context 'when necessary label missing from array config' do
      it 'tracks unknown metric' do
        bad_key = TestForm::KEY.deep_dup
        bad_key['fruit'].delete(:item_label)
        stub_const('TestForm::KEY', bad_key)
        new_fruit = {
          'name' => 'cantelope',
          'inStock' => true,
          'nutrition' => {
            'sugar' => 200,
            'calories' => 200
          }
        }
        set_form { claim.parsed_form['fruit'] << new_fruit }
        tracker.track_pdf_overflow_by_field
        expect(StatsD).to have_received(:increment).with("#{described_class::STATSD_KEY_PREFIX}.array",
                                                         tags('array:unknown')).once
      end
    end
  end
end
