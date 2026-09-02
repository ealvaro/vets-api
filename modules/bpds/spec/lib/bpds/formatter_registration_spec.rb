# frozen_string_literal: true

require 'rails_helper'
require 'bpds/sidekiq/submit_to_bpds_job'

# The real guard against BPDS silently receiving unformatted data.
#
# Formatters live under modules/*/lib, which an engine puts on $LOAD_PATH but not on the autoload
# path, so SubmitToBPDSJob's constantize only resolves them if the owning engine requires them. A
# spec cannot prove that by asserting the constant resolves: RSpec runs every spec file's top-level
# requires before any example, and sibling specs require both formatters directly, so the constant
# is always defined by the time an example runs.
#
# This checks registration instead of resolution, which load order cannot affect. It fails when a
# formatter is added to FORMATTERS without the matching engine require - the exact shape of the
# original bug, for the next formatter rather than the two already fixed.
RSpec.describe BPDS::Sidekiq::SubmitToBPDSJob do
  describe 'formatter registration' do
    described_class::FORMATTERS.each do |form_id, formatter_class_name|
      context "#{form_id} (#{formatter_class_name})" do
        # 'Burials::BPDS::Formatter' -> Burials::Engine, 'burials.bpds.require_formatter'
        let(:namespace) { formatter_class_name.split('::').first }
        let(:engine) { "#{namespace}::Engine".constantize }
        let(:initializer_name) { "#{namespace.underscore}.bpds.require_formatter" }

        it 'has an engine that registers an initializer requiring the formatter' do
          expect(engine.initializers.map(&:name)).to include(initializer_name)
        end
      end
    end
  end
end
