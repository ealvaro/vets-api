# frozen_string_literal: true

require 'rails_helper'
require_relative '../spec_helper'

describe MebApi::V0::Submit30FormConfirmation, type: :worker do
  it_behaves_like 'a chapter confirmation email worker',
                  form_type: '1990_CHAPTER30',
                  form_tag: 'form:1990_chapter30',
                  approved_template: :form1990_chapter30_approved_confirmation_email,
                  offramp_template: :form1990_chapter30_offramp_confirmation_email,
                  worker_class: 'MebApi::V0::Submit30FormConfirmation'
end
