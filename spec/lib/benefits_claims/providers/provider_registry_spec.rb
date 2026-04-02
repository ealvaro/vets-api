# frozen_string_literal: true

require 'rails_helper'
require 'benefits_claims/providers/provider_registry'
require 'benefits_claims/providers/benefits_claims/benefits_claims_provider'

RSpec.describe BenefitsClaims::Providers::ProviderRegistry do
  let(:mock_provider_class) do
    Class.new do
      include BenefitsClaims::Providers::BenefitsClaimsProvider
    end
  end

  let(:invalid_provider_class) do
    Class.new
  end

  let(:user) { build(:user, :loa3) }

  before do
    described_class.clear!
  end

  after do
    described_class.clear!
  end

  describe '.register' do
    it 'registers a provider successfully' do
      expect do
        described_class.register(:test_provider, mock_provider_class,
                                 feature_flag: 'test_flag')
      end.not_to raise_error
    end

    it 'defaults platform_flags to an empty hash when not specified' do
      described_class.register(:test_provider, mock_provider_class, feature_flag: 'test_flag')
      config = described_class.get(:test_provider)

      expect(config[:platform_flags]).to eq({})
    end

    it 'stores the specified platform_flags' do
      described_class.register(:test_provider, mock_provider_class,
                               feature_flag: 'test_flag',
                               platform_flags: { web: 'test_flag_web', mobile: 'test_flag_mobile' })
      config = described_class.get(:test_provider)

      expect(config[:platform_flags]).to eq({ web: 'test_flag_web', mobile: 'test_flag_mobile' })
    end

    it 'freezes the config hash to prevent mutation' do
      described_class.register(:test_provider, mock_provider_class, feature_flag: 'test_flag')
      config = described_class.get(:test_provider)

      expect(config).to be_frozen
      expect { config[:feature_flag] = 'other_flag' }.to raise_error(FrozenError)
    end

    context 'validation' do
      it 'raises when feature_flag is not provided' do
        expect do
          described_class.register(:test_provider, mock_provider_class)
        end.to raise_error(ArgumentError, /must be registered with a feature_flag/)
      end

      it 'accepts a provider class that includes BenefitsClaimsProvider' do
        expect do
          described_class.register(:valid_provider, mock_provider_class, feature_flag: 'test_flag')
        end.not_to raise_error
      end

      it 'rejects a provider class that does not include BenefitsClaimsProvider' do
        expect do
          described_class.register(:invalid_provider, invalid_provider_class, feature_flag: 'test_flag')
        end.to raise_error(ArgumentError, /must include.*BenefitsClaimsProvider module/)
      end

      it 'provides a helpful error message with the class name' do
        expect do
          described_class.register(:invalid_provider, invalid_provider_class, feature_flag: 'test_flag')
        end.to raise_error(ArgumentError, /#{invalid_provider_class}/)
      end
    end
  end

  describe '.enabled?' do
    context 'without a platform' do
      before do
        described_class.register(:test_provider, mock_provider_class, feature_flag: 'master_flag')
      end

      it 'returns true when master flag is enabled' do
        allow(Flipper).to receive(:enabled?).with('master_flag', user).and_return(true)
        expect(described_class.enabled?(:test_provider, user)).to be true
      end

      it 'returns false when master flag is disabled' do
        allow(Flipper).to receive(:enabled?).with('master_flag', user).and_return(false)
        expect(described_class.enabled?(:test_provider, user)).to be false
      end
    end

    context 'with platform flags' do
      before do
        described_class.register(
          :test_provider,
          mock_provider_class,
          feature_flag: 'master_flag',
          platform_flags: { web: 'web_flag', mobile: 'mobile_flag' }
        )
      end

      it 'returns false when master flag is disabled regardless of platform flag' do
        allow(Flipper).to receive(:enabled?).with('master_flag', user).and_return(false)
        allow(Flipper).to receive(:enabled?).with('web_flag', user).and_return(true)
        expect(described_class.enabled?(:test_provider, user, platform: :web)).to be false
      end

      it 'returns false when master is enabled but no platform flag is defined' do
        allow(Flipper).to receive(:enabled?).with('master_flag', user).and_return(true)
        expect(described_class.enabled?(:test_provider, user, platform: :unknown_platform)).to be false
      end

      it 'returns false when master is enabled but platform flag is disabled' do
        allow(Flipper).to receive(:enabled?).with('master_flag', user).and_return(true)
        allow(Flipper).to receive(:enabled?).with('mobile_flag', user).and_return(false)
        expect(described_class.enabled?(:test_provider, user, platform: :mobile)).to be false
      end

      it 'returns true when master and platform flag are both enabled' do
        allow(Flipper).to receive(:enabled?).with('master_flag', user).and_return(true)
        allow(Flipper).to receive(:enabled?).with('web_flag', user).and_return(true)
        expect(described_class.enabled?(:test_provider, user, platform: :web)).to be true
      end

      it 'returns true based on master flag alone when no platform is specified' do
        allow(Flipper).to receive(:enabled?).with('master_flag', user).and_return(true)
        expect(described_class.enabled?(:test_provider, user)).to be true
      end
    end

    context 'with unregistered provider' do
      it 'returns false' do
        expect(described_class.enabled?(:nonexistent)).to be false
      end
    end
  end

  describe '.enabled_providers' do
    let(:provider_class_two) do
      Class.new { include BenefitsClaims::Providers::BenefitsClaimsProvider }
    end

    before do
      described_class.register(:provider1, mock_provider_class, feature_flag: 'flag1')
      described_class.register(:provider2, provider_class_two, feature_flag: 'flag2')
    end

    it 'returns name and class for each enabled provider' do
      allow(Flipper).to receive(:enabled?).with('flag1', user).and_return(true)
      allow(Flipper).to receive(:enabled?).with('flag2', user).and_return(false)

      expect(described_class.enabled_providers(user)).to eq([{ name: :provider1, class: mock_provider_class }])
    end

    it 'returns empty array when no providers are enabled' do
      allow(Flipper).to receive(:enabled?).with('flag1', user).and_return(false)
      allow(Flipper).to receive(:enabled?).with('flag2', user).and_return(false)

      expect(described_class.enabled_providers(user)).to eq([])
    end

    context 'with platform flags' do
      let(:web_only_provider_class) do
        Class.new { include BenefitsClaims::Providers::BenefitsClaimsProvider }
      end

      before do
        described_class.clear!
        described_class.register(
          :shared_provider,
          mock_provider_class,
          feature_flag: 'shared_master',
          platform_flags: { web: 'shared_web', mobile: 'shared_mobile' }
        )
        described_class.register(
          :web_only_provider,
          web_only_provider_class,
          feature_flag: 'web_only_master',
          platform_flags: { web: 'web_only_web', mobile: 'web_only_mobile' }
        )
      end

      it 'returns all master-enabled providers when no platform is specified' do
        allow(Flipper).to receive(:enabled?).with('shared_master', user).and_return(true)
        allow(Flipper).to receive(:enabled?).with('web_only_master', user).and_return(true)

        result = described_class.enabled_providers(user)
        expect(result.map { |p| p[:name] }).to contain_exactly(:shared_provider, :web_only_provider)
      end

      it 'returns providers enabled for web' do
        allow(Flipper).to receive(:enabled?).with('shared_master', user).and_return(true)
        allow(Flipper).to receive(:enabled?).with('shared_web', user).and_return(true)
        allow(Flipper).to receive(:enabled?).with('web_only_master', user).and_return(true)
        allow(Flipper).to receive(:enabled?).with('web_only_web', user).and_return(true)

        result = described_class.enabled_providers(user, platform: :web)
        expect(result.map { |p| p[:name] }).to contain_exactly(:shared_provider, :web_only_provider)
      end

      it 'excludes providers whose mobile flag is disabled' do
        allow(Flipper).to receive(:enabled?).with('shared_master', user).and_return(true)
        allow(Flipper).to receive(:enabled?).with('shared_mobile', user).and_return(true)
        allow(Flipper).to receive(:enabled?).with('web_only_master', user).and_return(true)
        allow(Flipper).to receive(:enabled?).with('web_only_mobile', user).and_return(false)

        result = described_class.enabled_providers(user, platform: :mobile)
        expect(result.map { |p| p[:name] }).to contain_exactly(:shared_provider)
      end
    end
  end

  describe '.enabled_provider_classes' do
    let(:provider_class_two) do
      Class.new { include BenefitsClaims::Providers::BenefitsClaimsProvider }
    end

    let(:provider_class_three) do
      Class.new { include BenefitsClaims::Providers::BenefitsClaimsProvider }
    end

    before do
      described_class.register(:provider1, mock_provider_class, feature_flag: 'flag1')
      described_class.register(:provider2, provider_class_two, feature_flag: 'flag2')
      described_class.register(:provider3, provider_class_three, feature_flag: 'flag3')
    end

    it 'returns only enabled provider classes' do
      allow(Flipper).to receive(:enabled?).with('flag1', user).and_return(true)
      allow(Flipper).to receive(:enabled?).with('flag2', user).and_return(false)
      allow(Flipper).to receive(:enabled?).with('flag3', user).and_return(true)

      expect(described_class.enabled_provider_classes(user)).to contain_exactly(mock_provider_class,
                                                                                provider_class_three)
    end

    it 'returns empty array when no providers are enabled' do
      allow(Flipper).to receive(:enabled?).with('flag1', user).and_return(false)
      allow(Flipper).to receive(:enabled?).with('flag2', user).and_return(false)
      allow(Flipper).to receive(:enabled?).with('flag3', user).and_return(false)

      expect(described_class.enabled_provider_classes(user)).to eq([])
    end
  end

  describe '.get' do
    before do
      described_class.register(
        :test_provider,
        mock_provider_class,
        feature_flag: 'test_flag',
        platform_flags: { web: 'test_flag_web', mobile: 'test_flag_mobile' }
      )
    end

    it 'returns the configuration for a registered provider' do
      config = described_class.get(:test_provider)

      expect(config).to be_a(Hash)
      expect(config[:class]).to eq(mock_provider_class)
      expect(config[:feature_flag]).to eq('test_flag')
      expect(config[:platform_flags]).to eq({ web: 'test_flag_web', mobile: 'test_flag_mobile' })
    end

    it 'returns nil for an unregistered provider' do
      expect(described_class.get(:nonexistent)).to be_nil
    end

    it 'returns a frozen config hash' do
      config = described_class.get(:test_provider)
      expect(config).to be_frozen
    end
  end

  describe '.clear!' do
    it 'removes all registered providers' do
      described_class.register(:test_provider, mock_provider_class, feature_flag: 'test_flag')

      allow(Flipper).to receive(:enabled?).with('test_flag', nil).and_return(true)
      expect(described_class.enabled_provider_classes).not_to be_empty

      described_class.clear!
      expect(described_class.enabled_provider_classes).to be_empty
    end

    it 'raises error in production environment' do
      allow(Rails.env).to receive(:production?).and_return(true)

      expect { described_class.clear! }.to raise_error('ProviderRegistry.clear! cannot be called in production')
    ensure
      allow(Rails.env).to receive(:production?).and_call_original
    end

    it 'works in non-production environments' do
      allow(Rails.env).to receive(:production?).and_return(false)

      described_class.register(:test_provider, mock_provider_class, feature_flag: 'test_flag')
      expect { described_class.clear! }.not_to raise_error
      expect(described_class.enabled_provider_classes).to be_empty
    ensure
      allow(Rails.env).to receive(:production?).and_call_original
    end
  end
end
