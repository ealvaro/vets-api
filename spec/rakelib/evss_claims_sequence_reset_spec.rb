# frozen_string_literal: true

require 'rails_helper'
require 'rake'

RSpec.describe 'data_migration:evss_claims_sequence_reset rake task', type: :task do
  before(:all) do
    Rake.application.rake_require '../rakelib/evss_claims_sequence_reset'
    Rake::Task.define_task(:environment)
  end

  let(:task) { Rake::Task['data_migration:evss_claims_sequence_reset'] }

  before { task.reenable }

  it 'delegates to the data migration' do
    expect(DataMigrations::EVSSClaimsSequenceReset).to receive(:run).and_return(
      { previous_value: 2_031_834_429, new_value: 1, min_id: 1_590_858_608 }
    )

    suppress_stdout { task.invoke }
  end

  it 'prints the before and after values' do
    allow(DataMigrations::EVSSClaimsSequenceReset).to receive(:run).and_return(
      { previous_value: 2_031_834_429, new_value: 1, min_id: 1_590_858_608 }
    )

    expect { task.invoke }.to output(
      a_string_including('previous value: 2031834429')
        .and(including('new value:      1'))
        .and(including('lowest live id: 1590858608'))
    ).to_stdout
  end

  it 'lets a guard failure propagate' do
    allow(DataMigrations::EVSSClaimsSequenceReset).to receive(:run)
      .and_raise(RuntimeError, 'Refusing to reset evss_claims_id_seq')

    expect { task.invoke }.to raise_error(RuntimeError, /Refusing to reset/)
  end

  def suppress_stdout
    original = $stdout
    $stdout = StringIO.new
    yield
  ensure
    $stdout = original
  end
end
