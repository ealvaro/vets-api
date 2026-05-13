# frozen_string_literal: true

class AddIndexesToMobileSurveyResponses < ActiveRecord::Migration[7.2]
  disable_ddl_transaction!

  def change
    add_index :mobile_survey_responses, :survey_type, algorithm: :concurrently, if_not_exists: true
    add_index :mobile_survey_responses, :needs_kms_rotation, algorithm: :concurrently, if_not_exists: true
  end
end
