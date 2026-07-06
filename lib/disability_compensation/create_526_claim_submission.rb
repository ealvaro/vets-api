# frozen_string_literal: true

raise 'This script cannot be run in production' if Rails.env.production?

# Create a Form 526 claim submission for testing
#
# This script creates a saved claim and form submission for a test user,
# useful for testing the disability compensation claim submission workflow.
#
# Usage:
#   bundle exec rails runner lib/disability_compensation/create_526_claim_submission.rb \
#     --json-path /path/to/form.json --user-icn 1012345678V123456
#
# Options:
#   --json-path PATH   Path to JSON file containing form data (required)
#   --user-icn ICN     ICN of the test user (optional, creates new user if not provided)
#   --help             Show this help message
#
# Examples:
#   # Create with minimal fixture
#   bundle exec rails runner lib/disability_compensation/create_526_claim_submission.rb \
#     --json-path tmp/json/minimal-condition-date.json \
#     --user-icn 1012860875V895695
#
#   # Create with form data and existing user
#   bundle exec rails runner lib/disability_compensation/create_526_claim_submission.rb \
#     --json-path path/to/form526.json \
#     --user-icn 1012667122V019349
#
# Output:
#   Returns JSON with:
#     - saved_claim_id: ID of the created SavedClaim record
#     - submission_id: ID of the Form526Submission record
#     - user_uuid: UUID of the test user
#     - user_icn: ICN of the test user
#
# Notes:
#   - JSON file can be in 'form526' or 'data' shape (frontend form format)
#   - User ICN is looked up in UserAccount; creates if needed
#   - Form data is translated and validated before submission creation

require 'json'
require 'factory_bot_rails'
require 'optparse'

options = {
  json_file_path: ENV.fetch('FORM_526_JSON_PATH', nil),
  user_icn: ENV.fetch('USER_ICN', nil)
}

OptionParser.new do |opts|
  opts.banner = 'Usage: rails runner lib/disability_compensation/create_526_claim_submission.rb [options]'

  opts.on('--json-path PATH', 'Path to JSON payload file') do |path|
    options[:json_file_path] = path
  end

  opts.on('--user-icn ICN', 'Build a test user with this ICN') do |icn|
    options[:user_icn] = icn
  end

  opts.on('--help', 'Show this help') do
    puts opts # rubocop:disable Rails/Output
    raise SystemExit
  end
end.parse!(ARGV)

raise 'Missing --json-path (or FORM_526_JSON_PATH)' if options[:json_file_path].blank?

json_file_path = options[:json_file_path]
user_icn = options[:user_icn]

def build_testing_user(icn: nil)
  FactoryBot.find_definitions unless FactoryBot.factories.registered?(:user)
  existing_user_account = icn.present? ? UserAccount.find_by(icn:) : nil

  attrs = {
    mhv_user_account: nil,
    should_stub_mpi: false,
    skip_mhv_user_account_preload: true
  }

  if existing_user_account.present?
    attrs[:icn] = existing_user_account.icn
    attrs[:user_account] = existing_user_account
    if existing_user_account.user_verifications.present?
      attrs[:user_verification] =
        existing_user_account.user_verifications.first
    end
  elsif icn.present?
    attrs[:icn] = icn
  end

  attrs
end

def add_0781_metadata(form526)
  if form526['syncModern0781Flow'].present?
    {
      sync_modern0781_flow: form526['syncModern0781Flow'],
      sync_modern0781_flow_answered_online: form526['form0781'].present?
    }.to_json
  end
end

def check_for_0781_metadata(form_content)
  if Flipper.enabled?(:disability_compensation_sync_modern0781_flow_metadata) && form_content['form526'].present?
    add_0781_metadata(form_content['form526'])
  end
end

def auth_headers(current_user)
  EVSS::DisabilityCompensationAuthHeaders.new(current_user)
                                         .add_headers(EVSS::AuthHeaders.new(current_user).to_h)
end

def create_submission(saved_claim, current_user)
  user_account = current_user.user_account
  user_account = UserAccount.find_or_create_by!(icn: current_user.icn) unless user_account&.persisted?

  submission = Form526Submission.new(
    user_uuid: current_user.uuid,
    user_account:,
    saved_claim_id: saved_claim.id,
    auth_headers_json: auth_headers(current_user).to_json,
    form_json: saved_claim.to_submission_data(current_user),
    submit_endpoint: 'claims_api'
  ) { |sub| sub.add_birls_ids current_user.birls_id }

  submission.save!
  submission
end

parsed = JSON.parse(File.read(json_file_path))

# Accept either shape:
# 1) { "form526": { ... } } (submit payload)
# 2) { "data": { ... } } (frontend form data fixture shape)
form_content = if parsed['form526'].is_a?(Hash)
                 parsed
               elsif parsed['data'].is_a?(Hash)
                 { 'form526' => parsed['data'] }
               else
                 raise "JSON must include top-level key 'form526' or 'data'"
               end

user_attrs = build_testing_user(icn: user_icn)
current_user = FactoryBot.build(:user, :loa3, **user_attrs)
raise 'Could not build test user' if current_user.blank?

saved_claim = SavedClaim::DisabilityCompensation::Form526AllClaim.from_hash(form_content)
saved_claim.metadata = check_for_0781_metadata(form_content)

raise "SavedClaim validation failed: #{saved_claim.errors.full_messages.join(', ')}" unless saved_claim.save

submission = create_submission(saved_claim, current_user)

puts({
       saved_claim_id: saved_claim.id,
       submission_id: submission.id,
       user_uuid: current_user.uuid,
       user_icn: current_user.icn
     })
