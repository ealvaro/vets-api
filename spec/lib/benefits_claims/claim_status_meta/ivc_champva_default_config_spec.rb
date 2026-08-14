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

    it 'has two steps with phase, header, and description' do
      expect(overview['steps'].length).to eq(2)
      overview['steps'].each do |step|
        expect(step['phase']).to be_present
        expect(step['header']).to be_present
        expect(step['description']).to be_present
      end
    end

    it 'step 1 has a descriptionDateTemplate with a {date} placeholder' do
      template = overview.dig('steps', 0, 'descriptionDateTemplate')
      expect(template).to be_present
      expect(template).to include('{date}')
    end

    it 'step 1 description and descriptionDateTemplate include the processing timeline sentence' do
      description = overview.dig('steps', 0, 'description')
      template = overview.dig('steps', 0, 'descriptionDateTemplate')
      expect(description).to include('5 business days')
      expect(template).to include('5 business days')
    end

    it 'currentStepByStatus covers pending, claimReceived, vbms, and complete' do
      expect(overview['currentStepByStatus'].keys).to match_array(%w[pending claimReceived vbms complete])
    end

    it 'step 1 has noteText, uploadLinkText, and uploadLinkUrl for supporting document guidance' do
      step1 = overview.dig('steps', 0)
      expect(step1['noteText']).to be_present
      expect(step1['uploadLinkText']).to be_present
      expect(step1['uploadLinkUrl']).to be_present
    end
  end
end
# rubocop:enable RSpec/SpecFilePathFormat
