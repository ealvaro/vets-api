# frozen_string_literal: true

require 'sidekiq'

module RepresentationManagement
  # This is the first job in a two job process for updating accredited entities.
  # Processes and updates accredited entities (agents and attorneys) from the GCLAWS API
  #
  # This Sidekiq job fetches data about accredited agents and attorneys from the GCLAWS API,
  # creates or updates records in the database, validates addresses through the VAProfile
  # address validation service, and removes records that are no longer present in the API.
  # That address validation is done in the second job, RepresentationManagement::AccreditedIndividualsUpdate.
  #
  # The job includes data validation to prevent large decreases in entity counts, which might
  # indicate data quality issues. This validation can be bypassed for specific entity types
  # using the force_update_types parameter.
  #
  # @example Enqueue the job to process all entity types
  #   RepresentationManagement::AccreditedEntitiesQueueUpdates.perform_async
  #
  # @example Force update for a specific entity type
  #   RepresentationManagement::AccreditedEntitiesQueueUpdates.perform_async(['agents'])
  #
  # @example Force update for multiple entity types
  #   RepresentationManagement::AccreditedEntitiesQueueUpdates.perform_async(['agents', 'attorneys'])
  # rubocop:disable Metrics/ClassLength
  class AccreditedEntitiesQueueUpdates
    include Sidekiq::Job

    # Maximum allowed decrease percentage for entity counts before updates are blocked
    DECREASE_THRESHOLD = RepresentationManagement::AccreditationApiEntityCount::DECREASE_THRESHOLD

    # Number of records to process in each address validation batch
    SLICE_SIZE = 30

    AGENTS = RepresentationManagement::AGENTS
    ATTORNEYS = RepresentationManagement::ATTORNEYS
    REPRESENTATIVES = RepresentationManagement::REPRESENTATIVES
    VSOS = RepresentationManagement::VSOS
    ENTITY_CONFIG = RepresentationManagement::ENTITY_CONFIG

    # Main job method that processes accredited entities
    #
    # @param force_update_types [Array<String>] Optional array of entity types to force update
    #   regardless of count validation ('agents', 'attorneys', 'representatives', 'veteran_service_organizations')
    # @return [void]
    def perform(force_update_types = [])
      @force_update_types = force_update_types
      setup_ingestion
      process_all_entities
      cleanup_removed_records
      complete_ingestion_log
    rescue => e
      handle_ingestion_error(e)
    ensure
      finalize_and_send_report
    end

    private

    def initialize_instance_variables
      @start_time = Time.current
      @report = String.new
      @agent_ids = []
      @attorney_ids = []
      @vso_ids = []
      @representative_ids = []
      @agent_ids_for_address_validation = []
      @attorney_ids_for_address_validation = []
      @representative_ids_for_address_validation = []
      @rep_to_vso_associations = {}
      @accreditation_ids = []
      @processing_error_types = []
      @expected_counts = {}
      @count_mismatch_types = []
      @logged_errors = Hash.new(0)
      # Raw count of representative rows processed (not deduplicated). One person can be accredited
      # with multiple VSOs, so the API returns multiple rows per individual. This raw count is what
      # the count validation compares against the API's totalRecords.
      @representative_rows_processed = 0
    end

    def setup_daily_report
      @report << 'RepresentationManagement::AccreditedEntitiesQueueUpdates Report\n'
      @report << "📊 **Entity Counts:**\n"
      @report << "```\n#{@entity_counts&.count_report || 'Entity counts unavailable'}\n```\n"
    end

    def finalize_and_send_report
      end_time = Time.current
      duration = calculate_duration(@start_time, end_time)

      # Add deletion skip summary
      add_deletion_skip_summary
      add_error_summary
      add_address_quality_report_by_individual_type

      @report << "\nJob Duration: #{duration}\n"
      log_to_slack_channel(@report)
    end

    # Sets up the ingestion process by initializing variables and starting the log
    #
    # @return [void]
    def setup_ingestion
      initialize_instance_variables
      @ingestion_log = RepresentationManagement::AccreditationDataIngestionLog.start_ingestion!(
        dataset: :accreditation_api
      )
      @entity_counts = RepresentationManagement::AccreditationApiEntityCount.new
      setup_daily_report
      # Don't save fresh API counts if updates are forced
      @entity_counts.save_api_counts unless @force_update_types.any?
    end

    # Processes all entity types
    #
    # @return [void]
    def process_all_entities
      process_entity_type(AGENTS)
      process_entity_type(ATTORNEYS)
      process_orgs_and_reps
    end

    # Cleans up removed records from the database
    #
    # @return [void]
    def cleanup_removed_records
      log_progress('Cleaning up removed records...')
      remove_skipped_deletions
      delete_removed_accredited_individuals
      delete_removed_accredited_organizations
      log_progress('  Cleanup complete.')
    end

    # Handles errors during ingestion
    #
    # @param error [Exception] The error that occurred
    # @return [void]
    def handle_ingestion_error(error)
      log_error("Error in AccreditedEntitiesQueueUpdates: #{error.message}")
      fail_ingestion_log("Error in AccreditedEntitiesQueueUpdates: #{error.message}")
    end

    # Adds a summary of skipped deletions to the report
    #
    # @return [void]
    def add_deletion_skip_summary
      skipped_types = (@processing_error_types + @count_mismatch_types.map(&:to_s)).uniq
      return if skipped_types.empty?

      @report << "\n⚠️ **Deletion Skipped for Some Entity Types:**\n"

      if @processing_error_types.any?
        @report << "Due to errors during processing:\n"
        @processing_error_types.each { |type| @report << "  - #{type.humanize}\n" }
      end

      if @count_mismatch_types.any?
        threshold_display = (DECREASE_THRESHOLD.abs * 100).round(0)
        @report << "Due to count mismatches (>#{threshold_display}% decrease):\n"
        @count_mismatch_types.each { |type| @report << mismatch_summary_line(type) }
      end
    end

    def mismatch_summary_line(type)
      expected = @expected_counts[type].to_i
      actual = get_processed_count_for_type(type)
      label = type.to_s.humanize
      # For representatives, `actual` is the raw rows processed (the basis for validation); also show
      # the deduplicated unique count so the report reflects both numbers.
      suffix = type == :representatives ? " (#{@representative_ids.uniq.compact.size} unique)" : ''
      if expected.positive?
        change = ((actual - expected).to_f / expected * 100).round(2)
        "  - #{label}: Expected #{expected}, Processed #{actual}#{suffix} (#{change}% change)\n"
      else
        "  - #{label}: Expected #{expected}, Processed #{actual}#{suffix}\n"
      end
    end

    # Adds a deduplicated error summary to the report
    #
    # @return [void]
    def add_error_summary
      return if @logged_errors.blank?

      repeated = @logged_errors.select { |_, count| count > 1 }
      return if repeated.empty?

      @report << "\n\u274c **Errors (deduplicated):**\n"
      repeated.each do |message, count|
        @report << "  - (#{count}x) #{message}\n"
      end
    end

    # Gets the processed count for a given entity type
    #
    # @param type [Symbol] The entity type
    # @return [Integer] The number of processed records
    def get_processed_count_for_type(type)
      case type
      when :agents then @agent_ids.uniq.compact.size
      when :attorneys then @attorney_ids.uniq.compact.size
      when :veteran_service_organizations then @vso_ids.uniq.compact.size
      # Use the raw rows processed (not the deduplicated @representative_ids) so this matches the
      # basis used by validate_all_counts and lines up with the API's totalRecords count.
      when :representatives then @representative_rows_processed.to_i
      else 0
      end
    end

    # Processes entities of a specific type based on count validation and force update settings
    #
    # @param entity_type [String] The type of entity to process ('agents' or 'attorneys')
    # @return [void]
    def process_entity_type(entity_type)
      return if should_skip_entity_type?(entity_type)

      @ingestion_log&.mark_entity_running!(entity_type)

      if should_process_entity_type?(entity_type)
        process_valid_entity_type(entity_type)
      else
        handle_invalid_entity_count(entity_type)
      end
    rescue => e
      @processing_error_types << entity_type unless @processing_error_types.include?(entity_type)
      @ingestion_log&.mark_entity_failed!(entity_type, error: e.message)
      log_progress("  ❌ Error processing #{entity_type}: #{e.message}")
      log_error("Error processing #{entity_type}: #{e.message}")
    end

    # Determines if an entity type should be skipped
    #
    # @param entity_type [String] The entity type
    # @return [Boolean]
    def should_skip_entity_type?(entity_type)
      @force_update_types.any? && @force_update_types.exclude?(entity_type)
    end

    # Determines if an entity type should be processed
    #
    # @param entity_type [String] The entity type
    # @return [Boolean]
    def should_process_entity_type?(entity_type)
      @entity_counts.valid_count?(entity_type) || @force_update_types.include?(entity_type)
    end

    # Processes a validated entity type
    #
    # @param entity_type [String] The entity type
    # @return [void]
    def process_valid_entity_type(entity_type)
      @expected_counts[entity_type.to_sym] = @entity_counts.current_api_counts[entity_type.to_sym]

      if entity_type == AGENTS
        process_agents
      else
        process_attorneys
      end

      @ingestion_log&.mark_entity_success!(entity_type, count: entity_count_for(entity_type))
    end

    # Processes agents
    #
    # @return [void]
    def process_agents
      log_progress('Processing agents...')
      update_agents
      log_progress("  Agents processed: #{@agent_ids.uniq.compact.size}")
      @report << "Agents processed: #{@agent_ids.uniq.compact.size}\n"
      validate_agent_addresses
    end

    # Processes attorneys
    #
    # @return [void]
    def process_attorneys
      log_progress('Processing attorneys...')
      update_attorneys
      log_progress("  Attorneys processed: #{@attorney_ids.uniq.compact.size}")
      @report << "Attorneys processed: #{@attorney_ids.uniq.compact.size}\n"
      validate_attorney_addresses
    end

    # Returns the count for a specific entity type
    #
    # @param entity_type [String] The entity type
    # @return [Integer]
    def entity_count_for(entity_type)
      entity_type == AGENTS ? @agent_ids.uniq.compact.size : @attorney_ids.uniq.compact.size
    end

    # Handles invalid entity counts
    #
    # @param entity_type [String] The entity type
    # @return [void]
    def handle_invalid_entity_count(entity_type)
      entity_type_sym = entity_type.to_sym
      @count_mismatch_types << entity_type_sym unless @count_mismatch_types.include?(entity_type_sym)
      @expected_counts[entity_type_sym] ||= @entity_counts.current_api_counts[entity_type_sym]
      entity_display = entity_type.capitalize
      message = "#{entity_display} count decreased by more than #{DECREASE_THRESHOLD * 100}% - skipping update"
      log_progress("  ⚠️  #{message}")
      log_error(message)
      @ingestion_log&.mark_entity_failed!(
        entity_type,
        error: 'Count validation failed',
        threshold: DECREASE_THRESHOLD
      )
    end

    def process_orgs_and_reps
      return if should_skip_orgs_and_reps?

      mark_orgs_and_reps_running
      log_invalid_counts_for_orgs_and_reps
      return unless can_process_orgs_and_reps?

      capture_expected_counts_for_orgs_and_reps
      process_vsos_and_reps
      create_or_update_accreditations
    rescue => e
      @processing_error_types << VSOS unless @processing_error_types.include?(VSOS)
      @processing_error_types << REPRESENTATIVES unless @processing_error_types.include?(REPRESENTATIVES)
      mark_orgs_and_reps_failed(e.message)
      log_error("Error processing orgs and reps: #{e.message}")
    end

    # Determines if orgs and reps should be skipped
    #
    # @return [Boolean]
    def should_skip_orgs_and_reps?
      @force_update_types.any? && !@force_update_types.intersect?(orgs_and_reps)
    end

    # Marks organizations and representatives as running
    #
    # @return [void]
    def mark_orgs_and_reps_running
      @ingestion_log&.mark_entity_running!(REPRESENTATIVES)
      @ingestion_log&.mark_entity_running!(VSOS)
    end

    # Logs invalid counts for organizations and representatives
    #
    # @return [void]
    def log_invalid_counts_for_orgs_and_reps
      orgs_and_reps.each do |type|
        unless @entity_counts.valid_count?(type) || @force_update_types.include?(type)
          log_error("#{type.humanize} count decreased by more than #{DECREASE_THRESHOLD * 100}% - skipping update")
        end
      end
    end

    # Determines if organizations and representatives can be processed
    #
    # @return [Boolean]
    def can_process_orgs_and_reps?
      if orgs_and_reps_both_valid? || @force_update_types.intersect?(orgs_and_reps)
        true
      else
        handle_invalid_orgs_and_reps_counts
        false
      end
    end

    # Handles invalid counts for organizations and representatives
    #
    # @return [void]
    def handle_invalid_orgs_and_reps_counts
      api_counts = @entity_counts.current_api_counts
      %i[veteran_service_organizations representatives].each do |type|
        @count_mismatch_types << type unless @count_mismatch_types.include?(type)
        @expected_counts[type] ||= api_counts[type]
      end
      log_error('Both Orgs and Reps must have valid counts to process together - skipping update for both')
      mark_orgs_and_reps_failed('Both Orgs and Reps must have valid counts')
    end

    # Captures expected counts for organizations and representatives
    #
    # @return [void]
    def capture_expected_counts_for_orgs_and_reps
      api_counts = @entity_counts.current_api_counts
      @expected_counts[:veteran_service_organizations] = api_counts[:veteran_service_organizations]
      @expected_counts[:representatives] = api_counts[:representatives]
    end

    # Processes VSOs and representatives
    #
    # @return [void]
    def process_vsos_and_reps
      # Process VSOs first (must exist before representatives can reference them)
      log_progress('Processing VSOs...')
      update_vsos
      log_progress("  VSOs processed: #{@vso_ids.uniq.compact.size}")
      @report << "VSOs processed: #{@vso_ids.uniq.compact.size}\n"
      @ingestion_log&.mark_entity_success!(VSOS, count: @vso_ids.uniq.compact.size)

      # Process representatives
      log_progress('Processing representatives...')
      update_reps
      rep_rows = @representative_rows_processed.to_i
      rep_unique = @representative_ids.uniq.compact.size
      log_progress("  Representatives processed: #{rep_rows} rows (#{rep_unique} unique)")
      @report << "Representatives processed: #{rep_rows} rows (#{rep_unique} unique)\n"
      validate_rep_addresses
      @ingestion_log&.mark_entity_success!(REPRESENTATIVES, count: rep_unique)
    end

    # Marks organizations and representatives as failed
    #
    # @param error_message [String] The error message
    # @return [void]
    def mark_orgs_and_reps_failed(error_message)
      @ingestion_log&.mark_entity_failed!(REPRESENTATIVES, error: error_message)
      @ingestion_log&.mark_entity_failed!(VSOS, error: error_message)
    end

    # Fetches agent data from the GCLAWS API and updates database records
    #
    # @return [void]
    def update_agents
      update_entities(AGENTS)
    end

    # Fetches attorney data from the GCLAWS API and updates database records
    #
    # @return [void]
    def update_attorneys
      update_entities(ATTORNEYS)
    end

    # Generic method to update entities of a specific type
    #
    # @param entity_type [String] The type of entity to update ('agents' or 'attorneys')
    # @return [void]
    def update_entities(entity_type)
      config = ENTITY_CONFIG[entity_type]
      page = 1

      loop do
        response = client.get_accredited_entities(type: entity_type, page:)
        entities = response.body['items']
        break if entities.empty?

        log_progress("  Page #{page}: #{entities.size} #{entity_type}")
        entities.each { |entity| handle_entity_record(entity, config) }
        page += 1
      end
    rescue => e
      @processing_error_types << entity_type unless @processing_error_types.include?(entity_type)
      log_error("Error updating #{entity_type}: #{e.message}")
    end

    # Fetches VSO data from the GCLAWS API and updates database records
    #
    # @return [void]
    def update_vsos
      page = 1

      loop do
        response = client.get_accredited_entities(type: VSOS, page:)
        vsos = response.body['items']
        break if vsos.empty?

        log_progress("  Page #{page}: #{vsos.size} VSOs")
        vsos.each { |vso| handle_vso_record(vso) }
        page += 1
      end
    rescue => e
      @processing_error_types << VSOS unless @processing_error_types.include?(VSOS)
      log_error("Error updating VSOs: #{e.message}")
    end

    # Process individual VSO record
    #
    # @param vso [Hash] VSO data from the API
    # @return [void]
    def handle_vso_record(vso)
      # Skip rows without a POA code — it's the unique key on accredited_organizations, so a blank
      # value would only fail validation and land in the (deduped) rescue, adding noise to the
      # error summary rather than surfacing a real problem.
      return if vso['poa'].blank?

      vso_hash = data_transform_for_vso(vso)

      # Find or create by poa_code, which is the unique key on accredited_organizations. ogc_id
      # (organization.id) is set/updated via vso_hash below — keying the lookup on ogc_id here
      # would collide with the unique poa_code index whenever an existing row's ogc_id differs.
      record = AccreditedOrganization.find_or_create_by(poa_code: vso['poa'])

      # Update record
      record.update(vso_hash)
      @vso_ids << record.id
    rescue => e
      log_error("Error handling VSO record with POA #{vso['poa']}: #{e.message}")
    end

    # Transforms VSO data from the GCLAWS API into a format suitable for the AccreditedOrganization model
    #
    # @param vso [Hash] Raw VSO data from the GCLAWS API
    # @return [Hash] Transformed data for AccreditedOrganization record
    def data_transform_for_vso(vso)
      {
        ogc_id: vso.dig('organization', 'id'),
        poa_code: vso['poa'],
        name: vso.dig('organization', 'name')
      }
    end

    # Fetches representative data from the GCLAWS API and updates database records
    #
    # @return [void]
    def update_reps
      page = 1

      loop do
        response = client.get_accredited_entities(type: REPRESENTATIVES, page:)
        representatives = response.body['items']
        break if representatives.empty?

        log_progress("  Page #{page}: #{representatives.size} representatives")
        representatives.each { |rep| handle_representative_record(rep) }
        page += 1
      end
    rescue => e
      @processing_error_types << REPRESENTATIVES unless @processing_error_types.include?(REPRESENTATIVES)
      log_error("Error updating representatives: #{e.message}")
    end

    # Process individual representative record
    #
    # @param rep [Hash] Representative data from the API (flat structure)
    # @return [void]
    def handle_representative_record(rep)
      # Skip rows without a registration number — it's part of the natural key and required by the
      # unique index, so a blank value would only fail validation and land in the (deduped) rescue,
      # adding noise to the error summary rather than surfacing a real problem.
      return if rep['number'].blank?

      rep_hash = data_transform_for_representative(rep)

      # Find or create record by the natural key (registration_number + individual_type), which
      # matches the unique index on the table. ogc_id is set/updated via rep_hash below.
      # registration_number is cast to a string to stay consistent with the XLSX ingestion path,
      # which stores registration numbers as strings.
      record = AccreditedIndividual.find_or_create_by(
        individual_type: 'representative',
        registration_number: rep['number'].to_s
      )

      # Check if address validation is needed
      raw_address = raw_address_for_representative(rep)
      @representative_ids_for_address_validation << record.id if record.raw_address != raw_address

      # Update record
      record.update(rep_hash)
      @representative_ids << record.id
      # Count every processed row (not deduplicated) for count validation against the API total.
      @representative_rows_processed = @representative_rows_processed.to_i + 1

      # Track VSO associations for this representative.
      #
      # A representative's `organizationID` is the same UUID as a VSO's `organization.id`, which we
      # persist as the AccreditedOrganization's `ogc_id`. That shared UUID is the link between a rep
      # and their organization: accreditation pairs are later resolved via
      # AccreditedOrganization.find_by(ogc_id: vso_ogc_id). This linkage was confirmed against
      # staging data (81 of 82 organizations matched). If a rep's `organizationID` has no matching
      # org `ogc_id`, the association is simply skipped downstream (no accreditation created) rather
      # than raising — so divergence degrades gracefully instead of erroring.
      vso_ogc_id = rep['organizationID']
      @rep_to_vso_associations[record.id] ||= []
      @rep_to_vso_associations[record.id] << vso_ogc_id unless @rep_to_vso_associations[record.id].include?(vso_ogc_id)
    rescue => e
      log_error("Error handling representative record with registration number #{rep['number']}: #{e.message}")
    end

    # Transforms representative data from the GCLAWS API into a format suitable for the AccreditedIndividual model
    # Note: The representative API response uses a flat structure (not nested like VSOs)
    #
    # @param rep [Hash] Raw representative data from the GCLAWS API (flat structure)
    # @return [Hash] Transformed data for AccreditedIndividual record
    def data_transform_for_representative(rep)
      data_transform_for_entity(rep, 'representative', {
                                  phone: rep['workPhoneNumber'],
                                  email: rep['workEmailAddress'],
                                  raw_address: raw_address_for_representative(rep),
                                  ogc_id: rep['accrRepresentativeId']
                                })
    end

    # Creates a standardized address hash for a representative
    #
    # @param rep [Hash] Raw representative data from the GCLAWS API
    # @return [Hash] Standardized address data
    def raw_address_for_representative(rep)
      raw_address_from_entity(rep, city: 'workCity', state_code: 'workState')
    end

    def processed_individual_types
      # Determine which individual types were processed based on force_update_types
      [AGENTS, ATTORNEYS, REPRESENTATIVES].filter_map do |type|
        ENTITY_CONFIG.public_send(type.downcase).individual_type if @force_update_types.include?(type)
      end
    end

    def remove_skipped_deletions
      # If @processing_error_types includes an entity type, we skip deletions for that type
      # by preloading the current IDs into the respective ID arrays.
      # Also skip deletions if processed counts don't match expected counts.

      # Validate all processed counts
      validate_all_counts

      individual_types = {
        AGENTS => :@agent_ids,
        ATTORNEYS => :@attorney_ids,
        REPRESENTATIVES => :@representative_ids
      }

      individual_types.each do |type, ivar|
        skip_due_to_error = @processing_error_types.include?(type)
        skip_due_to_mismatch = @count_mismatch_types.include?(type.to_sym)

        next unless skip_due_to_error || skip_due_to_mismatch

        ids = AccreditedIndividual.where(
          individual_type: ENTITY_CONFIG.send(type).individual_type
        ).pluck(:id)
        instance_variable_set(ivar, ids)
      end

      skip_vso_deletion = @processing_error_types.include?(VSOS) ||
                          @count_mismatch_types.include?(:veteran_service_organizations)
      @vso_ids = AccreditedOrganization.all.pluck(:id) if skip_vso_deletion
    end

    def add_address_quality_report_by_individual_type
      types = {
        'Attorney' => AccreditedIndividual.attorneys,
        'Claims agent' => AccreditedIndividual.claims_agents,
        'Representative' => AccreditedIndividual.representatives
      }

      @report << "\n📍 **Address Quality by AccreditedIndividual Type:**\n"
      @report << "```\n"

      types.each do |label, scope|
        counts = scope.address_quality_counts

        @report << "#{label}:\n"
        @report << "  Full (validated): #{counts[:full]}\n"
        @report << "  Partial (zip-only): #{counts[:partial_zip_only]}\n"
        @report << "  Partial (city/state-only): #{counts[:partial_city_state_only]}\n"
        @report << "  No location: #{counts[:no_location]}\n"
        @report << "  Other w/ location: #{counts[:other]}\n" if counts[:other].positive?
      end

      @report << "```\n"
    end

    # Validates processed counts for all entity types against expected counts
    #
    # @return [void]
    def validate_all_counts
      processed_counts = {
        agents: @agent_ids.uniq.compact.size,
        attorneys: @attorney_ids.uniq.compact.size,
        veteran_service_organizations: @vso_ids.uniq.compact.size,
        # Representatives are deduplicated by registration_number (one person can be accredited with
        # multiple VSOs, producing multiple API rows). Validate against the raw number of rows
        # processed so it lines up with the API's totalRecords count rather than the unique count.
        representatives: @representative_rows_processed.to_i
      }

      processed_counts.each do |type_key, processed_count|
        next unless @expected_counts[type_key]

        counts_match_expected?(type_key.to_s, processed_count)
      end
    end

    # Validates that the processed count matches the expected count within tolerance
    # Uses the same DECREASE_THRESHOLD as count validation to maintain consistency
    #
    # @param entity_type [String, Symbol] The type of entity to validate
    # @param processed_count [Integer] The number of records actually processed
    # @return [Boolean] true if counts match within tolerance, false otherwise
    def counts_match_expected?(entity_type, processed_count)
      entity_type = entity_type.to_sym
      expected_count = @expected_counts[entity_type]

      # If we don't have an expected count, we can't validate
      return true if expected_count.nil? || expected_count.zero?

      # If processed count is greater or equal to expected, that's fine
      return true if processed_count >= expected_count

      # Calculate percentage change (negative for decrease)
      change_percentage = ((processed_count - expected_count).to_f / expected_count)

      # Check if decrease is within acceptable threshold (DECREASE_THRESHOLD is negative, e.g., -0.20)
      within_tolerance = change_percentage > DECREASE_THRESHOLD

      # Track mismatch if outside tolerance
      unless within_tolerance
        @count_mismatch_types << entity_type unless @count_mismatch_types.include?(entity_type)
        percentage_display = (change_percentage * 100).round(2)
        log_error("Count mismatch for #{entity_type}: expected #{expected_count}, " \
                  "processed #{processed_count} (#{percentage_display}% change)")
      end

      within_tolerance
    end

    # Removes AccreditedIndividual records that are no longer present in the GCLAWS API
    # When force_update_types is specified, only deletes records of the processed types
    #
    # @return [void]
    def delete_removed_accredited_individuals
      # @force_update_types are only present when manually reprocessing entity types.  They aren't present in the
      # ordinary daily job run.
      if @force_update_types.any?
        # Only delete records of types that were actually processed

        # If no individual types were processed, return early to avoid deleting any records.
        # This safeguards against accidental deletion when no types were selected for processing.
        return if processed_individual_types.empty?

        # Delete only records of processed types that are not in the current ID lists
        AccreditedIndividual.where(individual_type: processed_individual_types)
                            .where.not(id: @agent_ids + @attorney_ids + @representative_ids)
                            .find_each do |record|
          record.destroy
        rescue => e
          log_error("Error deleting old accredited individual with ID #{record.id}: #{e.message}")
        end
      else
        # Original behavior: delete all records not in current ID lists
        AccreditedIndividual.where.not(id: @agent_ids + @attorney_ids + @representative_ids).find_each do |record|
          record.destroy
        rescue => e
          log_error("Error deleting old accredited individual with ID #{record.id}: #{e.message}")
        end
      end
    end

    # Handle an individual entity
    #
    # @param entity [Hash] The entity data from the API
    # @param config [Hash] Configuration for the entity type
    # @return [void]
    def handle_entity_record(entity, config)
      # Skip rows without a registration number — it's part of the natural key and required by the
      # unique index, so a blank value would only fail validation and land in the (deduped) rescue,
      # adding noise to the error summary rather than surfacing a real problem.
      return if entity['number'].blank?

      api_type = config[:api_type]
      entity_hash = send("data_transform_for_#{api_type}", entity)

      # Find or create record by the natural key (registration_number + individual_type), which
      # matches the unique index on the table. ogc_id is set/updated via entity_hash below.
      # registration_number is cast to a string to stay consistent with the XLSX ingestion path,
      # which stores registration numbers as strings.
      entity_identifier = { individual_type: config[:individual_type], registration_number: entity['number'].to_s }
      record = AccreditedIndividual.find_or_create_by(entity_identifier)

      # Check if address validation is needed
      raw_address = send("raw_address_for_#{api_type}", entity)
      instance_variable_get(config[:validation_ids_var]) << record.id if record.raw_address != raw_address

      # Update record and store ID
      record.update(entity_hash)
      instance_variable_get(config[:ids_var]) << record.id
    end

    # Transforms agent data from the GCLAWS API into a format suitable for the AccreditedIndividual model
    #
    # @param agent [Hash] Raw agent data from the GCLAWS API
    # @return [Hash] Transformed data for AccreditedIndividual record
    def data_transform_for_agent(agent)
      data_transform_for_entity(agent, ENTITY_CONFIG.send(AGENTS).individual_type, {
                                  phone: agent['workPhoneNumber'],
                                  email: agent['workEmailAddress'],
                                  raw_address: raw_address_for_agent(agent)
                                })
    end

    # Transforms attorney data from the GCLAWS API into a format suitable for the AccreditedIndividual model
    #
    # @param attorney [Hash] Raw attorney data from the GCLAWS API
    # @return [Hash] Transformed data for AccreditedIndividual record
    def data_transform_for_attorney(attorney)
      data_transform_for_entity(attorney, ENTITY_CONFIG.send(ATTORNEYS).individual_type, {
                                  phone: attorney['workNumber'],
                                  email: attorney['emailAddress'],
                                  raw_address: raw_address_for_attorney(attorney)
                                })
    end

    # Base transformation method for both agents and attorneys
    #
    # @param entity [Hash] Raw entity data from the GCLAWS API
    # @param entity_type [String] The type of entity ('claims_agent' or 'attorney')
    # @param extra_attrs [Hash] Additional attributes specific to this entity type
    # @return [Hash] Transformed data for AccreditedIndividual record
    def data_transform_for_entity(entity, entity_type, extra_attrs = {})
      {
        individual_type: entity_type,
        registration_number: entity['number'].to_s,
        poa_code: entity['poa'],
        ogc_id: entity['id'],
        first_name: entity['firstName'],
        middle_initial: entity['middleName'].to_s.strip.first,
        last_name: entity['lastName']
      }.merge(extra_attrs)
    end

    # Builds the base raw_address hash (string keys) with values normalized to align with the XLSX
    # pipeline (XlsxFileProcessor) so API-sourced and XLSX-sourced addresses compare equal and don't
    # trigger spurious revalidation: whitespace stripped, blank/"null" -> nil, zip padded/formatted
    # (ZZZZZ or ZZZZZ-NNNN). extra_fields adds the type-specific keys the API provides for that entity
    # (e.g. work_country for agents; city/state_code for attorneys and representatives).
    #
    # @param entity [Hash] Raw entity data from the GCLAWS API
    # @param extra_fields [Hash] raw_address key (Symbol) => API field name (String)
    # @return [Hash] Standardized address data
    def raw_address_from_entity(entity, extra_fields = {})
      base = {
        'address_line1' => normalize_address_value(entity['workAddress1']),
        'address_line2' => normalize_address_value(entity['workAddress2']),
        'address_line3' => normalize_address_value(entity['workAddress3']),
        'zip_code' => normalize_zip(entity['workZip'])
      }
      extra = extra_fields.each_with_object({}) do |(key, api_field), hash|
        hash[key.to_s] = normalize_address_value(entity[api_field])
      end
      base.merge(extra)
    end

    # Creates a standardized address hash for an agent
    #
    # @param agent [Hash] Raw agent data from the GCLAWS API
    # @return [Hash] Standardized address data
    def raw_address_for_agent(agent)
      raw_address_from_entity(agent, work_country: 'workCountry')
    end

    # Creates a standardized address hash for an attorney
    #
    # @param attorney [Hash] Raw attorney data from the GCLAWS API
    # @return [Hash] Standardized address data
    def raw_address_for_attorney(attorney)
      raw_address_from_entity(attorney, city: 'workCity', state_code: 'workState')
    end

    # Normalizes a raw address string the same way XlsxFileProcessor does: strips surrounding
    # whitespace and treats blank or the literal "null" as nil.
    def normalize_address_value(value)
      stripped = value.to_s.strip
      return nil if stripped.empty? || stripped.casecmp('null').zero?

      stripped
    end

    # Formats a raw zip the same way XlsxFileProcessor does: pads the 5-digit part to 5 and any
    # +4 part to 4, rejoining with a hyphen. Returns nil when blank/"null".
    def normalize_zip(value)
      stripped = value.to_s.strip
      return nil if stripped.empty? || stripped.casecmp('null').zero?

      zip5, zip4 = stripped.split('-', 2)
      zip5 = zip5.to_s.strip
      zip5 = zip5.rjust(5, '0') if zip5.length < 5
      zip4 = zip4.to_s.strip
      return zip5 if zip4.empty?

      zip4 = zip4.rjust(4, '0') if zip4.length < 4
      "#{zip5}-#{zip4}"
    end

    # Queues address validation jobs for a batch of record IDs
    #
    # @param record_ids_for_validation [Array<Integer>] Record IDs to validate
    # @param description [String] Description for the Sidekiq batch
    # @return [void]
    def validate_addresses(record_ids_for_validation,
                           description = 'Batching address updates from GCLAWS Accreditation API')
      return if record_ids_for_validation.empty?

      delay = 0
      batch = Sidekiq::Batch.new
      batch.description = description

      begin
        batch.jobs do
          record_ids_for_validation.uniq.each_slice(SLICE_SIZE) do |ids|
            RepresentationManagement::AccreditedIndividualsUpdate.perform_in(delay.minutes, ids)
            delay += 1
          end
        end
      rescue => e
        log_error("Error queuing address updates: #{e.message}")
      end
    end

    # Queues address validation jobs for agents
    #
    # @return [void]
    def validate_agent_addresses
      validate_entity_addresses(AGENTS)
    end

    # Queues address validation jobs for attorneys
    #
    # @return [void]
    def validate_attorney_addresses
      validate_entity_addresses(ATTORNEYS)
    end

    # Queues address validation jobs for representatives
    #
    # @return [void]
    def validate_rep_addresses
      validate_entity_addresses(REPRESENTATIVES)
    end

    # Queues address validation jobs for a specific entity type
    #
    # @param entity_type [String] The entity type to validate ('agents', 'attorneys', or 'representatives')
    # @return [void]
    def validate_entity_addresses(entity_type)
      config = ENTITY_CONFIG[entity_type]
      validation_ids_var = config[:validation_ids_var]
      description = config[:validation_description]

      validate_addresses(
        instance_variable_get(validation_ids_var),
        description
      )
    end

    # @return [RepresentationManagement::GCLAWS::Client] The client for GCLAWS API calls
    def client
      RepresentationManagement::GCLAWS::Client
    end

    # Outputs progress messages to stdout when running in an interactive terminal (e.g., Rails console).
    # Silently no-ops when running as a background Sidekiq job or in the test environment.
    #
    # @param message [String] The progress message to display
    # @return [void]
    def log_progress(message)
      return if Rails.env.test?

      puts message if $stdout.tty? # rubocop:disable Rails/Output
    end

    # Logs an error message to the Rails logger.
    # Deduplicates identical messages: only logs to Slack and Rails on the first occurrence,
    # and tracks counts for summary reporting.
    #
    # @param message [String] The error message to log
    # @return [void]
    def log_error(message)
      @logged_errors ||= Hash.new(0)
      @logged_errors[message] += 1
      return if @logged_errors[message] > 1

      log_to_slack_channel("RepresentationManagement::AccreditedEntitiesQueueUpdates error: #{message}")
      Rails.logger.error("RepresentationManagement::AccreditedEntitiesQueueUpdates error: #{message}")
    end

    def log_to_slack_channel(message)
      return unless Settings.vsp_environment == 'production'

      slack_client = SlackNotify::Client.new(webhook_url: Settings.edu.slack.webhook_url,
                                             channel: '#benefits-representation-management-notifications',
                                             username: 'RepresentationManagement::AccreditationApiEntityCountBot')
      slack_client.notify(message)
    end

    def calculate_duration(start_time, end_time)
      total_seconds = (end_time - start_time).to_i
      hours = total_seconds / 3600
      minutes = (total_seconds % 3600) / 60
      seconds = total_seconds % 60

      if hours.positive?
        "#{hours}h #{minutes}m #{seconds}s"
      elsif minutes.positive?
        "#{minutes}m #{seconds}s"
      else
        "#{seconds}s"
      end
    end

    # Helper method to get array of org and rep types
    #
    # @return [Array<String>]
    def orgs_and_reps
      [REPRESENTATIVES, VSOS]
    end

    # Check if both orgs and reps have valid counts
    #
    # @return [Boolean]
    def orgs_and_reps_both_valid?
      @entity_counts.valid_count?(REPRESENTATIVES) && @entity_counts.valid_count?(VSOS)
    end

    # Helper method to delete records that are not in the specified ID list
    #
    # @param model_class [Class] The model class to operate on
    # @param id_list [Array<Integer>] The list of valid IDs
    # @param error_context [String] Context for error logging
    # @return [void]
    def delete_removed_records(model_class, id_list, error_context)
      model_class.where.not(id: id_list).find_each do |record|
        record.destroy
      rescue => e
        log_error("Error deleting old #{error_context} with ID #{record.id}: #{e.message}")
      end
    end

    # Removes AccreditedOrganization records that are no longer present in the GCLAWS API
    # When force_update_types is specified, only deletes when VSOs were processed
    #
    # @return [void]
    def delete_removed_accredited_organizations
      # Only delete VSO records if VSOs were processed or no force update specified
      if @force_update_types.empty? || @force_update_types.include?(VSOS)
        delete_removed_records(AccreditedOrganization, @vso_ids, 'accredited organization')
      end
    end

    # Creates or updates Accreditation records based on representative-VSO associations.
    #
    # Resolves each association to an [accredited_individual_id, accredited_organization_id] pair and
    # hands off to AccreditationSync, which seeds acceptance_mode from the organization's
    # default_new_rep_acceptance_mode on first insert, preserves acceptance_mode on existing rows, and
    # soft-deletes joins that are no longer present.
    #
    # @return [void]
    def create_or_update_accreditations
      id_pairs, pair_org_ids = resolve_accreditation_pairs
      # Scope the sync (and its deactivation) to every VSO processed this run, not just those that still
      # have reps — otherwise a VSO that lost all of its reps would keep its now-stale accreditations
      # active. Union in the pair-derived org ids so a reps-only run (empty @vso_ids) still syncs.
      org_ids = (Array(@vso_ids) + pair_org_ids).uniq

      RepresentationManagement::AccreditationSync.sync!(
        individual_org_id_pairs: id_pairs,
        organization_ids: org_ids
      )

      @accreditation_ids = Accreditation.active.where(accredited_organization_id: org_ids).pluck(:id)
    rescue => e
      log_error("Error creating/updating accreditations: #{e.message}")
    end

    # Resolves each representative-VSO association to an
    # [accredited_individual_id, accredited_organization_id] pair, plus the unique organization ids seen.
    #
    # @return [Array(Array, Array)] the [individual_id, organization_id] pairs and the unique organization ids
    def resolve_accreditation_pairs
      id_pairs = []
      org_ids = []

      @rep_to_vso_associations.each do |rep_id, vso_ogc_ids|
        vso_ogc_ids.each do |vso_ogc_id|
          vso = AccreditedOrganization.find_by(ogc_id: vso_ogc_id)

          if vso.nil?
            log_error("VSO not found for ogc_id: #{vso_ogc_id} when creating accreditation")
            next
          end

          id_pairs << [rep_id, vso.id]
          org_ids << vso.id
        end
      end

      [id_pairs, org_ids.uniq]
    end

    # Completes the ingestion log with overall metrics
    def complete_ingestion_log
      return unless @ingestion_log

      @ingestion_log.complete_ingestion!(
        agents: @agent_ids.uniq.compact.size,
        attorneys: @attorney_ids.uniq.compact.size,
        representatives: @representative_ids.uniq.compact.size,
        veteran_service_organizations: @vso_ids.uniq.compact.size,
        accreditations: @accreditation_ids.uniq.compact.size
      )
    end

    # Marks the ingestion log as failed
    #
    # @param error_message [String] The error message to log
    def fail_ingestion_log(error_message)
      return unless @ingestion_log

      @ingestion_log.fail_ingestion!(error: error_message)
    end
  end
  # rubocop:enable Metrics/ClassLength
end
