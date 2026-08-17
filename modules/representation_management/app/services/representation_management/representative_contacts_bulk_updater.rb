# frozen_string_literal: true

module RepresentationManagement
  # Service that fetches a representative contact CSV from the GHE sensitive repo,
  # transforms rows into the GCLAWS RepresentativeContactPostDto shape, and POSTs
  # the batch to the RepresentativeContacts API endpoint.
  class RepresentativeContactsBulkUpdater
    CSV_TO_DTO_MAPPING = {
      'Number' => :number,
      'LastName' => :lastName,
      'FirstName' => :firstName,
      'MiddleName' => :middleName,
      'WorkAddress1' => :workAddress1,
      'WorkAddress2' => :workAddress2,
      'WorkAddress3' => :workAddress3,
      'WorkCity' => :workCity,
      'WorkState' => :workState,
      'WorkZip' => :workZip,
      'FaxNumber' => :faxNumber,
      'WorkNumber' => :workNumber,
      'WorkEmailAddress' => :workEmailAddress,
      'VeteranServiceOrganization' => :veteranServiceOrganization
    }.freeze

    OPTIONAL_CSV_COLUMNS = {
      'Primary / Cross' => :primaryCross,
      'Primary Accrediting Agency' => :primaryAccreditation
    }.freeze

    # Identity key that locates the upstream record. A row missing it cannot target
    # a record, so it is rejected before any POST rather than sent to the API.
    REQUIRED_DTO_KEYS = %i[number].freeze

    def initialize(csv_path: SensitiveRepoCsvFileFetcher::DEFAULT_PATH)
      @csv_path = csv_path
    end

    # Runs the full pipeline: fetch, transform, POST, report.
    # Returns a hash with :success, :submitted, :updated, :rejected keys.
    def run
      validate_settings!
      rows = fetch_csv
      contacts = transform_rows(rows)
      post_and_report(contacts)
    end

    private

    def validate_settings!
      return if Settings.gclaws.accreditation.representative_contacts&.url.present?

      raise 'Settings.gclaws.accreditation.representative_contacts.url is not configured'
    end

    def fetch_csv
      rows = SensitiveRepoCsvFileFetcher.new(path: @csv_path).fetch
      raise 'Failed to fetch CSV file from GHE repo' if rows.nil?
      raise 'CSV file is empty (headers only, no data rows)' if rows.empty?

      rows
    end

    def transform_rows(rows)
      rows.map { |row| transform_row(row) }
    end

    # Maps a CSV row to the GCLAWS DTO. Only present values are included: a blank or
    # absent CSV cell is omitted from the payload rather than sent as an empty string,
    # so it never overwrites (clobbers) existing contact data in the OGC system of
    # record. This assumes the endpoint treats omitted fields as "leave unchanged"
    # (merge semantics). A row missing a REQUIRED_DTO_KEYS value cannot target a
    # record and raises before any POST, so a malformed CSV aborts the batch instead
    # of pushing untargetable updates upstream.
    def transform_row(row)
      contact = {}
      CSV_TO_DTO_MAPPING.merge(OPTIONAL_CSV_COLUMNS).each do |csv_col, dto_key|
        value = row[csv_col].to_s.strip
        contact[dto_key] = value if value.present?
      end
      validate_required_fields!(contact)
      contact
    end

    def validate_required_fields!(contact)
      missing = REQUIRED_DTO_KEYS.select { |key| contact[key].blank? }
      return if missing.empty?

      raise "CSV row missing required field(s): #{missing.join(', ')}"
    end

    def post_and_report(contacts)
      response = GCLAWS::Client.post_representative_contacts(contacts:)

      unless response.status == 200
        return {
          success: false,
          error: response.body.is_a?(Hash) ? response.body['errors'] : response.body,
          status: response.status
        }
      end

      {
        success: true,
        submitted: contacts.length,
        updated: response.body['updated'].to_i,
        rejected: response.body['rejected'] || []
      }
    end
  end
end
