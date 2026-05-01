# frozen_string_literal: true

require './modules/decision_reviews/spec/dr_spec_helper'

RSpec.describe DecisionReviews::V1::SupplementalClaims::RequestBodyNormalizer do
  describe '#normalize' do
    context 'when redesign is enabled with full evidence data' do
      subject(:normalized_data) { described_class.new(request_body).normalize }

      let(:request_body) do
        {
          'scRedesign' => true,
          'data' => {
            'type' => 'supplementalClaim',
            'attributes' => {
              'benefitType' => 'compensation',
              'claimantType' => 'veteran',
              'homeless' => false,
              'veteran' => {
                'timezone' => 'America/Chicago',
                'address' => {
                  'addressLine1' => '123 Mailing Address St.',
                  'city' => 'Fulton',
                  'stateCode' => 'NY',
                  'countryCodeISO2' => 'US',
                  'zipCode5' => '97063'
                },
                'phone' => {
                  'countryCode' => '1',
                  'areaCode' => '989',
                  'phoneNumber' => '8981233'
                },
                'email' => 'test@example.com'
              },
              'treatmentLocations' => [
                'VA MEDICAL CENTERS (VAMC) AND COMMUNITY-BASED OUTPATIENT CLINICS (CBOC)',
                'PRIVATE HEALTH CARE PROVIDER'
              ],
              'vaEvidence' => [
                {
                  'treatmentBefore2005' => 'N',
                  'vaTreatmentLocation' => 'Midwest Alabama VA Facility'
                },
                {
                  'treatmentBefore2005' => 'Y',
                  'treatmentMonthYear' => '2000-05',
                  'vaTreatmentLocation' => 'Southwest Georgia VA Facility'
                }
              ]
            }
          },
          'form4142' => {
            'authorization' => true,
            'lcPrompt' => true,
            'lcDetails' => 'Only records from Dr. Smith',
            'evidenceEntries' => [
              {
                'treatmentStart' => '2012-10-11',
                'treatmentEnd' => '2012-10-12',
                'issues' => {
                  'Hypertension' => true,
                  'Migraines' => false
                },
                'privateTreatmentLocation' => 'South Texas Clinic',
                'address' => {
                  'country' => 'USA',
                  'street' => '123 Main Street',
                  'city' => 'San Antonio',
                  'state' => 'TX',
                  'postalCode' => '78258'
                }
              }
            ]
          },
          'additionalDocuments' => [{
            'name' => 'document.pdf',
            'confirmationCode' => '123-456-789'
          }]
        }
      end

      it 'transforms vaEvidence into evidenceSubmission.retrieveFrom' do
        evidence_submission = normalized_data.dig('data', 'attributes', 'evidenceSubmission')

        expect(evidence_submission['retrieveFrom']).to be_an(Array)
        expect(evidence_submission['retrieveFrom'].length).to eq(2)
        expect(evidence_submission['retrieveFrom'].first['attributes']['locationAndName'])
          .to eq('Midwest Alabama VA Facility')
      end

      it 'sets evidenceType correctly' do
        evidence_submission = normalized_data.dig('data', 'attributes', 'evidenceSubmission')

        expect(evidence_submission['evidenceType']).to include('retrieval')
        expect(evidence_submission['evidenceType']).to include('upload')
      end

      it 'moves treatmentLocations into evidenceSubmission' do
        evidence_submission = normalized_data.dig('data', 'attributes', 'evidenceSubmission')

        expect(evidence_submission['treatmentLocations']).to be_an(Array)
        expect(normalized_data.dig('data', 'attributes', 'treatmentLocations')).to be_nil
      end

      it 'removes vaEvidence from original location' do
        expect(normalized_data.dig('data', 'attributes', 'vaEvidence')).to be_nil
      end

      it 'transforms form4142 private evidence entries' do
        form4142 = normalized_data['form4142']

        expect(form4142['privacyAgreementAccepted']).to be(true)
        expect(form4142['limitedConsent']).to eq('Only records from Dr. Smith')
        expect(form4142['providerFacility']).to be_an(Array)
        expect(form4142['providerFacility'].first['providerFacilityName']).to eq('South Texas Clinic')
        expect(form4142['providerFacility'].first['issues']).to eq(['Hypertension'])
      end

      it 'formats treatment dates correctly for pre-2005 evidence' do
        evidence_submission = normalized_data.dig('data', 'attributes', 'evidenceSubmission')
        pre_2005_entry = evidence_submission['retrieveFrom'].find do |e|
          e.dig('attributes', 'locationAndName') == 'Southwest Georgia VA Facility'
        end

        expect(pre_2005_entry['attributes']['evidenceDates']).to eq([{
                                                                      'startDate' => '2000-05-01',
                                                                      'endDate' => '2000-05-01'
                                                                    }])
        expect(pre_2005_entry['attributes']['noTreatmentDates']).to be(false)
      end

      it 'sets noTreatmentDates for non-pre-2005 evidence' do
        evidence_submission = normalized_data.dig('data', 'attributes', 'evidenceSubmission')
        post_2005_entry = evidence_submission['retrieveFrom'].find do |e|
          e.dig('attributes', 'locationAndName') == 'Midwest Alabama VA Facility'
        end

        expect(post_2005_entry['attributes']['noTreatmentDates']).to be(true)
        expect(post_2005_entry['attributes']['evidenceDates']).to be_nil
      end
    end

    context 'when redesign is disabled' do
      subject(:normalized_data) { described_class.new(request_body).normalize }

      let(:request_body) do
        {
          'data' => {
            'attributes' => {
              'veteran' => {
                'phone' => {
                  'countryCode' => '1',
                  'areaCode' => '555',
                  'phoneNumber' => '1234567'
                }
              },
              'evidenceSubmission' => {
                'evidenceType' => ['none']
              }
            }
          }
        }
      end

      it 'does not transform evidence data' do
        expect(normalized_data.dig('data', 'attributes', 'evidenceSubmission')).to eq({ 'evidenceType' => ['none'] })
      end

      it 'still normalizes area code' do
        expect(normalized_data.dig('data', 'attributes', 'veteran', 'phone', 'areaCode')).to eq('555')
      end
    end

    context 'when area code is empty' do
      subject(:normalized_data) { described_class.new(request_body).normalize }

      let(:request_body) do
        {
          'data' => {
            'attributes' => {
              'veteran' => {
                'phone' => {
                  'countryCode' => '1',
                  'areaCode' => '',
                  'phoneNumber' => '1234567'
                }
              },
              'evidenceSubmission' => {
                'evidenceType' => ['none']
              }
            }
          }
        }
      end

      it 'removes the empty areaCode' do
        expect(normalized_data.dig('data', 'attributes', 'veteran', 'phone')).not_to have_key('areaCode')
      end
    end

    context 'when there are duplicate VA facility locations' do
      subject(:normalized_data) { described_class.new(request_body).normalize }

      let(:request_body) do
        {
          'data' => {
            'attributes' => {
              'veteran' => {
                'phone' => {
                  'areaCode' => '555',
                  'phoneNumber' => '1234567'
                }
              },
              'evidenceSubmission' => {
                'evidenceType' => ['retrieval'],
                'retrieveFrom' => [
                  {
                    'type' => 'retrievalEvidence',
                    'attributes' => {
                      'locationAndName' => 'Same VA Facility',
                      'evidenceDates' => [{ 'startDate' => '2000-01-01', 'endDate' => '2000-01-01' }]
                    }
                  },
                  {
                    'type' => 'retrievalEvidence',
                    'attributes' => {
                      'locationAndName' => 'Same VA Facility',
                      'evidenceDates' => [{ 'startDate' => '2001-02-01', 'endDate' => '2001-02-01' }]
                    }
                  }
                ]
              }
            }
          }
        }
      end

      it 'merges duplicate facility entries' do
        retrieve_from = normalized_data.dig('data', 'attributes', 'evidenceSubmission', 'retrieveFrom')

        expect(retrieve_from.length).to eq(1)
        expect(retrieve_from.first.dig('attributes', 'locationAndName')).to eq('Same VA Facility')
      end

      it 'combines evidence dates from merged entries' do
        retrieve_from = normalized_data.dig('data', 'attributes', 'evidenceSubmission', 'retrieveFrom')
        evidence_dates = retrieve_from.first.dig('attributes', 'evidenceDates')

        expect(evidence_dates.length).to eq(2)
        expect(evidence_dates.map { |d| d['startDate'] }).to include('2000-01-01', '2001-02-01')
      end
    end

    context 'when merged entries produce more than 4 evidence dates' do
      subject(:normalized_data) { described_class.new(request_body).normalize }

      let(:request_body) do
        {
          'data' => {
            'attributes' => {
              'veteran' => { 'phone' => { 'areaCode' => '555', 'phoneNumber' => '1234567' } },
              'evidenceSubmission' => {
                'evidenceType' => ['retrieval'],
                'retrieveFrom' => (1..5).map do |i|
                  {
                    'type' => 'retrievalEvidence',
                    'attributes' => {
                      'locationAndName' => 'Same VA Facility',
                      'evidenceDates' => [{ 'startDate' => "200#{i}-01-01", 'endDate' => "200#{i}-01-01" }]
                    }
                  }
                end
              }
            }
          }
        }
      end

      it 'limits evidence dates to 4' do
        retrieve_from = normalized_data.dig('data', 'attributes', 'evidenceSubmission', 'retrieveFrom')

        expect(retrieve_from.length).to eq(1)
        expect(retrieve_from.first.dig('attributes', 'evidenceDates').length).to eq(4)
      end
    end

    context 'when duplicate entries have nil evidenceDates' do
      subject(:normalized_data) { described_class.new(request_body).normalize }

      let(:request_body) do
        {
          'data' => {
            'attributes' => {
              'veteran' => { 'phone' => { 'areaCode' => '555', 'phoneNumber' => '1234567' } },
              'evidenceSubmission' => {
                'evidenceType' => ['retrieval'],
                'retrieveFrom' => [
                  {
                    'type' => 'retrievalEvidence',
                    'attributes' => { 'locationAndName' => 'Same VA Facility', 'evidenceDates' => nil }
                  },
                  {
                    'type' => 'retrievalEvidence',
                    'attributes' => {
                      'locationAndName' => 'Same VA Facility',
                      'evidenceDates' => [{ 'startDate' => '2004-01-01', 'endDate' => '2004-01-01' }]
                    }
                  }
                ]
              }
            }
          }
        }
      end

      it 'handles nil evidenceDates gracefully' do
        retrieve_from = normalized_data.dig('data', 'attributes', 'evidenceSubmission', 'retrieveFrom')

        expect(retrieve_from.length).to eq(1)
        expect(retrieve_from.first.dig('attributes', 'evidenceDates')).to eq(
          [{ 'startDate' => '2004-01-01', 'endDate' => '2004-01-01' }]
        )
      end
    end

    context 'when duplicate entries have noTreatmentDates and no evidenceDates key' do
      subject(:normalized_data) { described_class.new(request_body).normalize }

      let(:request_body) do
        {
          'data' => {
            'attributes' => {
              'veteran' => { 'phone' => { 'areaCode' => '555', 'phoneNumber' => '1234567' } },
              'evidenceSubmission' => {
                'evidenceType' => ['retrieval'],
                'retrieveFrom' => [
                  {
                    'type' => 'retrievalEvidence',
                    'attributes' => { 'locationAndName' => 'Same VA Facility', 'noTreatmentDates' => true }
                  },
                  {
                    'type' => 'retrievalEvidence',
                    'attributes' => { 'locationAndName' => 'Same VA Facility', 'noTreatmentDates' => true }
                  }
                ]
              }
            }
          }
        }
      end

      it 'merges entries without adding evidenceDates' do
        retrieve_from = normalized_data.dig('data', 'attributes', 'evidenceSubmission', 'retrieveFrom')

        expect(retrieve_from.length).to eq(1)
        expect(retrieve_from.first['attributes']).not_to have_key('evidenceDates')
        expect(retrieve_from.first.dig('attributes', 'noTreatmentDates')).to be(true)
      end
    end

    context 'when form4142 is blank' do
      subject(:normalized_data) { described_class.new(request_body).normalize }

      let(:request_body) do
        {
          'scRedesign' => true,
          'data' => {
            'attributes' => {
              'veteran' => {
                'phone' => { 'areaCode' => '555', 'phoneNumber' => '1234567' }
              }
            }
          },
          'form4142' => nil
        }
      end

      it 'leaves form4142 as nil' do
        expect(normalized_data['form4142']).to be_nil
      end
    end

    context 'when no evidence is provided' do
      subject(:normalized_data) { described_class.new(request_body).normalize }

      let(:request_body) do
        {
          'scRedesign' => true,
          'data' => {
            'attributes' => {
              'veteran' => {
                'phone' => { 'areaCode' => '555', 'phoneNumber' => '1234567' }
              }
            }
          },
          'additionalDocuments' => nil
        }
      end

      it 'sets evidenceType to none' do
        evidence_submission = normalized_data.dig('data', 'attributes', 'evidenceSubmission')
        expect(evidence_submission['evidenceType']).to eq(['none'])
      end
    end
  end

  describe '#make_issues_list' do
    let(:normalizer) { described_class.new({}) }

    it 'returns keys where value is true' do
      issues = { 'Hypertension' => true, 'Migraines' => false, 'Back Pain' => true }
      result = normalizer.send(:make_issues_list, issues)

      expect(result).to contain_exactly('Hypertension', 'Back Pain')
    end

    it 'returns empty array when issues_hash is nil' do
      expect(normalizer.send(:make_issues_list, nil)).to eq([])
    end

    it 'returns empty array when issues_hash is empty' do
      expect(normalizer.send(:make_issues_list, {})).to eq([])
    end
  end

  describe '#validate_and_format_va_treatment_date' do
    let(:normalizer) { described_class.new({}) }

    it 'formats valid YYYY-MM date to YYYY-MM-01' do
      expect(normalizer.send(:validate_and_format_va_treatment_date, '2000-05')).to eq('2000-05-01')
    end

    it 'returns nil for invalid date format' do
      expect(normalizer.send(:validate_and_format_va_treatment_date, '2000-5')).to be_nil
      expect(normalizer.send(:validate_and_format_va_treatment_date, '2000/05')).to be_nil
      expect(normalizer.send(:validate_and_format_va_treatment_date, '05-2000')).to be_nil
    end
  end

  describe '#format_va_evidence_entries' do
    let(:normalizer) { described_class.new({}) }

    it 'returns nil when va_evidence is nil' do
      expect(normalizer.send(:format_va_evidence_entries, nil)).to be_nil
    end

    it 'returns nil when va_evidence is empty array' do
      expect(normalizer.send(:format_va_evidence_entries, [])).to be_nil
    end

    it 'builds evidence entry for each item' do
      va_evidence = [
        { 'treatmentBefore2005' => 'N', 'vaTreatmentLocation' => 'Facility 1' },
        { 'treatmentBefore2005' => 'Y', 'treatmentMonthYear' => '2000-05', 'vaTreatmentLocation' => 'Facility 2' }
      ]

      result = normalizer.send(:format_va_evidence_entries, va_evidence)

      expect(result).to be_an(Array)
      expect(result.length).to eq(2)
      expect(result.first['type']).to eq('retrievalEvidence')
    end
  end

  describe '#build_va_evidence_entry' do
    let(:normalizer) { described_class.new({}) }

    it 'sets noTreatmentDates to true when not treated before 2005' do
      entry = { 'treatmentBefore2005' => 'N', 'vaTreatmentLocation' => 'Test Facility' }
      result = normalizer.send(:build_va_evidence_entry, entry)

      expect(result['attributes']['noTreatmentDates']).to be(true)
      expect(result['attributes']).not_to have_key('evidenceDates')
    end

    it 'sets noTreatmentDates to true when treatment date is invalid' do
      entry = { 'treatmentBefore2005' => 'Y', 'treatmentMonthYear' => 'invalid',
                'vaTreatmentLocation' => 'Test Facility' }
      result = normalizer.send(:build_va_evidence_entry, entry)

      expect(result['attributes']['noTreatmentDates']).to be(true)
      expect(result['attributes']).not_to have_key('evidenceDates')
    end

    it 'includes evidenceDates when treated before 2005 with valid date' do
      entry = { 'treatmentBefore2005' => 'Y', 'treatmentMonthYear' => '2003-08',
                'vaTreatmentLocation' => 'Test Facility' }
      result = normalizer.send(:build_va_evidence_entry, entry)

      expect(result['attributes']['noTreatmentDates']).to be(false)
      expect(result['attributes']['evidenceDates']).to eq([{ 'startDate' => '2003-08-01', 'endDate' => '2003-08-01' }])
    end
  end

  describe '#format_va_evidence_dates' do
    let(:normalizer) { described_class.new({}) }

    it 'returns nil when treatmentMonthYear is nil' do
      entry = { 'treatmentMonthYear' => nil }
      expect(normalizer.send(:format_va_evidence_dates, entry)).to be_nil
    end

    it 'returns nil when treatmentMonthYear is invalid format' do
      entry = { 'treatmentMonthYear' => '2000/05' }
      expect(normalizer.send(:format_va_evidence_dates, entry)).to be_nil
    end

    it 'returns formatted date range when valid' do
      entry = { 'treatmentMonthYear' => '2004-12' }
      result = normalizer.send(:format_va_evidence_dates, entry)

      expect(result).to eq([{ 'startDate' => '2004-12-01', 'endDate' => '2004-12-01' }])
    end
  end

  describe '#format_private_evidence_entries' do
    let(:normalizer) { described_class.new({}) }

    it 'returns nil when private_evidence is nil' do
      expect(normalizer.send(:format_private_evidence_entries, nil)).to be_nil
    end

    it 'returns nil when private_evidence is blank' do
      expect(normalizer.send(:format_private_evidence_entries, {})).to be_nil
    end

    it 'sets privacyAgreementAccepted when authorization is true' do
      private_evidence = { 'authorization' => true, 'evidenceEntries' => [] }
      result = normalizer.send(:format_private_evidence_entries, private_evidence)

      expect(result['privacyAgreementAccepted']).to be(true)
    end

    it 'does not set privacyAgreementAccepted when authorization is false' do
      private_evidence = { 'authorization' => false, 'evidenceEntries' => [] }
      result = normalizer.send(:format_private_evidence_entries, private_evidence)

      expect(result).not_to have_key('privacyAgreementAccepted')
    end

    it 'sets limitedConsent when lcPrompt is true and lcDetails present' do
      private_evidence = { 'lcPrompt' => true, 'lcDetails' => 'Test consent', 'evidenceEntries' => [] }
      result = normalizer.send(:format_private_evidence_entries, private_evidence)

      expect(result['limitedConsent']).to eq('Test consent')
    end

    it 'does not set limitedConsent when lcPrompt is false' do
      private_evidence = { 'lcPrompt' => false, 'lcDetails' => 'Test consent', 'evidenceEntries' => [] }
      result = normalizer.send(:format_private_evidence_entries, private_evidence)

      expect(result).not_to have_key('limitedConsent')
    end

    it 'does not set limitedConsent when lcDetails is blank' do
      private_evidence = { 'lcPrompt' => true, 'lcDetails' => '', 'evidenceEntries' => [] }
      result = normalizer.send(:format_private_evidence_entries, private_evidence)

      expect(result).not_to have_key('limitedConsent')
    end

    it 'builds providerFacility array when evidenceEntries is present' do
      private_evidence = {
        'evidenceEntries' => [
          {
            'privateTreatmentLocation' => 'Clinic',
            'address' => { 'street' => '123 Main' },
            'issues' => { 'Issue1' => true },
            'treatmentStart' => '2020-01-01',
            'treatmentEnd' => '2020-12-31'
          }
        ]
      }
      result = normalizer.send(:format_private_evidence_entries, private_evidence)

      expect(result['providerFacility']).to be_an(Array)
      expect(result['providerFacility'].length).to eq(1)
    end

    it 'returns basic structure when evidenceEntries is not an array' do
      private_evidence = { 'evidenceEntries' => 'not an array' }
      result = normalizer.send(:format_private_evidence_entries, private_evidence)

      expect(result['providerFacility']).to eq([])
    end
  end

  describe '#build_facility_data' do
    let(:normalizer) { described_class.new({}) }

    it 'uses empty strings for missing fields' do
      entry = {}
      result = normalizer.send(:build_facility_data, entry)

      expect(result['providerFacilityName']).to eq('')
      expect(result['providerFacilityAddress']['street']).to eq('')
      expect(result['treatmentDateRange'].first['from']).to eq('')
      expect(result['treatmentDateRange'].first['to']).to eq('')
    end

    it 'includes all address fields when present' do
      entry = {
        'address' => {
          'country' => 'USA',
          'street' => '123 Main St',
          'street2' => 'Apt 4',
          'city' => 'Austin',
          'state' => 'TX',
          'postalCode' => '78701'
        }
      }
      result = normalizer.send(:build_facility_data, entry)

      expect(result['providerFacilityAddress']['country']).to eq('USA')
      expect(result['providerFacilityAddress']['street']).to eq('123 Main St')
      expect(result['providerFacilityAddress']['street2']).to eq('Apt 4')
      expect(result['providerFacilityAddress']['city']).to eq('Austin')
      expect(result['providerFacilityAddress']['state']).to eq('TX')
      expect(result['providerFacilityAddress']['postalCode']).to eq('78701')
    end

    it 'converts issues hash to array of selected issues' do
      entry = {
        'issues' => { 'Diabetes' => true, 'PTSD' => false, 'Hearing Loss' => true }
      }
      result = normalizer.send(:build_facility_data, entry)

      expect(result['issues']).to contain_exactly('Diabetes', 'Hearing Loss')
    end
  end

  describe '#normalize_area_code_for_lighthouse_schema' do
    let(:normalizer) { described_class.new(request_body) }

    context 'when phone is nil' do
      let(:request_body) { { 'data' => { 'attributes' => { 'veteran' => {} } } } }

      it 'does not raise an error' do
        expect { normalizer.send(:normalize_area_code_for_lighthouse_schema) }.not_to raise_error
      end
    end

    context 'when phone exists but has no areaCode' do
      let(:request_body) do
        { 'data' => { 'attributes' => { 'veteran' => { 'phone' => { 'phoneNumber' => '5551234' } } } } }
      end

      it 'does not modify phone hash' do
        normalizer.send(:normalize_area_code_for_lighthouse_schema)
        expect(request_body.dig('data', 'attributes', 'veteran', 'phone')).to eq({ 'phoneNumber' => '5551234' })
      end
    end

    context 'when areaCode is valid non-empty string' do
      let(:request_body) do
        { 'data' => { 'attributes' => { 'veteran' => { 'phone' => { 'areaCode' => '555' } } } } }
      end

      it 'keeps the areaCode' do
        normalizer.send(:normalize_area_code_for_lighthouse_schema)
        expect(request_body.dig('data', 'attributes', 'veteran', 'phone', 'areaCode')).to eq('555')
      end
    end

    context 'when areaCode is nil' do
      let(:request_body) do
        { 'data' => { 'attributes' => { 'veteran' => { 'phone' => { 'areaCode' => nil,
                                                                    'phoneNumber' => '5551234' } } } } }
      end

      it 'removes the areaCode key' do
        normalizer.send(:normalize_area_code_for_lighthouse_schema)
        expect(request_body.dig('data', 'attributes', 'veteran', 'phone')).not_to have_key('areaCode')
      end
    end
  end

  describe '#normalize_evidence_retrieval_for_lighthouse_schema' do
    let(:normalizer) { described_class.new(request_body) }

    context 'when evidenceSubmission is nil' do
      let(:request_body) { { 'data' => { 'attributes' => {} } } }

      it 'does not raise an error' do
        expect { normalizer.send(:normalize_evidence_retrieval_for_lighthouse_schema) }.not_to raise_error
      end
    end

    context 'when evidenceType does not include retrieval' do
      let(:request_body) do
        {
          'data' => {
            'attributes' => {
              'evidenceSubmission' => {
                'evidenceType' => ['upload'],
                'retrieveFrom' => [{ 'id' => '1' }, { 'id' => '2' }]
              }
            }
          }
        }
      end

      it 'does not modify retrieveFrom' do
        original_retrieve_from = request_body.dig('data', 'attributes', 'evidenceSubmission', 'retrieveFrom').dup
        normalizer.send(:normalize_evidence_retrieval_for_lighthouse_schema)

        expect(request_body.dig('data', 'attributes', 'evidenceSubmission',
                                'retrieveFrom')).to eq(original_retrieve_from)
      end
    end

    context 'when retrieveFrom has only one item' do
      let(:request_body) do
        {
          'data' => {
            'attributes' => {
              'evidenceSubmission' => {
                'evidenceType' => ['retrieval'],
                'retrieveFrom' => [{ 'attributes' => { 'locationAndName' => 'Single Facility' } }]
              }
            }
          }
        }
      end

      it 'does not modify retrieveFrom' do
        original_retrieve_from = request_body.dig('data', 'attributes', 'evidenceSubmission', 'retrieveFrom').dup
        normalizer.send(:normalize_evidence_retrieval_for_lighthouse_schema)

        expect(request_body.dig('data', 'attributes', 'evidenceSubmission',
                                'retrieveFrom')).to eq(original_retrieve_from)
      end
    end

    context 'when retrieveFrom is nil' do
      let(:request_body) do
        {
          'data' => {
            'attributes' => {
              'evidenceSubmission' => {
                'evidenceType' => ['retrieval'],
                'retrieveFrom' => nil
              }
            }
          }
        }
      end

      it 'does not raise an error' do
        expect { normalizer.send(:normalize_evidence_retrieval_for_lighthouse_schema) }.not_to raise_error
      end
    end
  end

  describe '#sc_redesign_enabled?' do
    it 'returns true when scRedesign is true' do
      normalizer = described_class.new({ 'scRedesign' => true })
      expect(normalizer.send(:sc_redesign_enabled?)).to be(true)
    end

    it 'returns true when scRedesign is "true" string' do
      normalizer = described_class.new({ 'scRedesign' => 'true' })
      expect(normalizer.send(:sc_redesign_enabled?)).to be(true)
    end

    it 'returns false when scRedesign is false' do
      normalizer = described_class.new({ 'scRedesign' => false })
      expect(normalizer.send(:sc_redesign_enabled?)).to be(false)
    end

    it 'returns falsy when scRedesign is nil' do
      normalizer = described_class.new({})
      expect(normalizer.send(:sc_redesign_enabled?)).to be_falsy
    end
  end

  describe 'treatmentLocationOther handling' do
    subject(:normalized_data) { described_class.new(request_body).normalize }

    context 'when treatmentLocationOther is provided' do
      let(:request_body) do
        {
          'scRedesign' => true,
          'data' => {
            'attributes' => {
              'veteran' => { 'phone' => { 'areaCode' => '555' } },
              'treatmentLocations' => ['VA MEDICAL CENTER'],
              'treatmentLocationOther' => 'Community clinic details'
            }
          }
        }
      end

      it 'moves treatmentLocationOther into evidenceSubmission' do
        evidence_submission = normalized_data.dig('data', 'attributes', 'evidenceSubmission')

        expect(evidence_submission['treatmentLocationOther']).to eq('Community clinic details')
      end

      it 'removes treatmentLocationOther from original location' do
        expect(normalized_data.dig('data', 'attributes', 'treatmentLocationOther')).to be_nil
      end
    end

    context 'when treatmentLocationOther is empty string' do
      let(:request_body) do
        {
          'scRedesign' => true,
          'data' => {
            'attributes' => {
              'veteran' => { 'phone' => { 'areaCode' => '555' } },
              'treatmentLocationOther' => ''
            }
          }
        }
      end

      it 'does not include treatmentLocationOther in evidenceSubmission' do
        evidence_submission = normalized_data.dig('data', 'attributes', 'evidenceSubmission')

        expect(evidence_submission).not_to have_key('treatmentLocationOther')
      end
    end
  end
end
