# frozen_string_literal: true

require 'rails_helper'

describe ClaimsApi::V3::JsonFormatValidation do
  let(:host_class) do
    Class.new do
      include ClaimsApi::V3::JsonFormatValidation

      attr_accessor :request
      attr_reader :rendered_options

      def render(**options)
        @rendered_options = options
      end
    end
  end

  let(:instance) { host_class.new }

  it 'renders 422 with an Unprocessable entity error envelope when the request body is not valid JSON' do
    instance.request = instance_double(ActionDispatch::Request, body: StringIO.new('not-json'))

    instance.validate_json_format

    expect(instance.rendered_options[:status]).to eq('422')
    errors = instance.rendered_options[:json][:errors]
    expect(errors).to be_an(Array)
    expect(errors.first[:title]).to eq('Unprocessable entity')
  end

  it 'reads the request body only once, so the rescue path does not read an already-consumed IO' do
    body = StringIO.new('not-json')
    instance.request = instance_double(ActionDispatch::Request, body:)

    expect(body).to receive(:read).once.and_call_original

    instance.validate_json_format
  end
end
