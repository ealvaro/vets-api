# frozen_string_literal: true

# rubocop:disable RSpec/SpecFilePathFormat
require 'rails_helper'
require 'benefits_claims/claim_status_meta/config_loader'

RSpec.describe BenefitsClaims::ClaimStatusMeta::ConfigLoader, '#load ivc_champva contract' do
  subject(:config) { described_class.load(provider: :ivc_champva) }

  it 'loads without error' do
    expect { config }.not_to raise_error
  end

  it 'has the expected top-level keys' do
    expect(config.keys).to include(
      'detail', 'statusHeader', 'whatYouNeedToDo', 'files',
      'help', 'overview', 'listCard', 'closedAlert', 'nextSteps', 'whatWeAreDoing'
    )
  end

  it 'does not include repeatIneligibilityAlert — that lives in its own variant file ' \
     '(repeat_ineligibility_alert.json) precisely so it never ends up in claimStatusMeta' do
    expect(config).not_to have_key('repeatIneligibilityAlert')
  end

  describe 'files section' do
    subject(:files) { config['files'] }

    it 'has option1 (mail) and option2 (fax)' do
      expect(files.dig('options', 'option1', 'description')).to include('mail')
      expect(files.dig('options', 'option2', 'description')).to include('fax')
    end

    it 'option1 has addressLines' do
      option1 = files.dig('options', 'option1')
      expect(option1['addressLines']).to be_present
    end

    it 'option2 has noteText' do
      expect(files.dig('options', 'option2', 'noteText')).to be_present
    end

    it 'confirmation has descriptionPrefix, phone, tty, and descriptionNote' do
      confirmation = files['confirmation']
      expect(confirmation['descriptionPrefix']).to be_present
      expect(confirmation['phone']).to be_present
      expect(confirmation['tty']).to be_present
      expect(confirmation['descriptionNote']).to be_present
    end
  end

  describe 'listCard section' do
    subject(:list_card) { config['listCard'] }

    it 'has title, receivedLabel, and decisionLetterLabel' do
      expect(list_card['title']).to eq('Application for CHAMPVA benefits')
      expect(list_card['receivedLabel']).to be_present
      expect(list_card['decisionLetterLabel']).to be_present
    end
  end

  describe 'closedAlert section' do
    subject(:closed_alert) { config['closedAlert'] }

    it 'has title and description' do
      expect(closed_alert['title']).to be_present
      expect(closed_alert['description']).to be_present
    end

    it 'title prompts the veteran that a decision was made' do
      expect(closed_alert['title']).to eq('We made a decision on your application on')
    end

    it 'title ends with "on" so the FE can append the formatted date' do
      expect(closed_alert['title']).to end_with('on')
    end

    it 'description directs veteran to read for the decision outcome' do
      expect(closed_alert['description']).to eq('Keep reading for our application decision.')
    end

    it 'does not contain old letter-based description copy (regression guard)' do
      expect(closed_alert['description']).not_to include('decision letter')
    end

    it 'includes title and description keys so FE rendering is predictable' do
      expect(closed_alert.keys).to include('title', 'description')
    end
  end

  describe 'nextSteps section' do
    subject(:next_steps) { config['nextSteps'] }

    it 'has a title and at least one item with boldText and text' do
      expect(next_steps['title']).to be_present
      expect(next_steps['items']).to be_an(Array).and have_attributes(length: (be >= 1))
      next_steps['items'].each do |item|
        expect(item['boldText']).to be_present
        expect(item['text']).to be_present
      end
    end

    it 'items with a linkUrl use a valid relative or absolute URL format' do
      next_steps['items'].select { |item| item['linkUrl'].present? }.each do |item|
        expect(item['linkUrl']).to match(%r{\A(https?://|/)})
        expect(item['linkText']).to be_present
      end
    end

    it 'includes an item directing veterans who disagree to request a decision review' do
      texts = next_steps['items'].map { |i| "#{i['boldText']} #{i['text']}" }.join(' ')
      expect(texts).to include('disagree')
    end
  end

  describe 'whatWeAreDoing section' do
    subject(:what_we_are_doing) { config['whatWeAreDoing'] }

    it 'has statusMap entries for pending and vbms' do
      %w[pending vbms].each do |status|
        entry = what_we_are_doing.dig('statusMap', status)
        expect(entry['title']).to be_present
        expect(entry['description']).to be_present
      end
    end

    it 'pending status description includes the processing timeline sentence' do
      description = what_we_are_doing.dig('statusMap', 'pending', 'description')
      expect(description).to include('We received your application.')
      expect(description).to include('5 business days')
    end

    it 'pending and claimReceived have a descriptionNote with the mail letter sentence' do
      %w[pending claimReceived].each do |status|
        note = what_we_are_doing.dig('statusMap', status, 'descriptionNote')
        expect(note).to be_present
        expect(note).to include("If we need more information, we'll mail you a letter.")
      end
    end
  end

  describe 'overview section' do
    subject(:overview) { config['overview'] }

    it 'has title and description' do
      expect(overview['title']).to eq('Overview of the application process')
      expect(overview['description']).to include('CHAMPVA benefits')
    end

    it 'has currentStepPrefix for the step date line' do
      expect(overview['currentStepPrefix']).to eq('Your application moved to this step on')
    end

    it 'has two steps with phase, header, and description' do
      expect(overview['steps'].length).to eq(2)
      overview['steps'].each do |step|
        expect(step['phase']).to be_present
        expect(step['header']).to be_present
        expect(step['description']).to be_present
      end
    end

    it 'steps have sequential phase numbers' do
      phases = overview['steps'].map { |s| s['phase'] }
      expect(phases).to eq([1, 2])
    end

    describe 'step 1 — Application received' do
      subject(:step1) { overview.dig('steps', 0) }

      it 'has the correct header' do
        expect(step1['header']).to eq('Step 1: Application received')
      end

      it 'description includes processing timeline' do
        expect(step1['description']).to include('5 business days')
      end

      it 'has a descriptionDateTemplate with {date} placeholder' do
        expect(step1['descriptionDateTemplate']).to include('{date}')
        expect(step1['descriptionDateTemplate']).to include('5 business days')
      end

      it 'has a link to the CHAMPVA what-to-do-after-applying resource' do
        expect(step1['linkUrl']).to include('what-to-do-after-applying-for-champva-benefits')
        expect(step1['linkText']).to be_present
      end

      it 'step 1 link is an absolute external URL (rendered as va-link by FE)' do
        expect(step1['linkUrl']).to match(%r{\Ahttps?://})
      end

      it 'does not have noteText or upload link (removed per Figma mock)' do
        expect(step1['noteText']).to be_nil
        expect(step1['uploadLinkText']).to be_nil
        expect(step1['uploadLinkUrl']).to be_nil
      end

      it 'does not have details array (removed per Figma mock)' do
        expect(step1['details']).to be_nil
      end
    end

    describe 'step 2 — Application decided' do
      subject(:step2) { overview.dig('steps', 1) }

      it 'has the correct header' do
        expect(step2['header']).to eq('Step 2: Application decided')
      end

      it 'description directs applicant to the Status tab' do
        expect(step2['description']).to include('Status tab')
      end

      it 'does not contain old decision copy (regression guard)' do
        expect(step2['description']).not_to eq('We made a decision on your application.')
      end

      it 'has a link to the Status tab with relative URL (rendered as BasicLink by FE)' do
        expect(step2['linkUrl']).to eq('../status')
        expect(step2['linkText']).to be_present
      end

      it 'details are present and mention decision letter and welcome letter' do
        expect(step2['details']).to be_an(Array).and have_attributes(length: be >= 1)
        details_text = step2['details'].join
        expect(details_text).to include('decision letter')
        expect(details_text).to include('welcome letter')
      end

      it 'does not have a descriptionDateTemplate (no date in step 2 description)' do
        expect(step2['descriptionDateTemplate']).to be_nil
      end

      it 'does not have uploadLinkUrl (no file upload in step 2)' do
        expect(step2['uploadLinkUrl']).to be_nil
      end

      it 'does not have noteText (no note block in step 2)' do
        expect(step2['noteText']).to be_nil
      end
    end

    describe 'currentStepByStatus — VES-driven step mapping' do
      subject(:step_map) { overview['currentStepByStatus'] }

      it 'covers all expected statuses' do
        expect(step_map.keys).to match_array(%w[pending claimReceived vbms complete])
      end

      it 'maps Step 1 (In Progress) statuses to phase 1' do
        expect(step_map['claimReceived']).to eq(1)
        expect(step_map['pending']).to eq(1)
      end

      it 'maps Step 2 (Closed/decided) statuses to phase 2' do
        expect(step_map['complete']).to eq(2)
        expect(step_map['vbms']).to eq(2)
      end
    end
  end

  describe '#load ivc_champva repeat_ineligibility_alert variant' do
    subject(:variant_config) { described_class.load(provider: :ivc_champva, variant: 'repeat_ineligibility_alert') }

    it 'loads without error' do
      expect { variant_config }.not_to raise_error
    end

    it 'has title and description with a [Name] placeholder' do
      expect(variant_config['title']).to include('[Name]')
      expect(variant_config['description']).to include('[Name]')
    end
  end
end
# rubocop:enable RSpec/SpecFilePathFormat
