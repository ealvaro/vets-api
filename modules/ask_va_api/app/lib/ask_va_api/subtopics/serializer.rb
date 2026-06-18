# frozen_string_literal: true

module AskVAApi
  module Subtopics
    class Serializer
      include JSONAPI::Serializer
      set_type :subtopics

      attributes :name,
                 :allow_attachments,
                 :description,
                 :display_name,
                 :parent_id,
                 :rank_order,
                 :requires_authentication,
                 :topic_type,
                 :contact_preferences
    end
  end
end
