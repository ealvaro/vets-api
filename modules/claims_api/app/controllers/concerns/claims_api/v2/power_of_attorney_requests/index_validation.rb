# frozen_string_literal: true

module ClaimsApi
  module V2
    module PowerOfAttorneyRequests
      module IndexValidation
        extend ActiveSupport::Concern

        MAX_PAGE_SIZE = 100
        MAX_PAGE_NUMBER = 100
        DEFAULT_PAGE_SIZE = 10
        DEFAULT_PAGE_NUMBER = 1

        private

        def validate_filter!(filter)
          return nil if filter.blank?

          valid_filters = %w[status state city country]
          invalid_filters = filter.keys - valid_filters

          if invalid_filters.any?
            raise ::Common::Exceptions::UnprocessableEntity.new(
              detail: "Invalid filter(s): #{invalid_filters.join(', ')}"
            )
          end

          validate_statuses!(filter['status'])
        end

        def validate_statuses!(statuses)
          return nil if statuses.blank?

          unless statuses.is_a?(Array)
            raise ::Common::Exceptions::UnprocessableEntity.new(
              detail: 'filter status must be an array'
            )
          end

          valid_statuses = ManageRepresentativeService::ALL_STATUSES
          if statuses.any? { |status| valid_statuses.exclude?(status.upcase) }
            raise ::Common::Exceptions::UnprocessableEntity.new(
              detail: "Status(es) must be one of: #{valid_statuses.join(', ')}"
            )
          end
        end

        def validate_page_size_and_number_params
          return [DEFAULT_PAGE_SIZE, DEFAULT_PAGE_NUMBER] if use_defaults?

          page = params[:page]

          valid_page_param?('size') if page[:size]
          valid_page_param?('number') if page[:number]

          page_size = page[:size] ? page[:size].to_i : DEFAULT_PAGE_SIZE
          page_number = page[:number] ? page[:number].to_i : DEFAULT_PAGE_NUMBER

          verify_under_max_values(page_size, page_number)

          [page_size, page_number]
        end

        def use_defaults?
          params[:page].blank?
        end

        def verify_under_max_values(page_size, page_number)
          if page_size > MAX_PAGE_SIZE
            raise_param_exceeded_warning = true
            include_page_size_msg = true
          end
          if page_number > MAX_PAGE_NUMBER
            raise_param_exceeded_warning = true
            include_page_number_msg = true
          end
          if raise_param_exceeded_warning.present?
            build_params_error_msg(include_page_size_msg,
                                   include_page_number_msg)
          end
        end

        def valid_page_param?(key)
          param_val = params[:page][:"#{key}"]
          return true if param_val.is_a?(String) && param_val.match?(/^\d+?$/) && param_val

          raise ::Common::Exceptions::BadRequest.new(
            detail: "The page[#{key}] param value #{params[:page][:"#{key}"]} is invalid"
          )
        end

        def build_params_error_msg(include_page_size_msg, include_page_number_msg)
          if include_page_size_msg.present? && include_page_number_msg.present?
            msg = "Both the maximum page size param value of #{MAX_PAGE_SIZE} has been exceeded and " \
                  "the maximum page number param value of #{MAX_PAGE_NUMBER} has been exceeded."
          elsif include_page_size_msg.present?
            msg = "The maximum page size param value of #{MAX_PAGE_SIZE} has been exceeded."
          elsif include_page_number_msg.present?
            msg = "The maximum page number param value of #{MAX_PAGE_NUMBER} has been exceeded."
          end

          raise ::Common::Exceptions::BadRequest.new(
            detail: msg
          )
        end
      end
    end
  end
end
