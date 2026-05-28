# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SubmissionTracking do
  let(:test_class) do
    Class.new do
      include SubmissionTracking
      public :derive_ial
    end
  end

  let(:instance) { test_class.new }

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
