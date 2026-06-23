# frozen_string_literal: true

module Common
  module Exceptions
    # Base error class all others inherit from
    class BaseError < StandardError
      def errors
        raise NotImplementedError, 'Subclass of Error must implement errors method'
      end

      def status_code
        return if errors&.first.blank?
        return errors.first[:status]&.to_i if errors.first.is_a?(Hash)

        errors&.first&.status&.to_i
      end

      def message
        i18n_data[:title]
      end

      # Whether this exception should be reported to the error tracking backend.
      # Individual exceptions opt out by setting `reportable: false` in exceptions.en.yml;
      # anything else, including an absent key, is reportable.
      def reportable?
        return true unless i18n_data.is_a?(Hash)

        i18n_data[:reportable] != false
      end

      private

      def i18n_key
        "common.exceptions.#{self.class.name.split('::').last.underscore}"
      end

      def i18n_data
        I18n.t(i18n_key)
      end

      def i18n_field(attribute, options)
        I18n.t("#{i18n_key}.#{attribute}", **options)
      rescue
        nil
      end

      def i18n_interpolated(options = {})
        merge_values = options.to_h { |attribute, opts| [attribute, i18n_field(attribute, opts)] }
        i18n_data.merge(merge_values)
      end
    end
  end
end
