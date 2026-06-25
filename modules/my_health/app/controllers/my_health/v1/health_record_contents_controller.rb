# frozen_string_literal: true

module MyHealth
  module V1
    ##
    # Streams a generated Blue Button report (PDF or text) to the client.
    #
    # Uses +ActionController::Live+ to stream the report in chunks so large
    # documents do not have to be buffered fully in memory.
    #
    class HealthRecordContentsController < BBController
      include ActionController::Live

      REPORT_HEADERS = %w[Content-Type Content-Disposition].freeze

      ##
      # Streams the generated Blue Button report download.
      #
      # @return [void] writes the report body to the live response stream;
      #   defaults to PDF unless +doc_type+ is +'txt'+
      #
      def show
        # doc_type will default to 'pdf' if any value, including nil is provided.
        doc_type = params[:doc_type] == 'txt' ? 'txt' : 'pdf'
        header_callback = lambda do |headers|
          headers.each { |k, v| response[k] = v if REPORT_HEADERS.include? k }
        end
        begin
          chunk_stream = Enumerator.new do |stream|
            client.get_download_report(doc_type, header_callback, stream)
          end
          chunk_stream.each { |c| response.stream.write c }
        ensure
          response.stream.close if response.committed?
        end
      end
    end
  end
end
