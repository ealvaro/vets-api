# frozen_string_literal: true

module UnifiedHealthData
  # Handles formatting of reference ranges from FHIR observation data
  class ReferenceRangeFormatter
    # Main method to fetch reference range from observation
    def self.format(obs)
      return '' unless obs['referenceRange'].is_a?(Array) && !obs['referenceRange'].empty?

      begin
        # Process each range element and transform it to a formatted string
        formatted_ranges = obs['referenceRange'].map do |range|
          next '' unless range.is_a?(Hash)

          # Use the text directly if available, otherwise format it
          if range['text'].is_a?(String) && !range['text'].empty?
            ensure_unit_in_text(range['text'], obs)
          else
            format_reference_range(range, obs)
          end
        end

        # Filter out empty strings and join the results
        formatted_ranges.reject(&:empty?).join(', ').strip
      rescue => e
        Rails.logger.error("Error processing reference range: #{e.message}")
        ''
      end
    end

    private_class_method def self.format_reference_range(range, obs = nil)
      return '' unless range.is_a?(Hash)

      begin
        return ensure_unit_in_text(range['text'], obs) if range['text'].is_a?(String) && !range['text'].empty?

        return format_numeric_range(range, obs) if range['low'].is_a?(Hash) || range['high'].is_a?(Hash)

        ''
      rescue => e
        Rails.logger.error("Error processing individual reference range: #{e.message}")
        ''
      end
    end

    # Extract numeric value and unit from range component.
    # Fallback chain when the component itself has no unit:
    #   1. obs['valueQuantity']['unit'] (structured FHIR field)
    #   2. Unit parsed from obs['valueString'] text (e.g. "99 mg/dL" → "mg/dL")
    #   3. Unit parsed from obs['valueQuantity'] formatted text when unit key is absent
    private_class_method def self.extract_range_component(component, obs = nil)
      # Handle the case where component is not a hash
      return [nil, ''] unless component.is_a?(Hash)

      value = component&.dig('value')
      value = nil unless value.is_a?(Numeric)
      unit = component&.dig('unit').is_a?(String) ? component&.dig('unit') : ''

      # Fall back to observation-level unit when the reference range component has no unit
      unit = extract_unit_from_observation(obs) if unit.empty? && obs.is_a?(Hash)

      [value, unit]
    end

    # Extracts a unit string from the observation using a fallback chain.
    # Returns an empty string if no unit can be determined.
    private_class_method def self.extract_unit_from_observation(obs)
      return '' unless obs.is_a?(Hash)

      # 1. Structured valueQuantity.unit
      vq_unit = obs.dig('valueQuantity', 'unit')
      return vq_unit if vq_unit.is_a?(String) && !vq_unit.empty?

      # 2. Parse unit from valueString text (e.g. "99 mg/dL" → "mg/dL")
      value_string = obs['valueString']
      parsed = extract_unit_from_text(value_string)
      return parsed unless parsed.empty?

      # 3. Parse unit from valueQuantity.value when it arrives as a String instead of Numeric
      #    (handles malformed data, e.g. 'value' => 'Negative mIU/mL' or 'value' => '99 mg/dL')
      vq_value = obs.dig('valueQuantity', 'value')
      if vq_value.is_a?(String)
        parsed = extract_unit_from_text(vq_value)
        return parsed unless parsed.empty?
      end

      ''
    end

    # Extracts the unit portion from a value string like "99 mg/dL" → "mg/dL".
    # Everything after the first whitespace-delimited token is treated as the unit.
    # Returns an empty string when no unit can be parsed.
    private_class_method def self.extract_unit_from_text(text)
      return '' unless text.is_a?(String) && !text.strip.empty?

      parts = text.strip.split(/\s+/)
      parts.length > 1 ? parts[1..].join(' ') : ''
    end

    # Ensures that a reference range text string includes a unit.
    # If the text is missing the observation-level unit, appends it.
    # If the text already contains the unit, returns it unchanged.
    #
    # Examples:
    #   ensure_unit_in_text("<=3", obs_with_unit_mg_dL)  → "<=3 mg/dL"
    #   ensure_unit_in_text("70-110 mg/dL", obs_with_unit_mg_dL)  → "70-110 mg/dL"
    #   ensure_unit_in_text("Normal", obs_with_unit_mg_dL)  → "Normal" (no numeric content)
    private_class_method def self.ensure_unit_in_text(text, obs = nil)
      return text unless obs.is_a?(Hash)

      unit = extract_unit_from_observation(obs)
      return text if unit.empty?

      # Only append unit if the text doesn't already end with it (case-insensitive)
      return text if text.strip.downcase.end_with?(unit.downcase)

      # Only append if the text contains numeric content (digits), indicating a value that
      # could benefit from a unit. Pure text like "Normal" or "YELLOW" should be left alone.
      return text unless text.match?(/\d/)

      "#{text.strip} #{unit}"
    end

    # Determine range type prefix
    private_class_method def self.get_range_type_prefix(range)
      return '' unless range.is_a?(Hash) && range['type'].present?

      # Handle the case where type is not a hash
      return '' unless range['type'].is_a?(Hash)

      type_text = range['type']['text'].is_a?(String) ? range['type']['text'] : nil

      # Always return the range type prefix if it exists
      if type_text
        "#{type_text}: "
      else
        ''
      end
    end

    # Format a numeric reference range
    private_class_method def self.format_numeric_range(range, obs = nil)
      # Extract values safely
      low_value, low_unit = extract_range_component(range['low'], obs)
      high_value, high_unit = extract_range_component(range['high'], obs)

      # Get range type prefix
      range_type = get_range_type_prefix(range)

      # Create params hash for formatting
      params = {
        range_type:,
        low: { value: low_value, unit: low_unit },
        high: { value: high_value, unit: high_unit },
        type_text: range['type'].is_a?(Hash) ? range['type']['text'] : nil
      }

      # Format based on available values
      format_range_based_on_values(params)
    rescue => e
      Rails.logger.error("Error in format_numeric_range: #{e.message}")
      ''
    end

    # Helper method to format range based on which values are available
    private_class_method def self.format_range_based_on_values(params)
      range_type = params[:range_type]
      low_value = params[:low][:value]
      low_unit = params[:low][:unit]
      high_value = params[:high][:value]
      high_unit = params[:high][:unit]

      if low_value && high_value
        format_low_high_range(params)
      elsif low_value
        unit_str = low_unit.empty? ? '' : " #{low_unit}"
        "#{range_type}>= #{low_value}#{unit_str}"
      elsif high_value
        unit_str = high_unit.empty? ? '' : " #{high_unit}"
        "#{range_type}<= #{high_value}#{unit_str}"
      else
        ''
      end
    end

    # Format range with both low and high values
    private_class_method def self.format_low_high_range(params)
      range_type = params[:range_type]
      low_value = params[:low][:value]
      low_unit = params[:low][:unit]
      high_value = params[:high][:value]
      high_unit = params[:high][:unit]

      if !low_unit.empty? || !high_unit.empty?
        format_range_with_units(params)
      else
        "#{range_type}#{low_value} - #{high_value}"
      end
    end

    # Helper method to format range with units
    private_class_method def self.format_range_with_units(params)
      range_type = params[:range_type]
      low_value = params[:low][:value]
      low_unit = params[:low][:unit]
      high_value = params[:high][:value]
      high_unit = params[:high][:unit]

      # Determine which unit to display (prefer high's unit, fall back to low's unit)
      final_unit = if !high_unit.empty?
                     high_unit
                   elsif !low_unit.empty?
                     low_unit
                   else
                     ''
                   end

      # Only show the unit on the last value
      unit_str = final_unit.empty? ? '' : " #{final_unit}"

      # Format the range with units only at the end
      "#{range_type}#{low_value} - #{high_value}#{unit_str}"
    end
  end
end
