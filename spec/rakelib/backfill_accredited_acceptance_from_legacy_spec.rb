# frozen_string_literal: true

require 'rails_helper'
require 'rake'

RSpec.describe 'vso:backfill_accredited_acceptance_from_legacy rake task', type: :task do
  before(:all) do
    Rake.application.rake_require '../rakelib/backfill_accredited_acceptance_from_legacy'
    Rake::Task.define_task(:environment)
  end

  let(:task) { Rake::Task['vso:backfill_accredited_acceptance_from_legacy'] }
  let(:poa_code) { 'A1Q' }
  let(:registration_number) { '12345' }

  # Legacy side: configured (the state the migration failed to carry over)
  let!(:legacy_org) do
    create(:veteran_organization,
           poa: poa_code,
           can_accept_digital_poa_requests: true,
           primary_org_acceptance_mode: 'any_request',
           default_new_rep_acceptance_mode: 'any_request')
  end
  let!(:legacy_rep) do
    rep = create(:veteran_representative, representative_id: registration_number, poa_codes: [poa_code])
    create(:veteran_organization_representative,
           representative: rep,
           organization: legacy_org,
           representative_id: registration_number,
           organization_poa: poa_code,
           acceptance_mode: 'any_request')
  end

  # Accredited side: at post-migration defaults
  let!(:accredited_org) { create(:accredited_organization, poa_code:) }
  let!(:accredited_individual) do
    create(:accredited_individual, registration_number:, individual_type: 'representative')
  end
  let!(:accreditation) do
    create(:accreditation,
           accredited_individual:,
           accredited_organization: accredited_org,
           acceptance_mode: 'no_acceptance')
  end

  before { task.reenable }

  def run(*)
    task.invoke(*)
  end

  describe 'dry run (default)' do
    it 'writes nothing to either table' do
      expect { run }.not_to(change do
        [accredited_org.reload.attributes.slice('can_accept_digital_poa_requests',
                                                'primary_org_acceptance_mode',
                                                'default_new_rep_acceptance_mode'),
         accreditation.reload.acceptance_mode]
      end)
    end

    it 'still emits a reversal manifest so the plan can be reviewed' do
      expect { run }.to output(/Reversal manifest: .*\.csv/).to_stdout
    end
  end

  describe 'commit' do
    it 'backfills org flags from legacy' do
      run('commit', poa_code)

      accredited_org.reload
      expect(accredited_org.can_accept_digital_poa_requests).to be(true)
      expect(accredited_org.primary_org_acceptance_mode).to eq('any_request')
      expect(accredited_org.default_new_rep_acceptance_mode).to eq('any_request')
    end

    it 'backfills rep acceptance_mode from legacy' do
      run('commit', poa_code)

      expect(accreditation.reload.acceptance_mode).to eq('any_request')
    end

    it 'is idempotent — a second run plans zero changes' do
      run('commit', poa_code)
      task.reenable

      expect { run('dry_run', poa_code) }
        .to output(/needing update:\s+0.*needing update:\s+0/m).to_stdout
    end
  end

  describe 'fill-if-unset semantics (regression: must not revert deliberate config)' do
    before do
      # Accredited side deliberately configured via the sibling accredited tasks,
      # while legacy still sits at defaults. The backfill must NOT revert this.
      accredited_org.update!(can_accept_digital_poa_requests: true,
                             primary_org_acceptance_mode: 'any_request')
      accreditation.update!(acceptance_mode: 'any_request')
      legacy_org.update!(can_accept_digital_poa_requests: false,
                         primary_org_acceptance_mode: 'no_acceptance')
      legacy_rep.update!(acceptance_mode: 'no_acceptance')
    end

    it 'does not turn off an org configured only on the accredited side' do
      run('commit', poa_code)

      accredited_org.reload
      expect(accredited_org.can_accept_digital_poa_requests).to be(true)
      expect(accredited_org.primary_org_acceptance_mode).to eq('any_request')
    end

    it 'does not revert a rep configured only on the accredited side' do
      run('commit', poa_code)

      expect(accreditation.reload.acceptance_mode).to eq('any_request')
    end
  end

  describe 'conflict reporting' do
    before do
      # Both sides non-default and disagreeing -> report, do not touch.
      accredited_org.update!(primary_org_acceptance_mode: 'self_only')
      legacy_org.update!(primary_org_acceptance_mode: 'any_request')
    end

    it 'reports the conflict and leaves the value untouched' do
      expect { run('commit', poa_code) }.to output(/CONFLICT \(left untouched\):\s+[1-9]/).to_stdout
      expect(accredited_org.reload.primary_org_acceptance_mode).to eq('self_only')
    end
  end

  describe 'scoping' do
    let!(:other_legacy_org) do
      create(:veteran_organization, poa: 'ZZZ', can_accept_digital_poa_requests: true)
    end
    let!(:other_accredited_org) { create(:accredited_organization, poa_code: 'ZZZ') }

    it 'leaves out-of-scope orgs untouched' do
      run('commit', poa_code)

      expect(other_accredited_org.reload.can_accept_digital_poa_requests).to be(false)
    end

    it 'warns when a requested POA code matches no legacy org' do
      expect { run('dry_run', 'QQQ') }
        .to output(/WARNING: requested POA codes with no legacy org: QQQ/).to_stdout
    end
  end

  describe 'argument validation' do
    it 'rejects an unknown mode' do
      expect { run('bogus') }.to raise_error(ArgumentError, /mode must be/)
    end
  end
end
