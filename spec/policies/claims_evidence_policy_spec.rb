# frozen_string_literal: true

require 'rails_helper'

describe ClaimsEvidencePolicy do
  subject { described_class }

  permissions :access? do
    context 'when the user is LOA3 and has an ICN' do
      let(:user) { build(:user, :loa3, :legacy_icn) }

      it 'grants access' do
        expect(subject).to permit(user, :claims_evidence)
      end
    end

    context 'when the user is not LOA3' do
      let(:user) { build(:user, :loa1) }

      it 'denies access' do
        expect(subject).not_to permit(user, :claims_evidence)
      end
    end

    context 'when the user has no ICN' do
      let(:user) { build(:user, :loa3) }

      before { allow(user).to receive(:icn).and_return(nil) }

      it 'denies access' do
        expect(subject).not_to permit(user, :claims_evidence)
      end
    end
  end
end
