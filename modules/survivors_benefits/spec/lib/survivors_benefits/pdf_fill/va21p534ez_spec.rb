# frozen_string_literal: true

require 'rails_helper'
require 'lib/pdf_fill/fill_form_examples'
require 'survivors_benefits/pdf_fill/va21p534ez'
require 'pdf_utilities/datestamp_pdf'
require 'pdf/reader'
require 'fileutils'
require 'tmpdir'
require 'timecop'

describe SurvivorsBenefits::PdfFill::Va21p534ez do
  include SchemaMatchers

  before do
    allow(Flipper).to receive(:enabled?).with(:survivors_benefits_form_2025_version_enabled).and_return(false)
  end

  describe '.section_classes' do
    it 'uses top-level V2022 section classes when the 2025 feature flag is disabled' do
      allow(Flipper).to receive(:enabled?).with(:survivors_benefits_form_2025_version_enabled).and_return(false)

      expect(described_class.section_classes.first).to eq(SurvivorsBenefits::PdfFill::Section1)
      expect(described_class.section_classes.last).to eq(SurvivorsBenefits::PdfFill::Section12)
    end

    it 'uses namespaced V2025 section classes when the 2025 feature flag is enabled' do
      allow(Flipper).to receive(:enabled?).with(:survivors_benefits_form_2025_version_enabled).and_return(true)

      expect(described_class.section_classes.first).to eq(SurvivorsBenefits::PdfFill::V2025::Section1)
      expect(described_class.section_classes.last).to eq(SurvivorsBenefits::PdfFill::V2025::Section12)
    end
  end

  describe 'feature-flagged class configuration' do
    context 'when the 2025 feature flag is disabled' do
      before do
        allow(Flipper).to receive(:enabled?).with(:survivors_benefits_form_2025_version_enabled).and_return(false)
      end

      it 'uses the V2022 template path and TEMPLATE alias' do
        expect(described_class.template_path).to end_with('/pdfs/V2022/21P-534EZ.pdf')
        expect(described_class::TEMPLATE).to eq(described_class.template_path)
      end

      it 'uses the V2022 signature field and SIGNATURE_FIELD_NAME alias' do
        expect(described_class.signature_field_name).to eq('form1[0].#subform[218].SignatureField1[1]')
        expect(described_class::SIGNATURE_FIELD_NAME).to eq(described_class.signature_field_name)
      end

      it 'uses the alternate V2022 signature field for custodian relationship' do
        form_data = { 'claimantRelationship' => 'CUSTODIAN_FILING_FOR_CHILD_UNDER_18' }

        expect(described_class.signature_field_name(form_data)).to eq('form1[0].#subform[218].SignatureField1[0]')
      end

      it 'uses V2022 merged KEY mapping and KEY alias' do
        expect(described_class.key['veteranFullName']['first'][:key])
          .to eq('form1[0].#subform[207].VeteransFirstName[0]')
        expect(described_class::KEY).to eq(described_class.key)
      end
    end

    context 'when the 2025 feature flag is enabled' do
      before do
        allow(Flipper).to receive(:enabled?).with(:survivors_benefits_form_2025_version_enabled).and_return(true)
      end

      it 'uses the V2025 template path and TEMPLATE alias' do
        expect(described_class.template_path).to end_with('/pdfs/V2025/21P-534EZ.pdf')
        expect(described_class::TEMPLATE).to eq(described_class.template_path)
      end

      it 'uses the V2025 signature field and SIGNATURE_FIELD_NAME alias' do
        expect(described_class.signature_field_name).to eq('form1[0].#subform[163].SignatureField1[1]')
        expect(described_class::SIGNATURE_FIELD_NAME).to eq(described_class.signature_field_name)
      end

      it 'uses the alternate V2025 signature field for custodian relationship' do
        form_data = { 'claimantRelationship' => 'CUSTODIAN_FILING_FOR_CHILD_UNDER_18' }

        expect(described_class.signature_field_name(form_data)).to eq('form1[0].#subform[163].SignatureField1[0]')
      end

      it 'uses V2025 merged KEY mapping and KEY alias' do
        merged_key = described_class.section_classes.each_with_object({}) do |section, acc|
          acc.merge!(section::KEY)
        end

        expect(described_class.section_classes.map(&:name))
          .to all(start_with('SurvivorsBenefits::PdfFill::V2025::'))
        expect(described_class.key).to eq(merged_key)
        expect(described_class::KEY).to eq(described_class.key)
      end
    end
  end

  describe '#to_pdf' do
    shared_examples 'merges the right keys for output fixtures' do
      it 'merges the right keys' do
        Timecop.freeze(Time.zone.parse('2025-10-27')) do
          files = %w[
            empty
            section-1 section-1_2
            section-2 section-2_1 section-2_2 section-2_3 section-2_4
            section-3 section-3_1 section-3_2 section-3_3 section-3_4 section-3_5 section-3_6 section-3_7
            section-3_8 section-3_9 section-3_10
            section-4 section-4_1 section-4_2 section-4_3 section-4_4
            section-5 section-5_1 section-5_2
            section-6 section-6_1 section-6_2
            section-7 section-7_1 section-7_2
            section-8 section-8_1
            section-9 section-9_1 section-9_2 section-9_3 section-9_4
            section-10 section-10_1 section-10_2 section-10_3 section-10_4 section-10_5
            section-11 section-11_1 section-11_2 section-11_3
            section-12 section-12_1
          ]
          files.each do |file|
            f1 = File.read File.join(__dir__, 'input', "21P-534EZ_#{file}.json")

            claim = SurvivorsBenefits::SavedClaim.new(form: f1)

            form_id = SurvivorsBenefits::FORM_ID
            form_class = SurvivorsBenefits::PdfFill::Va21p534ez
            fill_options = {
              created_at: '2025-10-08'
            }
            merged_form_data = form_class.new(claim.parsed_form).merge_fields(fill_options)
            submit_date = Utilities::DateParser.parse(
              fill_options[:created_at]
            )

            hash_converter = PdfFill::Filler.make_hash_converter(form_id, form_class, submit_date, fill_options)
            new_hash = hash_converter.transform_data(form_data: merged_form_data, pdftk_keys: form_class::KEY)

            f2 = File.read File.join(__dir__, output_dir, "21P-534EZ_#{file}.json")
            data = JSON.parse(f2)

            filtered = new_hash.slice(*(new_hash.keys & data.keys))

            expect(filtered).to eq(data)
          end
        end
      end
    end

    context 'when the 2025 feature flag is disabled' do
      let(:output_dir) { 'output' }

      before do
        allow(Flipper).to receive(:enabled?).with(:survivors_benefits_form_2025_version_enabled).and_return(false)
      end

      include_examples 'merges the right keys for output fixtures'
    end

    context 'when the 2025 feature flag is enabled' do
      let(:output_dir) { File.join('output', 'V2025') }

      before do
        allow(Flipper).to receive(:enabled?).with(:survivors_benefits_form_2025_version_enabled).and_return(true)
      end

      include_examples 'merges the right keys for output fixtures'
    end
  end

  # Section 9's income widgets carry no /MaxLen and set the DoNotScroll flag, so a value wider than
  # the field is silently clipped with no visual cue that text was lost. Anything that does not fit
  # must therefore be replaced on the form by the overflow placeholder and printed in full on the
  # ATTACHMENT page.
  #
  # 'Social Security Administration' is the case that reaches production: the frontend hides the
  # payer question for Social Security income and injects that 30-character string at submit time
  # (vets-website addPayerNameForSocialSecurity), while Income_Payer[n] shows only 24 characters at
  # CourierNewPSMT 10pt. Measured field capacities: Income_Payer 24, Name_Of_Child 28,
  # Specify_Type_Of_Income 29.
  describe 'section 9 income overflow' do
    # Long enough to overflow every one of the three fields under test.
    let(:payer) { 'Social Security Administration' }
    let(:recipient_name) { 'Bartholomew Q Featherstonehaugh' }
    let(:income_type_other) { 'Quarterly royalty distribution' }

    let(:income_entries) do
      [{
        'recipient' => 'CHILD',
        'recipientName' => recipient_name,
        'incomeType' => 'OTHER',
        'incomeTypeOther' => income_type_other,
        'incomePayer' => payer,
        'monthlyIncome' => 1500
      }]
    end

    # Runs the same path the real submission takes: merge_fields, then a hash converter built with
    # extras_redesign: true so it uses ExtrasGeneratorV2 (what SavedClaim#to_stamped_pdf passes).
    def fill_section9(entries)
      form_data = {
        'veteranSocialSecurityNumber' => '123456789',
        'incomeSourcesCount' => 'ONE_TO_FOUR_SOURCES',
        'incomeEntries' => entries
      }
      merged = described_class.new(form_data).merge_fields
      converter = PdfFill::Filler.make_hash_converter(
        SurvivorsBenefits::FORM_ID, described_class,
        Utilities::DateParser.parse('2025-10-08'), { extras_redesign: true }, merged
      )
      [converter.transform_data(form_data: merged, pdftk_keys: described_class.key), converter.extras_generator]
    end

    # The generated extras PDF is the actual ATTACHMENT page, so assert against its text rather than
    # the generator's internals -- the assertion then holds for either question shape. PDF::Reader
    # recovers the glyphs but not the inter-word spacing from Prawn's SourceSans3 subset, so strip
    # whitespace from both sides of the comparison (see #squished).
    def attachment_text(extras)
      path = extras.generate
      @extras_paths << path
      squished(PDF::Reader.new(path).pages.map(&:text).join("\n"))
    end

    def squished(value)
      value.gsub(/\s+/, '')
    end

    before { @extras_paths = [] }

    after { @extras_paths.each { |path| Common::FileHelpers.delete_file_if_exists(path) } }

    shared_examples 'overflows the section 9 income fields' do |subform|
      let(:placeholder) { PdfFill::ExtrasGeneratorV2.new.placeholder_text }

      it 'writes the placeholder into the income payer widget instead of clipping it' do
        pdftk_form, = fill_section9(income_entries)

        expect(pdftk_form["form1[0].##{subform}.Income_Payer[0]"]).to eq(placeholder)
      end

      it 'prints the full income payer on the attachment page' do
        _, extras = fill_section9(income_entries)

        expect(extras.text?).to be(true)
        expect(attachment_text(extras)).to include(squished(payer))
      end

      it 'overflows the recipient name and other-income-type fields too' do
        pdftk_form, extras = fill_section9(income_entries)
        text = attachment_text(extras)

        expect(pdftk_form["form1[0].##{subform}.Name_Of_Child[0]"]).to eq(placeholder)
        expect(pdftk_form["form1[0].##{subform}.Specify_Type_Of_Income[3]"]).to eq(placeholder)
        expect(text).to include(squished(recipient_name))
        expect(text).to include(squished(income_type_other))
      end

      it 'leaves values that fit on the form and off the attachment page' do
        pdftk_form, extras = fill_section9(
          [income_entries.first.merge('incomePayer' => 'HUD', 'recipientName' => 'Jane Doe',
                                      'incomeTypeOther' => 'Royalties')]
        )

        expect(pdftk_form["form1[0].##{subform}.Income_Payer[0]"]).to eq('HUD')
        expect(pdftk_form["form1[0].##{subform}.Name_Of_Child[0]"]).to eq('Jane Doe')
        expect(extras.text?).to be(false)
      end
    end

    context 'when the 2025 feature flag is disabled' do
      before do
        allow(Flipper).to receive(:enabled?).with(:survivors_benefits_form_2025_version_enabled).and_return(false)
      end

      include_examples 'overflows the section 9 income fields', 'subform[215]'
    end

    context 'when the 2025 feature flag is enabled' do
      before do
        allow(Flipper).to receive(:enabled?).with(:survivors_benefits_form_2025_version_enabled).and_return(true)
      end

      include_examples 'overflows the section 9 income fields', 'subform[160]'
    end
  end

  describe '#merge_fields' do
    shared_examples 'section12 date signed field selection' do
      it 'uses dateSignedAlt for the custodian relationship' do
        form_data = {
          'veteranSocialSecurityNumber' => '123456789',
          'claimantRelationship' => 'CUSTODIAN_FILING_FOR_CHILD_UNDER_18',
          'dateSigned' => '2024-01-01'
        }

        merged_data = described_class.new(form_data).merge_fields

        expect(merged_data['dateSignedAlt']).to eq({ 'month' => '01', 'day' => '01', 'year' => '2024' })
        expect(merged_data).not_to have_key('dateSigned')
      end

      it 'uses dateSigned for non-custodian relationships' do
        form_data = {
          'veteranSocialSecurityNumber' => '123456789',
          'claimantRelationship' => 'SURVIVING_SPOUSE',
          'dateSigned' => '2024-01-01'
        }

        merged_data = described_class.new(form_data).merge_fields

        expect(merged_data['dateSigned']).to eq({ 'month' => '01', 'day' => '01', 'year' => '2024' })
        expect(merged_data).not_to have_key('dateSignedAlt')
      end
    end

    # The output-fixture harness slices to the intersection of produced and expected keys, so it
    # can only assert which widgets ARE written. These cover the other half: that the unused
    # signature-date widget set stays empty.
    shared_examples 'section12 acroform widget selection' do |subform|
      def date_signed_keys(form_data)
        merged_data = SurvivorsBenefits::PdfFill::Va21p534ez.new(form_data).merge_fields
        hash_converter = PdfFill::Filler.make_hash_converter(
          SurvivorsBenefits::FORM_ID, SurvivorsBenefits::PdfFill::Va21p534ez,
          Utilities::DateParser.parse('2025-10-08'), {}
        )
        transformed = hash_converter.transform_data(
          form_data: merged_data, pdftk_keys: SurvivorsBenefits::PdfFill::Va21p534ez.key
        )
        transformed.keys.grep(/Date_Signed_/)
      end

      it 'writes only the §14B widgets for a custodian' do
        keys = date_signed_keys(
          'veteranSocialSecurityNumber' => '123456789',
          'claimantRelationship' => 'CUSTODIAN_FILING_FOR_CHILD_UNDER_18',
          'dateSigned' => '2024-01-01'
        )

        expect(keys).to contain_exactly(
          "form1[0].#subform[#{subform}].Date_Signed_Month[0]",
          "form1[0].#subform[#{subform}].Date_Signed_Day[0]",
          "form1[0].#subform[#{subform}].Date_Signed_Year[0]"
        )
      end

      it 'writes only the §12B widgets for non-custodian relationships' do
        keys = date_signed_keys(
          'veteranSocialSecurityNumber' => '123456789',
          'claimantRelationship' => 'SURVIVING_SPOUSE',
          'dateSigned' => '2024-01-01'
        )

        expect(keys).to contain_exactly(
          "form1[0].#subform[#{subform}].Date_Signed_Month[1]",
          "form1[0].#subform[#{subform}].Date_Signed_Day[1]",
          "form1[0].#subform[#{subform}].Date_Signed_Year[1]"
        )
      end
    end

    context 'when the 2025 feature flag is disabled' do
      before do
        allow(Flipper).to receive(:enabled?).with(:survivors_benefits_form_2025_version_enabled).and_return(false)
      end

      include_examples 'section12 date signed field selection'
      include_examples 'section12 acroform widget selection', 218
    end

    context 'when the 2025 feature flag is enabled' do
      before do
        allow(Flipper).to receive(:enabled?).with(:survivors_benefits_form_2025_version_enabled).and_return(true)
      end

      include_examples 'section12 date signed field selection'
      include_examples 'section12 acroform widget selection', 163
    end
  end

  describe '.stamp_signature' do
    let(:pdf_path) { '/tmp/test_form.pdf' }
    let(:stamped_path) { '/tmp/test_form_stamped.pdf' }
    let(:datestamp_instance) { instance_double(PDFUtilities::DatestampPdf) }
    let(:coordinates) { { x: 123, y: 456, page_number: 7 } }

    before do
      allow(PDFUtilities::DatestampPdf).to receive(:new).with(pdf_path).and_return(datestamp_instance)
      allow(described_class).to receive(:signature_overlay_coordinates).and_return(coordinates)
    end

    it 'stamps the signature when present' do
      form_data = { 'claimantSignature' => 'Jane Doe' }

      expect(datestamp_instance).to receive(:run).with(
        text: 'Jane Doe',
        x: coordinates[:x],
        y: coordinates[:y],
        page_number: coordinates[:page_number],
        size: described_class::SIGNATURE_FONT_SIZE,
        text_only: true,
        timestamp: '',
        template: pdf_path,
        multistamp: true
      ).and_return(stamped_path)

      result = described_class.stamp_signature(pdf_path, form_data)

      expect(described_class).to have_received(:signature_overlay_coordinates).with(pdf_path, form_data:)
      expect(result).to eq(stamped_path)
    end

    it 'builds the signature from yourName when signature is blank' do
      expect(datestamp_instance).to receive(:run).and_return(stamped_path)

      result = described_class.stamp_signature(pdf_path,
                                               { 'yourName' => { 'first' => 'Jane', 'middle' => 'Q',
                                                                 'last' => 'Doe' },
                                                 'claimantSignature' => '' })
      expect(result).to eq(stamped_path)
    end

    it 'prefers yourName over claimantFullName for fallback signer text' do
      expect(datestamp_instance).to receive(:run).with(
        hash_including(text: 'Correct Signer')
      ).and_return(stamped_path)

      result = described_class.stamp_signature(
        pdf_path,
        {
          'yourName' => { 'first' => 'Correct', 'last' => 'Signer' },
          'claimantFullName' => { 'first' => 'Wrong', 'last' => 'Person' },
          'claimantSignature' => ''
        }
      )

      expect(result).to eq(stamped_path)
    end

    it 'uses statement of truth signature when present' do
      expect(datestamp_instance).to receive(:run).with(
        text: 'Jane Q Doe',
        x: coordinates[:x],
        y: coordinates[:y],
        page_number: coordinates[:page_number],
        size: described_class::SIGNATURE_FONT_SIZE,
        text_only: true,
        timestamp: '',
        template: pdf_path,
        multistamp: true
      ).and_return(stamped_path)

      result = described_class.stamp_signature(pdf_path,
                                               { 'statementOfTruthSignature' => 'Jane Q Doe',
                                                 'claimantSignature' => '' })
      expect(result).to eq(stamped_path)
    end

    it 'returns the original PDF when signature is missing' do
      result = described_class.stamp_signature(pdf_path, { 'claimantSignature' => '' })
      expect(result).to eq(pdf_path)
      expect(PDFUtilities::DatestampPdf).not_to have_received(:new)
    end

    it 'returns nil when pdf_path is nil' do
      result = described_class.stamp_signature(nil, { 'claimantSignature' => 'Jane Doe' })

      expect(result).to be_nil
      expect(described_class).not_to have_received(:signature_overlay_coordinates)
      expect(PDFUtilities::DatestampPdf).not_to have_received(:new)
    end

    it 'falls back to template coordinates when filled PDF lacks widget' do
      form_data = { 'claimantRelationship' => 'CUSTODIAN_FILING_FOR_CHILD_UNDER_18', 'claimantSignature' => 'Jane Doe' }

      allow(described_class).to receive(:signature_overlay_coordinates).with(pdf_path, form_data:).and_return(nil)
      allow(described_class).to receive(:signature_overlay_coordinates)
        .with(described_class::TEMPLATE, form_data:).and_return(coordinates)

      expect(datestamp_instance).to receive(:run).and_return(stamped_path)

      result = described_class.stamp_signature(pdf_path, form_data)
      expect(result).to eq(stamped_path)
    end

    it 'rescues errors and returns the original PDF path' do
      allow(datestamp_instance).to receive(:run).and_raise(StandardError, 'boom')

      result = described_class.stamp_signature(pdf_path, { 'claimantSignature' => 'Jane Doe' })
      expect(result).to eq(pdf_path)
    end
  end

  describe '.stamp_submission_footer' do
    let(:timestamp) { Time.utc(2023, 12, 13, 11, 30) }

    it 'returns the original PDF (untouched) when the timestamp is blank' do
      expect(HexaPDF::Document).not_to receive(:open)

      expect(described_class.stamp_submission_footer('/tmp/does_not_matter.pdf', nil))
        .to eq('/tmp/does_not_matter.pdf')
    end

    it 'returns nil (untouched) when the pdf path is blank' do
      expect(HexaPDF::Document).not_to receive(:open)

      expect(described_class.stamp_submission_footer(nil, timestamp)).to be_nil
    end

    it 'fails open on stamping errors: logs, emits a metric, and returns the original PDF' do
      allow(HexaPDF::Document).to receive(:open).and_raise(StandardError, 'boom')
      allow(Rails.logger).to receive(:error)
      allow(StatsD).to receive(:increment)

      result = described_class.stamp_submission_footer('/tmp/x.pdf', timestamp)

      expect(result).to eq('/tmp/x.pdf')
      expect(StatsD).to have_received(:increment).with(described_class::SUBMISSION_STAMP_ERROR_METRIC)
    end

    context 'with a real multi-page PDF' do
      let(:source) { "#{Common::FileHelpers.random_file_path}.pdf" }
      let(:outputs) { [] }

      before do
        doc = HexaPDF::Document.new
        2.times { doc.pages.add }
        doc.write(source)
      end

      after do
        Common::FileHelpers.delete_file_if_exists(source)
        outputs.each { |p| Common::FileHelpers.delete_file_if_exists(p) }
      end

      it 'renders the two-line watermark (timestamp + IAL2 auth) on every page' do
        out = described_class.stamp_submission_footer(source, timestamp)
        outputs << out

        reader = PDF::Reader.new(out)
        expect(reader.pages.size).to eq(2)
        reader.pages.each do |page|
          expect(page.text).to include('Signed electronically and submitted via VA.gov at 11:30 UTC 2023-12-13.')
          expect(page.text).to include('Signee signed with an identity-verified account.')
        end
      end
    end
  end

  describe '.signers_full_name' do
    it 'prefers filingCustodianFullName over the residual yourName key' do
      form_data = {
        'filingCustodianFullName' => { 'first' => 'Jane', 'middle' => 'Quincy', 'last' => 'Custodian' },
        'yourName' => { 'first' => 'Stale', 'last' => 'Value' }
      }

      expect(described_class.signers_full_name(form_data)).to eq('Jane Quincy Custodian')
    end

    it 'still reads yourName when no custodian is filing' do
      expect(described_class.signers_full_name({ 'yourName' => { 'first' => 'Pat', 'last' => 'Spouse' } }))
        .to eq('Pat Spouse')
    end

    it 'never falls back to claimantFullName, which holds the child name for a custodian filing' do
      form_data = { 'claimantFullName' => { 'first' => 'Child', 'last' => 'Name' } }

      expect(described_class.signers_full_name(form_data)).to eq('')
    end

    it 'returns an empty string for nil form data' do
      expect(described_class.signers_full_name(nil)).to eq('')
    end
  end
end
