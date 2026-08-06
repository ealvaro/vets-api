# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SubmissionTracking do
  let(:test_class) do
    Class.new do
      include SubmissionTracking
      public :derive_ial, :submission_fields

      attr_accessor :data, :metadata

      def initialize(data: {}, metadata: {})
        @data = data
        @metadata = metadata
      end
    end
  end

  let(:instance) { test_class.new }

  describe '#submission_fields' do
    let(:form_uuid) { '12345678-1234-5678-1234-567812345678' }
    let(:metadata) do
      {
        'uuid' => form_uuid,
        'primaryContactInfo' => { 'email' => 'veteran@example.com' }
      }
    end
    let(:data) { { 'certifier_role' => 'applicant' } }
    let(:instance) { test_class.new(data:, metadata:) }
    let(:user_verification) { instance_double(UserVerification, verified?: true) }
    let(:user) { instance_double(User, loa: { current: 3 }, user_verification:) }

    it 'includes the form_uuid pulled from metadata' do
      expect(instance.submission_fields(user)[:form_uuid]).to eq(form_uuid)
    end

    it 'includes the existing identity, loa, ial, and email_used fields' do
      fields = instance.submission_fields(user)
      expect(fields[:identity]).to eq('applicant')
      expect(fields[:current_user_loa]).to eq(3)
      expect(fields[:current_user_ial]).to eq(SignIn::Constants::Auth::IAL_TWO)
      expect(fields[:email_used]).to eq('yes')
    end

    context 'when metadata is nil' do
      let(:instance) { test_class.new(data:, metadata: nil) }

      it 'returns nil form_uuid without raising' do
        fields = instance.submission_fields(user)
        expect(fields[:form_uuid]).to be_nil
        expect(fields[:email_used]).to eq('no')
      end
    end
  end

  describe '#derive_ial' do
    context 'when user is nil' do
      it 'returns 0' do
        expect(instance.derive_ial(nil)).to eq(0)
      end
    end

    context 'when user is verified' do
      let(:user) { double(user_verification: double(verified?: true)) }

      it 'returns IAL_TWO (2)' do
        expect(instance.derive_ial(user)).to eq(SignIn::Constants::Auth::IAL_TWO)
      end
    end

    context 'when user is not verified' do
      let(:user) { double(user_verification: double(verified?: false)) }

      it 'returns IAL_ONE (1)' do
        expect(instance.derive_ial(user)).to eq(SignIn::Constants::Auth::IAL_ONE)
      end
    end

    context 'when user has no user_verification' do
      let(:user) { double(user_verification: nil) }

      it 'returns 0' do
        expect(instance.derive_ial(user)).to eq(0)
      end
    end
  end
end
