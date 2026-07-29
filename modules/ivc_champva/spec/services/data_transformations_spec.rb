# frozen_string_literal: true

require 'rails_helper'

RSpec.describe IvcChampva::DataTransformations do
  # Use a real form class that includes the mixin
  let(:form_data) do
    {
      'form_number' => '10-10D',
      'applicants' => [
        { 'first_name' => 'John', 'last_name' => 'Doe' },
        { 'first_name' => 'Jane', 'last_name' => 'Doe' }
      ],
      'supporting_docs' => [
        { 'confirmation_code' => 'code1', 'attachment_id' => 'doc1' },
        { 'confirmation_code' => 'code2', 'attachment_id' => 'doc2' }
      ]
    }
  end
  let(:form) { IvcChampva::VHA1010d.new(form_data) }

  describe '#validated_metadata' do
    it 'delegates to MetadataValidator.validate and memoizes the result' do
      raw_metadata = form.metadata
      validated = { 'validated' => true }
      allow(IvcChampva::MetadataValidator).to receive(:validate).with(raw_metadata).and_return(validated)

      expect(form.validated_metadata).to eq(validated)
      # Second call should not invoke validate again
      expect(form.validated_metadata).to eq(validated)
      expect(IvcChampva::MetadataValidator).to have_received(:validate).once
    end
  end

  describe '.metadata_for_s3' do
    let(:full_metadata) do
      {
        'uuid' => 'test-uuid',
        'primaryContactInfo' => { 'name' => 'Test' },
        'attachment_ids' => %w[id1 id2],
        'supportingDocApplicants' => ['app1'],
        'additional_file_metadata' => {
          'file1.pdf' => { 'meta-jsonfile' => 'uuid_vha_10_10d_ves.json' },
          'file2.png' => { 'meta-jsonfile' => 'uuid_vha_10_10d_ves.json' }
        }
      }
    end

    context 'without additional_file_metadata' do
      let(:simple_metadata) do
        {
          'uuid' => 'test-uuid',
          'primaryContactInfo' => { 'name' => 'Test' },
          'attachment_ids' => %w[id1 id2]
        }
      end

      it 'returns metadata with attachment_id, excluding internal keys' do
        result = described_class.metadata_for_s3(simple_metadata, 'Social Security card')

        expect(result).to have_key('attachment_id')
        expect(result['attachment_id']).to eq('Social Security card')
        expect(result).not_to have_key('primaryContactInfo')
        expect(result).not_to have_key('attachment_ids')
        expect(result).not_to have_key('supportingDocApplicants')
      end

      it 'uses claim_id key when attachment_id is an integer' do
        result = described_class.metadata_for_s3(simple_metadata, 42)

        expect(result).to have_key('claim_id')
        expect(result['claim_id']).to eq('42')
        expect(result).not_to have_key('attachment_id')
      end

      it 'does not add per-file overrides even with file_path' do
        result = described_class.metadata_for_s3(simple_metadata, 'doc1', 'tmp/file1.pdf')

        expect(result).not_to have_key('meta-jsonfile')
      end
    end

    context 'with additional_file_metadata' do
      it 'merges per-file overrides for files in the map' do
        result = described_class.metadata_for_s3(full_metadata, 'Social Security card', 'tmp/file1.pdf')

        expect(result['meta-jsonfile']).to eq('uuid_vha_10_10d_ves.json')
      end

      it 'strips -tmp from file path when looking up in map' do
        custom_metadata = {
          'uuid' => 'test-uuid',
          'additional_file_metadata' => { 'myform.pdf' => { 'meta-jsonfile' => 'ves.json' } }
        }

        result = described_class.metadata_for_s3(custom_metadata, 'doc1', 'tmp/myform-tmp.pdf')

        expect(result['meta-jsonfile']).to eq('ves.json')
      end

      it 'does not add overrides for files not in the map' do
        result = described_class.metadata_for_s3(full_metadata, 'VES JSON', 'tmp/unknown_ves.json')

        expect(result).not_to have_key('meta-jsonfile')
      end

      it 'does not add overrides when file_path is nil' do
        result = described_class.metadata_for_s3(full_metadata, 'Social Security card')

        expect(result).not_to have_key('meta-jsonfile')
      end

      it 'strips additional_file_metadata from the returned metadata' do
        result = described_class.metadata_for_s3(full_metadata, 'Social Security card', 'tmp/file1.pdf')

        expect(result).not_to have_key('additional_file_metadata')
      end
    end
  end

  describe '#supporting_document_ids' do
    context 'with valid supporting documents' do
      before do
        allow(PersistentAttachments::MilitaryRecords).to receive(:find_by)
          .with(guid: 'code1')
          .and_return(double('Record1', created_at: 2.days.ago, file: double(id: 'file1')))
        allow(PersistentAttachments::MilitaryRecords).to receive(:find_by)
          .with(guid: 'code2')
          .and_return(double('Record2', created_at: 1.day.ago, file: double(id: 'file2')))
      end

      it 'orders supporting document ids by date created' do
        result = form.supporting_document_ids(form_data)
        expect(result).to eq(%w[doc1 doc2])
      end
    end

    it 'returns empty array when no supporting docs exist' do
      form_data_without_docs = { 'form_number' => '10-10D' }
      result = form.supporting_document_ids(form_data_without_docs)
      expect(result).to eq([])
    end

    it 'falls back to claim_id when attachment_id is nil' do
      claim_data = {
        'supporting_docs' => [
          { 'claim_id' => 'claim1', 'confirmation_code' => 'code1' },
          { 'claim_id' => 'claim2', 'confirmation_code' => 'code2' }
        ]
      }

      allow(PersistentAttachments::MilitaryRecords).to receive(:find_by)
        .with(guid: 'code1')
        .and_return(double('Record1', created_at: 2.days.ago, file: double(id: 'file1')))
      allow(PersistentAttachments::MilitaryRecords).to receive(:find_by)
        .with(guid: 'code2')
        .and_return(double('Record2', created_at: 1.day.ago, file: double(id: 'file2')))

      result = form.supporting_document_ids(claim_data)
      expect(result).to eq(%w[claim1 claim2])
    end

    it 'raises NoMethodError when supporting doc is not found in database' do
      invalid_data = {
        'supporting_docs' => [
          { 'confirmation_code' => 'invalid_code', 'attachment_id' => 'doc1' }
        ]
      }
      allow(PersistentAttachments::MilitaryRecords).to receive(:find_by)
        .with(guid: 'invalid_code')
        .and_return(nil)

      expect { form.supporting_document_ids(invalid_data) }.to raise_error(NoMethodError)
    end

    it 'keeps original order for equal created_at values when OHI docs are present' do
      equal_time = Time.zone.now
      tie_break_data = {
        'supporting_docs' => [
          { 'confirmation_code' => 'code1', 'attachment_id' => 'Front of insurance card' },
          { 'confirmation_code' => 'code2', 'attachment_id' => 'VA form 10-7959c' }
        ]
      }

      allow(Flipper).to receive(:enabled?).with(:champva_supporting_docs_ordering).and_return(true)

      allow(PersistentAttachments::MilitaryRecords).to receive(:find_by)
        .with(guid: 'code1')
        .and_return(double('Record1', created_at: equal_time, file: double(id: 'file1')))
      allow(PersistentAttachments::MilitaryRecords).to receive(:find_by)
        .with(guid: 'code2')
        .and_return(double('Record2', created_at: equal_time, file: double(id: 'file2')))

      result = form.supporting_document_ids(tie_break_data)
      expect(result).to eq(['Front of insurance card', 'VA form 10-7959c'])
    end

    it 'preserves created_at-only ordering when flipper is enabled but OHI docs are not present' do
      earlier_time = Time.zone.now
      later_time = earlier_time + 1.second
      non_ohi_data = {
        'supporting_docs' => [
          { 'confirmation_code' => 'code1', 'attachment_id' => 'Birth certificate' },
          { 'confirmation_code' => 'code2', 'attachment_id' => 'Marriage certificate' }
        ]
      }

      allow(Flipper).to receive(:enabled?).with(:champva_supporting_docs_ordering).and_return(true)

      allow(PersistentAttachments::MilitaryRecords).to receive(:find_by)
        .with(guid: 'code1')
        .and_return(double('Record1', created_at: earlier_time, file: double(id: 'file2')))
      allow(PersistentAttachments::MilitaryRecords).to receive(:find_by)
        .with(guid: 'code2')
        .and_return(double('Record2', created_at: later_time, file: double(id: 'file1')))

      result = form.supporting_document_ids(non_ohi_data)
      expect(result).to eq(['Birth certificate', 'Marriage certificate'])
    end

    it 'preserves created_at-only ordering when created_at timestamps are equal and flipper is disabled' do
      equal_time = Time.zone.now
      tie_break_data = {
        'supporting_docs' => [
          { 'confirmation_code' => 'code1', 'attachment_id' => 'Front of insurance card' },
          { 'confirmation_code' => 'code2', 'attachment_id' => 'VA form 10-7959c' }
        ]
      }

      allow(Flipper).to receive(:enabled?).with(:champva_supporting_docs_ordering).and_return(false)

      # Simulate non-deterministic DB retrieval order for equal created_at values.
      allow(PersistentAttachments::MilitaryRecords).to receive(:find_by)
        .with(guid: 'code1')
        .and_return(double('Record1', created_at: equal_time, file: double(id: 'file2')))
      allow(PersistentAttachments::MilitaryRecords).to receive(:find_by)
        .with(guid: 'code2')
        .and_return(double('Record2', created_at: equal_time, file: double(id: 'file1')))

      result = form.supporting_document_ids(tie_break_data)
      expect(result).to eq(['Front of insurance card', 'VA form 10-7959c'])
    end
  end

  describe '#applicant_pdf_count' do
    it 'returns ceiling of applicants count divided by ADDITIONAL_PDF_COUNT' do
      # VHA1010d has ADDITIONAL_PDF_COUNT=3, so 2 applicants / 3 = ceil(0.67) = 1
      result = form.applicant_pdf_count(form_data)
      expect(result).to eq(1)
    end

    it 'returns more than 1 when applicants exceed ADDITIONAL_PDF_COUNT' do
      many_applicants_data = form_data.merge(
        'applicants' => Array.new(4) { { 'first_name' => 'Test' } }
      )
      # 4 applicants / 3 = ceil(1.33) = 2
      result = form.applicant_pdf_count(many_applicants_data)
      expect(result).to eq(2)
    end

    it 'returns 1 when no applicants are present' do
      result = form.applicant_pdf_count({ 'applicants' => nil })
      expect(result).to eq(1)
    end

    it 'uses ADDITIONAL_PDF_KEY from the form class' do
      # VHA107959a uses ADDITIONAL_PDF_KEY='claims' and ADDITIONAL_PDF_COUNT=1
      claims_data = { 'claims' => [{ 'id' => 1 }] }
      claims_form = IvcChampva::VHA107959a.new(claims_data)
      result = claims_form.applicant_pdf_count(claims_data)
      expect(result).to eq(1)
    end
  end

  describe '#build_attachment_ids' do
    before do
      allow(PersistentAttachments::MilitaryRecords).to receive(:find_by)
        .and_return(double('Record', created_at: Time.zone.now, file: double(id: 'file1')))
    end

    it 'builds default attachment IDs with form_id prefix and supporting doc IDs' do
      result = form.build_attachment_ids('vha_10_10d', form_data, 1)
      expect(result).to eq(%w[vha_10_10d doc1 doc2])
    end
  end

  describe '#build_default_attachment_ids' do
    before do
      allow(PersistentAttachments::MilitaryRecords).to receive(:find_by)
        .and_return(double('Record', created_at: Time.zone.now, file: double(id: 'file1')))
    end

    it 'creates an array with form_id repeated for main pages plus supporting doc IDs' do
      result = form.build_default_attachment_ids('vha_10_10d', form_data, 2)
      expect(result).to eq(%w[vha_10_10d vha_10_10d doc1 doc2])
    end

    it 'handles submissions with no supporting docs' do
      result = form.build_default_attachment_ids('vha_10_10d', { 'form_number' => '10-10D' }, 1)
      expect(result).to eq(['vha_10_10d'])
    end
  end

  describe '#build_stamped_page' do
    let(:blank_page_path) { 'tmp/test_blank.pdf' }
    let(:claims_form) do
      IvcChampva::VHA107959a.new(
        'form_number' => '10-7959A',
        'has_claim_docs' => false
      )
    end

    before do
      allow(IvcChampva::Attachments).to receive(:get_blank_page).and_return(blank_page_path)
      allow(IvcChampva::PdfStamper).to receive(:stamp_metadata_items)
      allow(IvcChampva::FormVersionManager).to receive(:get_legacy_form_id)
        .with('vha_10_7959a').and_return('vha_10_7959a')
      allow(FileUtils).to receive(:mv)
      allow(Flipper).to receive(:enabled?).with(:champva_claims_duty_to_assist).and_return(true)
    end

    it 'returns a hash with file_path and attachment_id' do
      result = claims_form.build_stamped_page

      expect(result).to be_a(Hash)
      expect(result[:file_path]).to include('_vha_10_7959a_form_page.pdf')
      expect(result[:attachment_id]).to eq('Duty to Assist')
    end

    it 'stamps the blank page with form metadata' do
      expect(IvcChampva::PdfStamper).to receive(:stamp_metadata_items)
        .with(blank_page_path, hash_including('provider_name'))

      claims_form.build_stamped_page
    end

    it 'returns nil when form has no stamp_metadata method' do
      result = form.build_stamped_page
      expect(result).to be_nil
    end
  end

  describe '#add_blank_doc_and_stamp' do
    let(:controller) { IvcChampva::V1::UploadsController.new }
    let(:parsed_form_data) { { 'form_number' => '10-10D', 'supporting_docs' => [] } }

    it 'does nothing when form has no stamp_metadata method' do
      # VHA1010d does not define stamp_metadata, so this should be a no-op
      no_stamp_form = IvcChampva::VHA1010d.new({})
      expect(IvcChampva::PdfStamper).not_to receive(:stamp_metadata_items)

      no_stamp_form.add_blank_doc_and_stamp(parsed_form_data, controller)
    end
  end

  describe '#prepare_submission_data' do
    let(:current_user) { double('User', loa: { current: 3 }) }

    before do
      allow(PersistentAttachments::MilitaryRecords).to receive(:find_by)
        .and_return(double('Record', created_at: Time.zone.now, file: double(id: 'file1')))
    end

    context 'when champva_claims_duty_to_assist is enabled' do
      before do
        allow(Flipper).to receive(:enabled?).with(:champva_claims_duty_to_assist, current_user).and_return(true)
      end

      it 'returns attachment_ids and nil stamped_page for forms without stamp_metadata' do
        attachment_ids, stamped_page = form.prepare_submission_data('vha_10_10d', form_data, current_user)

        expect(attachment_ids).to include('vha_10_10d')
        expect(stamped_page).to be_nil
      end
    end

    context 'when champva_claims_duty_to_assist is disabled' do
      before do
        allow(Flipper).to receive(:enabled?).with(:champva_claims_duty_to_assist, current_user).and_return(false)
      end

      it 'returns attachment_ids and nil stamped_page' do
        attachment_ids, stamped_page = form.prepare_submission_data('vha_10_10d', form_data, current_user)

        expect(attachment_ids).to include('vha_10_10d')
        expect(stamped_page).to be_nil
      end
    end

    it 'ensures attachment_ids is never empty' do
      allow(Flipper).to receive(:enabled?).with(:champva_claims_duty_to_assist, current_user).and_return(false)
      empty_data = { 'form_number' => '10-10D' }
      empty_form = IvcChampva::VHA1010d.new(empty_data)

      attachment_ids, = empty_form.prepare_submission_data('vha_10_10d', empty_data, current_user)

      expect(attachment_ids).to eq(['vha_10_10d'])
    end
  end
end
