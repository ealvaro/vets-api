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

    it 'has option1 (online), option2 (mail), option3 (fax)' do
      expect(files.dig('options', 'option1', 'title')).to eq('Option 1: Online')
      expect(files.dig('options', 'option2', 'title')).to eq('Option 2: By mail')
      expect(files.dig('options', 'option3', 'title')).to eq('Option 3: By fax')
    end

    it 'option1 has linkUrl and linkExternal' do
      option1 = files.dig('options', 'option1')
      expect(option1['linkUrl']).to be_present
      expect(option1['linkExternal']).to be true
    end

    it 'option3 has noteText' do
      expect(files.dig('options', 'option3', 'noteText')).to be_present
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
  end

  describe 'whatWeAreDoing section' do
    subject(:what_we_are_doing) { config['whatWeAreDoing'] }

    it 'has statusMap entries for pending, vbms, and error' do
      %w[pending vbms error].each do |status|
        entry = what_we_are_doing.dig('statusMap', status)
        expect(entry['title']).to be_present
        expect(entry['description']).to be_present
      end
    end

    it 'pending status description includes both sentences' do
      description = what_we_are_doing.dig('statusMap', 'pending', 'description')
      expect(description).to include('We received your application.')
      expect(description).to include("If we need more information, we'll mail you a letter.")
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

    it 'currentStepByStatus covers pending, vbms, and error' do
      expect(overview['currentStepByStatus'].keys).to match_array(%w[pending vbms error])
    end
  end
end
# rubocop:enable RSpec/SpecFilePathFormat
