# frozen_string_literal: true

module Coe
  module ServiceBranch
    CONFIG_PATH = Rails.root.join('config', 'coe', 'service_branch.json')
    TABLE = JSON.parse(CONFIG_PATH.read).freeze
    VALID_BRANCH_KEYS = TABLE.keys.freeze

    RESERVE_KEYS = %w[AR NR MCR AFR CGR].freeze
    GUARD_KEYS = %w[ARNG ANG].freeze

    GROUP_TO_LGY_MILITARY = {
      'Army' => 'ARMY',
      'Navy' => 'NAVY',
      'Marine Corps' => 'MARINES',
      'Air Force' => 'AIR_FORCE',
      'Coast Guard' => 'COAST_GUARD',
      'Space Force' => 'AIR_FORCE',
      'Other' => 'OTHER'
    }.freeze

    class << self
      def data
        TABLE
      end

      def keys
        VALID_BRANCH_KEYS
      end

      def lgy_military_branch_and_service_type(key)
        row = TABLE[key]
        return [nil, nil] unless row

        group = row['group']
        military = GROUP_TO_LGY_MILITARY[group] || 'OTHER'
        service_type = if RESERVE_KEYS.include?(key) || GUARD_KEYS.include?(key)
                         'RESERVE_NATIONAL_GUARD'
                       else
                         'ACTIVE_DUTY'
                       end
        [military, service_type]
      end
    end
  end
end
