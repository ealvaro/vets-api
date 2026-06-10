# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AskVAApi::Categories::Entity do
  subject(:content) { described_class }

  let(:info) do
    { Name: 'Education benefits and work study',
      Id: '75524deb-d864-eb11-bb24-000d3a579c45',
      ParentId: nil,
      Description: nil,
      RequiresAuthentication: true,
      AllowAttachments: true,
      RankOrder: 1,
      DisplayName: 'Education benefits and work study',
      TopicType: 'Category',
      ContactPreferences: ['Email'] }
  end

  let(:category) { content.new(info) }

  it 'creates a category' do
    expect(category).to have_attributes({
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
