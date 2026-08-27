# frozen_string_literal: true

require 'sidekiq'
require 'logging/helper/data_scrubber'

module ClaimsApi
  class VSOReloader < BaseReloader
    include Sidekiq::Job

    # The total number of representatives and organizations parsed from the ingested .ASP files
    # must not decrease by more than this percentage from the previous count
    DECREASE_THRESHOLD = 0.20 # 20% maximum decrease allowed

    # User type constants
    USER_TYPE_ATTORNEY = 'attorney'
    USER_TYPE_CLAIM_AGENT = 'claim_agents'
    USER_TYPE_VSO = 'veteran_service_officer'

    def perform
      setup_ingestion
      array_of_organizations = reload_representatives
      remove_obsolete_representatives(array_of_organizations)
      complete_ingestion_log
    rescue Faraday::ConnectionFailed => e
      handle_connection_failure(e)
    rescue ::Common::Client::Errors::ClientError, ::Common::Exceptions::GatewayTimeout => e
      # :: prefix needed because Ruby would otherwise look for ClaimsApi::Common first
      handle_client_error(e)
    end

    # Reloads attorney data from OGC
    # @return [Array<String>] Array of representative IDs that should remain in the system
    #   Used by perform method to determine which representatives to keep vs delete
    def reload_attorneys
      reload_representative_type(
        endpoint: 'attorneyexcellist.asp',
        rep_type: :attorneys,
        user_type: USER_TYPE_ATTORNEY,
        processor: method(:find_or_create_attorneys)
      )
    end

    # Reloads claim agent data from OGC
    # @return [Array<String>] Array of representative IDs that should remain in the system
    #   Used by perform method to determine which representatives to keep vs delete
    def reload_claim_agents
      reload_representative_type(
        endpoint: 'caexcellist.asp',
        rep_type: :claims_agents,
        user_type: USER_TYPE_CLAIM_AGENT,
        processor: method(:find_or_create_claim_agents)
      )
    end

    # Reloads VSO representative and organization data from OGC
    # @return [Array<String>] Array of representative IDs that should remain in the system
    #   Used by perform method to determine which representatives to keep vs delete
    def reload_vso_reps
      ensure_initial_counts
      mark_vso_entities_running
      vso_data = fetch_data('orgsexcellist.asp')
      counts = calculate_vso_counts(vso_data)

      # Validate both counts - if either fails, skip processing both to maintain data integrity
      reps_valid = valid_count?(:vso_representatives, counts[:reps])
      orgs_valid = valid_count?(:vso_organizations, counts[:orgs])

      if reps_valid && orgs_valid
        process_valid_vso_data(vso_data, counts)
      else
        handle_vso_validation_failure(reps_valid, orgs_valid, counts)
      end
    rescue => e
      mark_vso_entities_failed(e.message)
      raise
    end

    # Common method for reloading attorney and claim agent data
    # @param endpoint [String] OGC endpoint to fetch data from
    # @param rep_type [Symbol] Type of representative for validation (:attorneys, :claims_agents)
    # @param user_type [String] Database user type constant
    # @param processor [Method] Method to process each record
    # @return [Array<String>] Representative IDs - either newly processed IDs or existing IDs if validation fails
    def reload_representative_type(endpoint:, rep_type:, user_type:, processor:)
      ensure_initial_counts
      mark_entity_running!(rep_type)

      data = fetch_data(endpoint)
      new_count = data.count { |record| record['Registration Num'].present? }

      if valid_count?(rep_type, new_count)
        process_valid_representative_data(data, processor, rep_type, new_count)
      else
        handle_representative_validation_failure(rep_type, user_type, new_count)
      end
    rescue => e
      mark_entity_failed!(rep_type, error: e.message)
      raise
    end

    private

    def normalize_poa(poa)
      poa&.gsub(/\W/, '')
    end

    def scrub_pii(message)
      Logging::Helper::DataScrubber.scrub(message)
    end

    # Setup methods for perform

    def setup_ingestion
      @initial_counts = fetch_initial_counts
      @ingestion_log = {
        attorneys: { status: :not_started, before: @initial_counts[:attorneys] },
        claims_agents: { status: :not_started, before: @initial_counts[:claims_agents] },
        vso_representatives: { status: :not_started, before: @initial_counts[:vso_representatives] },
        vso_organizations: { status: :not_started, before: @initial_counts[:vso_organizations] }
      }
    end

    def remove_obsolete_representatives(array_of_organizations)
      ClaimsApi::Representative.where.not(representative_id: array_of_organizations).find_each do |rep|
        next if test_user?(rep)

        rep.destroy!
      end
    end

    def test_user?(rep)
      (rep.first_name == 'Tamara' && rep.last_name == 'Ellis') ||
        (rep.first_name == 'John' && rep.last_name == 'Doe')
    end

    def handle_connection_failure(error)
      ClaimsApi::Logger.log('vso_reloader', level: :warn, message: "OGC connection failed: #{scrub_pii(error.message)}")
      log_to_slack("VSO Reloader failed to connect to OGC: #{scrub_pii(error.message)}")
      fail_ingestion_log("OGC connection failed: #{error.message}")
    end

    def handle_client_error(error)
      ClaimsApi::Logger.log('vso_reloader', level: :warn, message: "VSO Reloading error: #{scrub_pii(error.message)}")
      log_to_slack("VSO Reloader job has failed: #{scrub_pii(error.message)}")
      fail_ingestion_log("VSO Reloading error: #{error.message}")
    end

    # VSO-specific helper methods

    # Uses consistent keys (:vso_representatives) instead of ingestion_log DB column names (:representatives)
    def mark_vso_entities_running
      mark_entity_running!(:vso_representatives)
      mark_entity_running!(:vso_organizations)
    end

    def mark_vso_entities_failed(error_message)
      mark_entity_failed!(:vso_representatives, error: error_message)
      mark_entity_failed!(:vso_organizations, error: error_message)
    end

    def process_valid_vso_data(vso_data, counts)
      result = process_vso_data(vso_data)
      mark_entity_success!(:vso_representatives, count: counts[:reps])
      mark_entity_success!(:vso_organizations, count: counts[:orgs])
      result
    end

    def handle_vso_validation_failure(reps_valid, orgs_valid, counts)
      mark_representatives_failed(counts) unless reps_valid
      mark_organizations_failed(counts) unless orgs_valid
      existing_vso_representative_ids
    end

    def mark_representatives_failed(counts)
      mark_entity_skipped!(:vso_representatives, reason: 'threshold exceeded', count: counts[:reps])
    end

    def mark_organizations_failed(counts)
      mark_entity_skipped!(:vso_organizations, reason: 'threshold exceeded', count: counts[:orgs])
    end

    def existing_vso_representative_ids
      ClaimsApi::Representative
        .where("'#{USER_TYPE_VSO}' = ANY(user_types)")
        .pluck(:representative_id)
    end

    # Representative type helper methods

    def process_valid_representative_data(data, processor, rep_type, new_count)
      result = data.map do |record|
        processor.call(record) if record['Registration Num'].present?
        record['Registration Num']
      end
      mark_entity_success!(rep_type, count: new_count)
      result
    end

    def handle_representative_validation_failure(rep_type, user_type, new_count)
      mark_entity_skipped!(rep_type, reason: 'threshold exceeded', count: new_count)
      ClaimsApi::Representative.where('? = ANY(user_types)', user_type).pluck(:representative_id)
    end

    # Combines all representative IDs from attorneys, claim agents, and VSOs
    # @return [Array<String>] Combined array of all representative IDs that should remain in the system
    #   This list is used to identify representatives that are no longer in OGC data and should be removed
    def reload_representatives
      reload_attorneys + reload_claim_agents + reload_vso_reps
    end

    def find_or_create_attorneys(attorney)
      rep = find_or_initialize_by_id(attorney, USER_TYPE_ATTORNEY)
      rep.save
    end

    def find_or_create_claim_agents(claim_agent)
      rep = find_or_initialize_by_id(claim_agent, USER_TYPE_CLAIM_AGENT)
      rep.save
    end

    def find_or_create_vso(vso)
      unless vso['Representative']&.match(/(.*?), (.*?)(?: (.{0,1})[a-zA-Z]*)?$/)
        ClaimsApi::Logger.log('VSO', message: "Rep name not in expected format: #{vso['Registration Num']}")
        return nil
      end

      rep = find_or_initialize_by_id(convert_vso_to_useable_hash(vso), USER_TYPE_VSO)
      rep.save
      rep
    end

    def convert_vso_to_useable_hash(vso)
      last_name, first_name, middle_initial =
        vso['Representative'].match(/(.*?), (.*?)(?: (.{0,1})[a-zA-Z]*)?$/).captures

      {
        'Last Name' => last_name&.strip,
        'First Name' => first_name&.strip,
        'Middle Initial' => (middle_initial || '').strip,
        'Registration Num' => vso['Registration Num'],
        'POA Code' => normalize_poa(vso['POA']),
        'Phone' => vso['Rep Phone'] || vso['Org Phone'],
        'City' => vso['Rep City'] || vso['Org City'],
        'State' => vso['Rep State'] || vso['Org State'],
        'Zip' => vso['Rep Zip']
      }
    end

    def log_to_slack(message)
      webhook_url = Settings.claims_api&.slack&.webhook_url
      return if webhook_url.blank?

      ClaimsApi::Slack::Client.new(
        webhook_url:,
        channel: '#api-benefits-claims-alerts',
        username: 'ClaimsApi::VSOReloader'
      ).notify(message)
    end

    def fetch_initial_counts
      {
        attorneys: ClaimsApi::Representative.where("'#{USER_TYPE_ATTORNEY}' = ANY(user_types)").count,
        claims_agents: ClaimsApi::Representative.where("'#{USER_TYPE_CLAIM_AGENT}' = ANY(user_types)").count,
        vso_representatives: ClaimsApi::Representative.where("'#{USER_TYPE_VSO}' = ANY(user_types)").count,
        vso_organizations: ClaimsApi::Organization.count
      }
    end

    # setup_ingestion always resets for a fresh perform run;
    # ensure_initial_counts uses ||= for standalone reload_* calls without perform
    def ensure_initial_counts
      @initial_counts ||= fetch_initial_counts
      @ingestion_log ||= {
        attorneys: { status: :not_started, before: @initial_counts[:attorneys] },
        claims_agents: { status: :not_started, before: @initial_counts[:claims_agents] },
        vso_representatives: { status: :not_started, before: @initial_counts[:vso_representatives] },
        vso_organizations: { status: :not_started, before: @initial_counts[:vso_organizations] }
      }
    end

    def valid_count?(rep_type, new_count)
      previous_count = get_previous_count(rep_type)

      # If no previous count exists, allow the update
      return true if previous_count.nil? || previous_count.zero?

      # If new count is greater or equal, allow the update
      return true if new_count >= previous_count

      # Calculate decrease percentage
      decrease_percentage = (previous_count - new_count).to_f / previous_count

      if decrease_percentage > DECREASE_THRESHOLD
        notify_threshold_exceeded(rep_type, previous_count, new_count, decrease_percentage, DECREASE_THRESHOLD)
        false
      else
        true
      end
    end

    def get_previous_count(rep_type)
      @initial_counts[rep_type]
    end

    def notify_threshold_exceeded(rep_type, previous_count, new_count, decrease_percentage, threshold)
      message = "⚠️ VSO Reloader Alert: #{rep_type.to_s.humanize} count decreased beyond threshold!\n" \
                "Previous: #{previous_count}\n" \
                "New: #{new_count}\n" \
                "Decrease: #{(decrease_percentage * 100).round(2)}%\n" \
                "Threshold: #{(threshold * 100).round(2)}%\n" \
                'Action: Update skipped, manual review required'

      log_to_slack(message)
      ClaimsApi::Logger.log('vso_reloader',
                            level: :warn,
                            message: "threshold exceeded for #{rep_type}",
                            previous_count:,
                            new_count:,
                            decrease_percentage:)
    end

    def mark_entity_running!(entity_type)
      @ingestion_log[entity_type][:status] = :running
    end

    def mark_entity_success!(entity_type, count: nil)
      @ingestion_log[entity_type].merge!(status: :success, after: count)
    end

    def mark_entity_failed!(entity_type, error: nil, count: nil)
      @ingestion_log[entity_type].merge!(status: :failed, error:, after: count).compact!
    end

    def mark_entity_skipped!(entity_type, reason: nil, count: nil)
      # :skipped is distinct from :failed — threshold exceeded is an intentional safety skip, not an error
      @ingestion_log[entity_type].merge!(status: :skipped, reason:, after: count).compact!
    end

    def complete_ingestion_log
      lines = @ingestion_log.map do |type, info|
        label = type.to_s.humanize
        case info[:status]
        when :success
          "  #{label}: #{info[:after]} (was #{info[:before]}) ✅"
        when :skipped
          "  #{label}: ⚠️ SKIPPED (#{info[:reason]})"
        when :failed
          "  #{label}: ❌ FAILED (#{scrub_pii(info[:error].to_s)})"
        else
          "  #{label}: #{info[:before]} (not processed)"
        end
      end

      overall = @ingestion_log.values.any? { |i| i[:status] == :failed } ? 'FAILED' : 'completed'
      message = "ClaimsApi::VSOReloader #{overall}\n#{lines.join("\n")}"
      log_to_slack(message)
      ClaimsApi::Logger.log('vso_reloader', message:)
    end

    def fail_ingestion_log(error_message)
      @ingestion_log&.each_key { |k| @ingestion_log[k].merge!(status: :failed, error: error_message) }
      complete_ingestion_log
    end

    def calculate_vso_counts(vso_data)
      normalized_poas =
        vso_data
        .map { |v| normalize_poa(v['POA']) }
        .compact_blank
        .uniq

      {
        reps: vso_data.count { |v| v['Representative'].present? && v['Registration Num'].present? },
        orgs: normalized_poas.count
      }
    end

    def process_vso_data(vso_data)
      vso_reps, rep_org_pairs, vso_orgs = extract_vso_entities(vso_data)

      current_poa_codes = vso_orgs.map { |org| org[:poa] }.compact_blank.uniq

      # Always import organizations when processing VSO data to maintain referential integrity
      ClaimsApi::Organization.transaction do
        import_vso_organizations(vso_orgs)

        ClaimsApi::RepresentativeRelationshipsSync.sync!(
          rep_org_pairs:,
          current_poa_codes:
        )
      end

      vso_reps
    end

    def extract_vso_entities(vso_data)
      vso_reps = []
      rep_org_pairs = []

      vso_orgs =
        vso_data.filter_map do |row|
          next unless row['Representative']

          rep_id = row['Registration Num']
          poa = normalize_poa(row['POA'])

          append_seen_rep_id!(vso_reps, rep_id)
          rep = create_vso_rep_if_valid(row)

          rep_org_pairs << [rep_id, poa] if rep.present? && rep.persisted? && rep_id.present? && poa.present?
          build_org_hash(row, poa)
        end.compact.uniq

      [vso_reps, rep_org_pairs, vso_orgs]
    end

    def append_seen_rep_id!(vso_reps, rep_id)
      vso_reps << rep_id if rep_id.present?
    end

    def create_vso_rep_if_valid(row)
      return nil if row['Registration Num'].blank?

      find_or_create_vso(row)
    end

    def build_org_hash(row, poa)
      return nil if poa.blank?

      {
        poa:,
        name: row['Organization Name'],
        phone: row['Org Phone'],
        state: row['Org State']
      }
    end

    def import_vso_organizations(vso_orgs)
      ClaimsApi::Organization.import(vso_orgs, on_duplicate_key_update: %i[name phone state])
    end
  end
end
