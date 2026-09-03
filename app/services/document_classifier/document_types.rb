# frozen_string_literal: true

require 'csv'

module DocumentClassifier
  module DocumentTypes
    CSV_PATH = File.join(__dir__, 'document_types.csv')

    def self.load
      CSV.foreach(CSV_PATH, headers: true).to_h do |row|
        [row.fetch('code'), row.fetch('description')]
      end.freeze
    end

    ALL = load
  end
end
