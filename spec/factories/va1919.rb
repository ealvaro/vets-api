# frozen_string_literal: true

FactoryBot.define do
  factory :va1919, class: 'SavedClaim::EducationBenefits::VA1919', parent: :education_benefits do
    form { Rails.root.join('spec', 'fixtures', 'education_benefits_claims', '1919', 'minimal.json').read }

    factory :va1919_overflow do
      form { Rails.root.join('spec', 'fixtures', 'education_benefits_claims', '1919', 'overflow.json').read }
    end
  end
end
