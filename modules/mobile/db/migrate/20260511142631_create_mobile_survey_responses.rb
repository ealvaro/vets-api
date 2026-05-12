class CreateMobileSurveyResponses < ActiveRecord::Migration[7.2]
  def change
    create_table :mobile_survey_responses do |t|
      t.string :survey_type, null: false
      t.string :user_uuid, null: false
      t.text :encrypted_kms_key
      t.text :survey_data_ciphertext, null: false
      t.jsonb :metadata

      t.timestamps
    end
  end
end
