# frozen_string_literal: true

module SignIn
  class ErrorPageRenderer
    DEFAULT_CONTENT = {
      page_title: 'Auth',
      alert_text: "There's a temporary issue in our system. We're working to fix it as soon as possible.",
      section_title: 'What you can do:',
      intro_text: 'Until we fix this issue, you can manage your VA benefits over the phone, by mail, or in ' \
                  "person. We understand this isn't as convenient, and appreciate your patience."
    }.freeze

    ERROR_CONTENT = {
      '001' => {
        alert_text: "We're sorry. We couldn't complete the identity verification process. It looks like you selected " \
                    '"Deny" when we asked for your permission to share your information with VA.gov. We can\'t give ' \
                    'you access to all the tools on VA.gov without sharing your information with the site.',
        intro_text: 'Please try again, and this time, select "Accept" on the final page of the identity ' \
                    'verification process.'
      },
      '007' => {
        alert_text: "We're sorry. Something went wrong on our end, and we couldn't sign you in."
      },
      '009' => {
        alert_text: "We're sorry. You were unable to create an account at Login.gov or failed to sign you " \
                    'into your account.'
      },
      '102' => {
        alert_text: "We're having trouble signing you in to VA.gov right now because we found more than one " \
                    'DoD ID number for you.'
      },
      '106' => {
        alert_text: "We're having trouble signing you in to VA.gov right now because we found more than one " \
                    'account number for you.',
        section_title: 'To fix this issue:'
      },
      '400' => {
        alert_text: "We're sorry. Something went wrong on our end, and we couldn't sign you in."
      },
      '113' => {
        alert_text: "There's an issue with one of our systems that's affecting sign-in for your account. " \
                    "We're working to fix it as soon as possible.",
        flag_overrides: {
          error_113_tech_support_line_active: {
            alert_text: "There's an issue with one of our systems that's affecting sign-in for your " \
                        "account. To request a fix, you'll need to call our technical support team."
          }
        }
      }
    }.freeze

    TEMPLATE_PATH = Rails.root.join('lib', 'sign_in', 'templates', 'error_page.html.erb').freeze

    attr_reader :error_code, :request_id, :redirect_uri, :occurred_at

    def initialize(error_code:, request_id:, redirect_uri:, occurred_at: nil)
      @error_code = error_code
      @request_id = request_id
      @redirect_uri = redirect_uri
      @occurred_at = occurred_at || Time.current.to_i
    end

    def perform
      template = File.read(TEMPLATE_PATH)
      ActionController::Base.render(
        inline: template,
        layout: false,
        locals: {
          page_title: content[:page_title],
          alert_text: content[:alert_text],
          section_title: content[:section_title],
          intro_text: content[:intro_text],
          error_code:,
          request_id:,
          redirect_uri:,
          home_uri:,
          timestamp: format_timestamp
        }
      )
    end

    private

    def content
      @content ||= begin
        entry = ERROR_CONTENT.fetch(error_code.to_s, {})
        override = entry[:flag_overrides]&.find { |flag, _| Flipper.enabled?(flag) }&.last

        DEFAULT_CONTENT.merge(entry.except(:flag_overrides)).merge(override || {})
      end
    end

    def format_timestamp
      Time.zone.at(occurred_at.to_i).strftime('%b %d, %Y, %l:%M:%S %p %Z').squeeze(' ')
    end

    def home_uri
      uri = URI.parse(IdentitySettings.sign_in.usip_uri)
      port = uri.port == uri.default_port ? nil : uri.port
      "#{uri.scheme}://#{uri.host}#{":#{port}" if port}"
    end
  end
end
