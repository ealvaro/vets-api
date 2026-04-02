# frozen_string_literal: true

require 'rails_helper'
require 'unified_health_data/reference_range_formatter'

RSpec.describe UnifiedHealthData::ReferenceRangeFormatter do
  describe '.format' do
    it 'returns empty string when referenceRange is nil' do
      obs = {}
      result = described_class.format(obs)
      expect(result).to eq('')
    end

    it 'returns text directly when available' do
      obs = {
        'referenceRange' => [
          { 'text' => '70-110 mg/dL' },
          { 'text' => '<=3' }
        ]
      }
      result = described_class.format(obs)
      expect(result).to eq('70-110 mg/dL, <=3')
    end

    it 'formats low-high values correctly' do
      obs = {
        'referenceRange' => [
          {
            'low' => { 'value' => 13.5, 'unit' => 'g/dL' },
            'high' => { 'value' => 18.0, 'unit' => 'g/dL' }
          }
        ]
      }
      result = described_class.format(obs)
      expect(result).to eq('13.5 - 18.0 g/dL')
    end

    it 'formats low-only values correctly' do
      obs = {
        'referenceRange' => [
          {
            'low' => { 'value' => 94 }
          }
        ]
      }
      result = described_class.format(obs)
      expect(result).to eq('>= 94')
    end

    it 'formats high-only values correctly' do
      obs = {
        'referenceRange' => [
          {
            'high' => { 'value' => 44 }
          }
        ]
      }
      result = described_class.format(obs)
      expect(result).to eq('<= 44')
    end

    it 'handles empty low/high values gracefully' do
      obs = {
        'referenceRange' => [
          {
            'low' => {},
            'high' => {}
          }
        ]
      }
      result = described_class.format(obs)
      expect(result).to eq('')
    end

    it 'handles mixed formats correctly' do
      obs = {
        'referenceRange' => [
          { 'text' => 'Normal: <100 mg/dL' },
          {
            'low' => { 'value' => 5.0 },
            'high' => { 'value' => 7.5 }
          },
          {
            'low' => { 'value' => 4.0 }
          }
        ]
      }
      result = described_class.format(obs)
      expect(result).to eq('Normal: <100 mg/dL, 5.0 - 7.5, >= 4.0')
    end

    it 'gracefully handles malformed reference range data' do
      # Test with various types of malformed data
      test_cases = [
        # Nil reference range
        { 'referenceRange' => nil },

        # Empty array
        { 'referenceRange' => [] },

        # Non-array reference range
        { 'referenceRange' => 'not an array' },

        # Array with non-hash elements
        { 'referenceRange' => ['string', 123, nil] }
      ]

      test_cases.each do |test_case|
        result = described_class.format(test_case)
        expect(result).to eq(''), "Failed for test case: #{test_case.inspect}"
      end
    end

    it 'handles type field that is not a hash' do
      test_case = { 'referenceRange' => [{ 'low' => { 'value' => 10 }, 'type' => 'not a hash' }] }
      result = described_class.format(test_case)
      expect(result).to eq('>= 10')
    end

    it 'handles missing low and high fields' do
      test_case = { 'referenceRange' => [{ 'other_field' => 'some value' }] }
      result = described_class.format(test_case)
      expect(result).to eq('')
    end

    it 'handles non-numeric values in low/high' do
      test_case = { 'referenceRange' => [{ 'low' => { 'value' => 'not a number' },
                                           'high' => { 'value' => 'also not a number' } }] }
      result = described_class.format(test_case)
      expect(result).to eq('')
    end

    it 'handles malformed nested structures' do
      test_case = { 'referenceRange' => [{ 'low' => 'not a hash', 'high' => 123 }] }
      result = described_class.format(test_case)
      expect(result).to eq('')
    end

    it 'handles low value with no unit and type with no text' do
      test_case = { 'referenceRange' => [{ 'low' => { 'value' => 5 }, 'type' => { 'coding' => [{}] } }] }
      result = described_class.format(test_case)
      expect(result).to eq('>= 5')
    end

    it 'handles multiple reference ranges with different types' do
      obs = {
        'referenceRange' => [
          {
            'low' => { 'value' => 14, 'unit' => 'mL' },
            'high' => { 'value' => 20, 'unit' => 'mL' },
            'type' => {
              'coding' => [
                {
                  'system' => 'http://terminology.hl7.org/CodeSystem/referencerange-meaning',
                  'code' => 'normal',
                  'display' => 'Normal Range'
                }
              ],
              'text' => 'Normal Range'
            }
          },
          {
            'low' => { 'value' => 1000, 'unit' => 'mg/dL' },
            'high' => { 'value' => 2000, 'unit' => 'mg/dL' },
            'type' => {
              'coding' => [
                {
                  'system' => 'http://terminology.hl7.org/CodeSystem/referencerange-meaning',
                  'code' => 'critical',
                  'display' => 'Critical Range'
                }
              ],
              'text' => 'Critical Range'
            }
          }
        ]
      }
      result = described_class.format(obs)
      expect(result).to eq('Normal Range: 14 - 20 mL, Critical Range: 1000 - 2000 mg/dL')
    end

    it 'handles multiple high-only reference ranges with different types' do
      obs = {
        'referenceRange' => [
          {
            'high' => { 'value' => 20 },
            'type' => {
              'coding' => [
                {
                  'system' => 'http://terminology.hl7.org/CodeSystem/referencerange-meaning',
                  'code' => 'normal',
                  'display' => 'Normal Range'
                }
              ],
              'text' => 'Normal Range'
            }
          },
          {
            'high' => { 'value' => 2000 },
            'type' => {
              'coding' => [
                {
                  'system' => 'http://terminology.hl7.org/CodeSystem/referencerange-meaning',
                  'code' => 'critical',
                  'display' => 'Critical Range'
                }
              ],
              'text' => 'Critical Range'
            }
          }
        ]
      }
      result = described_class.format(obs)
      expect(result).to eq('Normal Range: <= 20, Critical Range: <= 2000')
    end

    context 'when reference range component has no unit but valueQuantity does' do
      it 'falls back to valueQuantity unit for low-high range' do
        obs = {
          'valueQuantity' => { 'value' => 5, 'unit' => 'mg/dL' },
          'referenceRange' => [
            {
              'low' => { 'value' => 3.5 },
              'high' => { 'value' => 10.0 }
            }
          ]
        }
        result = described_class.format(obs)
        expect(result).to eq('3.5 - 10.0 mg/dL')
      end

      it 'falls back to valueQuantity unit for low-only range' do
        obs = {
          'valueQuantity' => { 'value' => 100, 'unit' => 'mL' },
          'referenceRange' => [
            {
              'low' => { 'value' => 50 }
            }
          ]
        }
        result = described_class.format(obs)
        expect(result).to eq('>= 50 mL')
      end

      it 'falls back to valueQuantity unit for high-only range' do
        obs = {
          'valueQuantity' => { 'value' => 8, 'unit' => 'mmol/L' },
          'referenceRange' => [
            {
              'high' => { 'value' => 10 }
            }
          ]
        }
        result = described_class.format(obs)
        expect(result).to eq('<= 10 mmol/L')
      end

      it 'prefers reference range unit over valueQuantity unit' do
        obs = {
          'valueQuantity' => { 'value' => 5, 'unit' => 'mg/dL' },
          'referenceRange' => [
            {
              'low' => { 'value' => 3.5, 'unit' => 'g/dL' },
              'high' => { 'value' => 10.0, 'unit' => 'g/dL' }
            }
          ]
        }
        result = described_class.format(obs)
        expect(result).to eq('3.5 - 10.0 g/dL')
      end

      it 'does not use valueQuantity unit when it is nil' do
        obs = {
          'valueQuantity' => { 'value' => 5 },
          'referenceRange' => [
            {
              'low' => { 'value' => 3.5 },
              'high' => { 'value' => 10.0 }
            }
          ]
        }
        result = described_class.format(obs)
        expect(result).to eq('3.5 - 10.0')
      end

      it 'does not use valueQuantity unit when valueQuantity is absent' do
        obs = {
          'referenceRange' => [
            {
              'low' => { 'value' => 3.5 },
              'high' => { 'value' => 10.0 }
            }
          ]
        }
        result = described_class.format(obs)
        expect(result).to eq('3.5 - 10.0')
      end
    end

    context 'when unit is extracted from valueString text' do
      it 'parses unit from valueString like "99 mg/dL"' do
        obs = {
          'valueString' => '99 mg/dL',
          'referenceRange' => [
            {
              'low' => { 'value' => 70 },
              'high' => { 'value' => 110 }
            }
          ]
        }
        result = described_class.format(obs)
        expect(result).to eq('70 - 110 mg/dL')
      end

      it 'parses multi-word unit from valueString like "5.0 10*3/uL"' do
        obs = {
          'valueString' => '5.0 10*3/uL',
          'referenceRange' => [
            {
              'low' => { 'value' => 4.0 },
              'high' => { 'value' => 11.0 }
            }
          ]
        }
        result = described_class.format(obs)
        expect(result).to eq('4.0 - 11.0 10*3/uL')
      end

      it 'handles valueString with comparator like ">10 mg/dL"' do
        obs = {
          'valueString' => '>10 mg/dL',
          'referenceRange' => [
            {
              'high' => { 'value' => 20 }
            }
          ]
        }
        result = described_class.format(obs)
        expect(result).to eq('<= 20 mg/dL')
      end

      it 'does not extract unit from valueString with no spaces' do
        obs = {
          'valueString' => 'POSITIVE',
          'referenceRange' => [
            {
              'low' => { 'value' => 0 },
              'high' => { 'value' => 1 }
            }
          ]
        }
        result = described_class.format(obs)
        expect(result).to eq('0 - 1')
      end

      it 'does not extract unit from empty valueString' do
        obs = {
          'valueString' => '',
          'referenceRange' => [
            {
              'low' => { 'value' => 3.5 },
              'high' => { 'value' => 10.0 }
            }
          ]
        }
        result = described_class.format(obs)
        expect(result).to eq('3.5 - 10.0')
      end

      it 'does not extract unit from whitespace-only valueString' do
        obs = {
          'valueString' => '   ',
          'referenceRange' => [
            {
              'low' => { 'value' => 3.5 },
              'high' => { 'value' => 10.0 }
            }
          ]
        }
        result = described_class.format(obs)
        expect(result).to eq('3.5 - 10.0')
      end

      it 'prefers valueQuantity.unit over valueString parsing' do
        obs = {
          'valueQuantity' => { 'value' => 99, 'unit' => 'mg/dL' },
          'valueString' => '99 mmol/L',
          'referenceRange' => [
            {
              'low' => { 'value' => 70 },
              'high' => { 'value' => 110 }
            }
          ]
        }
        result = described_class.format(obs)
        expect(result).to eq('70 - 110 mg/dL')
      end

      it 'falls through to valueString when valueQuantity has no unit' do
        obs = {
          'valueQuantity' => { 'value' => 99 },
          'valueString' => '99 mmol/L',
          'referenceRange' => [
            {
              'low' => { 'value' => 70 },
              'high' => { 'value' => 110 }
            }
          ]
        }
        result = described_class.format(obs)
        expect(result).to eq('70 - 110 mmol/L')
      end
    end

    context 'when valueQuantity.value is a string containing a unit (malformed data)' do
      it 'extracts unit from numeric string-typed valueQuantity value' do
        obs = {
          'valueQuantity' => { 'value' => '99 mg/dL' },
          'referenceRange' => [
            {
              'low' => { 'value' => 70 },
              'high' => { 'value' => 110 }
            }
          ]
        }
        result = described_class.format(obs)
        expect(result).to eq('70 - 110 mg/dL')
      end

      it 'extracts unit from alpha string-typed valueQuantity value' do
        obs = {
          'valueQuantity' => { 'value' => 'Negative mIU/mL' },
          'referenceRange' => [
            {
              'low' => { 'value' => 0.3 },
              'high' => { 'value' => 5.0 }
            }
          ]
        }
        result = described_class.format(obs)
        expect(result).to eq('0.3 - 5.0 mIU/mL')
      end
    end

    context 'when reference range has text but is missing units' do
      it 'appends unit to numeric text like "<=3" when observation has a unit' do
        obs = {
          'valueQuantity' => { 'value' => 2.5, 'unit' => 'mg/dL' },
          'referenceRange' => [
            { 'text' => '<=3' }
          ]
        }
        result = described_class.format(obs)
        expect(result).to eq('<=3 mg/dL')
      end

      it 'appends unit to range text like "70-110" when observation has a unit' do
        obs = {
          'valueQuantity' => { 'value' => 95, 'unit' => 'mg/dL' },
          'referenceRange' => [
            { 'text' => '70-110' }
          ]
        }
        result = described_class.format(obs)
        expect(result).to eq('70-110 mg/dL')
      end

      it 'does not duplicate unit when text already ends with it' do
        obs = {
          'valueQuantity' => { 'value' => 95, 'unit' => 'mg/dL' },
          'referenceRange' => [
            { 'text' => '70-110 mg/dL' }
          ]
        }
        result = described_class.format(obs)
        expect(result).to eq('70-110 mg/dL')
      end

      it 'does not append unit to purely alphabetic text like "YELLOW"' do
        obs = {
          'valueQuantity' => { 'value' => 5, 'unit' => 'units' },
          'referenceRange' => [
            { 'text' => 'YELLOW' }
          ]
        }
        result = described_class.format(obs)
        expect(result).to eq('YELLOW')
      end

      it 'does not append unit to descriptive text like "Normal"' do
        obs = {
          'valueQuantity' => { 'value' => 5, 'unit' => 'mg/dL' },
          'referenceRange' => [
            { 'text' => 'Normal' }
          ]
        }
        result = described_class.format(obs)
        expect(result).to eq('Normal')
      end

      it 'appends unit to text with comparator like ">5"' do
        obs = {
          'valueQuantity' => { 'value' => 8, 'unit' => 'mmol/L' },
          'referenceRange' => [
            { 'text' => '>5' }
          ]
        }
        result = described_class.format(obs)
        expect(result).to eq('>5 mmol/L')
      end

      it 'appends unit to descriptive text containing digits like "Normal: <100"' do
        obs = {
          'valueQuantity' => { 'value' => 80, 'unit' => 'mg/dL' },
          'referenceRange' => [
            { 'text' => 'Normal: <100' }
          ]
        }
        result = described_class.format(obs)
        expect(result).to eq('Normal: <100 mg/dL')
      end

      it 'does not append unit when observation has no unit available' do
        obs = {
          'referenceRange' => [
            { 'text' => '<=3' }
          ]
        }
        result = described_class.format(obs)
        expect(result).to eq('<=3')
      end

      it 'handles multiple text ranges, appending unit only where needed' do
        obs = {
          'valueQuantity' => { 'value' => 95, 'unit' => 'mg/dL' },
          'referenceRange' => [
            { 'text' => '70-110 mg/dL' },
            { 'text' => '<=3' }
          ]
        }
        result = described_class.format(obs)
        expect(result).to eq('70-110 mg/dL, <=3 mg/dL')
      end

      it 'appends unit parsed from valueString to text range' do
        obs = {
          'valueString' => '99 mg/dL',
          'referenceRange' => [
            { 'text' => '70-110' }
          ]
        }
        result = described_class.format(obs)
        expect(result).to eq('70-110 mg/dL')
      end
    end
  end
end
