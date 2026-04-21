# frozen_string_literal: true

module VAOS
  module V2
    module Unified
      # Translates between real-world VA station identifiers (used by the
      # Lighthouse Facilities API and production VAOS) and the staging-only
      # mock identifiers that lower-environment VistA test data is registered
      # against.
      #
      # In staging/lower envs, Lighthouse returns real station IDs (e.g.
      # +'442'+ for Cheyenne VAMC, +'552'+ for Dayton VAMC), but VAOS staging
      # holds the patient's PCP and clinic data under +'983'+ and +'984'+
      # respectively. Calls to VAOS for eligibility, clinics, slots, or
      # appointment creation must therefore use the staging IDs to resolve to
      # the patient's actual data.
      #
      # In production +Settings.vsp_environment+ is +'production'+ and these
      # methods are pure no-ops -- production VAOS and production Lighthouse
      # share the same station vocabulary, so no translation is needed (or
      # wanted). +Settings.vsp_environment+ is the canonical production
      # discriminator used throughout vets-api (50+ call sites across the
      # Mobile, Veteran, Travel Pay, Appeals, Check-In, and other modules).
      #
      # Mirrors {Mobile::V0::Appointment.convert_from_non_prod_id!} /
      # {Mobile::V0::Appointment.convert_to_non_prod_id!}, which solve the
      # same problem in the Mobile appointment adapter, and the frontend's
      # +getRealFacilityId+ / +getTestFacilityId+ pair in
      # +src/applications/vaos/utils/appointment.js+. Sub-station suffixes
      # (e.g. +'442GC'+ <-> +'983GC'+) round-trip correctly via the
      # leading-anchor regex.
      module FacilityIdTranslator
        REAL_TO_STAGING = { '442' => '983', '552' => '984' }.freeze
        STAGING_TO_REAL = REAL_TO_STAGING.invert.freeze

        # Precompiled leading-anchor regexes. +Regexp.union+ escapes each
        # alternative (future-proof if a station ID ever contains regex
        # metacharacters) and the +\A+ anchor + non-capturing group ensure
        # only the leading station prefix is matched, so sub-station suffixes
        # like +'442GC'+ round-trip to +'983GC'+.
        REAL_PREFIX_RE = /\A(?:#{Regexp.union(REAL_TO_STAGING.keys).source})/
        STAGING_PREFIX_RE = /\A(?:#{Regexp.union(STAGING_TO_REAL.keys).source})/

        module_function

        # Real (Lighthouse / production) station ID -> VAOS staging station ID.
        # Use anywhere a real station ID is about to be sent to a VAOS staging
        # endpoint (eligibility, clinics, slots, appointment create).
        def to_staging(id)
          translate(id, REAL_TO_STAGING, REAL_PREFIX_RE)
        end

        # VAOS staging station ID -> real (Lighthouse / production) station ID.
        # Use when surfacing a station ID to a caller that expects the
        # canonical real ID (e.g. building a +/find-locations/facility/vha_<id>+
        # link, or any subsequent Lighthouse facility lookup).
        def to_real(id)
          translate(id, STAGING_TO_REAL, STAGING_PREFIX_RE)
        end

        def production?
          Settings.vsp_environment == 'production'
        end
        private_class_method :production?

        def translate(id, mapping, prefix_regex)
          return id if production? || id.nil?

          match = id.match(prefix_regex)
          return id unless match

          id.sub(match[0], mapping[match[0]])
        end
        private_class_method :translate
      end
    end
  end
end
