# frozen_string_literal: true

require 'shrine/plugins/validate_unlocked_pdf'

# Shrine logic for claim evidence uploads, optimistically named so
# that they cover any sort of claim documentation in a sane way.

class ClaimDocumentation::Uploader < VetsShrine
  MAX_IMAGE_WIDTH = 5616
  MAX_IMAGE_HEIGHT = 7272

  plugin :storage_from_config, settings: Settings.shrine.claims
  plugin :activerecord, callbacks: false
  plugin :validate_unlocked_pdf
  plugin :store_dimensions

  Attacher.validate do
    validate_virus_free
    validate_max_size 100.megabytes
    validate_min_size 1.kilobyte

    allowed_types = %w[image/jpg image/jpeg image/png application/pdf]
    allowed_types += %w[image/heic image/heif] if record.respond_to?(:heif_enabled) && record.heif_enabled
    validate_mime_type_inclusion allowed_types

    validate_max_width ClaimDocumentation::Uploader::MAX_IMAGE_WIDTH if get.width
    validate_max_height ClaimDocumentation::Uploader::MAX_IMAGE_HEIGHT if get.height
    validate_unlocked_pdf
  end
end
