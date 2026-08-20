# frozen_string_literal: true

# Large union schema (Lighthouse + VBS shapes on one class); split would obscure Swagger::Blocks DSL.
# rubocop:disable Metrics/ClassLength
class Swagger::V1::Requests::MedicalCopays
  include Swagger::Blocks

  swagger_path '/v1/medical_copays' do
    operation :get do
      key :description, 'List of user medical copay statements (HCCC-backed)'
      key :operationId, 'getMedicalCopays'
      key :tags, %w[medical_copays]

      parameter :authorization

      parameter do
        key :name, :status
        key :in, :query
        key :description, 'Filter invoices by FHIR Invoice status. Multiple values can be comma-separated. ' \
                          'Allowed values: draft, issued, balanced, cancelled, entered-in-error'
        key :required, false
        key :type, :string
      end

      response 200 do
        key :description, 'Successful copays lookup'

        schema do
          property :isCerner, type: :boolean, example: false
          property :status, type: :integer, example: 200
          # Lighthouse response (conditionally returned based on Cerner location(s))
          property :data, type: :array do
            items do
              property :id, type: :string, example: '675-K3FD983'
              property :type, type: :string, example: 'medical_copays'

              property :attributes, type: :object do
                property :url,
                         type: :string,
                         example: 'https://api.va.gov/v1/medical_copays/675-K3FD983'

                property :facility,
                         type: :string,
                         example: 'TEST VAMC'

                property :city,
                         type: :string,
                         example: 'Tampa'

                property :invoiceDate,
                         type: :string,
                         example: '2024-11-30T17:10:47Z'

                property :facilityId,
                         type: :string,
                         example: '1234'

                property :externalId,
                         type: :string,
                         example: '675-K3FD983'

                property :latestBillingRef,
                         type: :string,
                         example: '4-6c9ZE23XQjkA9CC'

                property :currentBalance,
                         type: :number,
                         format: :float,
                         example: 284.59

                property :previousBalance,
                         type: :number,
                         format: :float,
                         example: 76.19

                property :previousUnpaidBalance,
                         type: :number,
                         format: :float,
                         example: 0.0

                property :lastUpdatedAt,
                         type: :string,
                         format: :'date-time',
                         example: '2012-11-01T04:00:00.000+00:00'

                property :chargeItems,
                         type: :object,
                         description: 'Included when include_line_items is used. Maps ChargeItem id to FHIR ' \
                                      'ChargeItem resource JSON.'

                property :lineItems, type: :array,
                                     description: 'Included when include_line_items is used.' do
                  items do
                    property :billingReference, type: :string
                    property :billNumber, type: :string, example: 'BN-001'
                    property :datePosted, type: :string
                    property :description, type: :string
                    property :providerName, type: :string

                    property :priceComponents, type: :array do
                      items do
                        property :type, type: :string
                        property :code, type: :string
                        property :amount, type: :number, format: :float
                      end
                    end

                    property :medication, type: :object do
                      property :medicationName, type: :string
                      property :rxNumber, type: :string
                      property :quantity, type: :number, format: :float
                      property :daysSupply, type: :integer
                    end
                  end
                end
              end

              # VBS response (conditionally returned based on Cerner location(s))
              property :accountNumber, type: :string
              property :pSSeqNum, type: :integer, example: 0
              property :pSTotSeqNum, type: :integer, example: 0
              property :pSFacilityNum, type: :string
              property :pSFacPhoneNum, type: :string
              property :pSTotStatement, type: :integer, example: 0
              property :pSStatementVal, type: :string
              property :pSStatementDate, type: :string
              property :pSStatementDateOutput, type: :string
              property :pSProcessDate, type: :string
              property :pSProcessDateOutput, type: :string
              property :pHPatientLstNme, type: :string
              property :pHPatientFstNme, type: :string
              property :pHPatientMidNme, type: :string
              property :pHAddress1, type: :string
              property :pHAddress2, type: :string
              property :pHAddress3, type: :string
              property :pHCity, type: :string
              property :pHState, type: :string
              property :pHZipCde, type: :string
              property :pHZipCdeOutput, type: :string
              property :pHCtryNme, type: :string
              property :pHAmtDue, type: :integer, example: 0
              property :pHAmtDueOutput, type: :string
              property :pHPrevBal, type: :integer, example: 0
              property :pHPrevBalOutput, type: :string
              property :pHTotCharges, type: :integer, example: 0
              property :pHTotChargesOutput, type: :string
              property :pHTotCredits, type: :integer, example: 0
              property :pHTotCreditsOutput, type: :string
              property :pHNewBalance, type: :integer, example: 0
              property :pHNewBalanceOutput, type: :string
              property :pHSpecialNotes, type: :string
              property :pHroParaCdes, type: :string
              property :pHNumOfLines, type: :integer, example: 0
              property :pHDfnNumber, type: :integer, example: 0
              property :pHCernerStatementNumber, type: :integer, example: 0
              property :pHCernerPatientId, type: :string
              property :pHCernerAccountNumber, type: :string
              property :pHIcnNumber, type: :string
              property :pHAccountNumber, type: :integer, example: 0
              property :pHLargeFontIndcator, type: :integer, example: 0
              property :details, type: :array do
                items do
                  property :pDDatePosted, type: :string
                  property :pDDatePostedOutput, type: :string
                  property :pDTransDesc, type: :string
                  property :pDTransDescOutput, type: :string
                  property :pDTransAmt, type: :integer, example: 0
                  property :pDTransAmtOutput, type: :string
                  property :pDRefNo, type: :string
                end
              end
              property :station, type: :object do
                property :facilitYNum, type: :string
                property :visNNum, type: :string
                property :facilitYDesc, type: :string
                property :cyclENum, type: :string
                property :remiTToFlag, type: :string
                property :maiLInsertFlag, type: :string
                property :staTAddress1, type: :string
                property :staTAddress2, type: :string
                property :staTAddress3, type: :string
                property :city, type: :string
                property :state, type: :string
                property :ziPCde, type: :string
                property :ziPCdeOutput, type: :string
                property :baRCde, type: :string
                property :teLNumFlag, type: :string
                property :teLNum, type: :string
                property :teLNum2, type: :string
                property :contacTInfo, type: :string
                property :dM2TelNum, type: :string
                property :contacTInfo2, type: :string
                property :toPTelNum, type: :string
                property :lbXFedexAddress1, type: :string
                property :lbXFedexAddress2, type: :string
                property :lbXFedexAddress3, type: :string
                property :lbXFedexCity, type: :string
                property :lbXFedexState, type: :string
                property :lbXFedexZipCde, type: :string
                property :lbXFedexBarCde, type: :string
                property :lbXFedexContact, type: :string
                property :lbXFedexContactTelNum, type: :string
              end
            end
          end

          # Only in Lighthouse response (conditionally returned based on Cerner location(s))
          property :meta, type: :object do
            property :total, type: :integer, example: 50
            property :page, type: :integer, example: 1
            property :per_page, type: :integer, example: 10

            property :copay_summary, type: :object,
                                     description: 'Rollups computed from the resolved Invoice list' do
              property :total_current_balance,
                       type: :number,
                       format: :float,
                       example: 450.25,
                       description: 'Sum of current balances across listed invoices'

              property :copay_bill_count,
                       type: :integer,
                       example: 4,
                       description: 'Number of invoices included in the response window'

              property :last_updated_on,
                       type: :string,
                       format: :'date-time',
                       description: 'Latest `meta.lastUpdated` among invoices; null when not available',
                       example: '2025-08-01T12:00:00Z'
            end
          end

          property :links, type: :object,
                           description: 'JSON:API pagination links (from FHIR Bundle.link), when present' do
            property :self, type: :string
            property :first, type: :string
            property :prev, type: :string
            property :next, type: :string
            property :last, type: :string
          end
        end
      end
    end
  end

  swagger_path '/v1/medical_copays/facilities' do
    operation :get do
      key :description, 'List medical copay facility accounts. Response is source-blind; isCerner indicates source.'
      key :operationId, 'getMedicalCopayFacilities'
      key :tags, %w[medical_copays]

      parameter :authorization

      response 200 do
        key :description, 'Successful facility accounts lookup'

        schema do
          property :totalCurrentBalance,
                   type: :number,
                   format: :float,
                   example: 105.24,
                   description: 'Sum of current balances across all facilities'

          property :facilities, type: :array do
            items do
              property :stationId,
                       type: :string,
                       example: '757',
                       description: 'Canonical VA facility station number'

              property :facilityName,
                       type: :string,
                       example: 'Chalmers P. Wylie Veterans Outpatient Clinic'

              property :isCerner,
                       type: :boolean,
                       example: false,
                       description: 'true when the data came from VBS (Cerner), false for Lighthouse'

              property :currentBalance,
                       type: :number,
                       format: :float,
                       example: 105.24

              property :pastDueBalance,
                       type: :number,
                       format: :float,
                       example: 0.00

              property :dueDate,
                       type: :string,
                       format: :date,
                       example: '2026-01-05'

              property :statementDate,
                       type: :string,
                       format: :date,
                       example: '2025-12-11'

              property :accountNumber,
                       type: %i[string null],
                       description: 'Always null on this index; populated only by the per-facility detail lookup'

              property :transactions,
                       type: %i[array null],
                       description: 'Always null on this index; populated only by the per-facility detail lookup' do
                items type: :object
              end
            end
          end
        end
      end

      response 403 do
        key :description, 'Forbidden; requires enable_facility_account_history feature flag or missing ICN'
        schema do
          key :$ref, :Errors
        end
      end

      response 502 do
        key :description, 'An upstream copay service (VBS or Lighthouse) failed'
        schema do
          key :$ref, :Errors
        end
      end
    end
  end

  swagger_path '/v1/medical_copays/facility/{facility_id}' do
    operation :get do
      key :description,
          'A single medical copay facility account, with its account number and transaction history. ' \
          'Response is source-blind; isCerner indicates source.'
      key :operationId, 'getMedicalCopayFacility'
      key :tags, %w[medical_copays]

      parameter :authorization

      parameter do
        key :name, :facility_id
        key :in, :path
        key :description,
            'VA facility station number (e.g. 757), as returned by GET /v1/medical_copays/facilities'
        key :required, true
        key :type, :string
      end

      response 200 do
        key :description, 'Successful facility account lookup'

        schema do
          property :stationId,
                   type: :string,
                   example: '757',
                   description: 'Canonical VA facility station number'

          property :facilityName,
                   type: :string,
                   example: 'Chalmers P. Wylie Veterans Outpatient Clinic'

          property :isCerner,
                   type: :boolean,
                   example: false,
                   description: 'true when the data came from VBS (Cerner), false for Lighthouse'

          property :accountNumber,
                   type: %i[string null],
                   example: '123456'

          property :currentBalance,
                   type: :number,
                   format: :float,
                   example: 105.24

          property :pastDueBalance,
                   type: :number,
                   format: :float,
                   example: 0.00

          property :dueDate,
                   type: :string,
                   format: :date,
                   example: '2026-01-05'

          property :statementDate,
                   type: :string,
                   format: :date,
                   example: '2025-12-11'

          property :transactions,
                   type: %i[array null],
                   description: 'Charges and payments across the account, most recent first' do
            items do
              property :id, type: %i[string null], example: 'B1'

              property :type,
                       type: :string,
                       enum: %w[charge payment credit],
                       example: 'charge'

              property :date, type: %i[string null], format: :date, example: '2025-12-01'

              property :amount, type: %i[number null], format: :float, example: 105.24

              property :description,
                       type: %i[string null],
                       example: 'RX COPAY',
                       description: 'Charges only; absent on payments'

              property :billingReference,
                       type: %i[string null],
                       example: 'H1234',
                       description: 'Charges only; absent on payments'

              property :provider,
                       type: %i[string null],
                       example: 'Dr X',
                       description: 'Charges only; absent on payments'

              property :medication,
                       type: %i[object null],
                       description: 'Prescription charges only; null when the charge has no MedicationDispense' do
                property :medicationName, type: %i[string null], example: 'ATORVASTATIN'
                property :rxNumber, type: %i[string null], example: '2719324'
                property :quantity, type: %i[number null], example: 30
                property :daysSupply, type: %i[number null], example: 30
              end
            end
          end
        end
      end

      response 403 do
        key :description, 'Forbidden; requires enable_facility_account_history feature flag or missing ICN'
        schema do
          key :$ref, :Errors
        end
      end

      response 404 do
        key :description, 'The user has no copay account at that facility'
        schema do
          key :$ref, :Errors
        end
      end

      response 502 do
        key :description, 'An upstream copay service (VBS or Lighthouse) failed'
        schema do
          key :$ref, :Errors
        end
      end
    end
  end

  swagger_path '/v1/medical_copays/summary' do
    operation :get do
      key :description,
          'Aggregate medical copay totals over a recent month window ' \
          '(same HCCC Invoice search as GET /v1/medical_copays). ' \
          'Returns JSON:API-shaped JSON with **empty `data`** and rollups in **`meta`** ' \
          '(`total_amount_due`, `total_copays`, `month_window`). ' \
          'Does not include `isCerner` (Lighthouse-only path).'
      key :operationId, 'getMedicalCopaysSummary'
      key :tags, %w[medical_copays]

      parameter :authorization

      parameter do
        key :name, :months
        key :in, :query
        key :description,
            'Number of whole months to look back from the current date for including invoices (default: 6)'
        key :required, false
        key :type, :integer
      end

      response 200 do
        key :description, 'Successful summary'

        schema do
          property :data, type: :array, description: 'Always empty in current implementation.' do
            items do
              property :id, type: :string, example: '675-K3FD983'
              property :type, type: :string, example: 'medical_copays'

              property :attributes, type: :object do
                property :externalId, type: :string
                property :facility, type: :string
                property :city, type: :string
                property :invoiceDate, type: :string
                property :facilityId, type: :string
                property :latestBillingRef, type: :string
                property :currentBalance, type: :number, format: :float
                property :previousBalance, type: :number, format: :float
                property :previousUnpaidBalance, type: :number, format: :float
                property :lastUpdatedAt, type: :string, format: :'date-time'
                property :url, type: :string
              end
            end
          end

          property :meta, type: :object do
            property :total_amount_due,
                     type: :number,
                     format: :float,
                     example: 125.5,
                     description: 'Sum of current balances for invoices in the month window'

            property :total_copays,
                     type: :integer,
                     example: 3,
                     description: 'Count of invoices in the window'

            property :month_window,
                     type: :integer,
                     example: 6,
                     description: 'Lookback in months (from `months` query or default 6)'
          end
        end
      end
    end
  end

  swagger_path '/v1/medical_copays/{id}' do
    operation :get do
      key :description, 'Fetch detailed medical copay invoice by ID. Response includes an isCerner boolean. ' \
                        'When isCerner is true, the response body matches the V0 VBS copay detail schema ' \
                        '(see /v0/medical_copays/{id}). When isCerner is false, the response follows the ' \
                        'JSON:API structure documented below.'
      key :operationId, 'getMedicalCopayById'
      key :tags, %w[medical_copays]

      parameter :authorization

      parameter do
        key :name, :id
        key :in, :path
        key :description, 'External ID of the copay invoice (e.g., 675-K3FD983)'
        key :required, true
        key :type, :string
      end

      response 200 do
        key :description, 'Successful copay detail lookup. Non-Cerner users receive the JSON:API ' \
                          'structure below. Cerner users receive the VBS response shape (see V0 schema) ' \
                          'with an additional isCerner: true field.'

        schema do
          property :isCerner,
                   type: :boolean,
                   description: 'Whether the user is associated with a Cerner facility. ' \
                                'Determines the response shape.',
                   example: false

          # JSON:API top-level data (single resource)
          property :data, type: :object do
            property :id, type: :string, example: '675-K3FD983'
            property :type, type: :string, example: 'medicalCopayDetails'

            property :attributes, type: :object do
              property :externalId,
                       type: :string,
                       example: '675-K3FD983'

              property :facility, type: :object do
                property :name, type: :string, example: 'TEST VAMC'

                property :address, type: :object do
                  property :address_line1, type: :string, example: '151 KNOLLCROFT ROAD'
                  property :address_line2, type: :string
                  property :address_line3, type: :string
                  property :city, type: :string, example: 'LYONS'
                  property :state, type: :string, example: 'NJ'
                  property :postalCode, type: :string, example: '07939-5001'
                end
              end

              property :patient, type: :object do
                property :first_name, type: :string, example: 'Travis'
                property :middle_name, type: :string
                property :last_name, type: :string, example: 'Jones'

                property :address, type: :object do
                  property :address_line1, type: :string, example: '909 Rohan Highlands'
                  property :address_line2, type: :string
                  property :address_line3, type: :string
                  property :city, type: :string, example: 'Mesa'
                  property :state, type: :string, example: 'AZ'
                  property :postalCode, type: :string, example: '85120'
                end
              end

              property :billNumber,
                       type: :string,
                       example: 'BILL-123456'

              property :status,
                       type: :string,
                       example: 'issued'

              property :statusDescription,
                       type: :string,
                       example: 'Balance due'

              property :invoiceDate,
                       type: :string,
                       example: '2024-11-15T10:30:00Z'

              property :paymentDueDate,
                       type: :string,
                       example: '2024-02-14'

              property :accountNumber,
                       type: :string,
                       example: 'ACCT-789012'

              property :originalAmount,
                       type: :number,
                       format: :float,
                       example: 500.0

              property :principalBalance,
                       type: :number,
                       format: :float,
                       example: 284.59

              property :interestBalance,
                       type: :number,
                       format: :float,
                       example: 0.0

              property :administrativeCostBalance,
                       type: :number,
                       format: :float,
                       example: 0.0

              property :principalPaid,
                       type: :number,
                       format: :float,
                       example: 215.41

              property :interestPaid,
                       type: :number,
                       format: :float,
                       example: 0.0

              property :administrativeCostPaid,
                       type: :number,
                       format: :float,
                       example: 0.0

              property :associatedStatements, type: :array do
                items type: :object do
                  property :id, type: :string
                  property :date, type: :string
                  property :composite_id, type: :string
                  property :bill_number, type: :string, example: '573-K3FDDA0'
                  property :original_amount,
                           type: :number,
                           format: :float,
                           description: 'Original amount from the detail invoice totalPriceComponent ' \
                                        '(same value as top-level originalAmount).',
                           example: 86.21
                  property :charge_items, type: :array do
                    items type: :object do
                      property :id, type: :string
                      property :lastUpdatedAt, type: :string
                      property :status, type: :string
                      property :code, type: :string
                      property :occurrenceDateTime, type: :string
                      property :enteredDate, type: :string
                    end
                  end

                  property :lineItems, type: :array do
                    items do
                      property :billingReference, type: :string
                      property :datePosted, type: :string
                      property :description, type: :string
                      property :providerName, type: :string

                      property :priceComponents, type: :array do
                        items do
                          property :type, type: :string
                          property :code, type: :string
                          property :amount, type: :number, format: :float
                        end
                      end

                      property :medication, type: :object do
                        property :medicationName, type: :string
                        property :rxNumber, type: :string
                        property :quantity, type: :number, format: :float
                        property :daysSupply, type: :integer
                      end
                    end
                  end
                end
              end

              property :associatedInvoices, type: :array do
                items type: :object do
                  property :id, type: :string
                  property :date, type: :string
                  property :composite_id, type: :string

                  property :charge_items, type: :array do
                    items type: :object do
                      property :id, type: :string
                      property :lastUpdatedAt, type: :string
                      property :status, type: :string
                      property :code, type: :string
                      property :occurrenceDateTime, type: :string
                      property :enteredDate, type: :string
                    end
                  end

                  property :lineItems, type: :array do
                    items do
                      property :billingReference, type: :string
                      property :datePosted, type: :string
                      property :description, type: :string
                      property :providerName, type: :string

                      property :priceComponents, type: :array do
                        items do
                          property :type, type: :string
                          property :code, type: :string
                          property :amount, type: :number, format: :float
                        end
                      end

                      property :medication, type: :object do
                        property :medicationName, type: :string
                        property :rxNumber, type: :string
                        property :quantity, type: :number, format: :float
                        property :daysSupply, type: :integer
                      end
                    end
                  end
                end
              end

              property :lineItems, type: :array do
                items do
                  property :billingReference, type: :string
                  property :datePosted, type: :string
                  property :description, type: :string
                  property :providerName, type: :string

                  property :priceComponents, type: :array do
                    items do
                      property :type, type: :string
                      property :code, type: :string
                      property :amount, type: :number, format: :float
                    end
                  end

                  property :medication, type: :object do
                    property :medicationName, type: :string
                    property :rxNumber, type: :string
                    property :quantity, type: :number, format: :float
                    property :daysSupply, type: :integer
                  end
                end
              end

              property :payments, type: :array do
                items do
                  property :paymentId, type: :string, example: 'PMT-001'
                  property :paymentDate, type: :string, example: '2024-01-20'
                  property :paymentAmount, type: :number, format: :float, example: 100.0
                  property :transactionNumber, type: :string, example: 'TXN-789'
                  property :billNumber, type: :string, example: 'BILL-123456'
                  property :invoiceReference, type: :string, example: '675-K3FD983'
                  property :disposition, type: :string, example: 'Complete'

                  property :detail, type: :array do
                    items do
                      property :type, type: :string, example: 'Principal'
                      property :amount, type: :number, format: :float, example: 100.0
                    end
                  end
                end
              end
            end

            # Resource-level meta (`CopayDetailSerializer` — snake_case keys)
            property :meta, type: :object do
              property :line_item_count, type: :integer, example: 3
              property :payment_count, type: :integer, example: 1
            end
          end
        end
      end
    end
  end
end
# rubocop:enable Metrics/ClassLength
