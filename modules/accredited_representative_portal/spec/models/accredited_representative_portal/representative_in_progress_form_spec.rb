# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AccreditedRepresentativePortal::RepresentativeInProgressForm, type: :model do
  describe 'validations' do
    it { is_expected.to validate_presence_of(:form_id) }
    it { is_expected.to validate_presence_of(:veteran_icn) }
  end

  describe '#expires_after' do
    it 'defaults to 60 days' do
      form = build(:representative_in_progress_form)
      expect(form.expires_after).to eq(60.days)
    end
  end

  describe 'expiry on create' do
    it 'sets expires_at to next_expires_at when not already set' do
      form = create(:representative_in_progress_form)
      expect(form.expires_at).to be_within(1.second).of(60.days.from_now)
    end

    it 'does not overwrite an explicitly provided expires_at' do
      explicit = 5.days.from_now
      form = create(:representative_in_progress_form, expires_at: explicit)
      expect(form.expires_at).to be_within(1.second).of(explicit)
    end
  end

  describe '.for_rep_and_veteran' do
    it 'finds the form scoped to the full composite key' do
      form = create(:representative_in_progress_form)

      expect(
        described_class.for_rep_and_veteran(form.form_id, form.rep_user_account_id, form.veteran_icn)
      ).to eq(form)
    end

    it 'returns nil when the veteran_icn does not match' do
      form = create(:representative_in_progress_form)

      expect(
        described_class.for_rep_and_veteran(form.form_id, form.rep_user_account_id, 'wrong-icn')
      ).to be_nil
    end
  end

  describe '.build_for_rep_and_veteran' do
    let(:rep_user_account) { create(:user_account) }
    let(:expected_form_data) do
      <<~HEREDOC
        {"veteranFullName":{"first":"Maurice","last":"Murphy"},"address":{"view:militaryBaseDescription":{},"postalCode":"10458-5149","country":"USA","street":"441 E Fordham Rd","city":"Bronx","state":"NY"},"veteranSsn":"796265005","veteranDateOfBirth":"19730526"}
      HEREDOC
    end

    let(:veteran_icn) { '1012832013V553700' }

    it 'returns prefill data' do
      VCR.use_cassette('mpi/find_candidate/find_profile_with_identifier') do
        form = described_class.build_for_rep_and_veteran(nil, rep_user_account.id, veteran_icn)
        expect(form.form_data).to eq expected_form_data.chomp
        expect(form.rep_user_account_id).to eq rep_user_account.id
        expect(form.veteran_icn).to eq veteran_icn
      end
    end
  end
end
