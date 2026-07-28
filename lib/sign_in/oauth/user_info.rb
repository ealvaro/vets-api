# frozen_string_literal: true

module SignIn
  module OAuth
    class UserInfo
      include ActiveModel::Model
      include ActiveModel::Attributes

      attribute :sub
      attribute :email
      attribute :all_emails
      attribute :multifactor
      attribute :first_name
      attribute :middle_name
      attribute :last_name
      attribute :ssn
      attribute :birth_date
      attribute :phone_number
      attribute :address
      attribute :level_of_assurance
      attribute :credential_ial
      attribute :verified_at
      attribute :mhv_icn
      attribute :mhv_credential_uuid
      attribute :mhv_assurance

      def ssn=(value)
        super(value&.tr('-', ''))
      end

      def ==(other)
        other.is_a?(self.class) && attributes == other.attributes
      end
      alias eql? ==

      delegate :hash, to: :attributes
    end
  end
end
