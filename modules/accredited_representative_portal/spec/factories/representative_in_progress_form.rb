# frozen_string_literal: true

FactoryBot.define do
  factory :representative_in_progress_form,
          class: 'AccreditedRepresentativePortal::RepresentativeInProgressForm' do
    rep_user_account { create(:user_account) }
    veteran_icn { '1234567890V123456' }
    form_id { '21-686c-ARP' }
    form_data { { veteranInformation: { firstName: 'John', lastName: 'Doe' } }.to_json }
    metadata { { version: 1, returnUrl: '/representative/686c/veteran-information' } }
  end
end
