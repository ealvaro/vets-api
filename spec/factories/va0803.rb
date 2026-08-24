# frozen_string_literal: true

FactoryBot.define do
  factory :va0803, class: 'SavedClaim::EducationBenefits::VA0803', parent: :education_benefits do
    form { Rails.root.join('spec', 'fixtures', 'education_benefits_claims', '0803', 'minimal.json').read }
  end

  factory :va0803_overflow, class: 'SavedClaim::EducationBenefits::VA0803', parent: :education_benefits do
    form { Rails.root.join('spec', 'fixtures', 'education_benefits_claims', '0803', 'overflow.json').read }
  end
end
