# frozen_string_literal: true

require 'mhv/oh_facilities_helper/service'

module SM
  class Client < Common::Client::Base
    ##
    # Module containing triage team-related methods for the SM Client
    #
    module TriageTeams
      ##
      # Get a collection of triage team recipients
      #
      # @return [Common::Collection[TriageTeam]]
      #
      def get_triage_teams(user_uuid, use_cache)
        cache_key = "#{user_uuid}-triage-teams"
        get_cached_or_fetch_data(use_cache, cache_key, TriageTeam) do
          json = perform(:get, 'triageteam', nil, token_headers).body
          Vets::Collection.new(json[:data], TriageTeam, metadata: json[:metadata], errors: json[:errors])
        end
      end

      ##
      # Get EHR transition crosswalk entries mapping VistA to Oracle Health triage groups
      #
      # @return [Array<Hash>] array of crosswalk entries
      #
      def get_crosswalk
        json = perform(:get, 'triageteam/crosswalk', nil, token_headers).body
        json[:data] || []
      end

      ##
      # Get a collection of all triage team recipients, including blocked
      # with detailed attributes per each team
      # including a total tally of associated and locked teams
      #
      # @note Only triage_team_id and station_number are cached via TriageTeamCache model
      # @return [Common::Collection[AllTriageTeams]]
      #
      def get_all_triage_teams(user_uuid, filter_virtual_groups: true, &block)
        path = append_requires_oh_messages_query('alltriageteams', 'requiresOHTriageGroup')
        response = perform(:get, path, nil, token_headers)
        block&.call(response)
        json = response.body

        # Instantiate teams and filter out those migrating to OH
        teams = json[:data].map { |data| AllTriageTeams.new(data) }
        filtered_teams = exclude_migrating_teams(teams)
        filtered_teams = exclude_non_pretransitioned_virtual_groups(filtered_teams) if filter_virtual_groups

        # Compute metadata with excluded teams count
        associated_blocked_triage_groups = filtered_teams.count(&:blocked_status)
        associated_triage_groups = filtered_teams.length
        metadata = json[:metadata].merge(
          associated_triage_groups:,
          associated_blocked_triage_groups:
        )

        # Create collection once with all data ready
        collection = Vets::Collection.new(filtered_teams, AllTriageTeams, metadata:, errors: json[:errors])
        MyHealth::FacilitiesHelper.set_health_care_system_names(collection)
        cache_triage_team_station_numbers(user_uuid, collection.data)
        log_health_care_system_names(collection.data)

        collection
      end

      ##
      # Update preferredTeam value for a patient's list of triage teams
      #
      # @param updated_triage_teams_list [Array] an array of objects
      # with triage_team_id and preferred_team values
      # @return [Fixnum] the response status code
      #
      def update_triage_team_preferences(updated_triage_teams_list)
        custom_headers = token_headers.merge('Content-Type' => 'application/json')
        response = perform(:post, 'preferences/patientpreferredtriagegroups', updated_triage_teams_list, custom_headers)
        response&.status
      end

      ##
      # Get cached triage team station numbers, fetching from API if not cached
      #
      # @return [Array<TriageTeamCache>, nil] cached triage teams with triage_team_id and station_number
      #
      def get_triage_teams_station_numbers
        cache_key = "#{session.user_uuid}-all-triage-teams-station-numbers"
        cached = TriageTeamCache.get_cached(cache_key)
        return cached if cached.present?

        get_all_triage_teams(session.user_uuid)
        TriageTeamCache.get_cached(cache_key)
      end

      private

      # Filters out VTGs whose station is not in the pretransitioned OH facilities list
      def exclude_non_pretransitioned_virtual_groups(teams)
        pretransitioned = MHV::OhFacilitiesHelper::Service.parse_facility_setting(
          Settings.mhv.oh_facility_checks.pretransitioned_oh_facilities
        )
        teams.reject do |team|
          team.virtual_group && pretransitioned.exclude?(team.station_number.to_s)
        end
      end

      # Filters out teams in p3-p5 migration phases (returns only non-migrating teams)
      def exclude_migrating_teams(teams)
        oh_service = MHV::OhFacilitiesHelper::Service.new(current_user)
        station_numbers = teams.map(&:station_number).compact.uniq
        phases_map = oh_service.get_phases_for_station_numbers(station_numbers)

        # Exclude teams whose station is in p3-p5 migration phases
        teams.reject do |team|
          phase = phases_map[team.station_number.to_s]
          %w[p3 p4 p5].include?(phase)
        end
      end

      # Caches minimal triage team data (triage_team_id and station_number)
      def cache_triage_team_station_numbers(user_uuid, teams)
        minimal_data = teams.map do |team|
          { triage_team_id: team.triage_team_id, station_number: team.station_number }
        end
        cache_key = "#{user_uuid}-all-triage-teams-station-numbers"
        TriageTeamCache.set_cached(cache_key, minimal_data)
      end

      # Logs count of triage teams with missing healthCareSystemName values
      def log_health_care_system_names(triage_teams)
        system_names = triage_teams.map(&:health_care_system_name).uniq
        log_message_to_rails(
          'AllTriageTeams healthCareSystemName validation',
          'info',
          { health_care_system_names: system_names }
        )

        missing_system_teams = triage_teams.select { |team| team.health_care_system_name.blank? }
        if missing_system_teams.present?
          missing_names = missing_system_teams.map(&:name)
          log_message_to_rails(
            'AllTriageTeams missing healthCareSystemName',
            'warn',
            { triage_team_names: missing_names }
          )
        end
      end
    end
  end
end
