# frozen_string_literal: true

class RenameDigitalDisputeSubmissionsIdSequence < ActiveRecord::Migration[7.2]
  def up
    safety_assured do
      execute <<~SQL.squish
        ALTER SEQUENCE IF EXISTS digital_dispute_submissions_new_id_seq
          RENAME TO digital_dispute_submissions_id_seq;
      SQL

      execute <<~SQL.squish
        ALTER TABLE digital_dispute_submissions
          ALTER COLUMN id SET DEFAULT nextval('digital_dispute_submissions_id_seq'::regclass);
      SQL
    end
  end

  def down
    safety_assured do
      execute <<~SQL.squish
        ALTER TABLE digital_dispute_submissions
          ALTER COLUMN id SET DEFAULT nextval('digital_dispute_submissions_new_id_seq'::regclass);
      SQL

      execute <<~SQL.squish
        ALTER SEQUENCE IF EXISTS digital_dispute_submissions_id_seq
          RENAME TO digital_dispute_submissions_new_id_seq;
      SQL
    end
  end
end
