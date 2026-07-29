# frozen_string_literal: true

require 'rails_helper'
require 'nokogiri'

RSpec.describe 'flipper', type: :request do
  def with_current_flipper_ui
    Rails.application.routes.draw do
      mount Flipper::UI.app(Flipper.instance) => '/flipper', constraints: Flipper::RouteAuthorizationConstraint
    end
    yield
    Rails.application.reload_routes!
  end

  def bypass_flipper_authenticity_token
    Rails.application.routes.draw do
      mount Flipper::UI.app(
        Flipper.instance,
        rack_protection: { except: :authenticity_token }
      ) => '/flipper', constraints: Flipper::RouteAuthorizationConstraint
    end
    yield
    Rails.application.reload_routes!
  end

  include Warden::Test::Helpers

  let(:default_attrs) do
    { 'login' => 'john',
      'name' => 'John Doe',
      'gravatar_id' => '38581cb351a52002548f40f8066cfecg',
      'avatar_url' => 'http://example.com/avatar.jpg',
      'email' => 'john@doe.com',
      'company' => 'Doe, Inc.' }
  end
  let(:user) { Warden::GitHub::User.new(default_attrs) }

  github_oauth_message = "If you'd like to modify feature toggles, please login with GitHub"

  before do
    Flipper.add(:this_is_only_a_test)

    allow_any_instance_of(Warden::Proxy).to receive(:authenticate!).and_return(user)
    allow_any_instance_of(Warden::Proxy).to receive(:user).and_return(user)
    allow(user).to receive_messages(organization_member?: false, team_member?: false)
  end

  context 'GET /flipper/features' do
    context 'Unauthenticated user' do
      it 'is told to sign in with GitHub to access features' do
        get '/flipper/features'
        expect(response.body).to include(github_oauth_message)
        assert_response :success
      end

      it 'is shown a button to sign in with GitHub' do
        get '/flipper/features'
        body = Nokogiri::HTML(response.body)
        signin_button = body.at_css('button:contains("Login with GitHub")')
        expect(signin_button).not_to be_nil
        assert_response :success
      end

      it 'can see a list of features, but they are inside of a disabled div and not clickable' do
        Flipper.enable(:this_is_only_a_test) # rubocop:disable Project/ForbidFlipperToggleInSpecs

        with_current_flipper_ui do
          get '/flipper/features'
          body = Nokogiri::HTML(response.body)
          disabled_div = body.at_css('div[style="pointer-events: none; opacity: 0.5;"]')

          expect(response.body).to include('this_is_only_a_test')
          expect(disabled_div).not_to be_nil
          assert_response :success
        end
      end
    end

    context 'Authenticated user (through GitHub Oauth)' do
      before do
        # Mimic the functionality of the end of the OAuth handshake, where #finalize_flow! (`warden_github.rb`)
        # is called, setting the value of request.session[:flipper_user] to the mocked Warden::Github user
        allow_any_instance_of(ActionDispatch::Request).to receive(:session) { { flipper_user: user } }
      end

      it 'is not shown a notice to sign into GitHub' do
        get '/flipper/features'
        expect(response.body).not_to include(github_oauth_message)
        assert_response :success
      end

      it 'is not shown a button to sign in with GitHub' do
        get '/flipper/features'
        body = Nokogiri::HTML(response.body)
        signin_button = body.at_css('button:contains("Login with GitHub")')
        expect(signin_button).to be_nil
        assert_response :success
      end

      context 'and Authorized user (organization and team membership)' do
        before do
          allow(user).to receive_messages(organization_member?: true, team_member?: true)
          allow_any_instance_of(Warden::GitHub::User).to receive(:organization_member?).and_return(true)
          allow_any_instance_of(Warden::GitHub::User).to receive(:team_member?).and_return(true)
        end

        it 'can see a list of features and they are clickable (hrefs to feature page)' do
          get '/flipper/features'
          body = Nokogiri::HTML(response.body)
          content_div = body.at_css('div#content')

          expect(content_div).not_to be_nil
          expect(content_div['style'].to_s).not_to include('pointer-events: none')
          assert_response :success
        end
      end

      context 'but Unauthorized user' do
        unauthorized_message = 'You are not authorized to perform any actions'

        it 'can see a list of features, but they are inside of a disabled div and not clickable' do
          Flipper.enable(:this_is_only_a_test) # rubocop:disable Project/ForbidFlipperToggleInSpecs

          with_current_flipper_ui do
            get '/flipper/features'
            body = Nokogiri::HTML(response.body)
            disabled_div = body.at_css('div[style="pointer-events: none; opacity: 0.5;"]')

            expect(response.body).to include('this_is_only_a_test')
            expect(response.body).to include(unauthorized_message)
            expect(disabled_div).not_to be_nil
            assert_response :success
          end
        end

        context 'without organization membership' do
          it 'is told that they are unauthorized and links to documentation' do
            allow(user).to receive(:organization_member?).and_return(false)

            get '/flipper/features'
            body = Nokogiri::HTML(response.body)
            docs_link = body.at_css('a[href*="depo-platform-documentation"]')
            expect(response.body).to include(unauthorized_message)
            expect(docs_link).not_to be_nil
          end
        end

        context 'without team membership' do
          it 'is told that they are unauthorized and links to documentation' do
            allow(user).to receive_messages(organization_member?: true, team_member?: false)

            get '/flipper/features'
            body = Nokogiri::HTML(response.body)
            docs_link = body.at_css('a[href*="depo-platform-documentation"]')
            expect(response.body).to include(unauthorized_message)
            expect(docs_link).not_to be_nil
          end
        end
      end
    end
  end

  context 'GET flipper/features/:some_feature' do
    context 'Unauthenticated user' do
      it 'is told to sign in with GitHub to access features' do
        get '/flipper/features/this_is_only_a_test'
        expect(response.body).to include(github_oauth_message)
        assert_response :success
      end

      it 'is shown a button to sign in with GitHub' do
        get '/flipper/features/this_is_only_a_test'
        body = Nokogiri::HTML(response.body)
        signin_button = body.at_css('button:contains("Login with GitHub")')
        expect(signin_button).not_to be_nil
        assert_response :success
      end

      it 'cannot see the feature name or content div on the page' do
        get '/flipper/features/this_is_only_a_test'
        body = Nokogiri::HTML(response.body)
        title = body.at_css('h4:contains("this_is_only_a_test")')
        content_div = body.at_css('div#content')
        expect(title).to be_nil
        expect(content_div).to be_nil
        assert_response :success
      end
    end

    context 'Authenticated (through GitHub Oauth)' do
      before do
        # Mimic the functionality of the end of the OAuth handshake, where #finalize_flow! (`warden_github.rb`)
        # is called, setting the value of request.session[:flipper_user] to the mocked Warden::Github user
        allow_any_instance_of(ActionDispatch::Request).to receive(:session) { { flipper_user: user } }
      end

      it 'is not shown a notice to sign into GitHub' do
        get '/flipper/features/this_is_only_a_test'
        expect(response.body).not_to include(github_oauth_message)
        assert_response :success
      end

      it 'is not shown a button to sign in with GitHub' do
        get '/flipper/features/this_is_only_a_test'
        body = Nokogiri::HTML(response.body)
        signin_button = body.at_css('button:contains("Login with Github")')
        expect(signin_button).to be_nil
        assert_response :success
      end

      context 'and Authorized user (organization and team membership)' do
        before do
          allow(user).to receive_messages(organization_member?: true, team_member?: true)
          Flipper.disable(:this_is_only_a_test) # rubocop:disable Project/ForbidFlipperToggleInSpecs
        end

        it 'can see the feature name in title (h4) and button to enable/disable feature' do
          get '/flipper/features/this_is_only_a_test'
          body = Nokogiri::HTML(response.body)
          title = body.at_css('h4:contains("this_is_only_a_test")')
          toggle_button = body.at_css('button:contains("Fully Enable")')
          expect(title).not_to be_nil
          expect(toggle_button).not_to be_nil
          assert_response :success
        end
      end

      context 'but Unauthorized user' do
        unauthorized_message = 'You are not authorized to perform any actions'

        it 'cannot see the feature name or content div on the page' do
          get '/flipper/features/this_is_only_a_test'
          body = Nokogiri::HTML(response.body)
          title = body.at_css('h4:contains("this_is_only_a_test")')
          content_div = body.at_css('div#content')
          expect(title).to be_nil
          expect(content_div).to be_nil
          assert_response :success
        end

        context 'without organization membership' do
          it 'is told that they are unauthorized and links to documentation' do
            allow(user).to receive(:organization_member?).and_return(false)

            get '/flipper/features/this_is_only_a_test'
            body = Nokogiri::HTML(response.body)
            docs_link = body.at_css('a[href*="depo-platform-documentation"]')
            expect(response.body).to include(unauthorized_message)
            expect(docs_link).not_to be_nil
          end
        end

        context 'without team membership' do
          it 'is told that they are unauthorized and links to documentation' do
            allow(user).to receive_messages(organization_member?: true, team_member?: false)

            get '/flipper/features/this_is_only_a_test'
            body = Nokogiri::HTML(response.body)
            docs_link = body.at_css('a[href*="depo-platform-documentation"]')
            expect(response.body).to include(unauthorized_message)
            expect(docs_link).not_to be_nil
          end
        end
      end
    end
  end

  context 'POST flipper/features/:some_feature' do
    context 'Unauthenticated User' do
      it 'cannot toggle features and returns 403' do
        bypass_flipper_authenticity_token do
          expect do
            post '/flipper/features/this_is_only_a_test/boolean'
          end.to raise_error(Common::Exceptions::Forbidden)
        end
      end

      it 'cannot add actors and returns 403' do
        bypass_flipper_authenticity_token do
          expect do
            post '/flipper/features/this_is_only_a_test/actors'
          end.to raise_error(Common::Exceptions::Forbidden)
        end
      end

      it 'cannot add groups and returns 403' do
        bypass_flipper_authenticity_token do
          expect do
            post '/flipper/features/this_is_only_a_test/groups'
          end.to raise_error(Common::Exceptions::Forbidden)
        end
      end

      it 'cannot adjust percentage_of_actors and returns 403' do
        bypass_flipper_authenticity_token do
          expect do
            post '/flipper/features/this_is_only_a_test/percentage_of_actors'
          end.to raise_error(Common::Exceptions::Forbidden)
        end
      end

      it 'cannot adjust percentage_of_time and returns 403' do
        bypass_flipper_authenticity_token do
          expect do
            post '/flipper/features/this_is_only_a_test/percentage_of_time'
          end.to raise_error(Common::Exceptions::Forbidden)
        end
      end
    end

    context 'Authenticated User' do
      before do
        allow_any_instance_of(ActionDispatch::Request).to receive(:session) { { flipper_user: user } }
      end

      context 'Unauthorized User' do
        it 'cannot toggle features and returns 403' do
          bypass_flipper_authenticity_token do
            expect do
              post '/flipper/features/this_is_only_a_test/boolean'
            end.to raise_error(Common::Exceptions::Forbidden)
          end
        end

        it 'cannot add actors and returns 403' do
          bypass_flipper_authenticity_token do
            expect do
              post '/flipper/features/this_is_only_a_test/actors'
            end.to raise_error(Common::Exceptions::Forbidden)
          end
        end

        it 'cannot add groups and returns 403' do
          bypass_flipper_authenticity_token do
            expect do
              post '/flipper/features/this_is_only_a_test/groups'
            end.to raise_error(Common::Exceptions::Forbidden)
          end
        end

        it 'cannot adjust percentage_of_actors and returns 403' do
          bypass_flipper_authenticity_token do
            expect do
              post '/flipper/features/this_is_only_a_test/percentage_of_actors'
            end.to raise_error(Common::Exceptions::Forbidden)
          end
        end

        it 'cannot adjust percentage_of_time and returns 403' do
          bypass_flipper_authenticity_token do
            expect do
              post '/flipper/features/this_is_only_a_test/percentage_of_time'
            end.to raise_error(Common::Exceptions::Forbidden)
          end
        end
      end

      context 'Authorized User' do
        it 'can toggle features' do
          allow(user).to receive(:organization_member?).with(Settings.flipper.github_organization).and_return(true)
          allow(user).to receive(:team_member?).with(Settings.flipper.github_team).and_return(true)
          Flipper.enable(:this_is_only_a_test) # rubocop:disable Project/ForbidFlipperToggleInSpecs

          bypass_flipper_authenticity_token do
            expect(Flipper.enabled?(:this_is_only_a_test)).to be true
            post '/flipper/features/this_is_only_a_test/boolean', params: nil
            follow_redirect!
            assert_response :success
            expect(Flipper.enabled?(:this_is_only_a_test)).to be false
          end
        end

        it 'can add actors' do
          allow(user).to receive(:organization_member?).with(Settings.flipper.github_organization).and_return(true)
          allow(user).to receive(:team_member?).with(Settings.flipper.github_team).and_return(true)
          Flipper.disable(:this_is_only_a_test) # rubocop:disable Project/ForbidFlipperToggleInSpecs
          test_user = create(:user)

          bypass_flipper_authenticity_token do
            expect(Flipper.enabled?(:this_is_only_a_test)).to be false
            post '/flipper/features/this_is_only_a_test/actors',
                 params: { operation: 'enable', value: test_user.flipper_id }
            follow_redirect!
            assert_response :success
            expect(Flipper.enabled?(:this_is_only_a_test, test_user)).to be true
          end
        end

        it 'can adjust percentage_of_actors' do
          allow(user).to receive(:organization_member?).with(Settings.flipper.github_organization).and_return(true)
          allow(user).to receive(:team_member?).with(Settings.flipper.github_team).and_return(true)
          Flipper.disable(:this_is_only_a_test) # rubocop:disable Project/ForbidFlipperToggleInSpecs
          test_user1 = create(:user_account)
          test_user2 = create(:user_account)

          bypass_flipper_authenticity_token do
            expect(Flipper.enabled?(:this_is_only_a_test)).to be false
            post '/flipper/features/this_is_only_a_test/percentage_of_actors', params: { value: 100 }
            follow_redirect!
            assert_response :success
            expect(Flipper.enabled?(:this_is_only_a_test, test_user1)).to be true
            expect(Flipper.enabled?(:this_is_only_a_test, test_user2)).to be true

            post '/flipper/features/this_is_only_a_test/percentage_of_actors', params: { value: 0 }
            follow_redirect!
            assert_response :success
            expect(Flipper.enabled?(:this_is_only_a_test, test_user1)).to be false
            expect(Flipper.enabled?(:this_is_only_a_test, test_user2)).to be false
          end
        end
      end
    end
  end

  context 'POST /flipper/features (feature creation)' do
    context 'Unauthenticated User' do
      it 'cannot create features and returns 403' do
        bypass_flipper_authenticity_token do
          expect do
            post '/flipper/features', params: { value: 'new_test_feature' }
          end.to raise_error(Common::Exceptions::Forbidden)
        end
      end
    end

    context 'Authenticated User' do
      before do
        allow_any_instance_of(ActionDispatch::Request).to receive(:session) { { flipper_user: user } }
      end

      context 'Unauthorized User (no org/team membership)' do
        it 'cannot create features and returns 403' do
          bypass_flipper_authenticity_token do
            expect do
              post '/flipper/features', params: { value: 'new_test_feature' }
            end.to raise_error(Common::Exceptions::Forbidden)
          end
        end
      end

      context 'Authorized User (org and team member)' do
        before do
          allow(user).to receive(:organization_member?).with(Settings.flipper.github_organization).and_return(true)
          allow(user).to receive(:team_member?).with(Settings.flipper.github_team).and_return(true)
          @original_creation_enabled = Flipper::UI.configuration.feature_creation_enabled
          Flipper::UI.configuration.feature_creation_enabled = true
        end

        after do
          Flipper::UI.configuration.feature_creation_enabled = @original_creation_enabled
        end

        it 'can create features' do
          bypass_flipper_authenticity_token do
            post '/flipper/features', params: { value: 'new_test_feature' }
            follow_redirect!
            assert_response :success
          end
        end
      end
    end
  end

  context 'DELETE /flipper/features/:feature_name (feature deletion)' do
    context 'Unauthenticated User' do
      it 'cannot delete features and returns 403' do
        bypass_flipper_authenticity_token do
          expect do
            delete '/flipper/features/this_is_only_a_test'
          end.to raise_error(Common::Exceptions::Forbidden)
        end
      end
    end

    context 'Authenticated User' do
      before do
        allow_any_instance_of(ActionDispatch::Request).to receive(:session) { { flipper_user: user } }
      end

      context 'Unauthorized User (no org/team membership)' do
        it 'cannot delete features and returns 403' do
          bypass_flipper_authenticity_token do
            expect do
              delete '/flipper/features/this_is_only_a_test'
            end.to raise_error(Common::Exceptions::Forbidden)
          end
        end
      end

      context 'Authorized User (org and team member)' do
        before do
          allow(user).to receive(:organization_member?).with(Settings.flipper.github_organization).and_return(true)
          allow(user).to receive(:team_member?).with(Settings.flipper.github_team).and_return(true)
          @original_removal_enabled = Flipper::UI.configuration.feature_removal_enabled
          Flipper::UI.configuration.feature_removal_enabled = true
        end

        after do
          Flipper::UI.configuration.feature_removal_enabled = @original_removal_enabled
        end

        it 'can delete features' do
          bypass_flipper_authenticity_token do
            delete '/flipper/features/this_is_only_a_test'
            follow_redirect!
            assert_response :success
          end
        end
      end
    end
  end

  context 'POST /flipper/settings/export' do
    context 'Unauthenticated User' do
      it 'cannot export settings and returns 403' do
        bypass_flipper_authenticity_token do
          expect do
            post '/flipper/settings/export'
          end.to raise_error(Common::Exceptions::Forbidden)
        end
      end
    end

    context 'Authenticated User' do
      before do
        allow_any_instance_of(ActionDispatch::Request).to receive(:session) { { flipper_user: user } }
      end

      context 'Unauthorized User (no org/team membership)' do
        it 'cannot export settings and returns 403' do
          bypass_flipper_authenticity_token do
            expect do
              post '/flipper/settings/export'
            end.to raise_error(Common::Exceptions::Forbidden)
          end
        end
      end

      context 'Authorized User (org and team member)' do
        before do
          allow(user).to receive(:organization_member?).with(Settings.flipper.github_organization).and_return(true)
          allow(user).to receive(:team_member?).with(Settings.flipper.github_team).and_return(true)
        end

        it 'can export settings' do
          bypass_flipper_authenticity_token do
            post '/flipper/settings/export'
            assert_response :success
            expect(response.headers['Content-Disposition']).to match(/Attachment;filename=flipper_/)
          end
        end
      end
    end
  end

  context 'POST /flipper/settings/import' do
    context 'Unauthenticated User' do
      it 'cannot import settings and returns 403' do
        bypass_flipper_authenticity_token do
          expect do
            post '/flipper/settings/import'
          end.to raise_error(Common::Exceptions::Forbidden)
        end
      end
    end

    context 'Authenticated User' do
      before do
        allow_any_instance_of(ActionDispatch::Request).to receive(:session) { { flipper_user: user } }
      end

      context 'Unauthorized User (no org/team membership)' do
        it 'cannot import settings and returns 403' do
          bypass_flipper_authenticity_token do
            expect do
              post '/flipper/settings/import'
            end.to raise_error(Common::Exceptions::Forbidden)
          end
        end
      end

      context 'Authorized User (org and team member)' do
        before do
          allow(user).to receive(:organization_member?).with(Settings.flipper.github_organization).and_return(true)
          allow(user).to receive(:team_member?).with(Settings.flipper.github_team).and_return(true)
        end

        it 'can import settings' do
          import_file = Tempfile.new(['flipper_import', '.json'])
          import_file.write({ version: 1, features: {} }.to_json)
          import_file.rewind

          bypass_flipper_authenticity_token do
            post '/flipper/settings/import',
                 params: { file: Rack::Test::UploadedFile.new(import_file.path, 'application/json') }
            follow_redirect!
            assert_response :success
          end
        ensure
          import_file.close
          import_file.unlink
        end
      end
    end
  end

  context 'Flipper UI placeholder text for actors' do
    before do
      allow_any_instance_of(ActionDispatch::Request).to receive(:session) { { flipper_user: user } }
      allow(user).to receive(:organization_member?).with(Settings.flipper.github_organization).and_return(true)
      allow(user).to receive(:team_member?).with(Settings.flipper.github_team).and_return(true)
    end

    it 'displays placeholder text indicating email or UUID and comma-separated values are supported' do
      Flipper.disable(:this_is_only_a_test) # rubocop:disable Project/ForbidFlipperToggleInSpecs

      get '/flipper/features/this_is_only_a_test'
      assert_response :success

      body = Nokogiri::HTML(response.body)
      actor_input = body.at_css('input[placeholder*="email or UUID"]')
      expect(actor_input).not_to be_nil
      expect(actor_input['placeholder']).to include('email or UUID')
      expect(actor_input['placeholder']).to include('comma-separated')
    end
  end
end
