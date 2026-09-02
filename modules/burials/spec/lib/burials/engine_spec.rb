# frozen_string_literal: true

require 'rails_helper'
# The job file is explicitly required by bpds/submission_handler in the real app; only the
# formatter it names is left to the engine, so requiring it here does not mask the bug.
require 'bpds/sidekiq/submit_to_bpds_job'

# This file does not require 'burials/bpds/formatter', but that does NOT make the resolution
# example below a guard against the formatter going unloaded in production. RSpec runs every spec
# file's top-level requires before any example, and siblings require the formatter directly
# (spec/lib/bpds/formatter_spec.rb, and modules/bpds/spec/lib/bpds/service_spec.rb), so the constant
# is already defined by the time these examples run. The real guard lives in
# modules/bpds/spec/lib/bpds/formatter_registration_spec.rb, which checks registration rather than
# resolution and so cannot be satisfied by load order.
RSpec.describe Burials::Engine do
  describe 'BPDS formatter loading' do
    it 'registers an initializer that requires the BPDS formatter' do
      expect(described_class.initializers.map(&:name)).to include('burials.bpds.require_formatter')
    end

    it 'resolves the formatter class name registered in the BPDS job' do
      formatter_class_name = BPDS::Sidekiq::SubmitToBPDSJob::FORMATTERS[Burials::FORM_ID]

      expect(formatter_class_name).to eq('Burials::BPDS::Formatter')
      expect { formatter_class_name.constantize }.not_to raise_error
    end
  end
end
