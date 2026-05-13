class AddNeedsKmsRotationToMobileSurveyResponse < ActiveRecord::Migration[7.2]
  def change
    add_column :mobile_survey_responses, :needs_kms_rotation, :boolean, default: false, null: false
  end
end
