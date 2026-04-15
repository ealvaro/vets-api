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
end
