# frozen_string_literal: true

FactoryBot.define do
  factory :fuzz_veteran_id, class: Hash do
    skip_create

    transient do
      rng { Random.new }
      matching_participant_id { '12345' }
    end

    # Default: valid PARTICIPANTID
    initialize_with do
      { 'identifierType' => 'PARTICIPANTID', 'value' => matching_participant_id }
    end

    trait :malformed do
      initialize_with do
        ['not-a-hash', rng.rand(0..99_999), nil, [], '', true].sample(random: rng)
      end
    end

    trait :wrong_type do
      initialize_with do
        { 'identifierType' => %w[SSN ICN EDIPI BIRLS].sample(random: rng),
          'value' => Faker::Number.number(digits: 9).to_s }
      end
    end

    trait :mismatch do
      initialize_with do
        { 'identifierType' => 'PARTICIPANTID',
          'value' => "#{matching_participant_id}_nope" }
      end
    end
  end

  factory :fuzz_dependent, class: Hash do
    skip_create

    transient do
      rng { Random.new }
    end

    initialize_with do
      {
        'fullName' => { 'first' => Faker::Name.first_name, 'last' => Faker::Name.last_name },
        'relationship' => %w[spouse child parent].sample(random: rng),
        'dateOfBirth' => Faker::Date.birthday(min_age: 0, max_age: 99).iso8601,
        'ssn' => rng.rand < 0.5 ? Faker::Number.number(digits: 9).to_s : nil
      }.compact
    end
  end

  factory :fuzz_submission_body, class: Hash do
    skip_create

    transient do
      rng { Random.new }
      matching_participant_id { '12345' }
      veteran_id { build(:fuzz_veteran_id, rng:, matching_participant_id:) }
    end

    initialize_with do
      evidence = if rng.rand < 0.3
                   Array.new(rng.rand(1..3)) do
                     { 'documentType' => %w[DD214 marriage_cert birth_cert other].sample(random: rng),
                       'description' => Faker::Lorem.sentence }
                   end
                 end

      {
        'envelope' => {
          'veteranId' => veteran_id,
          'payload' => {
            'veteranInformation' => {
              'fullName' => { 'first' => Faker::Name.first_name, 'last' => Faker::Name.last_name },
              'dateOfBirth' => Faker::Date.birthday(min_age: 18, max_age: 99).iso8601,
              'ssn' => Faker::Number.number(digits: 9).to_s
            },
            'dependents' => Array.new(rng.rand(0..4)) { build(:fuzz_dependent, rng:) },
            'additionalEvidence' => evidence
          }.compact
        }
      }
    end
  end
end
