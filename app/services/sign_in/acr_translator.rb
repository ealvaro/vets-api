# frozen_string_literal: true

module SignIn
  class AcrTranslator
    attr_reader :acr, :type, :uplevel

    def initialize(acr:, type:, uplevel: false)
      @acr = acr
      @type = type
      @uplevel = uplevel
    end

    def perform
      { acr: translate_acr, acr_values: translate_acr_values }.compact_blank
    end

    private

    def translate_acr
      case type
      when Constants::Auth::IDME
        translate_idme_values
      when Constants::Auth::LOGINGOV
        translate_logingov_values
      when Constants::Auth::MHV
        translate_mhv_values
      when Constants::Auth::CLEAR
        translate_clear_values
      when Constants::Auth::ENTRA
        translate_entra_values
      else
        raise Errors::InvalidTypeError.new message: 'Invalid Type value'
      end
    end

    def translate_acr_values
      return unless type == Constants::Auth::IDME

      values = if acr == 'min' && !uplevel
                 [Constants::Auth::IDME_LOA1]
               elsif idme_ial2_preferred?
                 [Constants::Auth::IDME_IAL2, Constants::Auth::IDME_LOA3]
               end

      [Constants::Auth::IDME_COMPARISON_MINIMUM, *values].join(' ') if values.present?
    end

    def translate_clear_values
      case acr
      when 'ial2', Constants::Auth::IAL2_PREFERRED, Constants::Auth::IAL2_REQUIRED, 'min'
        Constants::Auth::CLEAR_IAL2
      else
        invalid_acr!(type:)
      end
    end

    def translate_entra_values
      case acr
      when 'ial2', Constants::Auth::IAL2_PREFERRED, Constants::Auth::IAL2_REQUIRED, 'min'
        Constants::Auth::ENTRA_IAL2
      else
        invalid_acr!(type:)
      end
    end

    def translate_idme_values
      case acr
      when 'loa1'
        Constants::Auth::IDME_LOA1
      when 'loa3', Constants::Auth::IAL2_PREFERRED
        if Flipper.enabled?('identity_idme_ial2_full_enforcement')
          Constants::Auth::IDME_IAL1
        else
          Constants::Auth::IDME_LOA3_FORCE
        end
      when Constants::Auth::IAL2_REQUIRED
        ial2_enabled?(type:) ? Constants::Auth::IDME_IAL2 : invalid_acr!(type:)
      when 'min'
        uplevel ? Constants::Auth::IDME_LOA3 : Constants::Auth::IDME_LOA1
      else
        invalid_acr!(type:)
      end
    end

    def translate_mhv_values
      case acr
      when 'loa1', 'loa3', 'min'
        Constants::Auth::IDME_MHV_LOA1
      else
        raise Errors::InvalidAcrError.new message: 'Invalid ACR for mhv'
      end
    end

    def translate_logingov_values
      case acr
      when 'ial1'
        Constants::Auth::LOGIN_GOV_IAL1
      when 'ial2', Constants::Auth::IAL2_PREFERRED
        logingov_ial2_level
      when Constants::Auth::IAL2_REQUIRED
        ial2_enabled?(type:) ? Constants::Auth::LOGIN_GOV_IAL2_REQUIRED : invalid_acr!(type:)
      when 'min'
        uplevel ? logingov_ial2_level : Constants::Auth::LOGIN_GOV_IAL0
      else
        invalid_acr!(type:)
      end
    end

    def logingov_ial2_level
      if Flipper.enabled?('identity_logingov_ial2_full_enforcement')
        Constants::Auth::LOGIN_GOV_IAL2_PREFERRED
      else
        Constants::Auth::LOGIN_GOV_IAL2
      end
    end

    def idme_ial2_preferred?
      Flipper.enabled?('identity_idme_ial2_full_enforcement') && acr.in?([Constants::Auth::IAL2_PREFERRED, 'loa3'])
    end

    def ial2_enabled?(type:)
      Flipper.enabled?("identity_#{type}_ial2_enforcement")
    end

    def invalid_acr!(type:)
      raise Errors::InvalidAcrError.new message: "Invalid ACR for #{type}"
    end
  end
end
