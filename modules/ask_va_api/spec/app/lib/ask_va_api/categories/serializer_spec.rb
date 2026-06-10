# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AskVAApi::Categories::Serializer do
  let(:info) do
    {
      Name: 'Education benefits and work study',
      Id: '75524deb-d864-eb11-bb24-000d3a579c45',
      ParentId: nil,
      Description: nil,
      RequiresAuthentication: true,
      AllowAttachments: true,
      RankOrder: 1,
      DisplayName: 'Education benefits and work study',
      TopicType: 'Category',
      ContactPreferences: ['Email']
    }
  end
  let(:category) { AskVAApi::Categories::Entity.new(info) }
  let(:response) { described_class.new(category) }
  let(:expected_response) do
    { data: { id: '75524deb-d864-eb11-bb24-000d3a579c45',
              type: :categories,
              attributes: {
                name: info[:Name],
                allow_attachments: info[:AllowAttachments],
                description: info[:Description],
                display_name: info[:DisplayName],
                parent_id: info[:ParentId],
                rank_order: info[:RankOrder],
                requires_authentication: info[:RequiresAuthentication],
                topic_type: info[:TopicType],
                contact_preferences: info[:ContactPreferences]
              } } }
  end

  context 'when successful' do
    it 'returns a json hash' do
      expect(response.serializable_hash).to include(expected_response)
    end
  end
end
