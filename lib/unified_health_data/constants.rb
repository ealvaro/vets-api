# frozen_string_literal: true

module UnifiedHealthData
  # Constants used across the UHD integration layer.
  module Constants
    # Data-source identifiers that appear in the SCDF API response envelope
    # (e.g. body['vista'], body['oracle-health']) and are tagged onto each
    # record's 'source' attribute for downstream consumers.
    module Source
      VISTA = 'vista'
      ORACLE_HEALTH = 'oracle-health'
    end

    STATSD_KEY_PREFIX = 'api.uhd'

    # Client application identifiers sent via the x-mhv-client-application
    # header so the UHD backend can distinguish traffic sources for analytics.
    CLIENT_APPLICATION_VAGOV = 'VAGOV'
    CLIENT_APPLICATION_VAHB = 'VAHB'

    # Lab and diagnostic report constants used by the LabOrTestAdapter.
    # HL7 v2-0074 diagnostic service section codes and LOINC codes to user-friendly display names
    TEST_CODE_DISPLAY_MAP = {
      'CH' => 'Chemistry and hematology',
      'MI' => 'Microbiology',
      'MB' => 'Microbiology',
      'SP' => 'Surgical Pathology',
      'CY' => 'Cytology',
      'EM' => 'Electron Microscopy',
      'LP29684-5' => 'Radiology'
    }.freeze

    # Interpretation code map based on
    # https://terminology.hl7.org/3.1.0/CodeSystem-v3-ObservationInterpretation.html
    INTERPRETATION_MAP = {
      'CAR' => 'Carrier',
      'CARRIER' => 'Carrier',
      '<' => 'Off scale low',
      '>' => 'Off scale high',
      'A' => 'Abnormal',
      'AA' => 'Critical abnormal',
      'AC' => 'Anti-complementary substances present',
      'B' => 'Better',
      'D' => 'Significant change down',
      'DET' => 'Detected',
      'E' => 'Equivocal',
      'EX' => 'Outside threshold',
      'EXP' => 'Expected',
      'H' => 'High',
      'H*' => 'Critical high',
      'HH' => 'Critical high',
      'HU' => 'Significantly high',
      'H>' => 'Significantly high',
      'HM' => 'Hold for Medical Review',
      'HX' => 'Above high threshold',
      'I' => 'Intermediate',
      'IE' => 'Insufficient evidence',
      'IND' => 'Indeterminate',
      'L' => 'Low',
      'L*' => 'Critical low',
      'LL' => 'Critical low',
      'LU' => 'Significantly low',
      'L<' => 'Significantly low',
      'LX' => 'Below low threshold',
      'MS' => 'Moderately susceptible',
      'N' => 'Normal',
      'NCL' => 'No CLSI defined breakpoint',
      'ND' => 'Not detected',
      'NEG' => 'Negative',
      'NR' => 'Non-reactive',
      'NS' => 'Non-susceptible',
      'OBX' => 'Interpretation qualifiers in separate OBX segments',
      'POS' => 'Positive',
      'QCF' => 'Quality control failure',
      'R' => 'Resistant',
      'RR' => 'Reactive',
      'S' => 'Susceptible',
      'SDD' => 'Susceptible-dose dependent',
      'SYN-R' => 'Synergy - resistant',
      'SYN-S' => 'Synergy - susceptible',
      'TOX' => 'Cytotoxic substance present',
      'U' => 'Significant change up',
      'UNE' => 'Unexpected',
      'VS' => 'Very susceptible',
      'W' => 'Worse',
      'WR' => 'Weakly reactive'
    }.freeze

    # Notes LOINC codes
    LOINC_CODES = {
      '11506-3' => 'physician_procedure_note',
      '11488-4' => 'consult_result',
      '18842-5' => 'discharge_summary'
    }.freeze

    AVS_LOINC_CODE_MAPPING = {
      '96345-4' => 'ambulatory_patient_summary',
      '68834-1' => 'primary_care_note',
      '18842-5' => 'discharge_summary',
      '96339-7' => 'inpatient_patient_summary',
      '78583-2' => 'pharmacology_discharge_instructions'
    }.freeze

    FHIR_RESOURCE_TYPES = {
      BINARY: 'Binary',
      BUNDLE: 'Bundle',
      DIAGNOSTIC_REPORT: 'DiagnosticReport',
      DOCUMENT_REFERENCE: 'DocumentReference',
      LOCATION: 'Location',
      OBSERVATION: 'Observation',
      ORGANIZATION: 'Organization',
      PRACTITIONER: 'Practitioner'
    }.freeze
  end

  # Backward-compatible alias so existing references to SourceConstants still work.
  # But don't use until the other files/adapters/services are all updated
  # SourceConstants = Constants::Source
end
