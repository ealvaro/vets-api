# frozen_string_literal: true

require 'rails_helper'

RSpec.describe BenefitsClaims::Providers::IvcChampva::RepeatIneligibilityLetterActivity do
  def create_letter(applicant, mail_status:, mail_status_date:, form_number: '10-10D-EXTENDED-EXISTING')
    applicant.ivc_champva_letters.create!(
      form_number:,
      mail_status:,
      mail_status_date:
    )
  end

  describe '.evaluate' do
    let(:applicant) do
      create(:ivc_champva_applicant, eligibility_resolved: true, ves_eligibility_status: 'Not Eligible')
    end

    it 'returns hasRepeatIneligibilityLetter false and a nil date when there is no repeat activity' do
      create_letter(applicant, mail_status: 'mailed_by_print_vendor', mail_status_date: 1.day.ago)

      result = described_class.evaluate(applicant)

      expect(result).to eq(
        'hasRepeatIneligibilityLetter' => false,
        'repeatIneligibilityLetterDate' => nil
      )
    end

    it 'returns hasRepeatIneligibilityLetter true and the most recent sent letter date when there is repeat activity' do
      create_letter(applicant, mail_status: 'mailed_by_print_vendor', mail_status_date: 2.days.ago)
      most_recent = create_letter(applicant, mail_status: 'mailed_by_print_vendor', mail_status_date: 1.day.ago)

      result = described_class.evaluate(applicant)

      expect(result).to eq(
        'hasRepeatIneligibilityLetter' => true,
        'repeatIneligibilityLetterDate' => most_recent.mail_status_date.iso8601
      )
    end
  end

  describe '.alert_for' do
    it 'returns nil when given an empty list of applicants' do
      expect(described_class.alert_for([])).to be_nil
    end

    it 'returns nil when the alert template fails to load' do
      allow(described_class).to receive(:alert_template).and_return({})

      applicant = build_stubbed(:ivc_champva_applicant, applicant_first_name: 'Jane')
      expect(described_class.alert_for([applicant])).to be_nil
    end

    it 'substitutes a single first name into the template' do
      applicant = build_stubbed(:ivc_champva_applicant, applicant_first_name: 'Jane')

      result = described_class.alert_for([applicant])

      expect(result).to eq(
        'title' => "Our decision on Jane's eligibility hasn't changed",
        'description' => 'Jane is still not eligible for CHAMPVA benefits. Read our updated application decision ' \
                         'for details.'
      )
    end

    it 'joins multiple first names into a single sentence, without deduping repeats' do
      jane1 = build_stubbed(:ivc_champva_applicant, applicant_first_name: 'Jane')
      john = build_stubbed(:ivc_champva_applicant, applicant_first_name: 'John')
      jane2 = build_stubbed(:ivc_champva_applicant, applicant_first_name: 'Jane')

      result = described_class.alert_for([jane1, john, jane2])

      expect(result['title']).to eq("Our decision on Jane, John, and Jane's eligibility hasn't changed")
    end

    it "falls back to 'This applicant' when no applicant has a first name" do
      applicant = build_stubbed(:ivc_champva_applicant, applicant_first_name: nil)

      result = described_class.alert_for([applicant])

      expect(result['title']).to eq("Our decision on This applicant's eligibility hasn't changed")
    end
  end

  describe '.alert_template' do
    it 'loads the repeat_ineligibility_alert config for ivc_champva' do
      expect(described_class.alert_template).to eq(
        'title' => "Our decision on [Name]'s eligibility hasn't changed",
        'description' => '[Name] is still not eligible for CHAMPVA benefits. Read our updated application ' \
                         'decision for details.'
      )
    end

    it 'logs and returns an empty hash when the config fails to load' do
      allow(BenefitsClaims::ClaimStatusMeta::ConfigLoader).to receive(:load).and_raise(ArgumentError, 'boom')
      expect(Rails.logger).to receive(:error).with(
        '[BenefitsClaims::Providers::IvcChampva::RepeatIneligibilityLetterActivity] ' \
        'Failed to load repeat ineligibility alert config',
        { message: 'boom' }
      )

      expect(described_class.alert_template).to eq({})
    end
  end

  describe '.repeat_activity?' do
    it 'returns false when the applicant is eligible, regardless of sent letters' do
      applicant = build_stubbed(:ivc_champva_applicant, ves_eligibility_status: 'Eligible')
      sent_letters = [double, double]

      expect(described_class.repeat_activity?(applicant, sent_letters)).to be(false)
    end

    it "returns false when the applicant's eligibility has not been resolved" do
      applicant = build_stubbed(:ivc_champva_applicant, eligibility_resolved: false,
                                                        ves_eligibility_status: 'Not Eligible')

      expect(described_class.repeat_activity?(applicant, [double, double])).to be(false)
    end

    it 'returns false when only one letter has been sent' do
      applicant = build_stubbed(:ivc_champva_applicant, eligibility_resolved: true,
                                                        ves_eligibility_status: 'Not Eligible')

      expect(described_class.repeat_activity?(applicant, [double])).to be(false)
    end

    it 'returns true when more than one letter has been sent to a resolved, ineligible applicant' do
      applicant = build_stubbed(:ivc_champva_applicant, eligibility_resolved: true,
                                                        ves_eligibility_status: 'Not Eligible')

      expect(described_class.repeat_activity?(applicant, [double, double])).to be(true)
    end
  end

  describe '.sent_letters_for' do
    let(:applicant) { create(:ivc_champva_applicant) }

    it 'excludes letters whose mail status is not in the sent-letter allowlist' do
      create_letter(applicant, mail_status: 'in_progress', mail_status_date: 1.day.ago)

      expect(described_class.sent_letters_for(applicant)).to eq([])
    end

    it 'matches the allowlisted status case-insensitively and ignoring surrounding whitespace' do
      letter = create_letter(applicant, mail_status: '  Mailed_By_Print_Vendor  ', mail_status_date: 1.day.ago)

      expect(described_class.sent_letters_for(applicant)).to eq([letter])
    end

    it 'returns sent letters oldest first' do
      newer = create_letter(applicant, mail_status: 'mailed_by_print_vendor', mail_status_date: 1.day.ago)
      older = create_letter(applicant, mail_status: 'mailed_by_print_vendor', mail_status_date: 2.days.ago)

      expect(described_class.sent_letters_for(applicant)).to eq([older, newer])
    end
  end

  describe '.format_datetime' do
    it 'returns nil when given nil' do
      expect(described_class.format_datetime(nil)).to be_nil
    end

    it 'formats a time as an ISO 8601 string' do
      value = Time.zone.parse('2026-05-01 12:00:00')
      expect(described_class.format_datetime(value)).to eq(value.iso8601)
    end
  end
end
