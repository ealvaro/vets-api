# frozen_string_literal: true

FactoryBot.define do
  factory :va214192, class: 'SavedClaim::Form214192' do
    form { Rails.root.join('spec', 'fixtures', 'form214192', 'valid_form.json').read }
    form_id { '21-4192' }
  end
end
