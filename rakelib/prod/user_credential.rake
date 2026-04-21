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

    validate_credential_args(args)
    context = build_context(args)
    log_message(level: 'info', message: "[#{namespace}] rake task start, context: #{context.to_json}")

    user_verification = UserVerification.find_by(["#{args[:type]}_uuid = ?", args[:credential_id]])
    if user_verification.nil?
      log_message(level: 'error', message: "[#{namespace}] failed - UserVerification not found")
      return
    end

    update_credential(user_verification, action, namespace, context)
    log_message(level: 'info', message: "[#{namespace}] rake task complete, context: #{context.to_json}")
  rescue => e
    log_message(level: 'error', message: "[#{namespace}] failed - #{e.message}")
  end

  def run_account_task(action, args)
    namespace = "UserCredential::UserAccount #{action}"

    validate_account_args(args)
    context = build_context(args)
    log_message(level: 'info', message: "[#{namespace}] rake task start, context: #{context.to_json}")

    user_account = UserAccount.find_by(icn: args[:icn])
    if user_account.nil?
      log_message(level: 'error', message: "[#{namespace}] failed - UserAccount not found")
      return
    end

    update_account(user_account, action, namespace, context)
    log_message(level: 'info', message: "[#{namespace}] rake task complete, context: #{context.to_json}")
  rescue => e
    log_message(level: 'error', message: "[#{namespace}] failed - #{e.message}")
  end

  def validate_credential_args(args)
    missing_args = %i[type credential_id requested_by]
    raise 'Missing required arguments' unless args.values_at(*missing_args).all?
    raise 'Invalid type' if SignIn::Constants::Auth::CSP_TYPES.exclude?(args[:type])
  end

  def validate_account_args(args)
    missing_args = %i[icn requested_by]
    raise 'Missing required arguments' unless args.values_at(*missing_args).all?
  end

  def build_context(args)
    { icn: args[:icn],
      type: args[:type],
      credential_id: args[:credential_id],
      requested_by: args[:requested_by] }.compact
  end

  def update_credential(user_verification, action, namespace, context)
    user_verification.send("#{action}!")
    credential_context = context.merge({ type: user_verification.credential_type,
                                         credential_id: user_verification.credential_identifier,
                                         locked: user_verification.locked }).compact
    log_message(level: 'info',
                message: "[#{namespace}] credential #{action}, context: #{credential_context.to_json}")
  end

  def update_account(user_account, action, namespace, context)
    user_account.send("#{action}!")
    account_context = context.merge({ locked: user_account.locked })
    log_message(level: 'info',
                message: "[#{namespace}] user account #{action}, context: #{account_context.to_json}")
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
