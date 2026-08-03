# frozen_string_literal: true

module FhirResourceBuilder
  def base_fhir_resource
    { 'resourceType' => 'MedicationRequest', 'id' => '12345', 'status' => 'active',
      'authoredOn' => '2025-01-29T19:41:43Z',
      'medicationCodeableConcept' => { 'text' => 'Test Medication' },
      'dosageInstruction' => [{ 'text' => 'Take as directed' }] }
  end

  def fhir_resource(**options)
    defaults = {
      status: 'active',
      refills: 3,
      expiration: 1.year.from_now,
      source: 'VA',
      dispense_status: 'completed',
      dispense_date: '2025-01-15T10:00:00Z'
    }
    opts = defaults.merge(options)

    base_fhir_resource.merge(
      'status' => opts[:status],
      'reportedBoolean' => (opts[:source] == 'NV'),
      'intent' => (opts[:source] == 'VA' ? 'order' : 'plan'),
      'category' => fhir_categories(opts[:source]),
      'dispenseRequest' => fhir_dispense_request(opts[:refills], opts[:expiration]),
      'contained' => fhir_dispenses(opts[:dispense_status], opts[:dispense_date])
    )
  end

  def fhir_resource_with_task(**options)
    defaults = { task_status: 'requested', task_intent: 'order',
                 task_date: '2025-06-24T21:05:53.000Z', med_request_id: '12345', dispenses: [] }
    opts = defaults.merge(options)
    contained = [fhir_task(opts[:task_status], opts[:task_intent], opts[:task_date], opts[:med_request_id])] +
                opts[:dispenses].map.with_index { |d, i| fhir_dispense(d, i) }
    build_resource_with_contained(opts[:med_request_id], contained)
  end

  def fhir_resource_with_renewal_task(**options)
    defaults = { task_status: 'requested', task_date: '2025-06-24T21:05:53.000Z',
                 med_request_id: '12345', task_type: 'renewal' }
    opts = defaults.merge(options)
    contained = [fhir_renewal_task(opts[:task_status], opts[:task_date], opts[:med_request_id],
                                   task_type: opts[:task_type])]
    build_resource_with_contained(opts[:med_request_id], contained)
  end

  private

  def build_resource_with_contained(med_request_id, contained)
    resource = fhir_resource(status: 'active', refills: 3, expiration: 30.days.from_now, dispense_status: nil)
    resource['id'] = med_request_id
    resource['contained'] = contained
    resource
  end

  def fhir_categories(source)
    codes = source == 'VA' ? %w[community discharge] : %w[community patientspecified]
    codes.map { |code| { 'coding' => [{ 'code' => code }] } }
  end

  def fhir_dispense_request(refills, expiration)
    { 'numberOfRepeatsAllowed' => refills, 'validityPeriod' => { 'end' => expiration.utc.iso8601 } }
  end

  def fhir_dispenses(status, date)
    return [] unless status

    [{ 'resourceType' => 'MedicationDispense', 'id' => 'dispense-1',
       'status' => status, 'whenHandedOver' => date, 'location' => { 'display' => '648' } }]
  end

  def fhir_task(status, intent, date, med_request_id)
    {
      'resourceType' => 'Task',
      'status' => status,
      'intent' => intent,
      'focus' => { 'reference' => "MedicationRequest/#{med_request_id}" },
      'executionPeriod' => { 'start' => date }
    }
  end

  def fhir_renewal_task(status, date, med_request_id, task_type: 'renewal')
    fhir_task(status, 'proposal', date, med_request_id).merge(
      'meta' => { 'extension' => [{ 'url' => 'http://va.gov/mhv/rx/task-type', 'valueString' => task_type }] }
    )
  end

  def fhir_dispense(data, index)
    dispense = {
      'resourceType' => 'MedicationDispense',
      'id' => "dispense-#{index + 1}",
      'status' => data[:status] || 'completed',
      'whenPrepared' => data[:when_prepared],
      'whenHandedOver' => data[:when_handed_over]
    }
    dispense['location'] = { 'display' => data[:location] } if data[:location]
    dispense
  end
end
