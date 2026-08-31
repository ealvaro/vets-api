# frozen_string_literal: true

FactoryBot.define do
  factory :va0810, class: 'SavedClaim::EducationBenefits::VA0810', parent: :education_benefits do
    form { Rails.root.join('spec', 'fixtures', 'education_benefits_claims', '0810', 'minimal.json').read }
  end

  factory :va0810_overflow, class: 'SavedClaim::EducationBenefits::VA0810', parent: :education_benefits do
    form { Rails.root.join('spec', 'fixtures', 'education_benefits_claims', '0810', 'overflow.json').read }
  end
end
