# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CoeClaimFormValidation::FullName do
  subject(:host) { full_name_host.new }

  let(:full_name_host) do
    Class.new do
      include ActiveModel::Model
      include ActiveModel::Validations

      attr_accessor :parsed_form

      include CoeClaimFormValidation::FullName
    end
  end

  describe '#validate_full_name' do
    it 'returns early when fullName is not a hash' do
      host.parsed_form = { 'fullName' => 'nope' }
      host.send(:validate_full_name)
      expect(host.errors).to be_empty
    end

    it 'validates required and optional name parts' do
      host.parsed_form = {
        'fullName' => {
          'first' => 'Jane',
          'last' => 'Doe',
          'middle' => 'Q',
          'suffix' => 'Jr'
        }
      }
      host.send(:validate_full_name)
      expect(host.errors).to be_empty
    end

    it 'rejects a required part that is not a string' do
      host.parsed_form = { 'fullName' => { 'first' => 1, 'last' => 'Doe' } }
      host.send(:validate_full_name)
      expect(host.errors['/fullName/first']).to include('must be a string')
    end

    it 'rejects an optional part that exceeds the max length' do
      host.parsed_form = { 'fullName' => { 'first' => 'Jane', 'last' => 'Doe', 'suffix' => 'x' * 31 } }
      host.send(:validate_full_name)
      expect(host.errors['/fullName/suffix']).to include('must be 30 characters or less')
    end
  end
end
