# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AskVAApi::Subtopics::Entity do
  subject(:content) { described_class }

  let(:info) do
    { Name: 'Application',
      Id: '952dbcee-eb64-eb11-bb23-000d3a579b83',
      ParentId: '152b8586-e764-eb11-bb23-000d3a579c3f',
      Description: nil,
      RequiresAuthentication: false,
      AllowAttachments: true,
      RankOrder: 0,
      DisplayName: 'Application',
      TopicType: 'SubTopic',
      ContactPreferences: ['Email'] }
  end

  let(:subtopic) { content.new(info) }

  it 'creates a subtopic' do
    expect(subtopic).to have_attributes({
                                          name: info[:Name],
                                          allow_attachments: info[:AllowAttachments],
                                          description: info[:Description],
                                          display_name: info[:DisplayName],
                                          id: info[:Id],
                                          parent_id: info[:ParentId],
                                          rank_order: info[:RankOrder],
                                          requires_authentication: info[:RequiresAuthentication],
                                          topic_type: info[:TopicType],
                                          contact_preferences: info[:ContactPreferences]
                                        })
  end
end
