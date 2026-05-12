# frozen_string_literal: true

require 'vets/model'

module UnifiedHealthData
  class ImagingStudy
    include Vets::Model

    attribute :id, String
    attribute :event_id, String # The ID of the associated event (i.e. Lab)
    attribute :identifier, String # The full FHIR identifier value
    attribute :status, String
    attribute :modality, String # Primary modality code (e.g., 'ECG', 'CT')
    attribute :date, String # Pass on as-is to the frontend (from started)
    attribute :sort_date, String # Normalized date for sorting (internal use only)
    attribute :description, String
    attribute :notes, String, array: true
    attribute :patient_id, String
    attribute :series_count, Integer
    attribute :image_count, Integer
    attribute :series, Array # Array of series info for potential image retrieval
    attribute :dicom_zip_url, String # Presigned S3 URL for DICOM zip download (study-level)
    attribute :dicom_size_bytes, Integer # Size of the DICOM zip in bytes (from ImagingStudy extension)
    attribute :dicom_status, String # Task status (e.g., 'in-progress', 'completed')
    attribute :dicom_progress_phase, String # Progress phase (e.g., 'fetching', 'completed')
    attribute :dicom_progress_completed_count, Integer # Number of completed items in DICOM zip generation
    attribute :dicom_progress_total_count, Integer # Total number of items in DICOM zip generation

    default_sort_by sort_date: :desc
  end
end
