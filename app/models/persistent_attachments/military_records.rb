# frozen_string_literal: true

class PersistentAttachments::MilitaryRecords < PersistentAttachment
  include ::ClaimDocumentation::Uploader::Attachment.new(:file)

  attr_accessor :heif_enabled

  before_destroy(:delete_file)

  def warnings
    @warnings ||= []
  end

  private

  def delete_file
    file.delete
  end
end
