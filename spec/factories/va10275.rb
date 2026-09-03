# frozen_string_literal: true

FactoryBot.define do
  factory :va10275, class: 'SavedClaim::EducationBenefits::VA10275', parent: :education_benefits do
    form { Rails.root.join('spec', 'fixtures', 'education_benefits_claims', '10275', 'minimal.json').read }

    factory :va10275_overflow do
      form { Rails.root.join('spec', 'fixtures', 'education_benefits_claims', '10275', 'overflow.json').read }
    end
  end
end
