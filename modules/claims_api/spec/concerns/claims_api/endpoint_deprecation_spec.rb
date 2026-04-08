# frozen_string_literal: true

require 'rails_helper'

describe ClaimsApi::EndpointDeprecation do
  subject { fake_endpoint_deprecation_controller_class.new }

  let(:fake_endpoint_deprecation_controller_class) do
    Class.new do
      include ClaimsApi::EndpointDeprecation
    end
  end

  context "adding a 'Deprecation' header to the response" do
    context "when a 'Response' object is not provided" do
      it "An 'ArgumentError' is raised" do
        expect { subject.add_deprecation_headers_to_response }.to raise_error(ArgumentError)
      end
    end

    context "when a 'Response' object is provided" do
      it "adds a 'Deprecation' header to the response" do
        response = ActionDispatch::Response.new
        subject.add_deprecation_headers_to_response(response:)
        expect(response.headers).to have_key('Deprecation')
        expect(response.headers['Deprecation']).to eq('true')
      end
    end
  end

  context "adding a 'Link' header to the response" do
    context "when a 'Link' is not provided" do
      it "A 'Link' header is not added to the response" do
        response = ActionDispatch::Response.new
        subject.add_deprecation_headers_to_response(response:)
        expect(response.headers).not_to have_key('Link')
      end
    end

    context "when a 'Link' is provided" do
      it "A 'Link' header is added to the response" do
        response = ActionDispatch::Response.new
        subject.add_deprecation_headers_to_response(response:, link: 'Hello World')
        expect(response.headers).to have_key('Link')
        expect(response.headers['Link']).to eq('Hello World')
      end
    end
  end
end
