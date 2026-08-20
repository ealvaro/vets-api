# frozen_string_literal: true

require 'rails_helper'
require 'rx/ndc_validator'

RSpec.describe Rx::NdcValidator do
  let(:test_class) { Class.new { include Rx::NdcValidator } }
  let(:validator) { test_class.new }

  describe '#valid_ndc_format?' do
    it 'accepts valid NDC formats' do
      %w[1234567890 12345678901 00013-2646-81 00013-264-681].each do |ndc|
        expect(validator.valid_ndc_format?(ndc)).to be(true), "Expected #{ndc} to be valid"
      end
    end

    it 'rejects invalid NDC formats' do
      invalid_ndcs = [
        nil, '', '123456789', '123456789012',
        '../../etc/passwd', '12345/67890', '12345;drop',
        '..%2F..%2Fetc', ['12345678901'], { ndc: '12345678901' }
      ]
      invalid_ndcs.each do |ndc|
        expect(validator.valid_ndc_format?(ndc)).to be(false), "Expected #{ndc.inspect} to be invalid"
      end
    end
  end

  describe '#validate_ndc_format!' do
    it 'does not raise for valid NDC' do
      expect { validator.validate_ndc_format!('12345678901') }.not_to raise_error
    end

    it 'raises InvalidNdcFormatError and logs warning for invalid NDC' do
      allow(Rails.logger).to receive(:warn)

      expect { validator.validate_ndc_format!('../../etc/passwd') }
        .to raise_error(Rx::NdcValidator::InvalidNdcFormatError, 'Invalid NDC format')

      expect(Rails.logger).to have_received(:warn).with(
        'Rx::NdcValidator: Invalid NDC format detected',
        { ndc: '../../etc/passwd' }
      )
    end
  end
end
