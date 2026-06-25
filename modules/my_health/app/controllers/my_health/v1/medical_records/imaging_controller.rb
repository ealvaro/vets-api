# frozen_string_literal: true

module MyHealth
  module V1
    module MedicalRecords
      ##
      # Controller for medical imaging studies retrieval.
      #
      # Lists imaging studies, requests on-demand study packaging, reports
      # request status, and streams individual images and DICOM zip archives
      # via the Blue Button client.
      #
      class ImagingController < MRController
        include ActionController::Live

        before_action :set_study_id, only: %i[request_download images image dicom]

        ##
        # Lists the current user's imaging studies.
        #
        # @return [JSON] serialized list of imaging studies
        #
        def index
          render_resource(bb_client.list_imaging_studies)
        end

        ##
        # Requests packaging/download of a specific imaging study.
        #
        # @return [JSON] serialized study request result
        #
        def request_download
          render_resource(bb_client.request_study(current_user.icn, @study_id))
        end

        ##
        # Returns the status of a pending imaging study request.
        #
        # @return [JSON] serialized study request status
        #
        def request_status
          render_resource(bb_client.get_study_status)
        end

        ##
        # Lists the images available for the selected imaging study.
        #
        # @return [JSON] serialized list of images
        #
        def images
          render_resource(bb_client.list_images(@study_id))
        end

        ##
        # Streams a single image (JPEG) for the selected study/series/image.
        #
        # @return [void] writes JPEG image data to the live response stream
        #
        def image
          response.headers['Content-Type'] = 'image/jpeg'
          stream_data do |stream|
            bb_client.get_image(@study_id, params[:series_id].to_s, params[:image_id].to_s, header_callback, stream)
          end
        end

        ##
        # Streams the DICOM archive (zip) for the selected imaging study.
        #
        # @return [void] writes zip data to the live response stream
        #
        def dicom
          # Disable ETag manually to omit the "Content-Length" header for this streaming resource.
          # Otherwise the download/save dialog doesn't appear until after the file fully downloads.
          headers['ETag'] = nil

          response.headers['Content-Type'] = 'application/zip'
          stream_data do |stream|
            bb_client.get_dicom(@study_id, header_callback, stream)
          end
        end

        private

        def set_study_id
          @study_id = params[:id].to_s
        end

        def render_resource(resource)
          render json: resource.to_json
        end

        def header_callback
          lambda do |headers|
            headers.each do |k, v|
              next if %w[Content-Type Transfer-Encoding Content-Encoding].include?(k)

              response.headers[k] = v if k.present?
            end
          end
        end

        def stream_data(&)
          chunk_stream = Enumerator.new(&)
          chunk_stream.each { |chunk| response.stream.write(chunk) }
        ensure
          response.stream.close if response.committed?
        end
      end
    end
  end
end
