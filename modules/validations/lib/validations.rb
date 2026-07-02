# frozen_string_literal: true

require 'validations/engine'

# Validations module provides a set of validators for various data types.
#
# This module includes validators for zipcodes and other address-related data,
# as well as controllers for accessing these validations via HTTP endpoints.
module Validations
  # API Version 0
  module V0; end

  # namespace for all validator classes
  module Validator; end
end
