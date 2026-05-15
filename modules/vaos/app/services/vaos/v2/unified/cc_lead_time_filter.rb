# frozen_string_literal: true

module VAOS
  module V2
    module Unified
      # Filters Community Care (EPS) appointment slots to a minimum
      # business-day lead time from today.
      #
      # Wellhive returns every open slot the provider has, including same-day
      # and next-day. CC providers need at least three business days to accept
      # and prepare for a referral, so showing nearer slots produces appointment
      # offers that the provider will reject. This module drops anything fewer
      # than +lead_business_days+ business days from "today" in the slot's own
      # embedded offset (Mon-Fri, excluding US federal holidays).
      #
      # Evaluating each slot in its own offset means the 3-day window matches
      # the provider's prep clock -- the offset Wellhive returns is the
      # provider's local zone, which is where the 3-day intake/prep actually
      # happens. This is independent of the server's TZ and of where the
      # veteran is physically located, which removes the off-by-one bug you
      # get when "today" in UTC differs from "today" in the slot's local zone
      # (Hawaii at 9pm, late-night East Coast scheduling, etc).
      module CCLeadTimeFilter
        DEFAULT_LEAD_BUSINESS_DAYS = 3

        # +:us+ covers calendar-date US federal holidays via the +holidays+ gem.
        # NOTE: the gem does NOT shift weekend holidays to the federally-
        # observed weekday (e.g. July 4 on a Saturday is tagged Jul 4, not the
        # observed Jul 3). That's an accepted launch limitation; if/when
        # federal-observed shifts matter we'll add a small wrapper here.
        HOLIDAY_REGIONS = %i[us].freeze

        # @param slots [Array<#start>] EpsSlot-like objects exposing +start+ as
        #   an ISO8601 string with an embedded offset (Wellhive returns the
        #   provider's local zone).
        # @param reference_time [Time] Defaults to +Time.current+. Injectable
        #   for tests; converted into each slot's offset before the count.
        # @param lead_business_days [Integer] Defaults to
        #   {DEFAULT_LEAD_BUSINESS_DAYS}.
        # @return [Array] Subset of +slots+ that are at least
        #   +lead_business_days+ business days after "today" measured in the
        #   slot's own offset. Slots with blank or unparseable +start+ are
        #   dropped.
        def self.filter(slots, reference_time: Time.current, lead_business_days: DEFAULT_LEAD_BUSINESS_DAYS)
          Array(slots).select { |slot| slot_passes_lead_time?(slot, reference_time, lead_business_days) }
        end

        # Saturday/Sunday + US federal holidays count as non-business.
        def self.business_day?(date)
          return false if date.saturday? || date.sunday?

          Holidays.on(date, *HOLIDAY_REGIONS, :observed).empty?
        end

        def self.slot_passes_lead_time?(slot, reference_time, lead_business_days)
          start_value = slot.respond_to?(:start) ? slot.start : nil
          return false if start_value.blank?

          slot_time = Time.iso8601(start_value.to_s)
          today_in_slot_zone = reference_time.getlocal(slot_time.utc_offset).to_date
          business_days_between(today_in_slot_zone, slot_time.to_date) >= lead_business_days
        rescue ArgumentError, TypeError
          false
        end

        def self.business_days_between(start_date, end_date)
          return 0 if end_date <= start_date

          count = 0
          date = start_date
          while date < end_date
            date += 1
            count += 1 if business_day?(date)
          end
          count
        end
      end
    end
  end
end
