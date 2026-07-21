# frozen_string_literal: true

# This will monkey patch olivebranch middleware https://github.com/vigetlabs/olive_branch/blob/master/lib/olive_branch/middleware.rb
# so that when the VA inflection changes a key like something_va_something, the results will
# have the old-inflection somethingVaSomething.

module OliveBranchMiddlewareExtension
  def call(env)
    status, headers, response = super(env)

    # olive branch uses this private method to determine if a transformation should happen
    # https://github.com/vigetlabs/olive_branch/blob/master/lib/olive_branch/middleware.rb#L92
    return [status, headers, response] if send(:exclude_response?, env, headers)
    return [status, headers, response] unless env['HTTP_X_KEY_INFLECTION'] =~ /camel/i

    # Build a new response body with transformed chunks
    # This avoids mutating potentially frozen strings from the original response
    new_body = []
    response.each do |chunk|
      new_body << un_camel_va_keys(chunk)
    end

    # Close the original response if it responds to close (Rack spec compliance)
    response.close if response.respond_to?(:close)

    [status, headers, new_body]
  end

  private

  # Per-instance timeout exempts this linear regex from the global Regexp.timeout (1s)
  # set by Rails 8.0 framework defaults. The pattern is not vulnerable to catastrophic
  # backtracking, but scanning multi-MB clinical note JSON responses can exceed 1 second.
  # Start high (20s) and lower after measuring actual durations in production.
  VA_KEY_REGEX = Regexp.new('("[^"]+VA[^"]*"):', timeout: 20)

  # Non-mutating version: returns a new string with VA keys transformed
  def un_camel_va_keys(json)
    return json if json.blank?

    # rubocop:disable Style/PerlBackrefs
    # gsub with a block explicitly sets backrefs correctly
    # https://ruby-doc.org/core-2.6.6/String.html#method-i-gsub
    begin
      json.gsub(VA_KEY_REGEX) do
        key = $1
        "#{key.gsub('VA', 'Va')}:"
      end
    rescue Regexp::TimeoutError
      Rails.logger.warn('OliveBranchPatch: VA_KEY_REGEX timed out on large response body, returning untransformed JSON')
      json
    end
    # rubocop:enable Style/PerlBackrefs
  end
end

module OliveBranch
  class Middleware
    prepend OliveBranchMiddlewareExtension
  end
end
