# frozen_string_literal: true

require 'common/models/base'
require 'date'
require 'disability_compensation/service_connected'

module Mobile
  module V0
    module Adapters
      class DisabilityRating
        include DisabilityCompensation::ServiceConnected

        def initialize(user = nil)
          @user = user
        end

        def parse(data)
          Mobile::V0::Rating.new(
            id: 0,
            combined_disability_rating: data['combined_disability_rating'],
            individual_ratings: individual_ratings(data)
          )
        end

        private

        def individual_ratings(response)
          return [] unless response['individual_ratings']

          individual_ratings = response['individual_ratings'].map do |rating|
            unless rating['rating_end_date']
              Mobile::V0::IndividualRating.new(
                decision: rating['decision'],
                effective_date: parse_date(rating['effective_date']),
                rating_percentage: rating_percentage_for(rating),
                diagnostic_text: rating['diagnostic_text']
              )
            end
          end
          individual_ratings.compact.sort_by { |rating| (rating.effective_date || '1/1/1800').to_datetime }.reverse!
        end

        def rating_percentage_for(rating)
          pct = rating['rating_percentage']&.to_i
          return pct unless Flipper.enabled?(:suppress_nsc_rating_percentage_mobile, Flipper::Actor.new(@user&.icn))

          service_connected?(rating['decision']) ? pct : nil
        end

        def parse_date(date)
          return nil unless date

          DateTime.strptime(date, '%Y-%m-%d').iso8601
        end
      end
    end
  end
end
