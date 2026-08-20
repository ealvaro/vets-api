# frozen_string_literal: true

require 'rails_helper'
require 'va_profile/contact_information/v2/service'
require 'va_profile/person_settings/service'

describe VAProfile::ContactInformation::V2::Service do
  subject { described_class.new(user) }

  let(:user) { build(:user, :loa3, :legacy_icn) }

  describe '#get_person' do
    context 'when successful' do
      it 'returns a status of 200' do
        VCR.use_cassette('va_profile/v2/contact_information/person', VCR::MATCH_EVERYTHING) do
          response = subject.get_person
          expect(response).to be_ok
          expect(response.person).to be_a(VAProfile::Models::Person)
        end
      end

      # Need an international user
      # it 'supports international provinces' do
      #   VCR.use_cassette('va_profile/v2/contact_information/person_intl_addr', VCR::MATCH_EVERYTHING) do
      #     response = subject.get_person

      #     expect(response.person.addresses[0].province).to eq('province')
      #   end
      # end

      it 'has a bad address' do
        VCR.use_cassette('va_profile/v2/contact_information/person', VCR::MATCH_EVERYTHING) do
          response = subject.get_person
          expect(response.person.addresses[0].bad_address).to be(true)
        end
      end
    end

    context 'when person response has no body data' do
      it 'returns 200' do
        VCR.use_cassette('va_profile/v2/contact_information/person_without_data', VCR::MATCH_EVERYTHING) do
          response = subject.get_person
          expect(response).to be_ok
          expect(response.person).to be_a(VAProfile::Models::Person)
        end
      end
    end
  end

  describe '#get_person when vet360 is null' do
    let(:verified_user) { build(:user, :loa3, vet360_id: nil) }

    context 'when successful' do
      it 'returns a status of 200' do
        VCR.use_cassette('va_profile/v2/contact_information/person_icn', VCR::MATCH_EVERYTHING) do
          response = subject.get_person
          expect(response).to be_ok
          expect(response.person).to be_a(VAProfile::Models::Person)
        end
      end

      it 'has a bad address' do
        VCR.use_cassette('va_profile/v2/contact_information/person_icn', VCR::MATCH_EVERYTHING) do
          response = subject.get_person
          expect(response.person.addresses[0].bad_address).to be(true)
        end
      end
    end

    context 'when person response has no body data' do
      it 'returns 200' do
        VCR.use_cassette('va_profile/v2/contact_information/verified_person_without_data', VCR::MATCH_EVERYTHING) do
          response = subject.get_person
          expect(response).to be_ok
          expect(response.person).to be_a(VAProfile::Models::Person)
        end
      end
    end
  end

  describe '#post_email' do
    let(:email) { build(:email, source_system_user: user.icn) }

    context 'when successful' do
      it 'returns a status of 200' do
        VCR.use_cassette('va_profile/v2/contact_information/post_email_success', VCR::MATCH_EVERYTHING) do
          email.email_address = 'person42@example.com'
          response = subject.post_email(email)
          expect(response).to be_ok
        end
      end
    end

    context 'when an ID is included' do
      it 'raises an exception' do
        VCR.use_cassette('va_profile/v2/contact_information/post_email_w_id_error', VCR::MATCH_EVERYTHING) do
          email.id = 42
          email.email_address = 'person42@example.com'
          expect { subject.post_email(email) }.to raise_error do |e|
            expect(e).to be_a(Common::Exceptions::BackendServiceException)
            expect(e.status_code).to eq(400)
            expect(e.errors.first.code).to eq('VET360_EMAIL200')
          end
        end
      end
    end
  end

  describe '#put_email' do
    let(:email) do
      build(
        :email, id: 318_927, email_address: 'person43@example.com',
                source_system_user: user.icn
      )
    end

    context 'when successful' do
      it 'creates an old_email record when email is changing' do
        VCR.use_cassette('va_profile/v2/contact_information/put_email_success', VCR::MATCH_EVERYTHING) do
          # Stub old email to be different from submitted email to simulate email change
          allow(user).to receive(:va_profile_email).and_return('old_email@example.com')
          expect_any_instance_of(VAProfile::Models::Transaction).to receive(:received?).and_return(true)

          response = subject.put_email(email)
          expect(OldEmail.find(response.transaction.id).email).to eq('old_email@example.com')
        end
      end

      it 'does not create an old_email record when confirming existing email' do
        VCR.use_cassette('va_profile/v2/contact_information/put_email_success', VCR::MATCH_EVERYTHING) do
          # User's current email matches the email being submitted (confirmation only)
          allow(user).to receive(:va_profile_email).and_return('person43@example.com')
          expect_any_instance_of(VAProfile::Models::Transaction).to receive(:received?).and_return(true)

          response = subject.put_email(email)
          expect(OldEmail.find(response.transaction.id)).to be_nil
        end
      end

      it 'returns a status of 200' do
        VCR.use_cassette('va_profile/v2/contact_information/put_email_success', VCR::MATCH_EVERYTHING) do
          response = subject.put_email(email)
          expect(response.transaction.id).to eq('c3c712ea-0cfb-484b-b81e-22f11ee0dcaf')
          expect(response).to be_ok
        end
      end
    end
  end

  describe '#put_email when vet360_id is null' do
    let(:user) { build(:user, :loa3, vet360_id: nil, icn: '123498767V234859') }

    let(:email) do
      build(
        :email, id: 318_927, email_address: 'person43@example.com',
                source_system_user: '123498767V234859'
      )
    end

    before { allow(user).to receive(:vet360_id).and_return(nil) }

    context 'when successful' do
      it 'creates an old_email record when email is changing' do
        VCR.use_cassette('va_profile/v2/contact_information/put_email_success_icn', VCR::MATCH_EVERYTHING) do
          # Stub old email to be different from submitted email to simulate email change
          allow(user).to receive(:va_profile_email).and_return('old_email@example.com')
          expect_any_instance_of(VAProfile::Models::Transaction).to receive(:received?).and_return(true)

          response = subject.put_email(email)
          expect(OldEmail.find(response.transaction.id).email).to eq('old_email@example.com')
        end
      end

      it 'does not create an old_email record when confirming existing email' do
        VCR.use_cassette('va_profile/v2/contact_information/put_email_success_icn', VCR::MATCH_EVERYTHING) do
          # User's current email matches the email being submitted (confirmation only)
          allow(user).to receive(:va_profile_email).and_return('person43@example.com')
          expect_any_instance_of(VAProfile::Models::Transaction).to receive(:received?).and_return(true)

          response = subject.put_email(email)
          expect(OldEmail.find(response.transaction.id)).to be_nil
        end
      end

      it 'returns a status of 200' do
        VCR.use_cassette('va_profile/v2/contact_information/put_email_success_icn', VCR::MATCH_EVERYTHING) do
          response = subject.put_email(email)
          expect(response.transaction.id).to eq('c3c712ea-0cfb-484b-b81e-22f11ee0dcaf')
          expect(response).to be_ok
        end
      end
    end
  end

  describe '#post_address' do
    let(:address) { build(:va_profile_address, :mobile) }

    context 'when successful' do
      it 'returns a status of 200' do
        VCR.use_cassette('va_profile/v2/contact_information/post_address_success', VCR::MATCH_EVERYTHING) do
          response = subject.post_address(address)
          expect(response).to be_ok
        end
      end
    end

    context 'when an ID is included' do
      let(:address) { build(:va_profile_address, :mobile, id: 42, effective_start_date: nil) }
      let(:frozen_time) { Time.zone.parse('2024-08-27T18:51:06.012Z') }

      it 'raises an exception' do
        VCR.use_cassette('va_profile/v2/contact_information/post_address_w_id_error', VCR::MATCH_EVERYTHING) do
          expect { subject.post_address(address) }.to raise_error do |e|
            expect(e).to be_a(Common::Exceptions::BackendServiceException)
            expect(e.status_code).to eq(400)
            expect(e.errors.first.code).to eq('VET360_ADDR200')
          end
        end
      end
    end
  end

  describe '#put_address' do
    let(:address) { build(:va_profile_address, :override, id: 577_127) }

    context 'when successful' do
      it 'returns a status of 200' do
        VCR.use_cassette('va_profile/v2/contact_information/put_address_success', VCR::MATCH_EVERYTHING) do
          response = subject.put_address(address)
          expect(response.transaction.id).to eq('7ac85cf3-b229-4034-9897-25c0ef1411eb')
          expect(response).to be_ok
        end
      end
    end

    context 'with a validation key' do
      let(:address) do
        build(:va_profile_address, :override, country_name: nil)
      end

      it 'overrides the address error', run_at: '2020-02-14T00:19:15.000Z' do
        VCR.use_cassette('va_profile/v2/contact_information/put_address_override', VCR::MATCH_EVERYTHING) do
          address.id = 577_127
          response = subject.put_address(address)
          expect(response.status).to eq(200)
          expect(response.transaction.id).to eq('cd7036df-630c-43e2-8911-063daa10021c')
        end
      end
    end
  end

  describe 'logging' do
    let(:user) { build(:user, :loa3, vet360_id: '1', icn: '123498767V234859') }
    let(:service) { described_class.new(user) }

    it 'logs status request failure' do
      response_class = class_double(VAProfile::ContactInformation::V2::EmailTransactionResponse)
      error_class = Class.new(StandardError) do
        attr_accessor :body, :status
      end
      error = error_class.new('boom')
      error.body = { 'messages' => [{ 'code' => 'VET360_ERR', 'key' => 'error' }] }
      error.status = 500

      allow(service).to receive(:perform).and_raise(error)
      allow(service).to receive(:handle_error).and_raise(error)

      expect(Rails.logger).to receive(:warn).with(
        hash_including(
          message: 'VAProfile transaction status request failed',
          request_path: 'emails/status/123'
        )
      )

      expect do
        service.send(:get_transaction_status, 'emails/status/123', response_class)
      end.to raise_error(StandardError, 'boom')
    end

    it 'logs create/update request failure' do
      response_class = class_double(VAProfile::ContactInformation::V2::EmailTransactionResponse)
      error_class = Class.new(StandardError) do
        attr_accessor :body, :status
      end
      error = error_class.new('boom')
      error.body = { 'messages' => [{ 'code' => 'VET360_ERR', 'key' => 'error' }] }
      error.status = 500

      allow(service).to receive(:verify_user!)
      allow(service).to receive(:perform).and_raise(error)
      allow(service).to receive(:handle_error).and_raise(error)

      expect(Rails.logger).to receive(:warn).with(
        hash_including(
          message: 'VAProfile transaction create/update request failed',
          request_method: 'POST',
          request_path: 'emails',
          error_class: error.class.to_s,
          error_message: 'boom',
          error_status: 500,
          error_code: 'VET360_ERR',
          error_key: 'error'
        )
      )

      expect do
        service.send(
          :post_or_put_data,
          :post,
          build(:email, source_system_user: user.icn),
          'emails',
          response_class
        )
      end.to raise_error(StandardError, 'boom')
    end

    it 'logs create/update request failure when error body is not a hash' do
      response_class = class_double(VAProfile::ContactInformation::V2::EmailTransactionResponse)
      error_class = Class.new(StandardError) do
        attr_accessor :body, :status
      end
      error = error_class.new('boom')
      error.body = 'unexpected body format'
      error.status = 500

      allow(service).to receive(:verify_user!)
      allow(service).to receive(:perform).and_raise(error)
      allow(service).to receive(:handle_error).and_raise(error)

      expect(Rails.logger).to receive(:warn).with(
        hash_including(
          message: 'VAProfile transaction create/update request failed',
          request_method: 'POST',
          request_path: 'emails',
          error_class: error.class.to_s,
          error_message: 'boom',
          error_status: 500,
          error_code: nil,
          error_key: nil
        )
      )

      expect do
        service.send(
          :post_or_put_data,
          :post,
          build(:email, source_system_user: user.icn),
          'emails',
          response_class
        )
      end.to raise_error(StandardError, 'boom')
    end

    it 'redacts AAID from error messages' do
      response_class = class_double(VAProfile::ContactInformation::V2::EmailTransactionResponse)
      aaid = "#{user.vet360_id}%5EPI%5E200VETS%5EUSDVA"
      url_with_aaid = "#{MPI::Constants::VA_ROOT_OID}/#{aaid}/emails"
      error = StandardError.new("the server responded with status 502 for #{url_with_aaid}")

      allow(service).to receive(:verify_user!)
      allow(service).to receive(:perform).and_raise(error)
      allow(service).to receive(:handle_error).and_raise(error)

      expected_redacted = "the server responded with status 502 for #{MPI::Constants::VA_ROOT_OID}/[REDACTED_AAID]/emails"

      expect(Rails.logger).to receive(:warn).with(
        hash_including(
          error_message: expected_redacted
        )
      )

      expect do
        service.send(
          :post_or_put_data,
          :post,
          build(:email, source_system_user: user.icn),
          'emails',
          response_class
        )
      end.to raise_error(StandardError)
    end
  end

  describe '#put_telephone' do
    let(:telephone) { build(:telephone, source_system_user: user.icn) }

    context 'when successful' do
      it 'returns a status of 200' do
        VCR.use_cassette('va_profile/v2/contact_information/put_telephone_success', VCR::MATCH_EVERYTHING) do
          telephone.id = 458_781
          telephone.phone_number = '5551235'
          response = subject.put_telephone(telephone)
          expect(response.transaction.id).to eq('c915d801-5693-4860-b2df-83baa8c3c910')
          expect(response).to be_ok
        end
      end
    end
  end

  describe '#post_telephone' do
    let(:telephone) do
      build(:telephone, id: nil, source_system_user: user.icn)
    end

    context 'when successful' do
      it 'returns a status of 200' do
        VCR.use_cassette('va_profile/v2/contact_information/post_telephone_success', VCR::MATCH_EVERYTHING) do
          response = subject.post_telephone(telephone)
          expect(response).to be_ok
        end
      end
    end

    context 'when an ID is included' do
      it 'raises an exception' do
        VCR.use_cassette('va_profile/v2/contact_information/post_telephone_w_id_error', VCR::MATCH_EVERYTHING) do
          telephone.id = 42
          expect { subject.post_telephone(telephone) }.to raise_error do |e|
            expect(e).to be_a(Common::Exceptions::BackendServiceException)
            expect(e.status_code).to eq(400)
            expect(e.errors.first.code).to eq('VET360_PHON124')
          end
        end
      end
    end
  end

  describe '#get_telephone_transaction_status' do
    context 'when successful' do
      let(:transaction_id) { 'c6ee12e2-d219-4d12-81e0-3eecdd5eb871' }

      it 'returns a status of 200' do
        VCR.use_cassette('va_profile/v2/contact_information/telephone_transaction_status', VCR::MATCH_EVERYTHING) do
          expect_any_instance_of(described_class).to receive(:send_contact_change_notification)

          response = subject.get_telephone_transaction_status(transaction_id)
          expect(response).to be_ok
          expect(response.transaction).to be_a(VAProfile::Models::Transaction)
          expect(response.transaction.id).to eq(transaction_id)
        end
      end

      context 'when the transaction completed successfully' do
        it 'invalidates the VAProfile redis cache and the MPI data cache' do
          VCR.use_cassette('va_profile/v2/contact_information/telephone_transaction_status', VCR::MATCH_EVERYTHING) do
            allow_any_instance_of(described_class).to receive(:send_contact_change_notification)
            allow_any_instance_of(VAProfile::Models::Transaction).to receive(:completed_success?).and_return(true)
            mpi_data = instance_double(MPIData, destroy: nil)
            allow(MPIData).to receive(:find).with(user.icn).and_return(mpi_data)
            expect(VAProfileRedis::V2::Cache).to receive(:invalidate).with(user)
            expect(mpi_data).to receive(:destroy)

            subject.get_telephone_transaction_status(transaction_id)
          end
        end
      end

      context 'when the transaction has not completed' do
        it 'does not invalidate either cache' do
          VCR.use_cassette('va_profile/v2/contact_information/telephone_transaction_status', VCR::MATCH_EVERYTHING) do
            allow_any_instance_of(described_class).to receive(:send_contact_change_notification)
            allow_any_instance_of(VAProfile::Models::Transaction).to receive(:completed_success?).and_return(false)
            expect(VAProfileRedis::V2::Cache).not_to receive(:invalidate)
            expect(MPIData).not_to receive(:find)

            subject.get_telephone_transaction_status(transaction_id)
          end
        end
      end
    end

    context 'when not successful' do
      let(:transaction_id) { 'd47b3d96-9ddd-42be-ac57-8e564aa38029' }

      it 'returns a status of 404' do
        VCR.use_cassette('va_profile/v2/contact_information/telephone_transaction_status_error',
                         VCR::MATCH_EVERYTHING) do
          expect { subject.get_telephone_transaction_status(transaction_id) }.to raise_error do |e|
            expect(e).to be_a(Common::Exceptions::BackendServiceException)
            expect(e.status_code).to eq(400)
            expect(e.errors.first.code).to eq('VET360_CORE103')
          end
        end
      end
    end
  end

  context 'update model methods', :skip_va_profile_user do
    before do
      VCR.insert_cassette('va_profile/v2/contact_information/person', VCR::MATCH_EVERYTHING)
      allow(VAProfile::Configuration::SETTINGS.contact_information).to receive(:cache_enabled).and_return(true)
    end

    after do
      VCR.eject_cassette
    end

    [
      {
        model_name: 'address',
        factory: 'va_profile_address',
        attr: 'residential_address',
        id: 577_127
      },
      {
        model_name: 'telephone',
        factory: 'telephone',
        attr: 'mobile_phone',
        id: 458_781
      },
      {
        model_name: 'email',
        factory: 'email',
        attr: 'email',
        id: 318_927
      }
    ].each do |spec_data|
      describe "#update_#{spec_data[:model_name]}" do
        let(:model) { build(spec_data[:factory], id: nil) }

        context "when the #{spec_data[:model_name]} doesnt exist" do
          before do
            allow_any_instance_of(VAProfileRedis::V2::ContactInformation).to receive(spec_data[:attr]).and_return(nil)
          end

          it 'makes a post request' do
            expect_any_instance_of(
              VAProfile::ContactInformation::V2::Service
            ).to receive("post_#{spec_data[:model_name]}").with(model)
            subject.public_send("update_#{spec_data[:model_name]}", model)
          end
        end

        context "when the #{spec_data[:model_name]} exists" do
          it 'makes a put request' do
            expect(model).to receive(:id=).with(spec_data[:id]).and_call_original
            expect_any_instance_of(
              VAProfile::ContactInformation::V2::Service
            ).to receive("put_#{spec_data[:model_name]}").with(model)
            subject.public_send("update_#{spec_data[:model_name]}", model)
          end
        end
      end
    end
  end

  describe '#get_email_transaction_status' do
    context 'when successful' do
      let(:transaction_id) { '5b4550b3-2bcb-4fef-8906-35d0b4b310a8' }

      it 'returns a status of 200' do
        VCR.use_cassette('va_profile/v2/contact_information/email_transaction_status', VCR::MATCH_EVERYTHING) do
          response = subject.get_email_transaction_status(transaction_id)
          expect(response).to be_ok
          expect(response.transaction).to be_a(VAProfile::Models::Transaction)
          expect(response.transaction.id).to eq(transaction_id)
        end
      end

      context 'when the transaction completed successfully' do
        it 'invalidates the VAProfile redis cache and the MPI data cache' do
          VCR.use_cassette('va_profile/v2/contact_information/email_transaction_status', VCR::MATCH_EVERYTHING) do
            allow_any_instance_of(VAProfile::Models::Transaction).to receive(:completed_success?).and_return(true)
            mpi_data = instance_double(MPIData, destroy: nil)
            allow(MPIData).to receive(:find).with(user.icn).and_return(mpi_data)
            expect(VAProfileRedis::V2::Cache).to receive(:invalidate).with(user)
            expect(mpi_data).to receive(:destroy)

            subject.get_email_transaction_status(transaction_id)
          end
        end
      end

      context 'when the transaction has not completed' do
        it 'does not invalidate either cache' do
          VCR.use_cassette('va_profile/v2/contact_information/email_transaction_status', VCR::MATCH_EVERYTHING) do
            allow_any_instance_of(VAProfile::Models::Transaction).to receive(:completed_success?).and_return(false)
            expect(VAProfileRedis::V2::Cache).not_to receive(:invalidate)
            expect(MPIData).not_to receive(:find)

            subject.get_email_transaction_status(transaction_id)
          end
        end
      end

      context 'with an old_email record' do
        before do
          OldEmail.create(email: 'email@email.com', transaction_id:)
        end

        context 'when the V2 flag is enabled' do
          before do
            allow(Flipper).to receive(:enabled?).with(:va_notify_v2_contact_info_change).and_return(true)
          end

          it 'calls send_email_change_notification' do
            VCR.use_cassette('va_profile/v2/contact_information/email_transaction_status', VCR::MATCH_EVERYTHING) do
              expect(VANotify::V2::QueueEmailJob).to receive(:enqueue).with(
                'email@email.com',
                described_class::CONTACT_INFO_CHANGE_TEMPLATE,
                { 'contact_info' => 'Email address', 'first_name' => user.first_name },
                'Settings.vanotify.services.va_gov.api_key',
                { callback_metadata: { notification_type: 'error',
                                       statsd_tags: { service: 'profile-contact-info',
                                                      function: 'contact_info_email_change_old_address',
                                                      template_id: described_class::CONTACT_INFO_CHANGE_TEMPLATE } } }
              )
              expect(VANotify::V2::QueueEmailJob).to receive(:enqueue).with(
                'person43@example.com',
                described_class::CONTACT_INFO_CHANGE_TEMPLATE,
                { 'contact_info' => 'Email address', 'first_name' => user.first_name },
                'Settings.vanotify.services.va_gov.api_key',
                { callback_metadata: { notification_type: 'error',
                                       statsd_tags: { service: 'profile-contact-info',
                                                      function: 'contact_info_email_change_new_address',
                                                      template_id: described_class::CONTACT_INFO_CHANGE_TEMPLATE } } }
              )

              subject.get_email_transaction_status(transaction_id)

              expect(OldEmail.find(transaction_id)).to be_nil
            end
          end
        end

        context 'when the V2 flag is disabled' do
          before do
            allow(Flipper).to receive(:enabled?).with(:va_notify_v2_contact_info_change).and_return(false)
          end

          it 'calls send_email_change_notification' do
            VCR.use_cassette('va_profile/v2/contact_information/email_transaction_status', VCR::MATCH_EVERYTHING) do
              expect(VANotifyEmailJob).to receive(:perform_async).with(
                'email@email.com',
                described_class::CONTACT_INFO_CHANGE_TEMPLATE,
                { 'contact_info' => 'Email address', 'first_name' => user.first_name }
              )
              expect(VANotifyEmailJob).to receive(:perform_async).with(
                'person43@example.com',
                described_class::CONTACT_INFO_CHANGE_TEMPLATE,
                { 'contact_info' => 'Email address', 'first_name' => user.first_name }
              )

              subject.get_email_transaction_status(transaction_id)

              expect(OldEmail.find(transaction_id)).to be_nil
            end
          end
        end
      end
    end

    context 'when not successful' do
      let(:transaction_id) { 'cb99a754-9fa9-4f3c-be93-ede12c14b68e' }

      it 'returns a status of 404' do
        VCR.use_cassette('va_profile/v2/contact_information/email_transaction_status_error', VCR::MATCH_EVERYTHING) do
          expect { subject.get_email_transaction_status(transaction_id) }.to raise_error do |e|
            expect(e).to be_a(Common::Exceptions::BackendServiceException)
            expect(e.status_code).to eq(400)
            expect(e.errors.first.code).to eq('VET360_CORE103')
          end
        end
      end

      it 'includes "general_client_error" tag in the logged error', :aggregate_failures do
        VCR.use_cassette('va_profile/v2/contact_information/email_transaction_status_error', VCR::MATCH_EVERYTHING) do
          expect(Rails.logger).to receive(:error).with(
            anything,
            hash_including(va_profile: 'general_client_error')
          )

          expect { subject.get_email_transaction_status(transaction_id) }.to raise_error do |e|
            expect(e).to be_a(Common::Exceptions::BackendServiceException)
            expect(e.status_code).to eq(400)
            expect(e.errors.first.code).to eq('VET360_CORE103')
          end
        end
      end
    end
  end

  describe '#send_contact_change_notification' do
    let(:transaction) { double }
    let(:transaction_status) do
      OpenStruct.new(
        transaction:
      )
    end
    let(:transaction_id) { '123' }

    context 'transaction completed success' do
      before do
        expect(transaction).to receive(:completed_success?).and_return(true)
        expect(transaction).to receive(:id).and_return(transaction_id)
      end

      context 'transaction notification already exists' do
        before do
          TransactionNotification.create(transaction_id:)
        end

        context 'when the V2 flag is enabled' do
          before do
            allow(Flipper).to receive(:enabled?).with(:va_notify_v2_contact_info_change).and_return(true)
          end

          it 'doesnt send an email' do
            expect(VANotify::V2::QueueEmailJob).not_to receive(:enqueue)
            expect(VANotifyEmailJob).not_to receive(:perform_async)
            subject.send(:send_contact_change_notification, transaction_status, :address)
          end
        end

        context 'when the V2 flag is disabled' do
          before do
            allow(Flipper).to receive(:enabled?).with(:va_notify_v2_contact_info_change).and_return(false)
          end

          it 'doesnt send an email' do
            expect(VANotify::V2::QueueEmailJob).not_to receive(:enqueue)
            expect(VANotifyEmailJob).not_to receive(:perform_async)
            subject.send(:send_contact_change_notification, transaction_status, :address)
          end
        end
      end

      context 'transaction notification doesnt exist' do
        context 'users email is blank' do
          context 'when the V2 flag is enabled' do
            before do
              allow(Flipper).to receive(:enabled?).with(:va_notify_v2_contact_info_change).and_return(true)
            end

            it 'doesnt send an email' do
              expect(user).to receive(:va_profile_email).and_return(nil)

              expect(VANotify::V2::QueueEmailJob).not_to receive(:enqueue)
              expect(VANotifyEmailJob).not_to receive(:perform_async)
              subject.send(:send_contact_change_notification, transaction_status, :email)
            end
          end

          context 'when the V2 flag is disabled' do
            before do
              allow(Flipper).to receive(:enabled?).with(:va_notify_v2_contact_info_change).and_return(false)
            end

            it 'doesnt send an email' do
              expect(user).to receive(:va_profile_email).and_return(nil)

              expect(VANotify::V2::QueueEmailJob).not_to receive(:enqueue)
              expect(VANotifyEmailJob).not_to receive(:perform_async)
              subject.send(:send_contact_change_notification, transaction_status, :email)
            end
          end
        end

        context 'users email exists' do
          context 'when the V2 flag is enabled' do
            before do
              allow(Flipper).to receive(:enabled?).with(:va_notify_v2_contact_info_change).and_return(true)
            end

            it 'sends an email' do
              VCR.use_cassette('va_profile/v2/contact_information/person', VCR::MATCH_EVERYTHING) do
                allow(VAProfile::Configuration::SETTINGS.contact_information).to receive(:cache_enabled)
                  .and_return(true)

                expect(VANotify::V2::QueueEmailJob).to receive(:enqueue).with(
                  user.va_profile_email,
                  described_class::CONTACT_INFO_CHANGE_TEMPLATE,
                  { 'contact_info' => 'Email address', 'first_name' => user.first_name },
                  'Settings.vanotify.services.va_gov.api_key',
                  { callback_metadata: { notification_type: 'error',
                                         statsd_tags: { service: 'profile-contact-info',
                                                        function: 'contact_info_change',
                                                        template_id: described_class::CONTACT_INFO_CHANGE_TEMPLATE } } }
                )

                subject.send(:send_contact_change_notification, transaction_status, :email)

                expect(TransactionNotification.find(transaction_id).present?).to be(true)
              end
            end
          end

          context 'when the V2 flag is disabled' do
            before do
              allow(Flipper).to receive(:enabled?).with(:va_notify_v2_contact_info_change).and_return(false)
            end

            it 'sends an email' do
              VCR.use_cassette('va_profile/v2/contact_information/person', VCR::MATCH_EVERYTHING) do
                allow(VAProfile::Configuration::SETTINGS.contact_information).to receive(:cache_enabled)
                  .and_return(true)

                expect(VANotifyEmailJob).to receive(:perform_async).with(
                  user.va_profile_email,
                  described_class::CONTACT_INFO_CHANGE_TEMPLATE,
                  { 'contact_info' => 'Email address', 'first_name' => user.first_name }
                )

                subject.send(:send_contact_change_notification, transaction_status, :email)

                expect(TransactionNotification.find(transaction_id).present?).to be(true)
              end
            end
          end
        end
      end
    end

    context 'if transaction does not have completed success status' do
      context 'when the V2 flag is enabled' do
        before do
          allow(Flipper).to receive(:enabled?).with(:va_notify_v2_contact_info_change).and_return(true)
        end

        it 'doesnt send an email' do
          expect(transaction).to receive(:completed_success?).and_return(false)

          expect(VANotify::V2::QueueEmailJob).not_to receive(:enqueue)
          expect(VANotifyEmailJob).not_to receive(:perform_async)
          subject.send(:send_contact_change_notification, transaction_status, :address)
        end
      end

      context 'when the V2 flag is disabled' do
        before do
          allow(Flipper).to receive(:enabled?).with(:va_notify_v2_contact_info_change).and_return(false)
        end

        it 'doesnt send an email' do
          expect(transaction).to receive(:completed_success?).and_return(false)

          expect(VANotify::V2::QueueEmailJob).not_to receive(:enqueue)
          expect(VANotifyEmailJob).not_to receive(:perform_async)
          subject.send(:send_contact_change_notification, transaction_status, :address)
        end
      end
    end
  end

  describe '#get_address_transaction_status' do
    context 'when successful' do
      let(:transaction_id) { '0ea91332-4713-4008-bd57-40541ee8d4d4' }

      it 'returns a status of 200' do
        VCR.use_cassette('va_profile/v2/contact_information/address_transaction_status', VCR::MATCH_EVERYTHING) do
          expect_any_instance_of(described_class).to receive(:send_contact_change_notification)

          response = subject.get_address_transaction_status(transaction_id)
          expect(response).to be_ok
          expect(response.transaction).to be_a(VAProfile::Models::Transaction)
          expect(response.transaction.id).to eq(transaction_id)
        end
      end

      context 'when the transaction completed successfully' do
        it 'invalidates the VAProfile redis cache and the MPI data cache' do
          VCR.use_cassette('va_profile/v2/contact_information/address_transaction_status', VCR::MATCH_EVERYTHING) do
            allow_any_instance_of(described_class).to receive(:send_contact_change_notification)
            allow_any_instance_of(VAProfile::Models::Transaction).to receive(:completed_success?).and_return(true)
            mpi_data = instance_double(MPIData, destroy: nil)
            allow(MPIData).to receive(:find).with(user.icn).and_return(mpi_data)
            expect(VAProfileRedis::V2::Cache).to receive(:invalidate).with(user)
            expect(mpi_data).to receive(:destroy)

            subject.get_address_transaction_status(transaction_id)
          end
        end
      end

      context 'when the transaction has not completed' do
        it 'does not invalidate either cache' do
          VCR.use_cassette('va_profile/v2/contact_information/address_transaction_status', VCR::MATCH_EVERYTHING) do
            allow_any_instance_of(described_class).to receive(:send_contact_change_notification)
            allow_any_instance_of(VAProfile::Models::Transaction).to receive(:completed_success?).and_return(false)
            expect(VAProfileRedis::V2::Cache).not_to receive(:invalidate)
            expect(MPIData).not_to receive(:find)

            subject.get_address_transaction_status(transaction_id)
          end
        end
      end
    end

    context 'when not successful' do
      let(:transaction_id) { 'd47b3d96-9ddd-42be-ac57-8e564aa38029' }

      it 'returns a status of 404' do
        VCR.use_cassette('va_profile/v2/contact_information/address_transaction_status_error', VCR::MATCH_EVERYTHING) do
          expect { subject.get_address_transaction_status(transaction_id) }.to raise_error do |e|
            expect(e).to be_a(Common::Exceptions::BackendServiceException)
            expect(e.status_code).to eq(400)
            expect(e.errors.first.code).to eq('VET360_CORE103')
          end
        end
      end
    end
  end

  describe '#get_person_transaction_status' do
    context 'when successful' do
      let(:transaction_id) { '153536a5-8b18-4572-a3d9-4030bea3ab5c' }

      it 'returns a status of 200', :aggregate_failures do
        VCR.use_cassette('va_profile/v2/contact_information/person_transaction_status', VCR::MATCH_EVERYTHING) do
          response = subject.get_person_transaction_status(transaction_id)

          expect(response).to be_ok
          expect(response.transaction).to be_a(VAProfile::Models::Transaction)
          expect(response.transaction.id).to eq(transaction_id)
        end
      end
    end

    context 'when not successful' do
      let(:transaction_id) { 'd47b3d96-9ddd-42be-ac57-8e564aa38029' }

      it 'returns a status of 400', :aggregate_failures do
        VCR.use_cassette('va_profile/v2/contact_information/person_transaction_status_error', VCR::MATCH_EVERYTHING) do
          expect { subject.get_person_transaction_status(transaction_id) }.to raise_error do |e|
            expect(e).to be_a(Common::Exceptions::BackendServiceException)
            expect(e.status_code).to eq(400)
            expect(e.errors.first.code).to eq('VET360_CORE103')
          end
        end
      end

      it 'logs a va_profile tagged error message', :aggregate_failures do
        VCR.use_cassette('va_profile/v2/contact_information/person_transaction_status_error', VCR::MATCH_EVERYTHING) do
          expect(Rails.logger).to receive(:error).with(
            anything,
            hash_including(va_profile: 'failed_vet360_id_initializations')
          )

          expect { subject.get_person_transaction_status(transaction_id) }.to raise_error do |e|
            expect(e).to be_a(Common::Exceptions::BackendServiceException)
            expect(e.status_code).to eq(400)
            expect(e.errors.first.code).to eq('VET360_CORE103')
          end
        end
      end
    end
  end

  describe '#get_person_options_transaction_status' do
    context 'when successful' do
      let(:transaction_id) { 'f7cbebd2-68e1-4da2-97b8-0e286da8d65d' }

      it 'returns 200 using the recorded cassette' do
        VCR.use_cassette('va_profile/person_settings/person_options_transaction_status', VCR::MATCH_EVERYTHING) do
          response = subject.get_person_options_transaction_status(transaction_id)

          expect(response).to be_ok
          expect(response.transaction.id).to eq(transaction_id)
        end
      end
    end

    context 'when transaction is not found' do
      let(:transaction_id) { 'invalid-transaction-id' }

      it 'returns a status of 400' do
        VCR.use_cassette('va_profile/person_settings/person_options_transaction_status_not_found',
                         VCR::MATCH_EVERYTHING) do
          expect { subject.get_person_options_transaction_status(transaction_id) }.to raise_error do |e|
            expect(e).to be_a(Common::Exceptions::BackendServiceException)
            expect(e.status_code).to eq(400)
          end
        end
      end
    end

    context 'service delegation' do
      let(:transaction_id) { '95ea4993-ade7-4ce9-a584-9a4f8a34e0e0' }
      let(:person_settings_service) { instance_double(VAProfile::PersonSettings::Service) }
      let(:raw_response) { double('raw_response', body: { 'tx_status' => 'COMPLETED_SUCCESS' }, status: 200) }
      let(:transaction_response) { instance_double(VAProfile::ContactInformation::V2::PersonOptionsTransactionResponse) }

      before do
        allow(VAProfile::PersonSettings::Service).to receive(:new).with(user).and_return(person_settings_service)
        allow(person_settings_service).to receive(:perform).and_return(raw_response)
        allow(VAProfile::ContactInformation::V2::PersonOptionsTransactionResponse).to receive(:from)
          .with(raw_response).and_return(transaction_response)
        allow(VAProfile::Stats).to receive(:increment_transaction_results)
      end

      it 'delegates to PersonSettings service' do
        expect(person_settings_service).to receive(:perform)
          .with(:get, "person-options/v1/status/#{transaction_id}")

        subject.get_person_options_transaction_status(transaction_id)
      end
    end
  end

  context 'When reporting StatsD statistics' do
    context 'when checking transaction status' do
      context 'for emails' do
        it 'increments the StatsD VAProfile posts_and_puts counters' do
          transaction_id = '5b4550b3-2bcb-4fef-8906-35d0b4b310a8'

          VCR.use_cassette('va_profile/v2/contact_information/email_transaction_status') do
            expect { subject.get_email_transaction_status(transaction_id) }.to trigger_statsd_increment(
              "#{VAProfile::Service::STATSD_KEY_PREFIX}.posts_and_puts.success"
            )
          end
        end
      end

      context 'for telephones' do
        it 'increments the StatsD VAProfile posts_and_puts counters' do
          transaction_id = 'c6ee12e2-d219-4d12-81e0-3eecdd5eb871'

          VCR.use_cassette('va_profile/v2/contact_information/telephone_transaction_status') do
            expect_any_instance_of(described_class).to receive(:send_contact_change_notification)

            expect { subject.get_telephone_transaction_status(transaction_id) }.to trigger_statsd_increment(
              "#{VAProfile::Service::STATSD_KEY_PREFIX}.posts_and_puts.success"
            )
          end
        end
      end

      context 'for addresses' do
        it 'increments the StatsD VAProfile posts_and_puts counters' do
          transaction_id = '0ea91332-4713-4008-bd57-40541ee8d4d4'

          VCR.use_cassette('va_profile/v2/contact_information/address_transaction_status') do
            expect_any_instance_of(described_class).to receive(:send_contact_change_notification)

            expect { subject.get_address_transaction_status(transaction_id) }.to trigger_statsd_increment(
              "#{VAProfile::Service::STATSD_KEY_PREFIX}.posts_and_puts.success"
            )
          end
        end
      end

      context 'for initializing va profile' do
        it 'increments the StatsD VAProfile init_va_profile counters' do
          transaction_id = '153536a5-8b18-4572-a3d9-4030bea3ab5c'

          VCR.use_cassette('va_profile/v2/contact_information/person_transaction_status') do
            expect { subject.get_person_transaction_status(transaction_id) }.to trigger_statsd_increment(
              "#{VAProfile::Service::STATSD_KEY_PREFIX}.init_va_profile.success"
            )
          end
        end
      end

      context 'for person options' do
        it 'increments the StatsD VAProfile person_options counters' do
          transaction_id = '95ea4993-ade7-4ce9-a584-9a4f8a34e0e0'
          person_settings_service = instance_double(VAProfile::PersonSettings::Service)
          raw_response = double('raw_response', body: { 'tx_status' => 'COMPLETED_SUCCESS' }, status: 200)

          allow(VAProfile::PersonSettings::Service).to receive(:new).and_return(person_settings_service)
          allow(person_settings_service).to receive(:perform).and_return(raw_response)
          allow(VAProfile::ContactInformation::V2::PersonOptionsTransactionResponse).to receive(:from)
            .and_return(double('response'))

          expect { subject.get_person_options_transaction_status(transaction_id) }.to trigger_statsd_increment(
            "#{VAProfile::Service::STATSD_KEY_PREFIX}.person_options.success"
          )
        end
      end
    end
  end

  context 'When measuring VA Profile contact-info request latency' do
    let(:latency_metric) { "#{VAProfile::Service::STATSD_KEY_PREFIX}.contact_info.latency" }

    context 'for a write (post/put) call' do
      let(:email) { build(:email, source_system_user: user.icn) }

      it 'measures latency on the success path tagged with operation and contact_type' do
        VCR.use_cassette('va_profile/v2/contact_information/post_email_success', VCR::MATCH_EVERYTHING) do
          email.email_address = 'person42@example.com'

          expect { subject.post_email(email) }.to trigger_statsd_measure(
            latency_metric,
            tags: ['operation:create', 'contact_type:email']
          )
        end
      end

      it 'measures latency on the failure path' do
        VCR.use_cassette('va_profile/v2/contact_information/post_email_w_id_error', VCR::MATCH_EVERYTHING) do
          email.id = 42
          email.email_address = 'person42@example.com'

          expect do
            expect { subject.post_email(email) }.to raise_error(Common::Exceptions::BackendServiceException)
          end.to trigger_statsd_measure(
            latency_metric,
            tags: ['operation:create', 'contact_type:email']
          )
        end
      end
    end

    context 'for a transaction status polling call' do
      it 'measures latency tagged with operation and contact_type' do
        transaction_id = '5b4550b3-2bcb-4fef-8906-35d0b4b310a8'

        VCR.use_cassette('va_profile/v2/contact_information/email_transaction_status') do
          expect { subject.get_email_transaction_status(transaction_id) }.to trigger_statsd_measure(
            latency_metric,
            tags: ['operation:poll_status', 'contact_type:email']
          )
        end
      end
    end

    context 'for a read (get_person) call', :skip_va_profile_user do
      it 'measures latency tagged with operation and contact_type' do
        VCR.use_cassette('va_profile/v2/contact_information/person', VCR::MATCH_EVERYTHING) do
          expect { subject.get_person }.to trigger_statsd_measure(
            latency_metric,
            tags: ['operation:read', 'contact_type:person']
          )
        end
      end
    end
  end

  describe '#get_person error', :skip_va_profile_user do
    let(:user) { build(:user, :loa3) }

    before do
      allow_any_instance_of(User).to receive(:icn).and_return('6767671')
    end

    context 'when not successful' do
      context 'with a 400 error' do
        it 'returns nil person' do
          VCR.use_cassette('va_profile/v2/contact_information/person_error', VCR::MATCH_EVERYTHING) do
            response = subject.get_person
            expect(response).not_to be_ok
            expect(response.person).to be_nil
          end
        end
      end

      it 'returns a status of 400' do
        VCR.use_cassette('va_profile/v2/contact_information/person_error', VCR::MATCH_EVERYTHING) do
          expect(Rails.logger).to receive(:error).with(
            instance_of(String),
            { vet360_id: user.vet360_id, va_profile: :person_not_found }
          )
          response = subject.get_person
          expect(response).not_to be_ok
          expect(response.person).to be_nil
        end
      end
    end
  end

  describe 'error handling' do
    describe 'MissingUserVAProfileIdError' do
      context 'when vet360_id is nil' do
        let(:user_without_vet360) { build(:user, :loa3, vet360_id: nil, icn: '123498767V234859') }
        let(:service) { described_class.new(user_without_vet360) }

        it 'raises MissingUserVAProfileIdError on verify_vet360_id!' do
          expect do
            service.send(:verify_vet360_id!)
          end.to raise_error(
            VAProfile::ContactInformation::V2::Service::Errors::MissingUserVAProfileIdError
          )
        end
      end

      context 'when vet360_id is empty string' do
        let(:user_empty_vet360) { build(:user, :loa3, vet360_id: '', icn: '123498767V234859') }
        let(:service) { described_class.new(user_empty_vet360) }

        it 'raises MissingUserVAProfileIdError on verify_vet360_id!' do
          expect do
            service.send(:verify_vet360_id!)
          end.to raise_error(
            VAProfile::ContactInformation::V2::Service::Errors::MissingUserVAProfileIdError
          )
        end
      end
    end

    describe 'MissingUserICNAndVAProfileIdError' do
      context 'when both icn and vet360_id are missing' do
        let(:user_no_ids) { build(:user, :loa3, vet360_id: nil, icn: nil) }
        let(:service) { described_class.new(user_no_ids) }

        it 'raises MissingUserICNAndVAProfileIdError on verify_user!' do
          expect do
            service.send(:verify_user!)
          end.to raise_error(
            VAProfile::ContactInformation::V2::Service::Errors::MissingUserICNAndVAProfileIdError
          )
        end
      end

      context 'when both icn and vet360_id are empty strings' do
        let(:user_empty_ids) { build(:user, :loa3, vet360_id: '', icn: '') }
        let(:service) { described_class.new(user_empty_ids) }

        it 'raises MissingUserICNAndVAProfileIdError on verify_user!' do
          expect do
            service.send(:verify_user!)
          end.to raise_error(
            VAProfile::ContactInformation::V2::Service::Errors::MissingUserICNAndVAProfileIdError
          )
        end
      end
    end

    describe 'exception inheritance' do
      it 'MissingUserVAProfileIdError inherits from StandardError' do
        expect(
          VAProfile::ContactInformation::V2::Service::Errors::MissingUserVAProfileIdError
        ).to be < StandardError
      end

      it 'MissingUserICNAndVAProfileIdError inherits from StandardError' do
        expect(
          VAProfile::ContactInformation::V2::Service::Errors::MissingUserICNAndVAProfileIdError
        ).to be < StandardError
      end
    end
  end
end
