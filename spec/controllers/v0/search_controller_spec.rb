# frozen_string_literal: true

require 'rails_helper'

RSpec.describe V0::SearchController, type: :controller do
  describe '#search_service' do
    context 'when not signed in' do
      [
        { kendra: false, gsa: false, service: Search::Service, backend: 'default' },
        { kendra: false, gsa: true, service: SearchGsa::Service, backend: 'gsa' },
        { kendra: true, gsa: false, service: SearchKendra::Service, backend: 'kendra' },
        { kendra: true, gsa: true, service: SearchKendra::Service, backend: 'kendra' }
      ].each do |scenario|
        context "when search_use_kendra=#{scenario[:kendra]} and search_use_v2_gsa=#{scenario[:gsa]}" do
          before do
            allow(controller).to receive(:current_user).and_return(nil)

            allow(Flipper).to receive(:enabled?)
              .with(:search_use_kendra, nil)
              .and_return(scenario[:kendra])

            allow(Flipper).to receive(:enabled?)
              .with(:search_use_v2_gsa)
              .and_return(scenario[:gsa])

            allow(controller).to receive_messages(
              query: 'benefits',
              page: nil
            )
          end

          it "uses #{scenario[:service]}" do
            expect(scenario[:service]).to receive(:new)
              .with('benefits', nil)
              .and_call_original

            controller.send(:search_service)

            expect(controller.send(:search_backend)).to eq(scenario[:backend])
          end
        end
      end
    end

    context 'when signed in' do
      it 'checks search_use_kendra for current user' do
        user = instance_double(User)
        allow(controller).to receive(:current_user).and_return(user)
        allow(controller).to receive_messages(query: 'benefits')

        expect(Flipper).to receive(:enabled?).with(:search_use_kendra, user).and_return(true)

        controller.send(:search_service)

        expect(controller.send(:search_backend)).to eq('kendra')
      end
    end
  end
end
