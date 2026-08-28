# frozen_string_literal: true

require 'rails_helper'

# rubocop:disable RSpec/DescribeClass
RSpec.describe 'IVC CHAMPVA staging scenario stub initializer' do
  describe 'IvcChampva::StagingScenarioStubActivation.enabled_by_environment?' do
    it 'is true when Settings.vsp_environment is staging, regardless of Rails.env' do
      allow(Settings).to receive(:vsp_environment).and_return('staging')

      expect(IvcChampva::StagingScenarioStubActivation.enabled_by_environment?).to be(true)
    end

    it 'is true in development with CHAMPVA_STAGING_SCENARIO_STUB=true' do
      allow(Settings).to receive(:vsp_environment).and_return('development')
      allow(Rails.env).to receive(:development?).and_return(true)
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('CHAMPVA_STAGING_SCENARIO_STUB').and_return('true')

      expect(IvcChampva::StagingScenarioStubActivation.enabled_by_environment?).to be(true)
    end

    it 'is false in development without CHAMPVA_STAGING_SCENARIO_STUB set' do
      allow(Settings).to receive(:vsp_environment).and_return('development')
      allow(Rails.env).to receive(:development?).and_return(true)
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('CHAMPVA_STAGING_SCENARIO_STUB').and_return(nil)

      expect(IvcChampva::StagingScenarioStubActivation.enabled_by_environment?).to be(false)
    end

    it 'is false for production-style settings (this is the safety claim the whole file rests on)' do
      allow(Settings).to receive(:vsp_environment).and_return('production')
      allow(Rails.env).to receive(:development?).and_return(false)

      expect(IvcChampva::StagingScenarioStubActivation.enabled_by_environment?).to be(false)
    end
  end

  describe 'IvcChampva::StagingScenarioStubActivation.call' do
    it 'does not attempt any prepend when disabled by environment' do
      allow(IvcChampva::StagingScenarioStubActivation).to receive(:enabled_by_environment?).and_return(false)
      allow(IvcChampva::StagingScenarioStubActivation).to receive(:prepend_once)

      expect(IvcChampva::StagingScenarioStubActivation.call).to be(false)
      expect(IvcChampva::StagingScenarioStubActivation).not_to have_received(:prepend_once)
    end

    it 'attempts to prepend the VES client and MPI service stubs when enabled by environment' do
      allow(IvcChampva::StagingScenarioStubActivation).to receive(:enabled_by_environment?).and_return(true)
      allow(IvcChampva::StagingScenarioStubActivation).to receive(:prepend_once)
      allow(Rails.application.config).to receive(:to_prepare)

      expect(IvcChampva::StagingScenarioStubActivation.call).to be(true)
      expect(IvcChampva::StagingScenarioStubActivation)
        .to have_received(:prepend_once).with(IvcChampva::VesApi::Client, IvcChampva::VesApi::StagingScenarioClientMethods)
      expect(IvcChampva::StagingScenarioStubActivation)
        .to have_received(:prepend_once).with(IvcChampva::MPIService, IvcChampva::StagingScenarioMPIServiceMethods)
    end

    it 'registers a to_prepare block that works when invoked via instance_exec, matching how ' \
       'ActiveSupport::Callbacks actually runs to_prepare callbacks (regression test: a prior ' \
       'version called prepend_controller_stub! as a bare method name inside this block, which ' \
       'raised NoMethodError at boot because instance_exec rebinds self away from this module)' do
      allow(IvcChampva::StagingScenarioStubActivation).to receive(:enabled_by_environment?).and_return(true)
      allow(IvcChampva::StagingScenarioStubActivation).to receive(:prepend_once)
      captured_block = nil
      allow(Rails.application.config).to receive(:to_prepare) { |&block| captured_block = block }

      IvcChampva::StagingScenarioStubActivation.call
      Object.new.instance_exec(&captured_block)

      expect(IvcChampva::StagingScenarioStubActivation).to have_received(:prepend_once).with(
        IvcChampva::V1::ChampvaEligibilityController, IvcChampva::V1::StagingScenarioControllerMethods
      )
    end
  end

  describe 'IvcChampva::StagingScenarioStubActivation.prepend_controller_stub!' do
    it 'prepends the controller stub via prepend_once' do
      allow(IvcChampva::StagingScenarioStubActivation).to receive(:prepend_once)

      IvcChampva::StagingScenarioStubActivation.prepend_controller_stub!

      expect(IvcChampva::StagingScenarioStubActivation).to have_received(:prepend_once).with(
        IvcChampva::V1::ChampvaEligibilityController, IvcChampva::V1::StagingScenarioControllerMethods
      )
    end
  end

  describe 'IvcChampva::StagingScenarioStubActivation.prepend_once' do
    it 'prepends the module onto the class' do
      mod = Module.new
      klass = Class.new

      IvcChampva::StagingScenarioStubActivation.prepend_once(klass, mod)

      expect(klass.ancestors).to include(mod)
    end

    it 'does not stack a duplicate prepend when called more than once for the same pair' do
      mod = Module.new
      klass = Class.new

      3.times { IvcChampva::StagingScenarioStubActivation.prepend_once(klass, mod) }

      expect(klass.ancestors.count(mod)).to eq(1)
    end
  end

  describe 'IvcChampva::StagingScenarioStub' do
    # Test env runs on ActiveSupport::Cache::NullStore (config/environments/test.rb), under
    # which Rails.cache.fetch always re-runs its default block and #write is a no-op -- so
    # this stub's state (which relies on Rails.cache actually persisting) would silently
    # never advance/pin across calls, even within the same example. Swap in a real store for
    # just this block, same pattern as spec/requests/v0/search_spec.rb.
    around do |example|
      original_store = Rails.cache
      Rails.cache = ActiveSupport::Cache::MemoryStore.new
      example.run
    ensure
      Rails.cache = original_store
    end

    before { IvcChampva::StagingScenarioStub.reset! }

    after { IvcChampva::StagingScenarioStub.reset! }

    describe '.for_transaction?' do
      it 'pins to the first transaction_uuid it sees and keeps returning true for it' do
        uuid = SecureRandom.uuid

        expect(IvcChampva::StagingScenarioStub.for_transaction?(uuid)).to be(true)
        expect(IvcChampva::StagingScenarioStub.for_transaction?(uuid)).to be(true)
      end

      it 'returns false for a different transaction_uuid once one is pinned, without moving the pin' do
        first = SecureRandom.uuid
        second = SecureRandom.uuid

        IvcChampva::StagingScenarioStub.for_transaction?(first)

        expect(IvcChampva::StagingScenarioStub.for_transaction?(second)).to be(false)
        expect(IvcChampva::StagingScenarioStub.for_transaction?(first)).to be(true)
      end
    end

    describe '.advance_for!' do
      it 'arms then advances the shared step counter when called for the pinned transaction_uuid' do
        uuid = SecureRandom.uuid

        IvcChampva::StagingScenarioStub.advance_for!([uuid]) # arms only
        expect(IvcChampva::StagingScenarioStub.current_step).to eq(0)

        IvcChampva::StagingScenarioStub.advance_for!([uuid]) # advances to step 1
        expect(IvcChampva::StagingScenarioStub.current_step).to eq(1)
      end

      it "does not advance for -- or get advanced by -- a different reviewer's transaction_uuid" do
        pinned = SecureRandom.uuid
        other = SecureRandom.uuid

        IvcChampva::StagingScenarioStub.advance_for!([pinned]) # arms + pins
        IvcChampva::StagingScenarioStub.advance_for!([pinned]) # step 1

        IvcChampva::StagingScenarioStub.advance_for!([other])

        expect(IvcChampva::StagingScenarioStub.current_step).to eq(1)
      end
    end

    describe '.reset_for!' do
      it 'raises ArgumentError for a blank transaction_uuid instead of scoping destroy_all to NULL rows' do
        expect { IvcChampva::StagingScenarioStub.reset_for!(nil) }.to raise_error(ArgumentError)
        expect { IvcChampva::StagingScenarioStub.reset_for!('') }.to raise_error(ArgumentError)
      end
    end

    describe '.real_name_from_application' do
      let(:transaction_uuid) { SecureRandom.uuid }
      let(:sponsor_icn) { IvcChampva::StagingScenarioStub::STUB_ICN_SPONSOR }

      before do
        create(:ivc_champva_applicant, transaction_uuid:, applicant_icn: sponsor_icn)
      end

      def veteran_request_json(first_name, last_name)
        { 'veteran' => { 'full_name' => { 'first' => first_name, 'last' => last_name } } }.to_json
      end

      it "picks up a later resubmission's name instead of staying locked onto the transaction's first submission" do
        first_submission = create(:ivc_champva_form,
                                  transaction_uuid:,
                                  request_json: veteran_request_json('Walkthrough', 'Verifier'))
        first_submission.update_column(:created_at, 2.days.ago) # rubocop:disable Rails/SkipsModelValidations
        create(:ivc_champva_form,
               transaction_uuid:,
               request_json: veteran_request_json('RealSubmitted', 'Beneficiary'))

        expect(IvcChampva::StagingScenarioStub.real_name_from_application(sponsor_icn))
          .to eq(first_name: 'RealSubmitted', last_name: 'Beneficiary')
      end
    end

    describe '.stub_icn?' do
      it 'is true for either of the stub\'s own two fixed demo ICNs' do
        stub = IvcChampva::StagingScenarioStub

        expect(stub.stub_icn?(stub::STUB_ICN_SPONSOR)).to be(true)
        expect(stub.stub_icn?(stub::STUB_ICN_BENEFICIARY)).to be(true)
      end

      it 'is false for a real (non-stub) ICN' do
        expect(IvcChampva::StagingScenarioStub.stub_icn?('1234567890V123456')).to be(false)
      end
    end
  end

  describe 'IvcChampva::VesApi::StagingScenarioClientMethods#get_ee_summary' do
    # See the .around/.before/.after in the describe block above for why a real cache store
    # is needed here.
    around do |example|
      original_store = Rails.cache
      Rails.cache = ActiveSupport::Cache::MemoryStore.new
      example.run
    ensure
      Rails.cache = original_store
    end

    after { IvcChampva::StagingScenarioStub.reset! }

    let(:client_class) do
      Class.new do
        def get_ee_summary(icn:, region_id_or_offset: nil) # rubocop:disable Lint/UnusedMethodArgument
          "real super result for #{icn}"
        end
      end.prepend(IvcChampva::VesApi::StagingScenarioClientMethods)
    end
    let(:client) { client_class.new }

    before do
      IvcChampva::StagingScenarioStub.reset!
      allow(IvcChampva::StagingScenarioStub).to receive(:active?).and_return(true)
    end

    it 'returns stubbed canned data for one of the stub\'s own fixed ICNs' do
      result = client.get_ee_summary(icn: IvcChampva::StagingScenarioStub::STUB_ICN_BENEFICIARY)

      expect(result).to eq(IvcChampva::StagingScenarioStub.ee_summary_for(IvcChampva::StagingScenarioStub::STUB_ICN_BENEFICIARY))
    end

    it 'falls through to the real client for a real (non-stub) ICN even while the flag is globally active' do
      result = client.get_ee_summary(icn: '1234567890V123456')

      expect(result).to eq('real super result for 1234567890V123456')
    end
  end
end
# rubocop:enable RSpec/DescribeClass
