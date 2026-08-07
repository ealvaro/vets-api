# frozen_string_literal: true

require 'rails_helper'
require 'pdf_fill/concerns/field_overflow_monitoring'
require 'pdf_fill/hash_converter'

class TestClaim < SavedClaim
  include PdfFill::Concerns::FieldOverflowMonitoring

  FORM = 'Form-XYZ'
end

class TestForm < PdfFill::Forms::FormBase
  FORM_ID = TestClaim::FORM

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

Rspec.describe PdfFill::Concerns::FieldOverflowMonitoring do
  describe '#track_pdf_overflow_by_field' do
    subject(:track_overflow) { claim.send(:track_pdf_overflow_by_field, TestForm) }

    let(:claim) { TestClaim.new(form: form.to_json) }
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

    before do
      allow(StatsD).to receive(:increment)
      allow(TestForm).to receive(:new).and_call_original
      allow(Rails.logger).to receive(:error)
    end

    def tags(key)
      { tags: ["form_id:#{claim.form_id}", key] }
    end

    it 'accepts form_class as optional argument' do
      track_overflow
      expect(TestForm).to have_received(:new).with(claim.parsed_form)
    end

    it 'grabs form class from form id if no form_class argument' do
      allow(PdfFill::Filler::FORM_CLASSES).to receive(:[]).with(claim.form_id).and_return(TestForm)
      claim.send(:track_pdf_overflow_by_field)
      expect(TestForm).to have_received(:new).with(claim.parsed_form)
    end

    it 'returns early if form class cannot be found' do
      expect(claim.send(:track_pdf_overflow_by_field)).to be_nil
    end

    context 'when error encountered' do
      it 'logs error' do
        hide_const('TestForm::KEY')
        track_overflow
        expect(Rails.logger).to have_received(:error).with(
          "#{claim.form_id}: Failure in track_pdf_overflow_by_field. #{TestClaim.name}: uninitialized constant TestForm::KEY"
        )
      end
    end

    context 'when no field or array overflow' do
      it 'does not track any metrics' do
        track_overflow
        expect(StatsD).not_to have_received(:increment)
      end
    end

    context 'when overflow of top-level field' do
      it 'tracks metric for field' do
        form['store'] = 'The Best Grocery Store'
        track_overflow
        expect(StatsD).to have_received(:increment).with("#{described_class::STATSD_KEY_PREFIX}.field",
                                                         tags('field:store_name')).once
      end
    end

    context 'when overflow of nested field' do
      it 'tracks metric for field' do
        form['owner']['first'] = 'Aristophanes'
        track_overflow
        expect(StatsD).to have_received(:increment).with("#{described_class::STATSD_KEY_PREFIX}.field",
                                                         tags('field:first_name')).once
      end
    end

    context 'when overflow of top-level field inside array' do
      it 'strips iterator and tracks metric for field' do
        form['fruit'].first['name'] = 'huckleberry'
        track_overflow
        expect(StatsD).to have_received(:increment).with("#{described_class::STATSD_KEY_PREFIX}.field",
                                                         tags('field:fruit_name')).once
      end
    end

    context 'when overflow of nested field inside array' do
      it 'tracks metric for field' do
        form['fruit'].first['nutrition']['sugar'] = 1000
        track_overflow
        expect(StatsD).to have_received(:increment).with("#{described_class::STATSD_KEY_PREFIX}.field",
                                                         tags('field:fruit_nutrition_sugar')).once
      end
    end

    context 'when overflow of same field across different items in array' do
      it 'tracks metric for each occurence of field overflow' do
        form['fruit'].first['name'] = 'huckleberry'
        form['fruit'].second['name'] = 'honeydew melon'
        track_overflow
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
        form['fruit'] << new_fruit
        track_overflow
        expect(StatsD).to have_received(:increment).with("#{described_class::STATSD_KEY_PREFIX}.array",
                                                         tags('array:available_fruit')).once
      end
    end

    context 'when kitchen sink' do
      it 'tracks metrics across the board' do
        form['fruit'].first['nutrition']['calories'] = 3000
        new_fruit = {
          'name' => 'huckleberry',
          'inStock' => true,
          'nutrition' => {
            'sugar' => 200,
            'calories' => 2000
          }
        }
        form.deep_merge!(
          {
            'store' => 'The Most Wonderful Grocery',
            'owner' => { 'last' => 'Squarepants' },
            'fruit' => [*form['fruit'], new_fruit]
          }
        )
        track_overflow
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
        form['store'] = 'The Supermarket to End All Supermarkets'
        track_overflow
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
        form['fruit'] << new_fruit
        track_overflow
        expect(StatsD).to have_received(:increment).with("#{described_class::STATSD_KEY_PREFIX}.array",
                                                         tags('array:unknown')).once
      end
    end
  end
end
