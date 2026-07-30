# frozen_string_literal: true

require 'rails_helper'

describe ClaimsApi::PoaVerification do
  subject { fake_poa_verification_controller_class.new }

  let(:fake_poa_verification_controller_class) do
    Class.new do
      include ClaimsApi::PoaVerification
      def initialize
        super
        @current_user = ClaimsApi::ClaimsUser.new('test')
        @current_user.first_name_last_name('John', 'Doe')
        @current_user.middle_name = 'Alexander'
        @current_user.suffix = 'III'
      end

      def token
        @token ||= double('Token', client_credentials_token?: false)
      end

      def target_veteran
        @target_veteran ||= {}
      end
    end
  end

  context 'validating poa_code for current_user' do
    let(:poa_code) { '091' }
    let(:first_name) { 'John' }
    let(:last_name) { 'Doe' }
    let(:phone) { '123-456-7890' }

    context 'when no rep is found' do
      it 'returns false' do
        ret = subject.valid_poa_code_for_current_user?(poa_code)
        expect(ret).to be(false)
      end
    end

    context 'when a single match is found by first/last name' do
      context 'when the poa_code matches' do
        before do
          create(:representative, representative_id: '12345', first_name:, last_name:,
                                  poa_codes: [poa_code], phone:)
        end

        it 'returns true' do
          ret = subject.valid_poa_code_for_current_user?(poa_code)
          expect(ret).to be(true)
        end
      end

      context 'when the poa_code does not match' do
        before do
          create(:representative, representative_id: '12345', first_name:, last_name:,
                                  poa_codes: ['ABC'], phone:)
        end

        it 'returns false' do
          ret = subject.valid_poa_code_for_current_user?(poa_code)
          expect(ret).to be(false)
        end
      end
    end

    context 'when multiple matches are found by first/last name' do
      before do
        create(:representative, representative_id: '12345', first_name:, last_name:,
                                middle_initial: 'A', poa_codes: ['091'], phone:)
        create(:representative, representative_id: '123456', first_name:, last_name:,
                                middle_initial: 'B', poa_codes: ['091'], phone:)
      end

      it 'searches with middle name' do
        res = subject.valid_poa_code_for_current_user?(poa_code)
        expect(res).to be(true)
      end
    end

    context 'when multiple matches are found by first/last/middle name' do
      context 'when a single rep is found' do
        before do
          create(:representative, representative_id: '12345', first_name:, last_name:,
                                  middle_initial: 'A', poa_codes: ['ABC'], phone:)
          create(:representative, representative_id: '123456', first_name:, last_name:,
                                  middle_initial: 'B', poa_codes: ['DEF'], phone:)
          create(:representative, representative_id: '1234567', first_name:, last_name:,
                                  middle_initial: 'A', poa_codes: ['091'], phone:)
        end

        it 'returns true' do
          res = subject.valid_poa_code_for_current_user?(poa_code)
          expect(res).to be(true)
        end
      end

      context 'when multiple reps are found' do
        before do
          create(:representative, representative_id: '12345', first_name:, last_name:,
                                  middle_initial: 'A', poa_codes: ['091'], phone:)
          create(:representative, representative_id: '123456', first_name:, last_name:,
                                  middle_initial: 'B', poa_codes: ['091'], phone:)
          create(:representative, representative_id: '1234567', first_name:, last_name:,
                                  middle_initial: 'A', poa_codes: ['091'], phone:)
        end

        it 'raises "Ambiguous VSO Representative Results"' do
          expect do
            subject.valid_poa_code_for_current_user?(poa_code)
          end.to raise_error(Common::Exceptions::UnprocessableEntity)
        end
      end
    end

    context 'when the repʼs last name includes a suffix that matches the current userʼs suffix' do
      before do
        create(:representative, representative_id: '12345', first_name:, last_name: "#{last_name} III",
                                poa_codes: ['091'], phone:)
      end

      it 'finds the rep and returns true' do
        res = subject.valid_poa_code_for_current_user?(poa_code)
        expect(res).to be(true)
      end
    end

    describe '#verify_power_of_attorney!' do
      before do
        allow_any_instance_of(subject.class).to receive(
          :token
        ).and_return(double(client_credentials_token?: false))
        poa_lookup = double('ClaimsApi::PoaLookupService')
        allow(ClaimsApi::PoaLookupService).to receive(:new).and_return(poa_lookup)
        allow(poa_lookup).to receive(:power_of_attorney).and_return(double(try: 'some_code'))
      end

      it 'handles an Unauthorized error' do
        allow_any_instance_of(subject.class).to receive(:valid_poa_code_for_current_user?).and_raise(Common::Exceptions::Unauthorized)

        expect do
          subject.verify_power_of_attorney!
        end.to raise_error(Common::Exceptions::Unauthorized)
      end

      context 'breakers outage' do
        let(:mock_service) do
          instance_double(
            Breakers::Service,
            name: 'Test Service'
          )
        end
        let(:mock_outage) do
          instance_double(
            Breakers::Outage,
            start_time: Time.zone.now,
            end_time: nil,
            service: mock_service
          )
        end
        let(:mock_exception) { Breakers::OutageException.new(mock_outage, mock_service) }

        it 'handles an Breakers Outage error' do
          allow_any_instance_of(subject.class).to receive(
            :valid_poa_code_for_current_user?
          ).and_raise(mock_exception)

          expect do
            subject.verify_power_of_attorney!
          end.to raise_error(Breakers::OutageException)
        end
      end
    end
  end

  # Reproduces the James Foster / OGC 49053 scenario:
  # Two different reps with the same first+last name, overlapping POA codes.
  context 'ambiguous rep scenario — two reps share a name and a POA code' do
    before do
      create(:representative, :vso,
             representative_id: '49053',
             first_name: 'James', last_name: 'Foster', middle_initial: 'P',
             poa_codes: %w[074 077 064 034 007 097],
             phone: '555-555-0101',
             email: 'james.foster@example.com',
             address_line1: '123 Main St',
             city: 'Lincoln', state_code: 'NE', zip_code: '68516',
             country_code_iso3: 'USA')
      create(:representative, :vso,
             representative_id: '15182',
             first_name: 'James', last_name: 'Foster', middle_initial: 'D',
             poa_codes: %w[074 083 085 017 086],
             phone: '555-555-0102',
             email: 'james.d.foster@example.com',
             address_line1: '456 Oak Ave', address_line2: 'Ste 2',
             city: 'Clearwater', state_code: 'FL', zip_code: '33765',
             country_code_iso3: 'USA')
    end

    context 'without middle name or email — disambiguation relies on POA code' do
      subject do
        klass = Class.new do
          include ClaimsApi::PoaVerification
          def initialize
            super
            @current_user = ClaimsApi::ClaimsUser.new('test')
            @current_user.first_name_last_name('James', 'Foster')
          end
        end
        klass.new
      end

      it 'errors for shared POA code (074)' do
        expect do
          subject.valid_poa_code_for_current_user?('074')
        end.to raise_error(Common::Exceptions::UnprocessableEntity)
      end

      it 'succeeds for unique POA code (034)' do
        expect(subject.valid_poa_code_for_current_user?('034')).to be(true)
      end
    end

    context 'with middle name — disambiguates regardless of POA code' do
      subject do
        klass = Class.new do
          include ClaimsApi::PoaVerification
          def initialize
            super
            @current_user = ClaimsApi::ClaimsUser.new('test')
            @current_user.first_name_last_name('James', 'Foster')
            @current_user.middle_name = 'Patrick'
          end
        end
        klass.new
      end

      it 'succeeds for shared POA code (074)' do
        expect(subject.valid_poa_code_for_current_user?('074')).to be(true)
      end
    end

    context 'with matching email — disambiguates when middle name is missing' do
      subject do
        klass = Class.new do
          include ClaimsApi::PoaVerification
          def initialize
            super
            @current_user = ClaimsApi::ClaimsUser.new('test')
            @current_user.first_name_last_name('James', 'Foster')
            @current_user.email = 'james.foster@example.com'
          end
        end
        klass.new
      end

      it 'succeeds for shared POA code (074)' do
        expect(subject.valid_poa_code_for_current_user?('074')).to be(true)
      end
    end

    context 'with non-matching email and no middle name — still ambiguous' do
      subject do
        klass = Class.new do
          include ClaimsApi::PoaVerification
          def initialize
            super
            @current_user = ClaimsApi::ClaimsUser.new('test')
            @current_user.first_name_last_name('James', 'Foster')
            @current_user.email = 'personal@example.com'
          end
        end
        klass.new
      end

      it 'errors for shared POA code (074)' do
        expect do
          subject.valid_poa_code_for_current_user?('074')
        end.to raise_error(Common::Exceptions::UnprocessableEntity)
      end
    end
  end
end
