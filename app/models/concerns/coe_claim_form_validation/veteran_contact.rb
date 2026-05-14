# frozen_string_literal: true

module CoeClaimFormValidation
  module VeteranContact
    extend ActiveSupport::Concern

    private

    def validate_veteran_contact
      vet = parsed_form['veteran']
      return unless vet.is_a?(Hash)

      validate_veteran_mailing_address(vet['mailingAddress'])
      validate_veteran_home_phone(vet['homePhone'])
      validate_veteran_email(vet['email'])
    end

    def validate_veteran_mailing_address(addr)
      fragment = '/veteran/mailingAddress'
      return validate_required_or_object_error(addr, fragment) unless addr.is_a?(Hash)

      %w[addressLine1 city stateCode zipCode].each { |f| validate_required_string(addr[f], "#{fragment}/#{f}") }
      %w[addressLine2 addressLine3].each do |f|
        validate_optional_string(addr[f], "#{fragment}/#{f}") if addr.key?(f)
      end

      validate_postal_code(addr['zipCode'], "#{fragment}/zipCode")
      validate_state_code(addr['stateCode'], "#{fragment}/stateCode")

      { 'addressLine1' => 100, 'addressLine2' => 100, 'addressLine3' => 100, 'city' => 100 }.each do |field, max|
        val = addr[field]
        errors.add("#{fragment}/#{field}", "must be #{max} characters or less") if val.is_a?(String) && val.length > max
      end
    end

    def validate_veteran_home_phone(phone)
      fragment = '/veteran/homePhone'
      return validate_required_or_object_error(phone, fragment) unless phone.is_a?(Hash)

      %w[areaCode phoneNumber].each { |f| validate_required_string(phone[f], "#{fragment}/#{f}") }
      return unless phone['areaCode'].is_a?(String) && phone['phoneNumber'].is_a?(String)

      digits = "#{phone['areaCode']}#{phone['phoneNumber']}".gsub(/\D/, '')
      errors.add(fragment, 'must represent a valid 10-digit US phone number') unless digits.match?(/\A\d{10}\z/)
    end

    def validate_veteran_email(email_block)
      fragment = '/veteran/email'
      return validate_required_or_object_error(email_block, fragment) unless email_block.is_a?(Hash)

      email = email_block['emailAddress']
      ef = "#{fragment}/emailAddress"
      if email.blank?
        errors.add(ef, 'is required')
        return
      end
      unless email.is_a?(String)
        errors.add(ef, 'must be a string')
        return
      end

      errors.add(ef, 'must be 256 characters or less') if email.length > 256
      errors.add(ef, 'must be a valid email address') unless email.match?(/.+@.+\..+/i)
    end
  end
end
