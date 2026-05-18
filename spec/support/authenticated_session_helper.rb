# frozen_string_literal: true

module AuthenticatedSessionHelper
  def sign_in(user = FactoryBot.build(:user, :loa3), token = nil, raw = false, stub_mhv_account: false)
    has_preloaded_mhv_account = user.instance_variable_defined?(:@mhv_user_account)
    preloaded_mhv_account = user.instance_variable_get(:@mhv_user_account)

    unless user.persisted?
      user = User.create(user)
      user.instance_variable_set(:@mhv_user_account, preloaded_mhv_account) if has_preloaded_mhv_account
    end

    stub_mhv_creator(user) if stub_mhv_account

    token ||= 'abracadabra'
    session_object = Session.create(uuid: user.uuid, token:)
    session_options = { key: 'api_session', secure: false, http_only: true }
    if raw
      Rails::SessionCookie::App.new(session_object.to_hash, session_options).session_cookie
    elsif cookies.is_a?(ActionDispatch::Cookies::CookieJar)
      request.session = ActionController::TestSession.new(session_object.to_hash)
    else
      raw_session_cookie = Rails::SessionCookie::App.new(session_object.to_hash, session_options).session_cookie
      cookies.merge(raw_session_cookie)
      raw_session_cookie
    end
  end

  def sign_in_as(user, token = nil, stub_mhv_account: false)
    sign_in(user, token, false, stub_mhv_account:)
  end

  private

  def stub_mhv_creator(user)
    user_verification_id = user.user_verification_id
    stubbed_account = user.instance_variable_get(:@mhv_user_account) || FactoryBot.build(:mhv_user_account)

    if user_verification_id.present?
      allow_any_instance_of(MHV::UserAccount::Creator).to receive(:perform)
        .and_wrap_original do |method, *args|
          creator = method.receiver
          if creator.user_verification&.id == user_verification_id
            stubbed_account
          else
            method.call(*args)
          end
        end
    else
      allow_any_instance_of(MHV::UserAccount::Creator).to receive(:perform).and_return(stubbed_account)
    end
  end
end
