# frozen_string_literal: true

def stub_mhv_user_account(account = nil)
  account ||= FactoryBot.build(:mhv_user_account)
  allow_any_instance_of(MHV::UserAccount::Creator).to receive(:perform).and_return(account)
end
