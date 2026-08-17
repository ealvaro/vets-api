# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_08_14_185750) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "btree_gin"
  enable_extension "fuzzystrmatch"
  enable_extension "pg_catalog.plpgsql"
  enable_extension "pg_stat_statements"
  enable_extension "pg_trgm"
  enable_extension "pgcrypto"
  enable_extension "postgis"
  enable_extension "uuid-ossp"

  # Custom types defined in this database.
  # Note that some types may not work with other database engines. Be careful if changing database.
  create_enum "bgs_submission_status", ["pending", "submitted", "failure"]
  create_enum "bpds_submission_status", ["pending", "submitted", "failure"]
  create_enum "claims_evidence_api_submission_status", ["pending", "accepted", "failed"]
  create_enum "client_config_auth_method", ["pkce", "client_secret", "private_key_jwt"]
  create_enum "digital_forms_api_submission_status", ["pending", "accepted", "failed"]
  create_enum "form21a_document_submission_status", ["pending", "uploading", "succeeded", "failed_transient", "failed_permanent", "abandoned"]
  create_enum "form21a_pilot_admission_status", ["started", "submitted"]
  create_enum "form21a_upload_failure_classification", ["transient", "permanent"]
  create_enum "itf_remediation_status", ["unprocessed"]
  create_enum "lighthouse_submission_status", ["pending", "submitted", "failure", "vbms", "manually"]
  create_enum "saved_claim_group_status", ["pending", "accepted", "failure", "processing", "success"]
  create_enum "user_action_status", ["initial", "success", "error"]

  create_table "accreditation_api_entity_counts", force: :cascade do |t|
    t.integer "agents"
    t.integer "attorneys"
    t.datetime "created_at", null: false
    t.integer "representatives"
    t.datetime "updated_at", null: false
    t.integer "veteran_service_organizations"
  end

  create_table "accreditation_data_ingestion_logs", force: :cascade do |t|
    t.integer "agents_status", default: 0, null: false
    t.integer "attorneys_status", default: 0, null: false
    t.datetime "created_at", null: false
    t.integer "dataset", null: false
    t.datetime "finished_at"
    t.jsonb "metrics", default: {}, null: false
    t.integer "representatives_status", default: 0, null: false
    t.datetime "started_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.integer "veteran_service_organizations_status", default: 0, null: false
    t.index ["dataset", "started_at"], name: "index_accr_data_ing_logs_on_dataset_started_at"
    t.index ["dataset", "status", "finished_at"], name: "index_accr_data_ing_logs_on_dataset_status_finished_at"
    t.index ["status", "finished_at"], name: "index_accr_data_ing_logs_on_status_and_finished_at"
  end

  create_table "accreditations", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "acceptance_mode", default: "no_acceptance", null: false
    t.uuid "accredited_individual_id", null: false
    t.uuid "accredited_organization_id", null: false
    t.boolean "can_accept_reject_poa"
    t.datetime "created_at", null: false
    t.datetime "deactivated_at"
    t.datetime "updated_at", null: false
    t.index ["accredited_individual_id", "accredited_organization_id"], name: "index_accreditations_on_indi_and_org_ids", unique: true
    t.index ["accredited_organization_id"], name: "index_accreditations_on_accredited_organization_id"
    t.check_constraint "acceptance_mode::text = ANY (ARRAY['any_request'::character varying::text, 'self_only'::character varying::text, 'no_acceptance'::character varying::text])", name: "check_accreditations_acceptance_mode"
  end

  create_table "accredited_individuals", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "address_line1"
    t.string "address_line2"
    t.string "address_line3"
    t.string "address_type"
    t.string "city"
    t.string "country_code_iso3"
    t.string "country_name"
    t.string "county_code"
    t.string "county_name"
    t.datetime "created_at", null: false
    t.string "email"
    t.datetime "fallback_location_updated_at"
    t.string "first_name"
    t.string "full_name"
    t.string "individual_type", null: false
    t.string "international_postal_code"
    t.string "last_name"
    t.float "lat"
    t.geography "location", limit: {srid: 4326, type: "st_point", geographic: true}
    t.float "long"
    t.string "middle_initial"
    t.uuid "ogc_id", null: false
    t.string "phone"
    t.string "poa_code", limit: 3
    t.string "province"
    t.jsonb "raw_address"
    t.string "registration_number", null: false
    t.string "state_code"
    t.datetime "updated_at", null: false
    t.string "zip_code"
    t.string "zip_suffix"
    t.index ["full_name"], name: "index_accredited_individuals_on_full_name"
    t.index ["location"], name: "index_accredited_individuals_on_location", using: :gist
    t.index ["poa_code"], name: "index_accredited_individuals_on_poa_code"
    t.index ["registration_number", "individual_type"], name: "index_on_reg_num_and_type_for_accredited_individuals", unique: true
  end

  create_table "accredited_organizations", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "address_line1"
    t.string "address_line2"
    t.string "address_line3"
    t.string "address_type"
    t.boolean "can_accept_digital_poa_requests", default: false, null: false
    t.string "city"
    t.string "country_code_iso3"
    t.string "country_name"
    t.string "county_code"
    t.string "county_name"
    t.datetime "created_at", null: false
    t.string "default_new_rep_acceptance_mode", default: "no_acceptance", null: false
    t.string "international_postal_code"
    t.float "lat"
    t.geography "location", limit: {srid: 4326, type: "st_point", geographic: true}
    t.float "long"
    t.string "name"
    t.uuid "ogc_id", null: false
    t.string "phone"
    t.string "poa_code", limit: 3, null: false
    t.string "primary_org_acceptance_mode", default: "no_acceptance", null: false
    t.string "province"
    t.jsonb "raw_address"
    t.string "state_code"
    t.datetime "updated_at", null: false
    t.string "zip_code"
    t.string "zip_suffix"
    t.index ["location"], name: "index_accredited_organizations_on_location", using: :gist
    t.index ["name"], name: "index_accredited_organizations_on_name"
    t.index ["poa_code"], name: "index_accredited_organizations_on_poa_code", unique: true
    t.check_constraint "default_new_rep_acceptance_mode::text = ANY (ARRAY['any_request'::character varying::text, 'self_only'::character varying::text, 'no_acceptance'::character varying::text])", name: "check_accredited_orgs_default_new_rep_acceptance_mode"
    t.check_constraint "primary_org_acceptance_mode::text = ANY (ARRAY['any_request'::character varying::text, 'self_only'::character varying::text, 'no_acceptance'::character varying::text])", name: "check_accredited_orgs_primary_org_acceptance_mode"
  end

  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum", null: false
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "appeal_submission_uploads", force: :cascade do |t|
    t.string "appeal_submission_id"
    t.datetime "created_at", null: false
    t.string "decision_review_evidence_attachment_guid"
    t.datetime "failure_notification_sent_at"
    t.string "lighthouse_upload_id"
    t.datetime "updated_at", null: false
    t.index ["appeal_submission_id"], name: "index_appeal_submission_uploads_on_appeal_submission_id"
  end

  create_table "appeal_submissions", force: :cascade do |t|
    t.string "board_review_option"
    t.datetime "created_at", null: false
    t.text "encrypted_kms_key"
    t.datetime "failure_notification_sent_at"
    t.boolean "needs_kms_rotation", default: false, null: false
    t.string "submitted_appeal_uuid"
    t.string "type_of_appeal"
    t.datetime "updated_at", null: false
    t.text "upload_metadata_ciphertext"
    t.uuid "user_account_id"
    t.string "user_uuid"
    t.index ["needs_kms_rotation"], name: "index_appeal_submissions_on_needs_kms_rotation"
    t.index ["submitted_appeal_uuid"], name: "index_appeal_submissions_on_submitted_appeal_uuid"
    t.index ["user_account_id"], name: "index_appeal_submissions_on_user_account_id"
  end

  create_table "appeals_api_evidence_submissions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "encrypted_kms_key"
    t.text "file_data_ciphertext"
    t.uuid "guid", null: false
    t.string "source"
    t.string "supportable_id"
    t.string "supportable_type"
    t.datetime "updated_at", null: false
    t.integer "upload_submission_id", null: false
    t.index ["guid"], name: "index_appeals_api_evidence_submissions_on_guid"
    t.index ["supportable_type", "supportable_id"], name: "evidence_submission_supportable_id_type_index"
    t.index ["upload_submission_id"], name: "index_appeals_api_evidence_submissions_on_upload_submission_id", unique: true
  end

  create_table "appeals_api_higher_level_reviews", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "api_version"
    t.text "auth_headers_ciphertext"
    t.string "code"
    t.datetime "created_at", null: false
    t.string "detail"
    t.text "encrypted_kms_key"
    t.text "form_data_ciphertext"
    t.jsonb "metadata", default: {}
    t.boolean "needs_kms_rotation", default: false, null: false
    t.string "pdf_version"
    t.string "source"
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.string "veteran_icn"
    t.index ["id"], name: "idx_ahlr_kms_rotation_true_id", where: "(needs_kms_rotation = true)"
    t.index ["needs_kms_rotation"], name: "index_appeals_api_higher_level_reviews_on_needs_kms_rotation"
    t.index ["veteran_icn"], name: "index_appeals_api_higher_level_reviews_on_veteran_icn"
  end

  create_table "appeals_api_notice_of_disagreements", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "api_version"
    t.text "auth_headers_ciphertext"
    t.string "board_review_option"
    t.string "code"
    t.datetime "created_at", null: false
    t.string "detail"
    t.text "encrypted_kms_key"
    t.text "form_data_ciphertext"
    t.jsonb "metadata", default: {}
    t.boolean "needs_kms_rotation", default: false, null: false
    t.string "pdf_version"
    t.string "source"
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.string "veteran_icn"
    t.index ["needs_kms_rotation"], name: "idx_on_needs_kms_rotation_8edcf0bbde"
    t.index ["veteran_icn"], name: "index_appeals_api_notice_of_disagreements_on_veteran_icn"
  end

  create_table "appeals_api_status_updates", force: :cascade do |t|
    t.string "code"
    t.datetime "created_at", null: false
    t.string "detail"
    t.string "from"
    t.datetime "status_update_time"
    t.string "statusable_id"
    t.string "statusable_type"
    t.string "to"
    t.datetime "updated_at", null: false
    t.index ["statusable_type", "statusable_id"], name: "status_update_id_type_index"
  end

  create_table "appeals_api_supplemental_claims", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "api_version"
    t.text "auth_headers_ciphertext"
    t.string "code"
    t.datetime "created_at", null: false
    t.string "detail"
    t.text "encrypted_kms_key"
    t.boolean "evidence_submission_indicated"
    t.text "form_data_ciphertext"
    t.jsonb "metadata", default: {}
    t.boolean "needs_kms_rotation", default: false, null: false
    t.string "pdf_version"
    t.string "source"
    t.string "status", default: "pending"
    t.datetime "updated_at", null: false
    t.string "veteran_icn"
    t.index ["needs_kms_rotation"], name: "index_appeals_api_supplemental_claims_on_needs_kms_rotation"
    t.index ["veteran_icn"], name: "index_appeals_api_supplemental_claims_on_veteran_icn"
  end

  create_table "ar_form21a_pilot_admissions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.enum "status", default: "started", null: false, enum_type: "form21a_pilot_admission_status"
    t.datetime "submitted_at", comment: "set when the user submits"
    t.datetime "updated_at", null: false
    t.uuid "user_account_id", null: false, comment: "one admission per user, ever"
    t.index ["created_at"], name: "index_ar_form21a_pilot_admissions_on_created_at"
    t.index ["user_account_id"], name: "index_ar_form21a_pilot_admissions_on_user_account_id", unique: true
    t.check_constraint "status <> 'submitted'::form21a_pilot_admission_status OR submitted_at IS NOT NULL", name: "check_ar_form21a_pilot_admissions_submitted_at_present"
  end

  create_table "ar_icn_temporary_identifiers", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at"
    t.string "icn", null: false
    t.index ["created_at"], name: "index_ar_icn_temporary_identifiers_on_created_at"
    t.index ["icn"], name: "index_ar_icn_temporary_identifiers_on_icn"
  end

  create_table "ar_power_of_attorney_form_submissions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "encrypted_kms_key"
    t.text "error_message_ciphertext"
    t.boolean "needs_kms_rotation", default: false, null: false
    t.uuid "power_of_attorney_request_id", null: false
    t.string "service_id"
    t.text "service_response_ciphertext"
    t.string "status", null: false
    t.datetime "status_updated_at"
    t.index ["needs_kms_rotation"], name: "idx_on_needs_kms_rotation_fff6def3ad"
  end

  create_table "ar_power_of_attorney_forms", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "claimant_city_bidx", null: false
    t.string "claimant_city_ciphertext", null: false
    t.string "claimant_state_code_bidx", null: false
    t.string "claimant_state_code_ciphertext", null: false
    t.string "claimant_zip_code_bidx", null: false
    t.string "claimant_zip_code_ciphertext", null: false
    t.text "data_ciphertext", null: false
    t.text "encrypted_kms_key"
    t.boolean "needs_kms_rotation", default: false, null: false
    t.uuid "power_of_attorney_request_id", null: false
    t.index ["claimant_city_bidx", "claimant_state_code_bidx", "claimant_zip_code_bidx"], name: "idx_on_claimant_city_bidx_claimant_state_code_bidx__11e9adbe25"
    t.index ["needs_kms_rotation"], name: "index_ar_power_of_attorney_forms_on_needs_kms_rotation"
    t.index ["power_of_attorney_request_id"], name: "idx_on_power_of_attorney_request_id_fc59a0dabc", unique: true
  end

  create_table "ar_power_of_attorney_request_decisions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "accredited_individual_registration_number"
    t.uuid "creator_id", null: false
    t.integer "declination_reason"
    t.string "power_of_attorney_holder_poa_code"
    t.string "power_of_attorney_holder_type"
    t.string "type", null: false
    t.index ["creator_id"], name: "index_ar_power_of_attorney_request_decisions_on_creator_id"
  end

  create_table "ar_power_of_attorney_request_expirations", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
  end

  create_table "ar_power_of_attorney_request_notifications", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.uuid "notification_id"
    t.uuid "power_of_attorney_request_id", null: false
    t.string "recipient_type"
    t.string "type", null: false
    t.datetime "updated_at", null: false
    t.index ["notification_id"], name: "idx_on_notification_id_2402e9daad"
    t.index ["power_of_attorney_request_id"], name: "idx_on_power_of_attorney_request_id_b7c74f46e5"
  end

  create_table "ar_power_of_attorney_request_resolutions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "declination_reason"
    t.text "encrypted_kms_key"
    t.boolean "needs_kms_rotation", default: false, null: false
    t.uuid "power_of_attorney_request_id", null: false
    t.text "reason_ciphertext"
    t.uuid "resolving_id", null: false
    t.string "resolving_type", null: false
    t.index ["needs_kms_rotation"], name: "idx_on_needs_kms_rotation_2e9bb1b8e7"
    t.index ["power_of_attorney_request_id"], name: "idx_on_power_of_attorney_request_id_fd7d2d11b1", unique: true
    t.index ["resolving_type", "resolving_id"], name: "unique_resolving_type_and_id", unique: true
  end

  create_table "ar_power_of_attorney_request_withdrawals", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "superseding_power_of_attorney_request_id"
    t.string "type", null: false
    t.index ["superseding_power_of_attorney_request_id"], name: "idx_on_superseding_power_of_attorney_request_id_7318c79fef"
  end

  create_table "ar_power_of_attorney_requests", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "accredited_individual_registration_number"
    t.uuid "claimant_id", null: false
    t.string "claimant_type", null: false
    t.datetime "created_at", null: false
    t.string "power_of_attorney_holder_poa_code"
    t.string "power_of_attorney_holder_type", null: false
    t.datetime "redacted_at"
    t.index ["claimant_id"], name: "index_ar_power_of_attorney_requests_on_claimant_id"
    t.index ["redacted_at"], name: "index_ar_power_of_attorney_requests_on_redacted_at"
  end

  create_table "ar_representative_in_progress_forms", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "encrypted_kms_key"
    t.datetime "expires_at"
    t.text "form_data_ciphertext"
    t.string "form_id", null: false
    t.json "metadata"
    t.boolean "needs_kms_rotation", default: false, null: false
    t.uuid "rep_user_account_id", null: false
    t.datetime "updated_at", null: false
    t.string "veteran_icn", null: false
    t.index ["form_id", "rep_user_account_id", "veteran_icn"], name: "index_ar_representative_in_progress_forms_on_composite_key", unique: true
    t.index ["needs_kms_rotation"], name: "index_ar_rep_in_progress_forms_on_needs_kms_rotation"
    t.index ["rep_user_account_id"], name: "index_ar_rep_in_progress_forms_on_rep_user_account_id"
  end

  create_table "ar_saved_claim_claimant_representatives", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "accredited_individual_registration_number", null: false
    t.string "claimant_id", null: false
    t.string "claimant_type", null: false
    t.datetime "created_at", null: false
    t.string "power_of_attorney_holder_poa_code", null: false
    t.string "power_of_attorney_holder_type", null: false
    t.bigint "saved_claim_id", null: false
    t.index ["saved_claim_id"], name: "idx_on_saved_claim_id_f4f27623c2", unique: true
  end

  create_table "ask_va_inquiry_submission_checkpoints", force: :cascade do |t|
    t.bigint "ask_va_inquiry_submission_id", null: false
    t.string "checkpoint_type", null: false
    t.datetime "created_at", null: false
    t.text "encrypted_kms_key"
    t.boolean "needs_kms_rotation", default: false, null: false
    t.text "payload_ciphertext", null: false
    t.datetime "updated_at", null: false
    t.index ["ask_va_inquiry_submission_id"], name: "idx_on_ask_va_inquiry_submission_id_532ebd2134"
    t.index ["checkpoint_type"], name: "index_ask_va_inquiry_submission_checkpoints_on_checkpoint_type"
    t.index ["needs_kms_rotation"], name: "idx_on_needs_kms_rotation_e1e0a40094"
  end

  create_table "ask_va_inquiry_submissions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "crm_message_id"
    t.string "inquiry_number"
    t.string "request_id", null: false
    t.datetime "updated_at", null: false
    t.index ["crm_message_id"], name: "index_ask_va_inquiry_submissions_on_crm_message_id"
    t.index ["inquiry_number"], name: "index_ask_va_inquiry_submissions_on_inquiry_number"
    t.index ["request_id"], name: "index_ask_va_inquiry_submissions_on_request_id", unique: true
  end

  create_table "async_transactions", id: :serial, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "encrypted_kms_key"
    t.text "metadata_ciphertext"
    t.boolean "needs_kms_rotation", default: false, null: false
    t.string "source"
    t.string "source_id"
    t.string "status"
    t.string "transaction_id"
    t.string "transaction_status"
    t.string "type"
    t.datetime "updated_at", null: false
    t.uuid "user_account_id"
    t.string "user_uuid"
    t.index ["created_at"], name: "index_async_transactions_on_created_at"
    t.index ["id", "type"], name: "index_async_transactions_on_id_and_type"
    t.index ["needs_kms_rotation"], name: "index_async_transactions_on_needs_kms_rotation"
    t.index ["source_id"], name: "index_async_transactions_on_source_id"
    t.index ["transaction_id", "source"], name: "index_async_transactions_on_transaction_id_and_source", unique: true
    t.index ["user_account_id"], name: "index_async_transactions_on_user_account_id"
    t.index ["user_uuid"], name: "index_async_transactions_on_user_uuid"
  end

  create_table "average_days_for_claim_completions", force: :cascade do |t|
    t.float "average_days"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "banners", force: :cascade do |t|
    t.string "alert_type"
    t.text "content"
    t.jsonb "context"
    t.datetime "created_at", null: false
    t.boolean "email_updates_button"
    t.string "entity_bundle"
    t.integer "entity_id", null: false
    t.boolean "find_facilities_cta"
    t.string "headline"
    t.boolean "limit_subpage_inheritance"
    t.boolean "operating_status_cta"
    t.string "path"
    t.boolean "show_close"
    t.datetime "updated_at", null: false
    t.index ["entity_id"], name: "index_banners_on_entity_id", unique: true
    t.index ["path"], name: "index_banners_on_path"
  end

  create_table "base_facilities", id: false, force: :cascade do |t|
    t.jsonb "access"
    t.string "active_status"
    t.jsonb "address"
    t.string "classification"
    t.datetime "created_at", null: false
    t.string "facility_type", null: false
    t.jsonb "feedback"
    t.string "fingerprint"
    t.jsonb "hours"
    t.float "lat", null: false
    t.geography "location", limit: {srid: 4326, type: "st_point", geographic: true}
    t.float "long", null: false
    t.boolean "mobile"
    t.string "name", null: false
    t.jsonb "phone"
    t.jsonb "services"
    t.string "unique_id", null: false
    t.datetime "updated_at", null: false
    t.string "visn"
    t.string "website"
    t.index ["lat"], name: "index_base_facilities_on_lat"
    t.index ["location"], name: "index_base_facilities_on_location", using: :gist
    t.index ["name"], name: "index_base_facilities_on_name", opclass: :gin_trgm_ops, using: :gin
    t.index ["unique_id", "facility_type"], name: "index_base_facilities_on_unique_id_and_facility_type", unique: true
  end

  create_table "bgs_submission_attempts", force: :cascade do |t|
    t.string "bgs_claim_id", comment: "claim ID returned from BGS"
    t.bigint "bgs_submission_id", null: false
    t.datetime "bgs_updated_at", comment: "timestamp of the last update from bgs"
    t.datetime "created_at", null: false
    t.text "encrypted_kms_key", comment: "KMS key used to encrypt sensitive data"
    t.jsonb "error_message_ciphertext", comment: "encrypted error message from the bgs submission"
    t.jsonb "metadata_ciphertext", comment: "encrypted metadata sent with the submission"
    t.boolean "needs_kms_rotation", default: false, null: false
    t.jsonb "response_ciphertext", comment: "encrypted response from the bgs submission"
    t.enum "status", default: "pending", enum_type: "bgs_submission_status"
    t.datetime "submitted_at", comment: "timestamp when submitted to BGS"
    t.datetime "updated_at", null: false
    t.index ["bgs_submission_id"], name: "index_bgs_submission_attempts_on_bgs_submission_id"
  end

  create_table "bgs_submissions", force: :cascade do |t|
    t.string "bgs_claim_id", comment: "claim ID in BGS system"
    t.datetime "created_at", null: false
    t.text "encrypted_kms_key", comment: "KMS key used to encrypt sensitive data"
    t.string "form_id", null: false, comment: "form type of the submission"
    t.enum "latest_status", default: "pending", enum_type: "bgs_submission_status"
    t.boolean "needs_kms_rotation", default: false, null: false
    t.jsonb "reference_data_ciphertext", comment: "encrypted data that can be used to identify the resource - ie, ICN, etc"
    t.bigint "saved_claim_id"
    t.datetime "updated_at", null: false
    t.index ["saved_claim_id"], name: "index_bgs_submissions_on_saved_claim_id"
  end

  create_table "bpds_submission_attempts", force: :cascade do |t|
    t.string "bpds_id", comment: "ID of the submission in BPDS"
    t.bigint "bpds_submission_id", null: false
    t.datetime "bpds_updated_at", comment: "timestamp of the last update from bpds"
    t.datetime "created_at", null: false
    t.text "encrypted_kms_key", comment: "KMS key used to encrypt sensitive data"
    t.jsonb "error_message_ciphertext", comment: "encrypted error message from the bpds submission"
    t.jsonb "metadata_ciphertext", comment: "encrypted metadata sent with the submission"
    t.boolean "needs_kms_rotation", default: false, null: false
    t.jsonb "response_ciphertext", comment: "encrypted response from the bpds submission"
    t.enum "status", default: "pending", enum_type: "bpds_submission_status"
    t.datetime "updated_at", null: false
    t.index ["bpds_submission_id"], name: "index_bpds_submission_attempts_on_bpds_submission_id"
    t.index ["needs_kms_rotation"], name: "index_bpds_submission_attempts_on_needs_kms_rotation"
  end

  create_table "bpds_submissions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "encrypted_kms_key", comment: "KMS key used to encrypt the reference data"
    t.string "form_id", null: false, comment: "form type of the submission"
    t.enum "latest_status", default: "pending", enum_type: "bpds_submission_status"
    t.boolean "needs_kms_rotation", default: false, null: false
    t.jsonb "reference_data_ciphertext", comment: "encrypted data that can be used to identify the resource - ie, ICN, etc"
    t.integer "saved_claim_id", comment: "ID of the saved claim in vets-api"
    t.datetime "updated_at", null: false
    t.string "va_claim_id", comment: "claim ID in VA (non-vets-api) systems"
    t.index ["needs_kms_rotation"], name: "index_bpds_submissions_on_needs_kms_rotation"
  end

  create_table "cave_submissions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "cave_document_id"
    t.string "cave_response_ciphertext"
    t.text "change_log_ciphertext"
    t.datetime "created_at", null: false
    t.datetime "delete_date"
    t.text "encrypted_kms_key"
    t.string "idp_user_id"
    t.string "kvpid"
    t.boolean "needs_kms_rotation", default: false, null: false
    t.bigint "saved_claim_id"
    t.datetime "updated_at", null: false
    t.index ["delete_date"], name: "index_cave_submissions_on_delete_date"
    t.index ["saved_claim_id"], name: "index_cave_submissions_on_saved_claim_id"
  end

  create_table "central_mail_submissions", id: :serial, force: :cascade do |t|
    t.integer "saved_claim_id", null: false
    t.string "state", default: "pending", null: false
    t.index ["saved_claim_id"], name: "index_central_mail_submissions_on_saved_claim_id"
    t.index ["state"], name: "index_central_mail_submissions_on_state"
  end

  create_table "claim_va_notifications", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.boolean "email_sent"
    t.string "email_template_id"
    t.string "form_type"
    t.uuid "notification_id"
    t.string "notification_status"
    t.string "notification_type"
    t.bigint "saved_claim_id", null: false
    t.datetime "updated_at", null: false
    t.index ["saved_claim_id"], name: "index_claim_va_notifications_on_saved_claim_id"
  end

  create_table "claims_api_auto_established_claims", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.text "auth_headers_ciphertext"
    t.text "bgs_flash_responses_ciphertext"
    t.text "bgs_special_issue_responses_ciphertext"
    t.string "cid"
    t.datetime "created_at", null: false
    t.text "encrypted_kms_key"
    t.integer "evss_id"
    t.text "evss_response_ciphertext"
    t.text "file_data_ciphertext"
    t.string "flashes", default: [], array: true
    t.text "form_data_ciphertext"
    t.string "header_hash"
    t.string "md5"
    t.boolean "needs_kms_rotation", default: false, null: false
    t.string "source"
    t.jsonb "special_issues", default: []
    t.string "status"
    t.string "transaction_id"
    t.datetime "updated_at", null: false
    t.string "veteran_icn"
    t.index ["evss_id"], name: "index_claims_api_auto_established_claims_on_evss_id"
    t.index ["header_hash"], name: "index_claims_api_auto_established_claims_on_header_hash"
    t.index ["md5"], name: "index_claims_api_auto_established_claims_on_md5"
    t.index ["needs_kms_rotation"], name: "index_claims_api_auto_established_claims_on_needs_kms_rotation"
    t.index ["source"], name: "index_claims_api_auto_established_claims_on_source"
    t.index ["veteran_icn"], name: "index_claims_api_auto_established_claims_on_veteran_icn"
  end

  create_table "claims_api_claim_submissions", force: :cascade do |t|
    t.uuid "claim_id", null: false
    t.string "claim_type", null: false
    t.string "consumer_label", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["claim_id"], name: "index_claims_api_claim_submissions_on_claim_id"
  end

  create_table "claims_api_evidence_waiver_submissions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.text "auth_headers_ciphertext"
    t.string "bgs_error_message"
    t.integer "bgs_upload_failure_count", default: 0
    t.string "cid"
    t.string "claim_id"
    t.datetime "created_at", null: false
    t.text "encrypted_kms_key"
    t.boolean "needs_kms_rotation", default: false, null: false
    t.string "status"
    t.integer "tracked_items", default: [], array: true
    t.datetime "updated_at", null: false
    t.string "vbms_error_message"
    t.integer "vbms_upload_failure_count", default: 0
    t.index ["needs_kms_rotation"], name: "idx_on_needs_kms_rotation_5ea0be45c3"
  end

  create_table "claims_api_intent_to_files", force: :cascade do |t|
    t.string "cid"
    t.datetime "created_at", null: false
    t.string "status"
    t.datetime "updated_at", null: false
  end

  create_table "claims_api_organization_representatives", force: :cascade do |t|
    t.string "acceptance_mode", default: "no_acceptance", null: false
    t.datetime "created_at", null: false
    t.datetime "deactivated_at"
    t.string "organization_poa", limit: 3, null: false
    t.string "representative_id", null: false
    t.datetime "updated_at", null: false
    t.index ["organization_poa", "representative_id"], name: "idx_claims_api_org_reps_on_org_poa_and_rep_id", unique: true
    t.index ["representative_id"], name: "idx_claims_api_org_reps_on_representative_id"
    t.check_constraint "acceptance_mode::text = ANY (ARRAY['any_request'::character varying::text, 'self_only'::character varying::text, 'no_acceptance'::character varying::text])", name: "claims_api_org_reps_acceptance_mode_check"
  end

  create_table "claims_api_organizations", id: false, force: :cascade do |t|
    t.string "address_line1"
    t.string "address_line2"
    t.string "address_line3"
    t.string "address_type"
    t.boolean "can_accept_digital_poa_requests", default: false
    t.string "city"
    t.string "country_code_iso3"
    t.string "country_name"
    t.string "county_code"
    t.string "county_name"
    t.datetime "created_at", null: false
    t.string "default_new_rep_acceptance_mode", default: "no_acceptance", null: false
    t.string "international_postal_code"
    t.float "lat"
    t.geography "location", limit: {srid: 4326, type: "st_point", geographic: true}
    t.float "long"
    t.string "name"
    t.string "phone"
    t.string "poa", limit: 3
    t.string "primary_org_acceptance_mode", default: "no_acceptance", null: false
    t.string "province"
    t.jsonb "raw_address"
    t.string "state", limit: 2
    t.string "state_code"
    t.datetime "updated_at", null: false
    t.string "zip_code"
    t.string "zip_suffix"
    t.index ["location"], name: "index_claims_api_organizations_on_location", using: :gist
    t.index ["name"], name: "index_claims_api_organizations_on_name"
    t.index ["poa"], name: "index_claims_api_organizations_on_poa", unique: true
    t.check_constraint "default_new_rep_acceptance_mode::text = ANY (ARRAY['any_request'::character varying::text, 'self_only'::character varying::text, 'no_acceptance'::character varying::text])", name: "check_claims_api_orgs_default_new_rep_acceptance_mode"
    t.check_constraint "primary_org_acceptance_mode::text = ANY (ARRAY['any_request'::character varying::text, 'self_only'::character varying::text, 'no_acceptance'::character varying::text])", name: "check_claims_api_orgs_primary_org_acceptance_mode"
  end

  create_table "claims_api_power_of_attorney_requests", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "claimant_icn"
    t.datetime "created_at", null: false
    t.jsonb "metadata", default: {}
    t.string "poa_code"
    t.uuid "power_of_attorney_id"
    t.string "proc_id"
    t.datetime "updated_at", null: false
    t.string "veteran_icn"
    t.index ["power_of_attorney_id"], name: "idx_on_power_of_attorney_id_9fc9134311"
    t.index ["proc_id"], name: "index_claims_api_power_of_attorney_requests_on_proc_id"
  end

  create_table "claims_api_power_of_attorneys", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.text "auth_headers_ciphertext"
    t.string "cid"
    t.datetime "created_at", null: false
    t.string "current_poa"
    t.text "encrypted_kms_key"
    t.text "file_data_ciphertext"
    t.text "form_data_ciphertext"
    t.string "header_hash"
    t.string "header_md5"
    t.string "md5"
    t.boolean "needs_kms_rotation", default: false, null: false
    t.string "signature_errors", default: [], array: true
    t.text "source_data_ciphertext"
    t.string "status"
    t.datetime "updated_at", null: false
    t.string "vbms_document_series_ref_id"
    t.string "vbms_error_message"
    t.string "vbms_new_document_version_ref_id"
    t.integer "vbms_upload_failure_count", default: 0
    t.index ["header_hash"], name: "index_claims_api_power_of_attorneys_on_header_hash"
    t.index ["header_md5"], name: "index_claims_api_power_of_attorneys_on_header_md5"
    t.index ["needs_kms_rotation"], name: "index_claims_api_power_of_attorneys_on_needs_kms_rotation"
  end

  create_table "claims_api_processes", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.jsonb "error_messages", default: []
    t.uuid "processable_id", null: false
    t.string "processable_type", null: false
    t.string "step_status"
    t.string "step_type"
    t.datetime "updated_at", null: false
    t.index ["processable_id", "processable_type"], name: "idx_on_processable_id_processable_type_91e46b55a4"
  end

  create_table "claims_api_record_metadata", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "encrypted_kms_key"
    t.text "metadata_ciphertext"
    t.boolean "needs_kms_rotation", default: false, null: false
    t.text "request_ciphertext"
    t.text "request_headers_ciphertext"
    t.string "request_url_ciphertext"
    t.text "response_ciphertext"
    t.datetime "updated_at", null: false
    t.index ["needs_kms_rotation"], name: "index_claims_api_record_metadata_on_needs_kms_rotation"
  end

  create_table "claims_api_representatives", id: false, force: :cascade do |t|
    t.string "address_line1"
    t.string "address_line2"
    t.string "address_line3"
    t.string "address_type"
    t.string "city"
    t.string "country_code_iso3"
    t.string "country_name"
    t.string "county_code"
    t.string "county_name"
    t.datetime "created_at", null: false
    t.string "email"
    t.datetime "fallback_location_updated_at"
    t.string "first_name"
    t.string "full_name"
    t.string "international_postal_code"
    t.string "last_name"
    t.float "lat"
    t.geography "location", limit: {srid: 4326, type: "st_point", geographic: true}
    t.float "long"
    t.string "middle_initial"
    t.string "phone"
    t.string "phone_number"
    t.string "poa_codes", default: [], array: true
    t.string "province"
    t.jsonb "raw_address"
    t.string "representative_id"
    t.string "state_code"
    t.datetime "updated_at", null: false
    t.string "user_types", default: [], array: true
    t.string "zip_code"
    t.string "zip_suffix"
    t.index "lower((email)::text)", name: "index_claims_api_representatives_on_lower_email"
    t.index ["full_name"], name: "index_claims_api_representatives_on_full_name"
    t.index ["location"], name: "index_claims_api_representatives_on_location", using: :gist
    t.index ["representative_id"], name: "index_claims_api_representatives_on_representative_id", unique: true
    t.check_constraint "representative_id IS NOT NULL", name: "claims_api_representatives_representative_id_null"
  end

  create_table "claims_api_supporting_documents", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "auto_established_claim_id"
    t.datetime "created_at", null: false
    t.text "encrypted_kms_key"
    t.text "file_data_ciphertext"
    t.boolean "needs_kms_rotation", default: false, null: false
    t.datetime "updated_at", null: false
    t.index ["needs_kms_rotation"], name: "index_claims_api_supporting_documents_on_needs_kms_rotation"
  end

  create_table "claims_evidence_api_submission_attempts", force: :cascade do |t|
    t.bigint "claims_evidence_api_submissions_id", null: false
    t.datetime "created_at", null: false
    t.text "encrypted_kms_key", comment: "KMS key used to encrypt the reference data"
    t.jsonb "error_message_ciphertext", comment: "encrypted error message from the claims evidence api submission"
    t.jsonb "metadata_ciphertext", comment: "encrypted metadata sent with the submission"
    t.boolean "needs_kms_rotation", default: false, null: false
    t.jsonb "response_ciphertext", comment: "encrypted response from the claims evidence api submission"
    t.enum "status", default: "pending", enum_type: "claims_evidence_api_submission_status"
    t.datetime "updated_at", null: false
    t.index ["claims_evidence_api_submissions_id"], name: "idx_on_claims_evidence_api_submissions_id_40971596ee"
    t.index ["needs_kms_rotation"], name: "idx_on_needs_kms_rotation_516b2a537c"
  end

  create_table "claims_evidence_api_submissions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "encrypted_kms_key", comment: "KMS key used to encrypt the reference data"
    t.string "form_id", null: false, comment: "form type of the submission"
    t.enum "latest_status", default: "pending", enum_type: "claims_evidence_api_submission_status"
    t.boolean "needs_kms_rotation", default: false, null: false
    t.integer "persistent_attachment_id", comment: "ID of the attachment in vets-api"
    t.jsonb "reference_data_ciphertext", comment: "encrypted data that can be used to identify the resource"
    t.integer "saved_claim_id", null: false, comment: "ID of the saved claim in vets-api"
    t.datetime "updated_at", null: false
    t.string "va_claim_id", comment: "uuid returned from claims evidence api"
    t.index ["needs_kms_rotation"], name: "index_claims_evidence_api_submissions_on_needs_kms_rotation"
    t.index ["saved_claim_id", "persistent_attachment_id", "form_id"], name: "idx_claims_evidence_submissions_on_claim_attachment_form"
  end

  create_table "client_configs", force: :cascade do |t|
    t.string "access_token_attributes", default: [], array: true
    t.string "access_token_audience"
    t.interval "access_token_duration", null: false
    t.boolean "anti_csrf", null: false
    t.enum "auth_method", default: "pkce", null: false, enum_type: "client_config_auth_method"
    t.string "authentication", null: false
    t.string "client_id", null: false
    t.string "client_secret_digest"
    t.datetime "created_at", null: false
    t.string "credential_service_providers", default: ["logingov", "idme", "mhv"], array: true
    t.text "description"
    t.text "enforced_terms"
    t.boolean "json_api_compatibility", default: true, null: false
    t.text "logout_redirect_uri"
    t.boolean "oidc", default: false, null: false
    t.boolean "pkce"
    t.text "redirect_uri", null: false
    t.interval "refresh_token_duration", null: false
    t.string "service_levels", default: ["ial1", "ial2", "loa1", "loa3", "min"], array: true
    t.boolean "shared_sessions", default: false, null: false
    t.text "terms_of_use_url"
    t.datetime "updated_at", null: false
    t.index ["client_id"], name: "index_client_configs_on_client_id", unique: true
  end

  create_table "console1984_commands", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "sensitive_access_id"
    t.bigint "session_id", null: false
    t.text "statements"
    t.datetime "updated_at", null: false
    t.index ["sensitive_access_id"], name: "index_console1984_commands_on_sensitive_access_id"
    t.index ["session_id", "created_at", "sensitive_access_id"], name: "on_session_and_sensitive_chronologically"
  end

  create_table "console1984_sensitive_accesses", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "justification"
    t.bigint "session_id", null: false
    t.datetime "updated_at", null: false
    t.index ["session_id"], name: "index_console1984_sensitive_accesses_on_session_id"
  end

  create_table "console1984_sessions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "reason"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["created_at"], name: "index_console1984_sessions_on_created_at"
    t.index ["user_id", "created_at"], name: "index_console1984_sessions_on_user_id_and_created_at"
  end

  create_table "console1984_users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "username", null: false
    t.index ["username"], name: "index_console1984_users_on_username"
  end

  create_table "debt_transaction_logs", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.jsonb "debt_identifiers", default: [], null: false
    t.string "external_reference_id"
    t.string "state"
    t.jsonb "summary_data", default: {}
    t.datetime "transaction_completed_at"
    t.datetime "transaction_started_at", null: false
    t.string "transaction_type", null: false
    t.uuid "transactionable_id", null: false
    t.string "transactionable_type", null: false
    t.datetime "updated_at", null: false
    t.uuid "user_uuid", null: false
    t.index ["debt_identifiers"], name: "index_debt_transaction_logs_on_debt_identifiers", using: :gin
    t.index ["transaction_started_at"], name: "index_debt_transaction_logs_on_transaction_started_at"
    t.index ["transactionable_type", "transactionable_id"], name: "idx_on_transactionable_type_transactionable_id_52a8eee11c"
    t.index ["user_uuid", "transaction_type"], name: "index_debt_transaction_logs_on_user_uuid_and_transaction_type"
  end

  create_table "decision_review_notification_audit_logs", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "encrypted_kms_key"
    t.boolean "needs_kms_rotation", default: false, null: false
    t.text "notification_id"
    t.text "payload_ciphertext"
    t.integer "pdf_upload_attempt_count", default: 0
    t.text "pdf_upload_error"
    t.datetime "pdf_uploaded_at"
    t.text "reference"
    t.text "status"
    t.datetime "updated_at", null: false
    t.string "vbms_file_uuid"
    t.index ["needs_kms_rotation"], name: "idx_on_needs_kms_rotation_16518323ec"
    t.index ["notification_id"], name: "idx_on_notification_id_e2314be616"
    t.index ["reference"], name: "index_decision_review_notification_audit_logs_on_reference"
    t.index ["vbms_file_uuid"], name: "idx_on_vbms_file_uuid_b00c6bc3b9"
  end

  create_table "deprecated_user_accounts", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "user_account_id"
    t.bigint "user_verification_id"
    t.index ["user_account_id"], name: "index_deprecated_user_accounts_on_user_account_id", unique: true
    t.index ["user_verification_id"], name: "index_deprecated_user_accounts_on_user_verification_id", unique: true
  end

  create_table "devices", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "key"
    t.string "name"
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_devices_on_key", unique: true
  end

  create_table "digital_dispute_submissions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.jsonb "debt_identifiers", default: [], null: false
    t.text "encrypted_kms_key"
    t.string "error_message"
    t.text "form_data_ciphertext"
    t.uuid "guid", default: -> { "gen_random_uuid()" }, null: false
    t.text "metadata_ciphertext"
    t.boolean "needs_kms_rotation", default: false, null: false
    t.uuid "old_uuid_id", default: -> { "gen_random_uuid()" }, null: false
    t.jsonb "public_metadata", default: {}
    t.string "reference_id"
    t.integer "state", default: 0, null: false
    t.datetime "updated_at", null: false
    t.uuid "user_account_id"
    t.uuid "user_uuid", null: false
    t.index ["debt_identifiers"], name: "index_digital_dispute_submissions_on_debt_identifiers", using: :gin
    t.index ["guid"], name: "index_digital_dispute_submissions_on_guid", unique: true
    t.index ["needs_kms_rotation"], name: "index_digital_dispute_submissions_on_needs_kms_rotation"
    t.index ["user_account_id"], name: "index_digital_dispute_submissions_on_user_account_id"
    t.index ["user_uuid"], name: "index_digital_dispute_submissions_on_user_uuid"
  end

  create_table "digital_forms_api_submission_attempts", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "digital_forms_api_submission_id", null: false, comment: "parent submission"
    t.text "encrypted_kms_key", comment: "KMS key used to encrypt sensitive data"
    t.jsonb "error_message_ciphertext", comment: "encrypted error message from the digital forms api submission"
    t.jsonb "metadata_ciphertext", comment: "encrypted metadata sent with the submission"
    t.boolean "needs_kms_rotation", default: false, null: false, comment: "flag for daily KmsKeyRotation::BatchInitiatorJob re-encryption"
    t.jsonb "response_ciphertext", comment: "encrypted response from the digital forms api submission"
    t.enum "status", default: "pending", comment: "attempt status; cascaded into the parent latest_status by the base callback", enum_type: "digital_forms_api_submission_status"
    t.datetime "updated_at", null: false
    t.index ["digital_forms_api_submission_id"], name: "idx_on_digital_forms_api_submission_id_fdfe22899a"
    t.index ["needs_kms_rotation"], name: "index_dfa_submission_attempts_on_needs_kms_rotation"
    t.index ["status"], name: "index_dfa_submission_attempts_on_status"
  end

  create_table "digital_forms_api_submissions", force: :cascade do |t|
    t.string "bip_submission_id", comment: "upstream BIP (Benefits Intake Platform) submission identifier"
    t.string "claim_guid", comment: "vets-api SavedClaim guid for cross-system correlation"
    t.datetime "created_at", null: false
    t.text "encrypted_kms_key", comment: "KMS key used to encrypt the reference data"
    t.string "form_id", null: false, comment: "form type of the submission, e.g. 21-686c"
    t.enum "latest_status", default: "pending", comment: "latest status, cascaded from the most recent submission attempt", enum_type: "digital_forms_api_submission_status"
    t.boolean "needs_kms_rotation", default: false, null: false, comment: "flag for daily KmsKeyRotation::BatchInitiatorJob re-encryption"
    t.jsonb "reference_data_ciphertext", comment: "encrypted data used to identify the resource"
    t.integer "saved_claim_id", comment: "ID of the associated SavedClaim in vets-api, if any"
    t.datetime "updated_at", null: false
    t.uuid "user_account_id", comment: "owning UserAccount (uuid PK); nullable for unlinked pilot rows"
    t.index ["bip_submission_id"], name: "index_digital_forms_api_submissions_on_bip_submission_id", unique: true
    t.index ["form_id"], name: "index_digital_forms_api_submissions_on_form_id"
    t.index ["needs_kms_rotation"], name: "index_digital_forms_api_submissions_on_needs_kms_rotation"
    t.index ["user_account_id"], name: "index_digital_forms_api_submissions_on_user_account_id"
  end

  create_table "directory_applications", force: :cascade do |t|
    t.string "app_type"
    t.string "app_url"
    t.datetime "created_at", null: false
    t.text "description"
    t.string "logo_url"
    t.string "name"
    t.text "platforms", default: [], array: true
    t.string "privacy_url"
    t.text "service_categories", default: [], array: true
    t.string "tos_url"
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_directory_applications_on_name", unique: true
  end

  create_table "disability_contentions", id: :serial, force: :cascade do |t|
    t.integer "code", null: false
    t.datetime "created_at", null: false
    t.string "lay_term"
    t.string "medical_term", null: false
    t.datetime "updated_at", null: false
    t.index ["code"], name: "index_disability_contentions_on_code", unique: true
    t.index ["lay_term"], name: "index_disability_contentions_on_lay_term", opclass: :gin_trgm_ops, using: :gin
    t.index ["medical_term"], name: "index_disability_contentions_on_medical_term", opclass: :gin_trgm_ops, using: :gin
  end

  create_table "drivetime_bands", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "max"
    t.integer "min"
    t.string "name"
    t.geography "polygon", limit: {srid: 4326, type: "st_polygon", geographic: true}, null: false
    t.string "unit"
    t.datetime "updated_at", null: false
    t.string "vha_facility_id", null: false
    t.datetime "vssc_extract_date", default: "2001-01-01 00:00:00"
    t.index ["polygon"], name: "index_drivetime_bands_on_polygon", using: :gist
  end

  create_table "education_benefits_claims", id: :serial, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "encrypted_kms_key"
    t.text "form_ciphertext"
    t.string "form_type", default: "1990"
    t.datetime "processed_at"
    t.string "regional_processing_office", null: false
    t.integer "saved_claim_id", null: false
    t.datetime "submitted_at"
    t.string "token"
    t.datetime "updated_at", null: false
    t.index ["created_at"], name: "index_education_benefits_claims_on_created_at"
    t.index ["id"], name: "index_education_benefits_claims_on_unprocessed", where: "(processed_at IS NULL)"
    t.index ["saved_claim_id"], name: "index_education_benefits_claims_on_saved_claim_id"
    t.index ["submitted_at"], name: "index_education_benefits_claims_on_submitted_at"
    t.index ["token"], name: "index_education_benefits_claims_on_token", unique: true
  end

  create_table "education_benefits_submissions", id: :serial, force: :cascade do |t|
    t.boolean "chapter1606", default: false, null: false
    t.boolean "chapter1607", default: false, null: false
    t.boolean "chapter30", default: false, null: false
    t.boolean "chapter32", default: false, null: false
    t.boolean "chapter33", default: false, null: false
    t.boolean "chapter35", default: false, null: false
    t.datetime "created_at", null: false
    t.integer "education_benefits_claim_id"
    t.string "form_type", default: "1990", null: false
    t.string "region", null: false
    t.string "status", default: "submitted", null: false
    t.boolean "transfer_of_entitlement", default: false, null: false
    t.datetime "updated_at", null: false
    t.boolean "vettec", default: false
    t.boolean "vrrap", default: false, null: false
    t.index ["created_at"], name: "index_education_benefits_submissions_on_created_at"
    t.index ["education_benefits_claim_id"], name: "index_education_benefits_claim_id", unique: true
    t.index ["region", "created_at", "form_type"], name: "index_edu_benefits_subs_ytd"
  end

  create_table "education_stem_automated_decisions", force: :cascade do |t|
    t.text "auth_headers_json_ciphertext"
    t.string "automated_decision_state", default: "init"
    t.datetime "confirmation_email_sent_at"
    t.datetime "created_at", null: false
    t.datetime "denial_email_sent_at"
    t.bigint "education_benefits_claim_id"
    t.text "encrypted_kms_key"
    t.boolean "needs_kms_rotation", default: false, null: false
    t.boolean "poa"
    t.integer "remaining_entitlement"
    t.datetime "updated_at", null: false
    t.uuid "user_account_id"
    t.string "user_uuid", null: false
    t.index ["education_benefits_claim_id"], name: "index_education_stem_automated_decisions_on_claim_id"
    t.index ["needs_kms_rotation"], name: "index_education_stem_automated_decisions_on_needs_kms_rotation"
    t.index ["user_account_id"], name: "index_education_stem_automated_decisions_on_user_account_id"
    t.index ["user_uuid"], name: "index_education_stem_automated_decisions_on_user_uuid"
  end

  create_table "event_bus_gateway_notifications", force: :cascade do |t|
    t.integer "attempts", default: 1
    t.datetime "created_at", null: false
    t.string "template_id", null: false
    t.datetime "updated_at", null: false
    t.uuid "user_account_id"
    t.string "va_notify_id", null: false
    t.index ["user_account_id"], name: "index_event_bus_gateway_notifications_on_user_account_id"
    t.index ["va_notify_id"], name: "index_event_bus_gateway_notifications_on_va_notify_id"
  end

  create_table "event_bus_gateway_push_notifications", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "template_id", null: false
    t.datetime "updated_at", null: false
    t.uuid "user_account_id"
    t.index ["user_account_id"], name: "index_event_bus_gateway_push_notifications_on_user_account_id"
  end

  create_table "evidence_submissions", force: :cascade do |t|
    t.datetime "acknowledgement_date"
    t.string "caseflow_claim_id"
    t.integer "claim_id"
    t.datetime "created_at", null: false
    t.datetime "delete_date"
    t.text "encrypted_kms_key"
    t.string "error_message"
    t.datetime "failed_date"
    t.integer "file_size"
    t.string "job_class"
    t.string "job_id"
    t.boolean "needs_kms_rotation", default: false, null: false
    t.integer "request_id"
    t.json "template_metadata_ciphertext"
    t.integer "tracked_item_id"
    t.datetime "updated_at", null: false
    t.string "upload_status"
    t.uuid "user_account_id", null: false
    t.datetime "va_notify_date"
    t.string "va_notify_id"
    t.string "va_notify_status"
    t.index ["caseflow_claim_id"], name: "index_evidence_submissions_on_caseflow_claim_id"
    t.index ["claim_id"], name: "index_evidence_submissions_on_claim_id"
    t.index ["needs_kms_rotation"], name: "index_evidence_submissions_on_needs_kms_rotation"
    t.index ["user_account_id"], name: "index_evidence_submissions_on_user_account_id"
  end

  create_table "evss_claims", id: :serial, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.json "data", null: false
    t.integer "evss_id", null: false
    t.json "list_data", default: {}, null: false
    t.boolean "requested_decision", default: false, null: false
    t.datetime "updated_at", null: false
    t.uuid "user_account_id"
    t.string "user_uuid", null: false
    t.index ["evss_id"], name: "index_evss_claims_on_evss_id"
    t.index ["updated_at"], name: "index_evss_claims_on_updated_at"
    t.index ["user_account_id"], name: "index_evss_claims_on_user_account_id"
    t.index ["user_uuid"], name: "index_evss_claims_on_user_uuid"
  end

  create_table "excel_file_events", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "filename"
    t.integer "number_of_submissions"
    t.integer "retry_attempt", default: 0
    t.datetime "successful_at", precision: nil
    t.datetime "updated_at", null: false
    t.index ["filename"], name: "index_excel_file_events_uniqueness", unique: true
  end

  create_table "feature_toggle_events", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "feature_name"
    t.string "gate_name"
    t.string "operation"
    t.datetime "updated_at", null: false
    t.string "user"
    t.string "value"
    t.index ["feature_name"], name: "index_feature_toggle_events_on_feature_name"
  end

  create_table "flipper_features", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "key", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_flipper_features_on_key", unique: true
  end

  create_table "flipper_gates", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "feature_key", null: false
    t.string "key", null: false
    t.datetime "updated_at", null: false
    t.text "value"
    t.index ["feature_key", "key", "value"], name: "index_flipper_gates_on_feature_key_and_key_and_value", unique: true
  end

  create_table "form1010cg_submissions", force: :cascade do |t|
    t.datetime "accepted_at", null: false
    t.json "attachments"
    t.string "carma_case_id", limit: 18, null: false
    t.uuid "claim_guid", null: false
    t.datetime "created_at", null: false
    t.json "metadata"
    t.datetime "updated_at", null: false
    t.index ["carma_case_id"], name: "index_form1010cg_submissions_on_carma_case_id", unique: true
    t.index ["claim_guid"], name: "index_form1010cg_submissions_on_claim_guid", unique: true
  end

  create_table "form21a_document_submission_attempts", force: :cascade do |t|
    t.datetime "attempted_at", comment: "timestamp when this upload attempt ran"
    t.datetime "created_at", null: false
    t.text "encrypted_kms_key", comment: "KMS key used to encrypt sensitive data"
    t.jsonb "error_message_ciphertext", comment: "encrypted error message from the GCLAWS upload"
    t.enum "failure_classification", enum_type: "form21a_upload_failure_classification"
    t.bigint "form21a_document_submission_id", null: false
    t.integer "last_http_status", comment: "HTTP status from GCLAWS on this attempt"
    t.jsonb "metadata_ciphertext", comment: "encrypted metadata sent with the submission"
    t.boolean "needs_kms_rotation", default: false, null: false
    t.jsonb "response_ciphertext", comment: "encrypted response from the GCLAWS upload"
    t.enum "status", default: "pending", enum_type: "form21a_document_submission_status"
    t.datetime "updated_at", null: false
    t.index ["form21a_document_submission_id"], name: "idx_form21a_doc_attempts_on_submission_id"
    t.index ["needs_kms_rotation"], name: "idx_form21a_doc_attempts_on_needs_kms_rotation"
  end

  create_table "form21a_document_submissions", force: :cascade do |t|
    t.string "application_id", null: false, comment: "GCLAWS application this document belongs to"
    t.string "content_type", comment: "content type needed to re-upload the document"
    t.datetime "created_at", null: false
    t.integer "document_type", comment: "GCLAWS document-type code"
    t.text "encrypted_kms_key", comment: "KMS key used to encrypt the reference data"
    t.uuid "form21a_attachment_guid", null: false, comment: "guid of the Form21aAttachment / S3 object"
    t.string "form_id", null: false, comment: "form type of the submission"
    t.datetime "last_attempted_at", comment: "timestamp of the last upload attempt"
    t.datetime "last_stuck_alerted_at", comment: "timestamp when Ops was last alerted that this document upload was stuck"
    t.enum "latest_status", default: "pending", enum_type: "form21a_document_submission_status"
    t.boolean "needs_kms_rotation", default: false, null: false
    t.datetime "next_retry_at", comment: "timestamp when this document is eligible for re-drive"
    t.jsonb "reference_data_ciphertext", comment: "encrypted data that can be used to identify the resource - ie, original filename, ICN, user account ID, etc"
    t.datetime "succeeded_at", comment: "timestamp when this document upload succeeded"
    t.datetime "updated_at", null: false
    t.index ["application_id"], name: "idx_form21a_doc_subs_on_application_id"
    t.index ["form21a_attachment_guid"], name: "idx_form21a_doc_subs_on_attachment_guid", unique: true
    t.index ["last_stuck_alerted_at"], name: "idx_form21a_doc_subs_on_last_stuck_alerted_at"
    t.index ["latest_status", "next_retry_at"], name: "idx_form21a_doc_subs_on_status_and_retry_at"
    t.index ["needs_kms_rotation"], name: "idx_form21a_doc_subs_on_needs_kms_rotation"
  end

  create_table "form526_job_statuses", id: :serial, force: :cascade do |t|
    t.jsonb "bgjob_errors", default: {}
    t.string "error_class"
    t.string "error_message"
    t.integer "form526_submission_id", null: false
    t.string "job_class", null: false
    t.string "job_id", null: false
    t.string "status", null: false
    t.datetime "updated_at", null: false
    t.index ["bgjob_errors"], name: "index_form526_job_statuses_on_bgjob_errors", using: :gin
    t.index ["form526_submission_id"], name: "index_form526_job_statuses_on_form526_submission_id"
    t.index ["job_id"], name: "index_form526_job_statuses_on_job_id", unique: true
  end

  create_table "form526_submission_remediations", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "form526_submission_id", null: false
    t.boolean "ignored_as_duplicate", default: false
    t.text "lifecycle", default: [], array: true
    t.integer "remediation_type", default: 0
    t.boolean "success", default: true
    t.datetime "updated_at", null: false
    t.index ["form526_submission_id"], name: "index_form526_submission_remediations_on_form526_submission_id"
  end

  create_table "form526_submissions", id: :serial, force: :cascade do |t|
    t.string "aasm_state", default: "unprocessed"
    t.text "auth_headers_json_ciphertext"
    t.string "backup_submitted_claim_id", comment: "*After* a SubmitForm526 Job has exhausted all attempts, a paper submission is generated and sent to Central Mail Portal.This column will be nil for all submissions where a backup submission is not generated.It will have the central mail id for submissions where a backup submission is submitted."
    t.integer "backup_submitted_claim_status"
    t.text "birls_ids_tried_ciphertext"
    t.datetime "created_at", null: false
    t.text "encrypted_kms_key"
    t.text "form_json_ciphertext"
    t.boolean "multiple_birls", comment: "*After* a SubmitForm526 Job fails, a lookup is done to see if the veteran has multiple BIRLS IDs. This field gets set to true if that is the case. If the initial submit job succeeds, this field will remain false whether or not the veteran has multiple BIRLS IDs --so this field cannot technically be used to sum all Form526 veterans that have multiple BIRLS. This field /can/ give us an idea of how often having multiple BIRLS IDs is a problem."
    t.boolean "needs_kms_rotation", default: false, null: false
    t.integer "saved_claim_id", null: false
    t.integer "submit_endpoint"
    t.integer "submitted_claim_id"
    t.datetime "updated_at", null: false
    t.uuid "user_account_id"
    t.string "user_uuid", null: false
    t.boolean "workflow_complete", default: false, null: false
    t.index ["backup_submitted_claim_id"], name: "index_form526_submissions_on_backup_submitted_claim_id"
    t.index ["needs_kms_rotation"], name: "index_form526_submissions_on_needs_kms_rotation"
    t.index ["saved_claim_id"], name: "index_form526_submissions_on_saved_claim_id", unique: true
    t.index ["submitted_claim_id"], name: "index_form526_submissions_on_submitted_claim_id", unique: true
    t.index ["user_account_id"], name: "index_form526_submissions_on_user_account_id"
    t.index ["user_uuid"], name: "index_form526_submissions_on_user_uuid"
  end

  create_table "form5655_submissions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "encrypted_kms_key"
    t.string "error_message"
    t.text "form_json_ciphertext", null: false
    t.text "ipf_data_ciphertext"
    t.text "metadata_ciphertext"
    t.boolean "needs_kms_rotation", default: false, null: false
    t.jsonb "public_metadata"
    t.integer "state", default: 0
    t.datetime "updated_at", null: false
    t.uuid "user_account_id"
    t.string "user_uuid", null: false
    t.index ["needs_kms_rotation"], name: "index_form5655_submissions_on_needs_kms_rotation"
    t.index ["user_account_id"], name: "index_form5655_submissions_on_user_account_id"
    t.index ["user_uuid"], name: "index_form5655_submissions_on_user_uuid"
  end

  create_table "form_attachments", id: :serial, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "encrypted_kms_key"
    t.text "file_data_ciphertext"
    t.uuid "guid", null: false
    t.boolean "needs_kms_rotation", default: false, null: false
    t.string "type", null: false
    t.datetime "updated_at", null: false
    t.index ["guid", "type"], name: "index_form_attachments_on_guid_and_type", unique: true
    t.index ["id", "type"], name: "index_form_attachments_on_id_and_type"
    t.index ["needs_kms_rotation"], name: "index_form_attachments_on_needs_kms_rotation"
  end

  create_table "form_email_matches_profile_logs", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "in_progress_form_id", null: false
    t.datetime "updated_at", null: false
    t.uuid "user_account_id"
    t.string "user_uuid", null: false
    t.index ["user_account_id"], name: "index_form_email_matches_profile_logs_on_user_account_id"
    t.index ["user_uuid", "in_progress_form_id"], name: "idx_on_user_uuid_in_progress_form_id_f21f47b9c8", unique: true
  end

  create_table "form_intake_submissions", force: :cascade do |t|
    t.string "aasm_state", default: "pending", null: false
    t.string "benefits_intake_uuid", null: false
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.text "encrypted_kms_key", comment: "KMS key used to encrypt sensitive data"
    t.text "error_message_ciphertext"
    t.string "form_intake_submission_id"
    t.bigint "form_submission_id", null: false
    t.string "gcio_tracking_number"
    t.datetime "last_attempted_at"
    t.boolean "needs_kms_rotation", default: false, null: false
    t.text "request_payload_ciphertext"
    t.text "response_ciphertext"
    t.integer "retry_count", default: 0, null: false
    t.datetime "submitted_at"
    t.datetime "updated_at", null: false
    t.index ["aasm_state", "created_at"], name: "idx_form_intake_sub_on_state_and_created"
    t.index ["aasm_state"], name: "index_form_intake_submissions_on_aasm_state"
    t.index ["benefits_intake_uuid"], name: "index_form_intake_submissions_on_benefits_intake_uuid"
    t.index ["form_intake_submission_id"], name: "idx_form_intake_sub_on_intake_id", unique: true, where: "(form_intake_submission_id IS NOT NULL)"
    t.index ["form_submission_id", "aasm_state"], name: "idx_form_intake_sub_on_form_sub_id_and_state"
    t.index ["form_submission_id"], name: "index_form_intake_submissions_on_form_submission_id"
    t.index ["last_attempted_at"], name: "idx_form_intake_sub_on_last_attempted", where: "((aasm_state)::text = 'pending'::text)"
  end

  create_table "form_submission_attempts", force: :cascade do |t|
    t.string "aasm_state"
    t.uuid "benefits_intake_uuid"
    t.datetime "created_at", null: false
    t.text "encrypted_kms_key"
    t.string "error_message"
    t.text "error_message_ciphertext"
    t.bigint "form_submission_id", null: false
    t.datetime "lighthouse_updated_at"
    t.boolean "needs_kms_rotation", default: false, null: false
    t.jsonb "response"
    t.jsonb "response_ciphertext"
    t.datetime "updated_at", null: false
    t.index ["benefits_intake_uuid"], name: "index_form_submission_attempts_on_benefits_intake_uuid"
    t.index ["form_submission_id"], name: "index_form_submission_attempts_on_form_submission_id"
    t.index ["needs_kms_rotation"], name: "index_form_submission_attempts_on_needs_kms_rotation"
  end

  create_table "form_submissions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "encrypted_kms_key"
    t.datetime "expiration_email_sent_at"
    t.jsonb "form_data_ciphertext"
    t.string "form_type", null: false
    t.boolean "needs_kms_rotation", default: false, null: false
    t.bigint "saved_claim_id"
    t.datetime "updated_at", null: false
    t.uuid "user_account_id"
    t.index ["needs_kms_rotation"], name: "index_form_submissions_on_needs_kms_rotation"
    t.index ["saved_claim_id"], name: "index_form_submissions_on_saved_claim_id"
    t.index ["user_account_id"], name: "index_form_submissions_on_user_account_id"
  end

  create_table "gibs_not_found_users", id: :serial, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "dob", null: false
    t.string "edipi", null: false
    t.text "encrypted_kms_key"
    t.string "first_name", null: false
    t.string "last_name", null: false
    t.boolean "needs_kms_rotation", default: false, null: false
    t.text "ssn_ciphertext"
    t.datetime "updated_at", null: false
    t.index ["edipi"], name: "index_gibs_not_found_users_on_edipi", unique: true
    t.index ["needs_kms_rotation"], name: "index_gibs_not_found_users_on_needs_kms_rotation"
  end

  create_table "gmt_thresholds", force: :cascade do |t|
    t.string "county_name", null: false
    t.datetime "created", null: false
    t.string "created_by"
    t.integer "effective_year", null: false
    t.integer "fips", null: false
    t.integer "msa", null: false
    t.string "msa_name"
    t.string "state_name", null: false
    t.integer "trhd1", null: false
    t.integer "trhd2", null: false
    t.integer "trhd3", null: false
    t.integer "trhd4", null: false
    t.integer "trhd5", null: false
    t.integer "trhd6", null: false
    t.integer "trhd7", null: false
    t.integer "trhd8", null: false
    t.datetime "updated"
    t.string "updated_by"
    t.integer "version", null: false
  end

  create_table "health_care_applications", id: :serial, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "form_submission_id_string"
    t.string "state", default: "pending", null: false
    t.string "timestamp"
    t.datetime "updated_at", null: false
    t.uuid "user_account_id"
    t.index ["user_account_id"], name: "index_health_care_applications_on_user_account_id"
  end

  create_table "health_facilities", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name"
    t.string "postal_name"
    t.string "station_number"
    t.datetime "updated_at", null: false
    t.index ["station_number"], name: "index_health_facilities_on_station_number", unique: true
  end

  create_table "health_quest_questionnaire_responses", force: :cascade do |t|
    t.string "appointment_id"
    t.datetime "created_at", null: false
    t.text "encrypted_kms_key"
    t.boolean "needs_kms_rotation", default: false, null: false
    t.text "questionnaire_response_data_ciphertext"
    t.string "questionnaire_response_id"
    t.datetime "updated_at", null: false
    t.uuid "user_account_id"
    t.text "user_demographics_data_ciphertext"
    t.string "user_uuid"
    t.index ["needs_kms_rotation"], name: "idx_on_needs_kms_rotation_01daeb119b"
    t.index ["user_account_id"], name: "index_health_quest_questionnaire_responses_on_user_account_id"
    t.index ["user_uuid", "questionnaire_response_id"], name: "find_by_user_qr", unique: true
  end

  create_table "id_card_announcement_subscriptions", id: :serial, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_id_card_announcement_subscriptions_on_email", unique: true
  end

  create_table "in_progress_forms", id: :serial, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "encrypted_kms_key"
    t.datetime "expires_at"
    t.text "form_data_ciphertext"
    t.string "form_id", null: false
    t.json "metadata"
    t.boolean "needs_kms_rotation", default: false, null: false
    t.integer "status", default: 0
    t.datetime "updated_at", null: false
    t.uuid "user_account_id"
    t.string "user_uuid", null: false
    t.index ["form_id", "user_uuid"], name: "index_in_progress_forms_on_form_id_and_user_uuid", unique: true
    t.index ["needs_kms_rotation"], name: "index_in_progress_forms_on_needs_kms_rotation"
    t.index ["user_account_id"], name: "index_in_progress_forms_on_user_account_id"
    t.index ["user_uuid"], name: "index_in_progress_forms_on_user_uuid"
  end

  create_table "intent_to_file_queue_exhaustions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "form_start_date"
    t.string "form_type"
    t.enum "status", default: "unprocessed", enum_type: "itf_remediation_status"
    t.datetime "updated_at", null: false
    t.string "veteran_icn", null: false
    t.index ["veteran_icn"], name: "index_intent_to_file_queue_exhaustions_on_veteran_icn"
  end

  create_table "invalid_letter_address_edipis", id: :serial, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "edipi", null: false
    t.datetime "updated_at", null: false
    t.index ["edipi"], name: "index_invalid_letter_address_edipis_on_edipi", unique: true
  end

  create_table "ivc_champva_applicants", force: :cascade do |t|
    t.text "applicant_first_name_ciphertext"
    t.text "applicant_icn_ciphertext"
    t.text "applicant_last_name_ciphertext"
    t.datetime "created_at", null: false
    t.boolean "documents_requested", default: false, null: false
    t.boolean "eligibility_resolved", default: false, null: false
    t.text "encrypted_kms_key"
    t.boolean "needs_kms_rotation", default: false, null: false
    t.string "person_type", null: false, comment: "SPONSOR or BENEFICIARY, as returned by VES ICN lookup"
    t.string "sponsor_eligibility_reason"
    t.string "sponsor_eligibility_status"
    t.text "sponsor_icn_ciphertext"
    t.uuid "transaction_uuid", null: false
    t.datetime "updated_at", null: false
    t.string "ves_eligibility_reason"
    t.string "ves_eligibility_status"
    t.date "ves_status_updated_date"
    t.index ["needs_kms_rotation"], name: "index_ivc_champva_applicants_on_needs_kms_rotation"
    t.index ["transaction_uuid", "applicant_icn_ciphertext"], name: "index_ivc_champva_applicants_on_txn_uuid_and_icn_ciphertext", unique: true
    t.index ["transaction_uuid"], name: "index_ivc_champva_applicants_on_transaction_uuid"
  end

  create_table "ivc_champva_forms", force: :cascade do |t|
    t.boolean "application_decided", default: false, null: false
    t.boolean "application_is_closed", default: false, null: false
    t.uuid "application_uuid"
    t.string "case_id"
    t.datetime "created_at", null: false
    t.string "email"
    t.boolean "email_sent", default: false, null: false
    t.text "encrypted_kms_key"
    t.string "file_name"
    t.string "first_name"
    t.string "form_number"
    t.uuid "form_uuid"
    t.string "last_name"
    t.datetime "last_ves_fetch_at"
    t.boolean "needs_kms_rotation", default: false, null: false
    t.string "pega_status"
    t.text "request_json_ciphertext"
    t.string "s3_status"
    t.string "submitted_by_icn", comment: "ICN of the authenticated user who submitted the form. Null for unauthenticated submissions or forms created before this column existed."
    t.uuid "transaction_uuid"
    t.datetime "updated_at", null: false
    t.text "ves_request_data_ciphertext"
    t.string "ves_status"
    t.index ["email"], name: "index_ivc_champva_forms_on_email"
    t.index ["form_uuid"], name: "index_ivc_champva_forms_on_form_uuid"
    t.index ["form_uuid"], name: "index_ivc_champva_forms_on_pending_form_uuid", where: "((pega_status IS NULL) OR ((pega_status)::text <> ALL (ARRAY[('eligiblity denied/additional information needed'::character varying)::text, ('eligibility denied/additional information needed'::character varying)::text, ('processed - eligiblity determination unknown'::character varying)::text, ('processed - eligibility determination unknown'::character varying)::text, ('eligible - issued a card'::character varying)::text, ('duplicate application'::character varying)::text, ('eligible - reissued a card'::character varying)::text, ('document identification error'::character varying)::text, ('processed'::character varying)::text, ('manually processed'::character varying)::text])))"
    t.index ["needs_kms_rotation"], name: "index_ivc_champva_forms_on_needs_kms_rotation"
    t.index ["updated_at"], name: "index_ivc_champva_forms_on_updated_at"
  end

  create_table "ivc_champva_letters", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "form_number"
    t.bigint "ivc_champva_applicant_id", null: false
    t.string "letter_name"
    t.string "mail_status"
    t.datetime "mail_status_date"
    t.datetime "updated_at", null: false
    t.index ["ivc_champva_applicant_id"], name: "index_ivc_champva_letters_on_ivc_champva_applicant_id"
  end

  create_table "ivc_champva_sponsors", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "eligibility_status"
    t.text "encrypted_kms_key"
    t.text "first_name_ciphertext"
    t.text "last_name_ciphertext"
    t.boolean "needs_kms_rotation", default: false, null: false
    t.string "reason"
    t.text "sponsor_icn_ciphertext"
    t.uuid "transaction_uuid", null: false
    t.datetime "updated_at", null: false
    t.index ["needs_kms_rotation"], name: "index_ivc_champva_sponsors_on_needs_kms_rotation_true", where: "(needs_kms_rotation = true)"
    t.index ["transaction_uuid"], name: "index_ivc_champva_sponsors_on_transaction_uuid", unique: true
  end

  create_table "lighthouse526_document_uploads", force: :cascade do |t|
    t.string "aasm_state"
    t.datetime "created_at", null: false
    t.string "document_type"
    t.jsonb "error_message"
    t.bigint "form526_submission_id", null: false
    t.bigint "form_attachment_id"
    t.jsonb "last_status_response"
    t.string "lighthouse_document_request_id", null: false
    t.datetime "lighthouse_processing_ended_at"
    t.datetime "lighthouse_processing_started_at"
    t.datetime "status_last_polled_at"
    t.datetime "updated_at", null: false
    t.index ["aasm_state"], name: "index_lighthouse526_document_uploads_on_aasm_state"
    t.index ["form526_submission_id"], name: "index_lighthouse526_document_uploads_on_form526_submission_id"
    t.index ["form_attachment_id"], name: "index_lighthouse526_document_uploads_on_form_attachment_id"
    t.index ["status_last_polled_at"], name: "index_lighthouse526_document_uploads_on_status_last_polled_at"
  end

  create_table "lighthouse_submission_attempts", force: :cascade do |t|
    t.string "benefits_intake_uuid"
    t.datetime "created_at", null: false
    t.text "encrypted_kms_key", comment: "KMS key used to encrypt sensitive data"
    t.jsonb "error_message_ciphertext", comment: "encrypted error message from the lighthouse submission"
    t.bigint "lighthouse_submission_id", null: false
    t.datetime "lighthouse_updated_at", comment: "timestamp of the last update from lighthouse"
    t.jsonb "metadata_ciphertext", comment: "encrypted metadata sent with the submission"
    t.boolean "needs_kms_rotation", default: false, null: false
    t.jsonb "response_ciphertext", comment: "encrypted response from the lighthouse submission"
    t.enum "status", default: "pending", enum_type: "lighthouse_submission_status"
    t.datetime "updated_at", null: false
    t.index ["lighthouse_submission_id"], name: "idx_on_lighthouse_submission_id_e6e3dbad55"
    t.index ["needs_kms_rotation"], name: "index_lighthouse_submission_attempts_on_needs_kms_rotation"
  end

  create_table "lighthouse_submissions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "encrypted_kms_key", comment: "KMS key used to encrypt the reference data"
    t.string "form_id", null: false, comment: "form type of the submission"
    t.enum "latest_status", default: "pending", enum_type: "lighthouse_submission_status"
    t.boolean "needs_kms_rotation", default: false, null: false
    t.jsonb "reference_data_ciphertext", comment: "encrypted data that can be used to identify the resource - ie, ICN, etc"
    t.integer "saved_claim_id", comment: "ID of the saved claim in vets-api"
    t.datetime "updated_at", null: false
    t.index ["needs_kms_rotation"], name: "index_lighthouse_submissions_on_needs_kms_rotation"
  end

  create_table "maintenance_windows", id: :serial, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "description"
    t.datetime "end_time"
    t.string "external_service"
    t.string "pagerduty_id"
    t.datetime "start_time"
    t.datetime "updated_at", null: false
    t.index ["end_time"], name: "index_maintenance_windows_on_end_time"
    t.index ["pagerduty_id"], name: "index_maintenance_windows_on_pagerduty_id"
    t.index ["start_time"], name: "index_maintenance_windows_on_start_time"
  end

  create_table "mhv_metrics_unique_user_events", id: false, force: :cascade do |t|
    t.datetime "created_at", precision: nil
    t.string "event_name", limit: 50, null: false, comment: "Event type name"
    t.uuid "user_id", null: false, comment: "Unique user identifier"
    t.index ["user_id", "event_name"], name: "index_mhv_metrics_unique_user_events_on_user_id_and_event_name", unique: true
  end

  create_table "mhv_opt_in_flags", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "feature", null: false
    t.datetime "updated_at", null: false
    t.uuid "user_account_id"
    t.index ["feature"], name: "index_mhv_opt_in_flags_on_feature"
    t.index ["user_account_id"], name: "index_mhv_opt_in_flags_on_user_account_id"
  end

  create_table "mobile_survey_responses", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "encrypted_kms_key"
    t.jsonb "metadata"
    t.boolean "needs_kms_rotation", default: false, null: false
    t.text "survey_data_ciphertext", null: false
    t.string "survey_type", null: false
    t.datetime "updated_at", null: false
    t.string "user_uuid", null: false
    t.index ["needs_kms_rotation"], name: "index_mobile_survey_responses_on_needs_kms_rotation"
    t.index ["survey_type"], name: "index_mobile_survey_responses_on_survey_type"
  end

  create_table "multi_party_form_submissions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "form_type", null: false
    t.datetime "primary_completed_at"
    t.bigint "primary_in_progress_form_id"
    t.uuid "primary_user_uuid", null: false
    t.bigint "saved_claim_id"
    t.text "secondary_access_token_digest"
    t.datetime "secondary_access_token_expires_at"
    t.datetime "secondary_completed_at"
    t.string "secondary_email"
    t.bigint "secondary_in_progress_form_id"
    t.datetime "secondary_notified_at"
    t.uuid "secondary_user_uuid"
    t.string "status", default: "primary_in_progress", null: false
    t.datetime "submitted_at"
    t.datetime "updated_at", null: false
    t.index ["primary_in_progress_form_id"], name: "index_mpf_submissions_on_primary_form"
    t.index ["primary_user_uuid", "status", "form_type"], name: "index_mpf_submissions_on_primary_user_status_form"
    t.index ["saved_claim_id"], name: "index_mpf_submissions_on_saved_claim"
    t.index ["secondary_email", "status"], name: "index_mpf_submissions_on_secondary_email_status"
    t.index ["secondary_in_progress_form_id"], name: "index_mpf_submissions_on_secondary_form"
    t.index ["secondary_user_uuid", "status"], name: "index_mpf_submissions_on_secondary_user_status"
    t.index ["status", "created_at"], name: "index_mpf_submissions_on_status_created"
  end

  create_table "nod_notifications", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "encrypted_kms_key"
    t.boolean "needs_kms_rotation", default: false, null: false
    t.text "payload_ciphertext"
    t.datetime "updated_at", null: false
    t.index ["needs_kms_rotation"], name: "index_nod_notifications_on_needs_kms_rotation"
  end

  create_table "oauth_sessions", force: :cascade do |t|
    t.string "client_id", null: false
    t.datetime "created_at", null: false
    t.string "credential_email"
    t.text "encrypted_kms_key"
    t.uuid "handle", null: false
    t.string "hashed_device_secret"
    t.string "hashed_refresh_token", null: false
    t.boolean "needs_kms_rotation", default: false, null: false
    t.datetime "refresh_creation", null: false
    t.datetime "refresh_expiration", null: false
    t.datetime "updated_at", null: false
    t.uuid "user_account_id", null: false
    t.text "user_attributes_ciphertext"
    t.bigint "user_verification_id", null: false
    t.index ["handle"], name: "index_oauth_sessions_on_handle", unique: true
    t.index ["hashed_device_secret"], name: "index_oauth_sessions_on_hashed_device_secret"
    t.index ["hashed_refresh_token"], name: "index_oauth_sessions_on_hashed_refresh_token", unique: true
    t.index ["needs_kms_rotation"], name: "index_oauth_sessions_on_needs_kms_rotation"
    t.index ["refresh_creation"], name: "index_oauth_sessions_on_refresh_creation"
    t.index ["refresh_expiration"], name: "index_oauth_sessions_on_refresh_expiration"
    t.index ["user_account_id"], name: "index_oauth_sessions_on_user_account_id"
    t.index ["user_verification_id"], name: "index_oauth_sessions_on_user_verification_id"
  end

  create_table "onsite_notifications", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.boolean "dismissed", default: false, null: false
    t.string "template_id", null: false
    t.datetime "updated_at", null: false
    t.string "va_profile_id", null: false
    t.index ["va_profile_id", "dismissed"], name: "show_onsite_notifications_index"
  end

  create_table "organization_representatives", force: :cascade do |t|
    t.string "acceptance_mode", default: "no_acceptance", null: false
    t.datetime "created_at", null: false
    t.datetime "deactivated_at"
    t.string "organization_poa", limit: 3, null: false
    t.string "representative_id", null: false
    t.datetime "updated_at", null: false
    t.index ["organization_poa", "representative_id"], name: "idx_org_reps_on_org_poa_and_rep_id", unique: true
    t.index ["representative_id"], name: "index_organization_representatives_on_representative_id"
    t.check_constraint "acceptance_mode::text = ANY (ARRAY['any_request'::character varying::text, 'self_only'::character varying::text, 'no_acceptance'::character varying::text])", name: "org_reps_acceptance_mode_check"
  end

  create_table "persistent_attachments", id: :serial, force: :cascade do |t|
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.integer "doctype"
    t.text "encrypted_kms_key"
    t.text "file_data_ciphertext"
    t.string "form_id"
    t.uuid "guid"
    t.boolean "needs_kms_rotation", default: false, null: false
    t.integer "saved_claim_id"
    t.string "type"
    t.datetime "updated_at", null: false
    t.index ["guid"], name: "index_persistent_attachments_on_guid", unique: true
    t.index ["id", "type"], name: "index_persistent_attachments_on_id_and_type"
    t.index ["needs_kms_rotation"], name: "index_persistent_attachments_on_needs_kms_rotation"
    t.index ["saved_claim_id"], name: "index_persistent_attachments_on_saved_claim_id"
  end

  create_table "personal_information_logs", id: :serial, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "data_ciphertext"
    t.text "encrypted_kms_key"
    t.string "error_class", null: false
    t.boolean "needs_kms_rotation", default: false, null: false
    t.datetime "updated_at", null: false
    t.index ["created_at"], name: "index_personal_information_logs_on_created_at"
    t.index ["error_class"], name: "index_personal_information_logs_on_error_class"
    t.index ["needs_kms_rotation"], name: "index_personal_information_logs_on_needs_kms_rotation"
  end

  create_table "pghero_query_stats", force: :cascade do |t|
    t.bigint "calls"
    t.datetime "captured_at"
    t.text "database"
    t.text "query"
    t.bigint "query_hash"
    t.float "total_time"
    t.text "user"
    t.index ["database", "captured_at"], name: "index_pghero_query_stats_on_database_and_captured_at"
  end

  create_table "pghero_space_stats", force: :cascade do |t|
    t.datetime "captured_at"
    t.text "database"
    t.text "relation"
    t.text "schema"
    t.bigint "size"
    t.index ["database", "captured_at"], name: "index_pghero_space_stats_on_database_and_captured_at"
  end

  create_table "preneed_submissions", id: :serial, force: :cascade do |t|
    t.string "application_uuid"
    t.datetime "created_at", null: false
    t.integer "return_code"
    t.string "return_description", null: false
    t.string "tracking_number", null: false
    t.datetime "updated_at", null: false
    t.index ["application_uuid"], name: "index_preneed_submissions_on_application_uuid", unique: true
    t.index ["tracking_number"], name: "index_preneed_submissions_on_tracking_number", unique: true
  end

  create_table "remediation_batch_upload_items", force: :cascade do |t|
    t.string "claims_evidence_file_uuid"
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.integer "document_type_id", null: false
    t.string "error_class"
    t.text "error_message"
    t.string "form_type"
    t.integer "retry_count", default: 0, null: false
    t.string "s3_bucket", null: false
    t.text "s3_key", null: false
    t.datetime "started_at"
    t.string "status", default: "pending", null: false
    t.string "subject"
    t.datetime "submission_datetime"
    t.string "submission_id", null: false
    t.datetime "updated_at", null: false
    t.index ["claims_evidence_file_uuid"], name: "idx_unique_claims_evidence_file_uuid", unique: true, where: "(claims_evidence_file_uuid IS NOT NULL)"
    t.index ["status", "retry_count"], name: "index_remediation_batch_upload_items_on_status_and_retry_count"
    t.index ["status", "started_at"], name: "index_remediation_batch_upload_items_on_status_and_started_at"
    t.index ["submission_id"], name: "index_remediation_batch_upload_items_on_submission_id", unique: true
    t.check_constraint "retry_count >= 0 AND retry_count <= 3", name: "chk_retry_count"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying::text, 'downloading'::character varying::text, 'uploading'::character varying::text, 'completed'::character varying::text, 'failed'::character varying::text])", name: "chk_status"
  end

  create_table "representation_management_accreditation_totals", force: :cascade do |t|
    t.integer "attorneys"
    t.integer "claims_agents"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "vso_organizations"
    t.integer "vso_representatives"
    t.index ["created_at"], name: "idx_on_created_at_5b6fb39541"
  end

  create_table "saved_claim_groups", force: :cascade do |t|
    t.uuid "claim_group_guid", null: false
    t.datetime "created_at", null: false
    t.text "encrypted_kms_key", comment: "KMS key used to encrypt the reference data"
    t.boolean "needs_kms_rotation", default: false, null: false
    t.integer "parent_claim_id", null: false, comment: "ID of the saved claim in vets-api"
    t.integer "saved_claim_id", null: false, comment: "ID of the saved claim in vets-api"
    t.enum "status", default: "pending", enum_type: "saved_claim_group_status"
    t.datetime "updated_at", null: false
    t.jsonb "user_data_ciphertext", comment: "encrypted data that can be used to identify the associated user"
    t.index ["claim_group_guid"], name: "index_saved_claim_groups_on_claim_group_guid"
    t.index ["needs_kms_rotation"], name: "index_saved_claim_groups_on_needs_kms_rotation"
  end

  create_table "saved_claims", id: :serial, force: :cascade do |t|
    t.uuid "bpd_uuid"
    t.datetime "created_at"
    t.datetime "delete_date"
    t.text "encrypted_kms_key"
    t.text "form_ciphertext"
    t.string "form_id"
    t.datetime "form_start_date"
    t.uuid "guid", null: false
    t.text "metadata"
    t.datetime "metadata_updated_at"
    t.boolean "needs_kms_rotation", default: false, null: false
    t.string "type"
    t.datetime "updated_at"
    t.string "uploaded_forms", default: [], array: true
    t.uuid "user_account_id"
    t.index ["created_at", "type"], name: "index_saved_claims_on_created_at_and_type"
    t.index ["delete_date"], name: "index_saved_claims_on_delete_date"
    t.index ["guid"], name: "index_saved_claims_on_guid", unique: true
    t.index ["id", "type"], name: "index_saved_claims_on_id_and_type"
    t.index ["id"], name: "index_partial_saved_claims_on_id_metadata_like_error", where: "(metadata ~~ '%error%'::text)"
    t.index ["needs_kms_rotation"], name: "index_saved_claims_on_needs_kms_rotation"
    t.index ["user_account_id"], name: "index_saved_claims_on_user_account_id"
  end

  create_table "schema_contract_validations", force: :cascade do |t|
    t.string "contract_name", null: false
    t.datetime "created_at", null: false
    t.string "error_details"
    t.jsonb "response", null: false
    t.integer "status", null: false
    t.datetime "updated_at", null: false
    t.uuid "user_account_id"
    t.string "user_uuid", null: false
    t.index ["user_account_id"], name: "index_schema_contract_validations_on_user_account_id"
  end

  create_table "secondary_appeal_forms", force: :cascade do |t|
    t.bigint "appeal_submission_id"
    t.datetime "created_at", null: false
    t.datetime "delete_date"
    t.text "encrypted_kms_key"
    t.datetime "failure_notification_sent_at"
    t.text "form_ciphertext"
    t.string "form_id"
    t.uuid "guid"
    t.boolean "needs_kms_rotation", default: false, null: false
    t.string "status"
    t.datetime "status_updated_at"
    t.datetime "updated_at", null: false
    t.index ["appeal_submission_id"], name: "index_secondary_appeal_forms_on_appeal_submission_id"
    t.index ["needs_kms_rotation"], name: "index_secondary_appeal_forms_on_needs_kms_rotation"
  end

  create_table "service_account_configs", force: :cascade do |t|
    t.string "access_token_audience", null: false
    t.interval "access_token_duration", null: false
    t.string "access_token_user_attributes", default: [], array: true
    t.datetime "created_at", null: false
    t.text "description", null: false
    t.text "scopes", default: [], null: false, array: true
    t.string "service_account_id", null: false
    t.datetime "updated_at", null: false
    t.index ["service_account_id"], name: "index_service_account_configs_on_service_account_id", unique: true
  end

  create_table "sign_in_certificates", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "pem", null: false
    t.datetime "updated_at", null: false
  end

  create_table "sign_in_config_certificates", force: :cascade do |t|
    t.uuid "certificate_id", null: false
    t.integer "config_id", null: false
    t.string "config_type", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["certificate_id"], name: "index_sign_in_config_certificates_on_certificate_id"
    t.index ["config_type", "config_id"], name: "index_sign_in_config_certificates_on_config"
  end

  create_table "sign_in_session_records", force: :cascade do |t|
    t.string "browser"
    t.string "client_id", null: false
    t.datetime "created_at", null: false
    t.string "csp_type"
    t.string "device_description"
    t.text "encrypted_kms_key"
    t.uuid "handle", null: false
    t.datetime "last_activity_at"
    t.text "location_ciphertext"
    t.boolean "needs_kms_rotation", default: false, null: false
    t.text "sign_in_ip_ciphertext"
    t.datetime "signed_out_at"
    t.datetime "updated_at", null: false
    t.uuid "user_account_id", null: false
    t.text "user_agent_ciphertext"
    t.index ["handle"], name: "index_sign_in_session_records_on_handle", unique: true
    t.index ["signed_out_at"], name: "index_sign_in_session_records_on_signed_out_at", where: "(signed_out_at IS NOT NULL)"
    t.index ["user_account_id"], name: "index_sign_in_session_records_on_user_account_id"
  end

  create_table "sign_in_webauthn_credentials", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "aaguid"
    t.string "authenticator_attachment"
    t.boolean "backed_up", default: false, null: false
    t.boolean "backup_eligible", default: false, null: false
    t.datetime "created_at", null: false
    t.string "credential_id", null: false
    t.datetime "last_used_at"
    t.text "public_key", null: false
    t.bigint "sign_count", default: 0, null: false
    t.string "transports", default: [], array: true
    t.datetime "updated_at", null: false
    t.index ["credential_id"], name: "index_sign_in_webauthn_credentials_on_credential_id", unique: true
  end

  create_table "spool_file_events", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "filename"
    t.integer "number_of_submissions"
    t.integer "retry_attempt", default: 0
    t.integer "rpo"
    t.datetime "successful_at"
    t.datetime "updated_at", null: false
    t.index ["rpo", "filename"], name: "index_spool_file_events_uniqueness", unique: true
  end

  create_table "std_counties", force: :cascade do |t|
    t.integer "county_number", null: false
    t.datetime "created", null: false
    t.string "created_by"
    t.string "description", null: false
    t.string "name", null: false
    t.integer "state_id", null: false
    t.datetime "updated"
    t.string "updated_by"
    t.integer "version", null: false
  end

  create_table "std_incomethresholds", force: :cascade do |t|
    t.integer "add_dependent_pension"
    t.integer "add_dependent_threshold", null: false
    t.integer "add_ninety_day_hospital_copay"
    t.integer "aid_and_attendance_threshold"
    t.integer "child_income_exclusion", null: false
    t.datetime "created", null: false
    t.string "created_by"
    t.integer "dependent", null: false
    t.string "description"
    t.integer "exempt_amount", null: false
    t.integer "income_threshold_year", null: false
    t.integer "inpatient_per_diem"
    t.integer "ltc_domiciliary_copay"
    t.integer "ltc_inpatient_copay"
    t.integer "ltc_outpatient_copay"
    t.integer "medical_expense_deductible", null: false
    t.integer "medication_copay"
    t.integer "medication_copay_annual_cap"
    t.integer "ninety_day_hospital_copay"
    t.integer "outpatient_basic_care_copay"
    t.integer "outpatient_preventive_copay"
    t.integer "outpatient_specialty_copay"
    t.integer "pension_1_dependent"
    t.integer "pension_threshold"
    t.integer "property_threshold", null: false
    t.datetime "threshold_effective_date"
    t.datetime "updated"
    t.string "updated_by"
    t.integer "version", null: false
  end

  create_table "std_institution_facilities", force: :cascade do |t|
    t.date "activation_date"
    t.integer "agency_id"
    t.datetime "created"
    t.datetime "created_at", null: false
    t.string "created_by"
    t.date "deactivation_date"
    t.integer "facility_type_id"
    t.string "mailing_address_line1"
    t.string "mailing_address_line2"
    t.string "mailing_address_line3"
    t.string "mailing_city"
    t.integer "mailing_country_id"
    t.integer "mailing_county_id"
    t.string "mailing_postal_code"
    t.integer "mailing_state_id"
    t.integer "mfn_zeg_recipient"
    t.string "name"
    t.integer "parent_id"
    t.integer "realigned_from_id"
    t.integer "realigned_to_id"
    t.string "station_number"
    t.string "street_address_line1"
    t.string "street_address_line2"
    t.string "street_address_line3"
    t.string "street_city"
    t.integer "street_country_id"
    t.integer "street_county_id"
    t.string "street_postal_code"
    t.integer "street_state_id"
    t.datetime "updated"
    t.datetime "updated_at", null: false
    t.string "updated_by"
    t.integer "version"
    t.integer "visn_id"
    t.string "vista_name"
  end

  create_table "std_states", force: :cascade do |t|
    t.integer "country_id", null: false
    t.datetime "created", null: false
    t.string "created_by"
    t.integer "fips_code", null: false
    t.string "name", null: false
    t.string "postal_name", null: false
    t.datetime "updated"
    t.string "updated_by"
    t.integer "version", null: false
  end

  create_table "std_zipcodes", force: :cascade do |t|
    t.integer "county_number", null: false
    t.datetime "created", null: false
    t.string "created_by"
    t.integer "preferred_zip_place_id"
    t.integer "state_id", null: false
    t.datetime "updated"
    t.string "updated_by"
    t.integer "version", null: false
    t.integer "zip_classification_id"
    t.string "zip_code", null: false
  end

  create_table "terms_of_use_agreements", force: :cascade do |t|
    t.string "agreement_version", null: false
    t.datetime "created_at", null: false
    t.integer "response", null: false
    t.datetime "updated_at", null: false
    t.uuid "user_account_id", null: false
    t.index ["user_account_id"], name: "index_terms_of_use_agreements_on_user_account_id"
  end

  create_table "test_user_dashboard_tud_account_availability_logs", force: :cascade do |t|
    t.string "account_uuid"
    t.datetime "checkin_time"
    t.datetime "checkout_time"
    t.datetime "created_at", null: false
    t.boolean "has_checkin_error"
    t.boolean "is_manual_checkin"
    t.datetime "updated_at", null: false
    t.uuid "user_account_id"
    t.index ["account_uuid"], name: "tud_account_availability_logs"
    t.index ["user_account_id"], name: "idx_on_user_account_id_2569a82908"
  end

  create_table "test_user_dashboard_tud_accounts", force: :cascade do |t|
    t.string "account_uuid"
    t.datetime "birth_date"
    t.datetime "checkout_time"
    t.datetime "created_at", null: false
    t.string "email"
    t.string "first_name"
    t.string "gender"
    t.text "id_types", default: [], array: true
    t.uuid "idme_uuid"
    t.string "last_name"
    t.string "loa"
    t.uuid "logingov_uuid"
    t.string "mfa_code"
    t.string "middle_name"
    t.text "notes"
    t.string "password"
    t.string "phone"
    t.text "services"
    t.integer "ssn"
    t.datetime "updated_at", null: false
    t.uuid "user_account_id"
    t.index ["email"], name: "index_test_user_dashboard_tud_accounts_on_email", unique: true
    t.index ["user_account_id"], name: "index_test_user_dashboard_tud_accounts_on_user_account_id"
  end

  create_table "tooltips", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.integer "counter", default: 0
    t.datetime "created_at", null: false
    t.boolean "hidden", default: false
    t.datetime "last_signed_in", null: false
    t.jsonb "metadata", default: {}, null: false
    t.string "tooltip_name", null: false
    t.datetime "updated_at", null: false
    t.uuid "user_account_id", null: false
    t.index ["user_account_id", "tooltip_name"], name: "index_tooltips_on_user_account_id_and_tooltip_name", unique: true
  end

  create_table "user_acceptable_verified_credentials", force: :cascade do |t|
    t.datetime "acceptable_verified_credential_at"
    t.datetime "created_at", null: false
    t.datetime "idme_verified_credential_at"
    t.datetime "updated_at", null: false
    t.uuid "user_account_id", null: false
    t.index ["acceptable_verified_credential_at"], name: "index_user_avc_on_acceptable_verified_credential_at"
    t.index ["idme_verified_credential_at"], name: "index_user_avc_on_idme_verified_credential_at"
    t.index ["user_account_id"], name: "index_user_acceptable_verified_credentials_on_user_account_id", unique: true
  end

  create_table "user_accounts", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "icn"
    t.boolean "locked", default: false, null: false
    t.datetime "updated_at", null: false
    t.string "webauthn_handle"
    t.index ["icn"], name: "index_user_accounts_on_icn", unique: true
    t.index ["locked"], name: "index_user_accounts_on_locked", where: "(locked = true)"
    t.index ["webauthn_handle"], name: "index_user_accounts_on_webauthn_handle", unique: true, where: "(webauthn_handle IS NOT NULL)"
  end

  create_table "user_action_events", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "details", null: false
    t.string "event_type", null: false
    t.string "identifier", null: false
    t.datetime "updated_at", null: false
    t.index ["identifier"], name: "index_user_action_events_on_identifier", unique: true
  end

  create_table "user_actions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "acting_device_id"
    t.text "acting_ip_address"
    t.text "acting_user_agent"
    t.bigint "acting_user_verification_id"
    t.string "acting_visit_id"
    t.datetime "created_at", null: false
    t.enum "status", default: "initial", null: false, enum_type: "user_action_status"
    t.bigint "subject_user_verification_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_action_event_id", null: false
    t.index ["acting_user_verification_id"], name: "index_user_actions_on_acting_user_verification_id"
    t.index ["subject_user_verification_id"], name: "index_user_actions_on_subject_user_verification_id"
    t.index ["user_action_event_id"], name: "index_user_actions_on_user_action_event_id"
  end

  create_table "user_credential_emails", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "credential_email_ciphertext"
    t.text "encrypted_kms_key"
    t.boolean "needs_kms_rotation", default: false, null: false
    t.datetime "updated_at", null: false
    t.bigint "user_verification_id"
    t.index ["needs_kms_rotation"], name: "index_user_credential_emails_on_needs_kms_rotation"
    t.index ["user_verification_id"], name: "index_user_credential_emails_on_user_verification_id", unique: true
  end

  create_table "user_verifications", force: :cascade do |t|
    t.string "backing_idme_uuid"
    t.string "clear_uuid"
    t.datetime "created_at", null: false
    t.string "credential_attributes_digest"
    t.string "dslogon_uuid"
    t.string "entra_uuid"
    t.string "idme_uuid"
    t.boolean "locked", default: false, null: false
    t.string "logingov_uuid"
    t.string "mhv_uuid"
    t.datetime "updated_at", null: false
    t.uuid "user_account_id"
    t.datetime "verified_at"
    t.uuid "webauthn_credential_id"
    t.index ["backing_idme_uuid"], name: "index_user_verifications_on_backing_idme_uuid"
    t.index ["clear_uuid"], name: "index_user_verifications_on_clear_uuid", unique: true
    t.index ["dslogon_uuid"], name: "index_user_verifications_on_dslogon_uuid", unique: true
    t.index ["entra_uuid"], name: "index_user_verifications_on_entra_uuid", unique: true, where: "(entra_uuid IS NOT NULL)"
    t.index ["idme_uuid"], name: "index_user_verifications_on_idme_uuid", unique: true
    t.index ["logingov_uuid"], name: "index_user_verifications_on_logingov_uuid", unique: true
    t.index ["mhv_uuid"], name: "index_user_verifications_on_mhv_uuid", unique: true
    t.index ["user_account_id"], name: "index_user_verifications_on_user_account_id"
    t.index ["verified_at"], name: "index_user_verifications_on_verified_at"
    t.index ["webauthn_credential_id"], name: "index_user_verifications_on_webauthn_credential_id", unique: true, where: "(webauthn_credential_id IS NOT NULL)"
  end

  create_table "va_notify_in_progress_reminders_sent", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "form_id", null: false
    t.datetime "updated_at", null: false
    t.uuid "user_account_id", null: false
    t.index ["user_account_id", "form_id"], name: "index_in_progress_reminders_sent_user_account_form_id", unique: true
  end

  create_table "va_notify_notifications", force: :cascade do |t|
    t.text "callback_klass"
    t.jsonb "callback_metadata"
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.text "encrypted_kms_key"
    t.boolean "needs_kms_rotation", default: false, null: false
    t.uuid "notification_id", null: false
    t.text "notification_type"
    t.text "provider"
    t.text "reference"
    t.datetime "sent_at"
    t.text "service_api_key_path"
    t.uuid "service_id"
    t.text "source_location"
    t.text "status"
    t.text "status_reason"
    t.uuid "template_id"
    t.text "to_ciphertext"
    t.datetime "updated_at", null: false
    t.index ["needs_kms_rotation"], name: "index_va_notify_notifications_on_needs_kms_rotation"
    t.index ["notification_id"], name: "index_va_notify_notifications_on_notification_id"
  end

  create_table "vba_documents_monthly_stats", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "month", null: false
    t.jsonb "stats", default: {}
    t.datetime "updated_at", null: false
    t.integer "year", null: false
    t.index ["month", "year"], name: "index_vba_documents_monthly_stats_uniqueness", unique: true
  end

  create_table "vba_documents_upload_submissions", id: :serial, force: :cascade do |t|
    t.string "code"
    t.uuid "consumer_id"
    t.string "consumer_name"
    t.datetime "created_at", null: false
    t.string "detail"
    t.uuid "guid", null: false
    t.jsonb "metadata", default: {}
    t.boolean "s3_deleted"
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.json "uploaded_pdf"
    t.boolean "use_active_storage", default: false
    t.index ["created_at"], name: "index_vba_documents_upload_submissions_on_created_at"
    t.index ["guid"], name: "index_vba_documents_upload_submissions_on_guid"
    t.index ["s3_deleted"], name: "index_vba_documents_upload_submissions_on_s3_deleted"
    t.index ["status", "created_at"], name: "index_vba_docs_upload_submissions_status_created_at_false", where: "(s3_deleted IS FALSE)"
    t.index ["status"], name: "index_vba_documents_upload_submissions_on_status"
  end

  create_table "veteran_accreditation_totals", force: :cascade do |t|
    t.integer "attorneys"
    t.integer "claims_agents"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "vso_organizations"
    t.integer "vso_representatives"
  end

  create_table "veteran_device_records", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.bigint "device_id", null: false
    t.string "icn", null: false
    t.datetime "updated_at", null: false
    t.index ["device_id"], name: "index_veteran_device_records_on_device_id"
    t.index ["icn", "device_id"], name: "index_veteran_device_records_on_icn_and_device_id", unique: true
  end

  create_table "veteran_onboardings", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.boolean "display_onboarding_flow", default: true
    t.datetime "updated_at", null: false
    t.string "user_account_uuid"
    t.index ["user_account_uuid"], name: "index_veteran_onboardings_on_user_account_uuid", unique: true
  end

  create_table "veteran_organizations", id: false, force: :cascade do |t|
    t.string "address_line1"
    t.string "address_line2"
    t.string "address_line3"
    t.string "address_type"
    t.boolean "can_accept_digital_poa_requests", default: false
    t.string "city"
    t.string "country_code_iso3"
    t.string "country_name"
    t.string "county_code"
    t.string "county_name"
    t.datetime "created_at", null: false
    t.string "default_new_rep_acceptance_mode", default: "no_acceptance", null: false
    t.string "international_postal_code"
    t.float "lat"
    t.geography "location", limit: {srid: 4326, type: "st_point", geographic: true}
    t.float "long"
    t.string "name"
    t.string "phone"
    t.string "poa", limit: 3
    t.string "primary_org_acceptance_mode", default: "no_acceptance", null: false
    t.string "province"
    t.jsonb "raw_address"
    t.string "state", limit: 2
    t.string "state_code"
    t.datetime "updated_at", null: false
    t.string "zip_code"
    t.string "zip_suffix"
    t.index ["location"], name: "index_veteran_organizations_on_location", using: :gist
    t.index ["name"], name: "index_veteran_organizations_on_name"
    t.index ["poa"], name: "index_veteran_organizations_on_poa", unique: true
    t.check_constraint "default_new_rep_acceptance_mode::text = ANY (ARRAY['any_request'::character varying::text, 'self_only'::character varying::text, 'no_acceptance'::character varying::text])", name: "check_veteran_orgs_default_new_rep_acceptance_mode"
    t.check_constraint "primary_org_acceptance_mode::text = ANY (ARRAY['any_request'::character varying::text, 'self_only'::character varying::text, 'no_acceptance'::character varying::text])", name: "check_veteran_orgs_primary_org_acceptance_mode"
  end

  create_table "veteran_representatives", id: false, force: :cascade do |t|
    t.string "address_line1"
    t.string "address_line2"
    t.string "address_line3"
    t.string "address_type"
    t.string "city"
    t.string "country_code_iso3"
    t.string "country_name"
    t.string "county_code"
    t.string "county_name"
    t.datetime "created_at", null: false
    t.string "email"
    t.datetime "fallback_location_updated_at"
    t.string "first_name"
    t.string "full_name"
    t.string "international_postal_code"
    t.string "last_name"
    t.float "lat"
    t.geography "location", limit: {srid: 4326, type: "st_point", geographic: true}
    t.float "long"
    t.string "middle_initial"
    t.string "phone"
    t.string "phone_number"
    t.string "poa_codes", default: [], array: true
    t.string "province"
    t.jsonb "raw_address"
    t.string "representative_id"
    t.string "state_code"
    t.datetime "updated_at", null: false
    t.string "user_types", default: [], array: true
    t.string "zip_code"
    t.string "zip_suffix"
    t.index "lower((email)::text)", name: "index_veteran_representatives_on_lower_email"
    t.index ["full_name"], name: "index_veteran_representatives_on_full_name"
    t.index ["location"], name: "index_veteran_representatives_on_location", using: :gist
    t.index ["representative_id"], name: "index_veteran_representatives_on_representative_id", unique: true
    t.check_constraint "representative_id IS NOT NULL", name: "veteran_representatives_representative_id_null"
  end

  create_table "vic_submissions", id: :serial, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.uuid "guid", null: false
    t.json "response"
    t.string "state", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.index ["guid"], name: "index_vic_submissions_on_guid", unique: true
  end

  create_table "vye_address_changes", force: :cascade do |t|
    t.text "address1_ciphertext"
    t.text "address2_ciphertext"
    t.text "address3_ciphertext"
    t.text "address4_ciphertext"
    t.text "address5_ciphertext"
    t.string "benefit_type"
    t.text "city_ciphertext"
    t.datetime "created_at", null: false
    t.text "encrypted_kms_key"
    t.boolean "needs_kms_rotation", default: false, null: false
    t.string "origin"
    t.string "rpo"
    t.text "state_ciphertext"
    t.datetime "updated_at", null: false
    t.integer "user_info_id"
    t.text "veteran_name_ciphertext"
    t.text "zip_code_ciphertext"
    t.index ["created_at"], name: "index_vye_address_changes_on_created_at"
    t.index ["needs_kms_rotation"], name: "index_vye_address_changes_on_needs_kms_rotation"
    t.index ["user_info_id"], name: "index_vye_address_changes_on_user_info_id"
  end

  create_table "vye_awards", force: :cascade do |t|
    t.date "award_begin_date"
    t.date "award_end_date"
    t.string "begin_rsn"
    t.datetime "created_at", null: false
    t.string "cur_award_ind"
    t.string "end_rsn"
    t.decimal "monthly_rate"
    t.integer "number_hours"
    t.date "payment_date"
    t.integer "training_time"
    t.string "type_hours"
    t.string "type_training"
    t.datetime "updated_at", null: false
    t.integer "user_info_id"
    t.index ["user_info_id"], name: "index_vye_awards_on_user_info_id"
  end

  create_table "vye_bdn_clones", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.boolean "export_ready"
    t.boolean "is_active"
    t.date "transact_date"
    t.datetime "updated_at", null: false
    t.index ["export_ready"], name: "index_vye_bdn_clones_on_export_ready"
    t.index ["is_active"], name: "index_vye_bdn_clones_on_is_active"
  end

  create_table "vye_direct_deposit_changes", force: :cascade do |t|
    t.text "acct_no_ciphertext"
    t.text "acct_type_ciphertext"
    t.text "bank_name_ciphertext"
    t.text "bank_phone_ciphertext"
    t.string "ben_type"
    t.text "chk_digit_ciphertext"
    t.datetime "created_at", null: false
    t.text "email_ciphertext"
    t.text "encrypted_kms_key"
    t.text "full_name_ciphertext"
    t.boolean "needs_kms_rotation", default: false, null: false
    t.text "phone2_ciphertext"
    t.text "phone_ciphertext"
    t.text "routing_no_ciphertext"
    t.string "rpo"
    t.datetime "updated_at", null: false
    t.integer "user_info_id"
    t.index ["created_at"], name: "index_vye_direct_deposit_changes_on_created_at"
    t.index ["needs_kms_rotation"], name: "index_vye_direct_deposit_changes_on_needs_kms_rotation"
    t.index ["user_info_id"], name: "index_vye_direct_deposit_changes_on_user_info_id"
  end

  create_table "vye_pending_documents", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "doc_type"
    t.date "queue_date"
    t.string "rpo"
    t.datetime "updated_at", null: false
    t.integer "user_profile_id"
    t.index ["user_profile_id"], name: "index_vye_pending_documents_on_user_profile_id"
  end

  create_table "vye_user_infos", force: :cascade do |t|
    t.boolean "bdn_clone_active"
    t.integer "bdn_clone_id"
    t.integer "bdn_clone_line"
    t.date "cert_issue_date"
    t.datetime "created_at", null: false
    t.date "date_last_certified"
    t.date "del_date"
    t.text "dob_ciphertext"
    t.text "encrypted_kms_key"
    t.string "fac_code"
    t.text "file_number_ciphertext"
    t.string "indicator"
    t.string "mr_status"
    t.boolean "needs_kms_rotation", default: false, null: false
    t.decimal "payment_amt"
    t.string "rem_ent"
    t.integer "rpo_code"
    t.text "stub_nm_ciphertext"
    t.string "suffix"
    t.datetime "updated_at", null: false
    t.integer "user_profile_id"
    t.index ["bdn_clone_active"], name: "index_vye_user_infos_on_bdn_clone_active"
    t.index ["bdn_clone_id"], name: "index_vye_user_infos_on_bdn_clone_id"
    t.index ["bdn_clone_line"], name: "index_vye_user_infos_on_bdn_clone_line"
    t.index ["needs_kms_rotation"], name: "index_vye_user_infos_on_needs_kms_rotation"
    t.index ["user_profile_id"], name: "index_vye_user_infos_on_user_profile_id"
  end

  create_table "vye_user_profiles", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.binary "file_number_digest"
    t.string "icn"
    t.binary "ssn_digest"
    t.datetime "updated_at", null: false
    t.index ["file_number_digest"], name: "index_vye_user_profiles_on_file_number_digest", unique: true
    t.index ["icn"], name: "index_vye_user_profiles_on_icn", unique: true
    t.index ["ssn_digest"], name: "index_vye_user_profiles_on_ssn_digest", unique: true
  end

  create_table "vye_verifications", force: :cascade do |t|
    t.datetime "act_begin"
    t.datetime "act_end"
    t.integer "award_id"
    t.string "change_flag"
    t.datetime "created_at", null: false
    t.decimal "monthly_rate"
    t.integer "number_hours"
    t.date "payment_date"
    t.integer "rpo_code"
    t.boolean "rpo_flag"
    t.string "source_ind"
    t.string "trace"
    t.date "transact_date"
    t.datetime "updated_at", null: false
    t.integer "user_info_id"
    t.integer "user_profile_id"
    t.index ["award_id"], name: "index_vye_verifications_on_award_id"
    t.index ["created_at"], name: "index_vye_verifications_on_created_at"
    t.index ["user_info_id"], name: "index_vye_verifications_on_user_info_id"
    t.index ["user_profile_id"], name: "index_vye_verifications_on_user_profile_id"
  end

  add_foreign_key "accreditations", "accredited_individuals"
  add_foreign_key "accreditations", "accredited_organizations"
  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "appeal_submissions", "user_accounts"
  add_foreign_key "ar_form21a_pilot_admissions", "user_accounts"
  add_foreign_key "ar_power_of_attorney_forms", "ar_power_of_attorney_requests", column: "power_of_attorney_request_id"
  add_foreign_key "ar_power_of_attorney_request_decisions", "user_accounts", column: "creator_id"
  add_foreign_key "ar_power_of_attorney_request_notifications", "ar_power_of_attorney_requests", column: "power_of_attorney_request_id"
  add_foreign_key "ar_power_of_attorney_request_resolutions", "ar_power_of_attorney_requests", column: "power_of_attorney_request_id"
  add_foreign_key "ar_power_of_attorney_request_withdrawals", "ar_power_of_attorney_requests", column: "superseding_power_of_attorney_request_id"
  add_foreign_key "ar_power_of_attorney_requests", "user_accounts", column: "claimant_id"
  add_foreign_key "ar_representative_in_progress_forms", "user_accounts", column: "rep_user_account_id"
  add_foreign_key "ask_va_inquiry_submission_checkpoints", "ask_va_inquiry_submissions"
  add_foreign_key "async_transactions", "user_accounts"
  add_foreign_key "bgs_submission_attempts", "bgs_submissions"
  add_foreign_key "bgs_submissions", "saved_claims"
  add_foreign_key "bpds_submission_attempts", "bpds_submissions"
  add_foreign_key "claim_va_notifications", "saved_claims"
  add_foreign_key "claims_api_claim_submissions", "claims_api_auto_established_claims", column: "claim_id"
  add_foreign_key "claims_api_organization_representatives", "claims_api_organizations", column: "organization_poa", primary_key: "poa"
  add_foreign_key "claims_api_organization_representatives", "claims_api_representatives", column: "representative_id", primary_key: "representative_id"
  add_foreign_key "claims_evidence_api_submission_attempts", "claims_evidence_api_submissions", column: "claims_evidence_api_submissions_id"
  add_foreign_key "deprecated_user_accounts", "user_accounts"
  add_foreign_key "deprecated_user_accounts", "user_verifications"
  add_foreign_key "digital_dispute_submissions", "user_accounts"
  add_foreign_key "digital_forms_api_submission_attempts", "digital_forms_api_submissions"
  add_foreign_key "digital_forms_api_submissions", "user_accounts"
  add_foreign_key "education_stem_automated_decisions", "user_accounts"
  add_foreign_key "event_bus_gateway_notifications", "user_accounts"
  add_foreign_key "event_bus_gateway_push_notifications", "user_accounts"
  add_foreign_key "evidence_submissions", "user_accounts"
  add_foreign_key "evss_claims", "user_accounts"
  add_foreign_key "form21a_document_submission_attempts", "form21a_document_submissions", name: "fk_form21a_doc_attempts_on_submission_id"
  add_foreign_key "form526_submission_remediations", "form526_submissions"
  add_foreign_key "form526_submissions", "user_accounts"
  add_foreign_key "form5655_submissions", "user_accounts"
  add_foreign_key "form_email_matches_profile_logs", "user_accounts"
  add_foreign_key "form_intake_submissions", "form_submissions"
  add_foreign_key "form_submission_attempts", "form_submissions"
  add_foreign_key "form_submissions", "saved_claims"
  add_foreign_key "form_submissions", "user_accounts"
  add_foreign_key "health_quest_questionnaire_responses", "user_accounts"
  add_foreign_key "in_progress_forms", "user_accounts"
  add_foreign_key "lighthouse526_document_uploads", "form526_submissions"
  add_foreign_key "lighthouse526_document_uploads", "form_attachments"
  add_foreign_key "lighthouse_submission_attempts", "lighthouse_submissions"
  add_foreign_key "mhv_opt_in_flags", "user_accounts"
  add_foreign_key "oauth_sessions", "user_accounts"
  add_foreign_key "oauth_sessions", "user_verifications"
  add_foreign_key "organization_representatives", "veteran_organizations", column: "organization_poa", primary_key: "poa"
  add_foreign_key "organization_representatives", "veteran_representatives", column: "representative_id", primary_key: "representative_id"
  add_foreign_key "saved_claim_groups", "saved_claims"
  add_foreign_key "saved_claim_groups", "saved_claims", column: "parent_claim_id"
  add_foreign_key "schema_contract_validations", "user_accounts"
  add_foreign_key "sign_in_session_records", "user_accounts"
  add_foreign_key "terms_of_use_agreements", "user_accounts"
  add_foreign_key "test_user_dashboard_tud_account_availability_logs", "user_accounts"
  add_foreign_key "test_user_dashboard_tud_accounts", "user_accounts"
  add_foreign_key "tooltips", "user_accounts"
  add_foreign_key "user_acceptable_verified_credentials", "user_accounts"
  add_foreign_key "user_actions", "user_action_events"
  add_foreign_key "user_actions", "user_verifications", column: "acting_user_verification_id"
  add_foreign_key "user_actions", "user_verifications", column: "subject_user_verification_id"
  add_foreign_key "user_credential_emails", "user_verifications"
  add_foreign_key "user_verifications", "sign_in_webauthn_credentials", column: "webauthn_credential_id"
  add_foreign_key "user_verifications", "user_accounts"
  add_foreign_key "va_notify_in_progress_reminders_sent", "user_accounts"
  add_foreign_key "veteran_device_records", "devices"
end
