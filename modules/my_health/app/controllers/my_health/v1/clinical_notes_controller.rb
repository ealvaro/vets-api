# frozen_string_literal: true

module MyHealth
  module V1
    ##
    # Exposes a Veteran's clinical notes (care summaries and notes) sourced from
    # MHV or the Accelerated Delivery (Oracle Health) data path.
    #
    class ClinicalNotesController < MRController
      ##
      # Lists the current user's clinical notes.
      #
      # @return [JSON] serialized list of clinical notes, or 202 if the patient is not found
      #
      def index
        render_resource client.list_clinical_notes
      end

      ##
      # Retrieves a single clinical note by id.
      #
      # @return [JSON] serialized clinical note, or 202 if the patient is not found
      #
      def show
        note_id = params[:id].try(:to_i)
        render_resource client.get_clinical_note(note_id)
      end
    end
  end
end
