# frozen_string_literal: true

desc 'Lock and unlock user credentials'
namespace :user_credential do
  task :lock_verification, %i[type credential_id requested_by] => :environment do |_, args|
    run_credential_task(:lock, args)
  end

  task :unlock_verification, %i[type credential_id requested_by] => :environment do |_, args|
    run_credential_task(:unlock, args)
  end

  task :lock_account, %i[icn requested_by] => :environment do |_, args|
    run_account_task(:lock, args)
  end

  task :unlock_account, %i[icn requested_by] => :environment do |_, args|
    run_account_task(:unlock, args)
  end

  def run_credential_task(action, args)
    namespace = "UserCredential::UserVerification #{action}"

    validate_requested_by(args)
    log_message(level: 'info', message: "[#{namespace}] rake task start, context: #{build_context(args).to_json}")

    context = UserCredentialManager.perform_verification_action(
      action:,
      type: args[:type],
      credential_id: args[:credential_id]
    )

    log_message(level: 'info',
                message: "[#{namespace}] rake task complete, " \
                         "context: #{context.merge({ requested_by: args[:requested_by] }).to_json}")
  rescue => e
    log_message(level: 'error', message: "[#{namespace}] failed - #{e.message}")
  end

  def run_account_task(action, args)
    namespace = "UserCredential::UserAccount #{action}"

    validate_requested_by(args)
    log_message(level: 'info', message: "[#{namespace}] rake task start, context: #{build_context(args).to_json}")

    context = UserCredentialManager.perform_account_action(action:, icn: args[:icn])

    log_message(level: 'info',
                message: "[#{namespace}] rake task complete, " \
                         "context: #{context.merge({ requested_by: args[:requested_by] }).to_json}")
  rescue => e
    log_message(level: 'error', message: "[#{namespace}] failed - #{e.message}")
  end

  def validate_requested_by(args)
    raise Common::Exceptions::ParameterMissing, 'requested_by' if args[:requested_by].blank?
  end

  def build_context(args)
    { icn: args[:icn], type: args[:type], credential_id: args[:credential_id],
      requested_by: args[:requested_by] }.compact
  end

  def log_message(level:, message:)
    `echo "#{datadog_log(level:, message:).to_json.dump}" >> /proc/1/fd/1` if Rails.env.production?
    puts message
  end

  def datadog_log(level:, message:)
    {
      level:,
      message:,
      application: 'vets-api-server',
      environment: Rails.env,
      timestamp: Time.zone.now.iso8601,

      file: 'rakelib/prod/user_credential.rake',
      named_tags: {
        dd: {
          env: ENV.fetch('DD_ENV', nil),
          service: 'vets-api'
        },
        ddsource: 'ruby'
      },
      name: 'Rails'
    }
  end
end
