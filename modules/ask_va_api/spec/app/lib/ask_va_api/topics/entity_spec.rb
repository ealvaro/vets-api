# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AskVAApi::Topics::Entity do
  subject(:content) { described_class }

  let(:info) do
    { Name: 'Benefits for survivors and dependents',
      Id: '1b2b8586-e764-eb11-bb23-000d3a579c3f',
      ParentId: '75524deb-d864-eb11-bb24-000d3a579c45',
      Description: nil,
      RequiresAuthentication: true,
      AllowAttachments: true,
      RankOrder: 0,
      DisplayName: 'Benefits for survivors and dependents',
      TopicType: 'Topic',
      ContactPreferences: ['Email'],
      HasSubtopics: true }
  end

  let(:topic) { content.new(info) }

  it 'creates a topic' do
    expect(topic).to have_attributes({
                                       name: info[:Name],
                                       allow_attachments: info[:AllowAttachments],
                                       description: info[:Description],
                                       display_name: info[:DisplayName],
                                       id: info[:Id],
                                       parent_id: info[:ParentId],
                                       rank_order: info[:RankOrder],
                                       requires_authentication: info[:RequiresAuthentication],
                                       topic_type: info[:TopicType],
                                       contact_preferences: info[:ContactPreferences],
                                       has_subtopics: info[:HasSubtopics]
                                     })
  end
end
