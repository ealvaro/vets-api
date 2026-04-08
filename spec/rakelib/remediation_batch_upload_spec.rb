# frozen_string_literal: true

require 'rails_helper'
require 'rake'

RSpec.describe 'remediation:batch_upload rake tasks', type: :task do
  before(:all) do
    Rake.application.rake_require '../rakelib/remediation_batch_upload'
    Rake::Task.define_task(:environment)
  end

  let(:manifest_path) { Rails.root.join('spec', 'fixtures', 'remediation', 'valid_manifest.csv').to_s }
  let(:processor) { instance_double(Remediation::BatchUploadProcessor) }

  before do
    allow(Remediation::BatchUploadProcessor).to receive(:new).and_return(processor)
    allow(processor).to receive(:run!)
  end

  describe 'remediation:batch_upload:run' do
    let(:task) { Rake::Task['remediation:batch_upload:run'] }

    before { task.reenable }

    it 'aborts without MANIFEST_PATH' do
      stub_const('ENV', ENV.to_h.except('MANIFEST_PATH', 'MANIFEST_S3_URI'))
      expect { task.invoke }.to raise_error(SystemExit)
    end

    it 'creates a processor and calls run! with MANIFEST_PATH' do
      stub_const('ENV', ENV.to_h.merge('MANIFEST_PATH' => manifest_path))

      expect(Remediation::BatchUploadProcessor).to receive(:new).with(
        manifest_path:,
        limit: nil
      ).and_return(processor)
      expect(processor).to receive(:run!)

      task.invoke
    end

    it 'passes LIMIT when provided' do
      stub_const('ENV', ENV.to_h.merge('MANIFEST_PATH' => manifest_path, 'LIMIT' => '50'))

      expect(Remediation::BatchUploadProcessor).to receive(:new).with(
        manifest_path:,
        limit: 50
      ).and_return(processor)
      expect(processor).to receive(:run!)

      task.invoke
    end
  end

  describe 'remediation:batch_upload:status' do
    let(:task) { Rake::Task['remediation:batch_upload:status'] }

    before { task.reenable }

    it 'calls print_status' do
      expect(Remediation::BatchUploadProcessor).to receive(:print_status)
      task.invoke
    end
  end

  describe 'remediation:batch_upload:dry_run' do
    let(:task) { Rake::Task['remediation:batch_upload:dry_run'] }

    before { task.reenable }

    it 'aborts without MANIFEST_PATH' do
      stub_const('ENV', ENV.to_h.except('MANIFEST_PATH', 'MANIFEST_S3_URI'))
      expect { task.invoke }.to raise_error(SystemExit)
    end

    it 'creates a processor with dry_run: true' do
      stub_const('ENV', ENV.to_h.merge('MANIFEST_PATH' => manifest_path))

      expect(Remediation::BatchUploadProcessor).to receive(:new).with(
        manifest_path:,
        dry_run: true
      ).and_return(processor)
      expect(processor).to receive(:run!)

      task.invoke
    end
  end
end
