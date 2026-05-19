# frozen_string_literal: true

module MyHealth
  module RxGroupingHelperV2
    # Only strips a single trailing letter. This means multi-letter suffixes (e.g. 'AA', 'AB')
    # group together under base '...A', but do NOT group with the unsuffixed base number.
    # This is intentional and matches VA pharmacy data conventions.
    RX_NUMBER_SUFFIX_PATTERN = /[A-Z]$/

    def group_prescriptions(prescriptions)
      prescriptions ||= []
      with_numbers, without_numbers = prescriptions.partition { |rx| valid_prescription_number?(rx) }
      grouped = process_prescriptions_with_numbers(with_numbers)
      grouped + without_numbers
    end

    def get_single_rx_from_grouped_list(prescriptions, id)
      grouped_list = group_prescriptions(prescriptions)
      grouped_list.find { |rx| rx.prescription_id == id }
    end

    def count_grouped_prescriptions(prescriptions)
      return 0 if prescriptions.blank?

      groups = {}
      count_without_numbers = 0
      prescriptions.each do |rx|
        if valid_prescription_number?(rx)
          key = [rx.prescription_number.sub(RX_NUMBER_SUFFIX_PATTERN, ''), rx.station_number]
          groups[key] = true
        else
          count_without_numbers += 1
        end
      end
      groups.size + count_without_numbers
    end

    private

    def process_prescriptions_with_numbers(prescriptions_with_numbers)
      groups = prescriptions_with_numbers.group_by do |rx|
        base = rx.prescription_number.sub(RX_NUMBER_SUFFIX_PATTERN, '')
        [base, rx.station_number]
      end

      groups.map do |_key, members|
        if members.length == 1
          members.first
        else
          # compare_prescription_numbers sorts in descending suffix order (B, A, base),
          # so we swap a/b to pick the highest suffix as the base prescription.
          base_prescription = members.max do |a, b|
            compare_prescription_numbers(b.prescription_number, a.prescription_number)
          end
          related = members.reject { |p| p.prescription_id == base_prescription.prescription_id }
          related = sort_related_prescriptions(related)
          initialize_grouped_medications(base_prescription)
          related.each { |rx| base_prescription.grouped_medications << rx }
          base_prescription
        end
      end
    end

    def valid_prescription_number?(rx)
      rx.respond_to?(:prescription_number) && rx.prescription_number && !rx.prescription_number.to_s.strip.empty?
    end

    def initialize_grouped_medications(prescription)
      prescription.grouped_medications ||= []
    end

    def sort_related_prescriptions(related_prescriptions)
      related_prescriptions.sort do |rx1, rx2|
        compare_prescription_numbers(rx1.prescription_number, rx2.prescription_number)
      end
    end

    def compare_prescription_numbers(num1, num2)
      s1 = num1[/[A-Z]+$/] || ''
      s2 = num2[/[A-Z]+$/] || ''
      s1 == s2 ? num1.sub(/[A-Z]+$/, '').to_i <=> num2.sub(/[A-Z]+$/, '').to_i : s2 <=> s1
    end
  end
end
