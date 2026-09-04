# frozen_string_literal: true

module ClaimsEvidence
  # Turns a Veteran's filename into one Claims Evidence will accept as `contentName`. Its schema is
  # ASCII-only and rejects the whole upload on anything outside the pattern.
  module ContentName
    # Raised when nothing survives transliteration -- a name in a non-Latin script becomes "???"
    # and strips to empty. No stand-in: CE's uniqueness is eFolder-wide, so one would collide.
    class Unsupported < StandardError
      def code = 'DOC_UPLOAD_UNSUPPORTED_NAME'
    end

    # Every character CE accepts, minus `\` (it escapes the multipart filename header). Verified on
    # staging 08/30/2026 -- never widen this from a passing schema test, because our vendored copy
    # reads `&-_` as a range where CE reads three literals, so local specs pass on characters the
    # service rejects.
    DISALLOWED = /[^a-zA-Z0-9 `'~=+#^@$&(){};\[\]._-]/
    MAX_LENGTH = 256

    module_function

    # @return [String] a name inside CE's contentName pattern
    # @raise [Unsupported] nothing usable survived transliteration
    def sanitize(file_name)
      name = file_name.to_s
      extension = File.extname(name).downcase.delete_prefix('.')
      base = clean(File.basename(name, '.*'))

      assemble(base, extension)
    end

    def clean(str)
      I18n.transliterate(str.to_s).gsub(DISALLOWED, '').squeeze(' ').strip
    end

    # The extension is validated in the controller, so a bad one here means a caller skipped that
    # check. Defaulting it would file the document under a type it is not.
    def assemble(base, extension)
      raise Unsupported if base.blank?
      raise ArgumentError, "contentName extension not validated: #{extension.inspect}" unless
        extension.match?(/\A[a-zA-Z]{3,4}\z/)

      room = MAX_LENGTH - extension.length - 1
      "#{base[0, room].strip}.#{extension}"
    end

    private_class_method :clean, :assemble
  end
end
