# frozen_string_literal: true

require 'rails_helper'
require 'csv'
require 'rake'
require 'tmpdir'

RSpec.describe 'credential_uuid rake tasks', type: :task do
  subject { task.invoke(input_path) }

  before(:all) do
    Rake.application.rake_require '../rakelib/credential_uuid_icn_lookup'
    Rake::Task.define_task(:environment)
  end

  let(:task) { Rake::Task['credential_uuid:enrich_with_icn'] }
  let(:tmp_dir) { Dir.mktmpdir }
  let(:valid_input_path) { File.join(tmp_dir, 'credential_uuids.csv') }
  let(:input_path) { valid_input_path }
  let(:output_path) { File.join(tmp_dir, 'credential_uuids_enriched.csv') }
  let(:csv_rows) do
    [
      ['Credential Type', 'Credential UUID'],
      ['idme', idme_verification.idme_uuid],
      ['logingov', logingov_verification.logingov_uuid],
      ['mhv', mhv_verification.mhv_uuid],
      ['clear', clear_verification.clear_uuid],
      ['unknown_type', 'some-unknown-uuid'],
      ['idme', ''],
      ['', 'some-missing-type']
    ]
  end
  let(:idme_verification) { create(:idme_user_verification, idme_uuid: 'some-idme-uuid') }
  let(:logingov_verification) { create(:logingov_user_verification, logingov_uuid: 'some-logingov-uuid') }
  let(:mhv_verification) { create(:mhv_user_verification, mhv_uuid: 'some-mhv-uuid') }
  let(:clear_verification) { create(:clear_user_verification, clear_uuid: 'some-clear-uuid') }

  around do |example|
    CSV.open(valid_input_path, 'w') { |csv| csv_rows.each { |row| csv << row } }
    task.reenable
    example.run
    FileUtils.rm_rf(tmp_dir)
  end

  describe 'credential_uuid:enrich_with_icn' do
    context 'when the input file is invalid' do
      let(:input_path) { File.join(tmp_dir, 'nonexistent.csv') }

      it 'raises when file path does not exist' do
        expect { subject }.to raise_error(RuntimeError, /File not found/)
      end
    end

    context 'when the input file is valid' do
      it 'enriches supported credential types with their ICN' do
        expect { subject }.to output(/Output file: .*credential_uuids_enriched\.csv/).to_stdout

        expect(File.exist?(output_path)).to be(true)

        output_csv = CSV.read(output_path, headers: true).index_by do |row|
          [row['Credential Type'], row['Credential UUID']]
        end

        expect(output_csv[%w[idme some-idme-uuid]]['ICN']).to eq(idme_verification.user_account.icn)
        expect(output_csv[%w[logingov some-logingov-uuid]]['ICN'])
          .to eq(logingov_verification.user_account.icn)
        expect(output_csv[%w[mhv some-mhv-uuid]]['ICN']).to eq(mhv_verification.user_account.icn)
        expect(output_csv[%w[clear some-clear-uuid]]['ICN']).to eq(clear_verification.user_account.icn)
      end

      it 'leaves the ICN blank for unknown credential types' do
        subject

        output_csv = CSV.read(output_path, headers: true).index_by do |row|
          [row['Credential Type'], row['Credential UUID']]
        end

        expect(output_csv[%w[unknown_type some-unknown-uuid]]['ICN']).to be_nil
      end

      it 'skips rows missing a credential type or UUID' do
        subject

        rows = CSV.read(output_path, headers: true)

        expect(rows.size).to eq(5)
        expect(rows).to all(satisfy { |row| row['Credential Type'].present? && row['Credential UUID'].present? })
      end
    end
  end
end
