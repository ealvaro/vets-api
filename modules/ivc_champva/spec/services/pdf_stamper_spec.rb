# frozen_string_literal: true

require 'rails_helper'
require IvcChampva::Engine.root.join('spec', 'spec_helper.rb')

describe IvcChampva::PdfStamper do
  let(:test_payload) { 'vha_10_10d_extended' }
  let(:data) { JSON.parse(File.read("modules/ivc_champva/spec/fixtures/form_json/#{test_payload}.json")) }
  let(:form_model) { 'vha_10_10d_2027' }
  let(:form) { "IvcChampva::#{form_model.titleize.gsub(' ', '')}".constantize.new(data) }
  let(:template_path) { "modules/ivc_champva/templates/#{form_model}.pdf" }
  let(:path) { 'tmp/pii_stuff.pdf' }

  describe '.stamp_pdf' do
    subject(:stamp_pdf) { described_class.stamp_pdf(path, form, 2) }

    before do
      FileUtils.copy(template_path, path)
      monitor_instance = instance_double(IvcChampva::Monitor)
      allow(described_class).to receive(:monitor).and_return(monitor_instance)
      allow(monitor_instance).to receive(:track_pdf_stamper_error)
    end

    after do
      FileUtils.rm_f(path)
    end

    context 'when everything works fine' do
      before do
        allow(described_class).to receive_messages(stamp_signature: nil, stamp_auth_text: nil,
                                                   stamp_submission_date: nil)
      end

      it 'does not raise any errors' do
        expect { stamp_pdf }.not_to raise_error
        expect(described_class).to have_received(:stamp_signature).with(path, form)
        expect(described_class).to have_received(:stamp_auth_text).with(path, 2)
        expect(described_class).to have_received(:stamp_submission_date).with(path, form.submission_date_stamps)
      end
    end

    context 'when given characters outside of the Windows-1252 character set' do
      let(:data) do
        JSON.parse(File.read("modules/ivc_champva/spec/fixtures/form_json/#{test_payload}.json")).tap do |d|
          d['statement_of_truth_signature'] = "Eyl\u00fcl \u00c7amc\u0131"
        end
      end

      it 'removes the unsupported characters and does not throw an error' do
        expect { stamp_pdf }.not_to raise_error
      end
    end

    context 'when the file at the stamped_template_path is missing' do
      before do
        FileUtils.rm_f(path)
      end

      it 'raises an exception' do
        expect { stamp_pdf }.to raise_error(StandardError, "stamped template file does not exist: #{path}")
      end
    end

    context 'when stamping raises a PdfForms::PdftkError' do
      before do
        allow(described_class).to receive(:stamp_auth_text).and_raise(PdfForms::PdftkError,
                                                                      'pdftk error ./some_pii.pdf')
        allow(described_class).to receive_messages(stamp_signature: nil, stamp_submission_date: nil)
      end

      it 'logs it with no PII and raises a PdfForms::PdftkError' do
        expect { stamp_pdf }.to raise_error(PdfForms::PdftkError, 'pdftk error ./some_pii.pdf')
        expect(described_class.monitor).to have_received(:track_pdf_stamper_error) do |_, message|
          expect(message).to include('PdftkError:')
          expect(message).not_to include('some_pii')
        end
      end
    end

    context 'when stamping raises a SystemCallError such as Errno::ENOENT' do
      before do
        allow(described_class).to receive(:stamp_signature).and_raise(Errno::ENOENT, 'pii_stuff.pdf')
        allow(described_class).to receive_messages(stamp_auth_text: nil, stamp_submission_date: nil)
      end

      it 'logs it with no PII and raises a Errno::ENOENT' do
        expect { stamp_pdf }.to raise_error(Errno::ENOENT, 'No such file or directory - pii_stuff.pdf')
        expect(described_class.monitor).to have_received(:track_pdf_stamper_error) do |_, message|
          expect(message).to include('SystemCallError:')
          expect(message).not_to include('pii_stuff')
        end
      end
    end

    context 'when stamping raises a StandardError' do
      before do
        allow(described_class).to receive(:stamp_auth_text).and_raise(StandardError, 'oh no')
        allow(described_class).to receive_messages(stamp_signature: nil, stamp_submission_date: nil)
      end

      it 'logs it with no PII and raises a PdfForms::PdftkError' do
        expect { stamp_pdf }.to raise_error(StandardError, 'oh no')
        expect(described_class.monitor).to have_received(:track_pdf_stamper_error) do |_, message|
          expect(message).to include('CatchAll:')
        end
      end
    end
  end

  describe '.stamp_signature' do
    subject(:stamp_signature) { described_class.stamp_signature(path, form) }

    before do
      allow(File).to receive(:size).and_return(1, 2)
    end

    context 'when no stamps are needed' do
      before do
        allow(described_class).to receive(:stamp).and_return(true)
        stamp_signature
      end

      let(:test_payload) { 'vha_10_7959f_2' }
      let(:form_model) { test_payload }
      let(:stamps) { [] }

      it 'does not call :stamp' do
        expect(described_class).not_to have_received(:stamp)
      end
    end

    context 'when it is called with legitimate parameters' do
      before do
        allow(described_class).to receive(:multistamp).and_return(true)
        stamp_signature
      end

      let(:signature) { form.data['statement_of_truth_signature'] }
      let(:page_config) do
        [
          { type: :text, position: [40, 105] },
          { type: :new_page },
          { type: :new_page },
          { type: :new_page },
          { type: :new_page }
        ]
      end
    end

    context 'when not in production' do
      before do
        allow(Settings).to receive(:vsp_environment).and_return('development')
        allow(described_class).to receive(:stamp).and_return(true)
        allow(Rails.logger).to receive(:info)
      end

      it 'logs the desired stamp text for each stamp' do
        stamp_signature

        form.desired_stamps.each do |desired_stamp|
          expect(Rails.logger).to have_received(:info).with(
            "IVC Champva Forms - PdfStamper: desired stamp text: #{desired_stamp[:text]}"
          ).at_least(:once)
        end
      end

      it 'calls stamp for each desired stamp' do
        stamp_signature

        form.desired_stamps.each do |desired_stamp|
          expect(described_class).to have_received(:stamp).with(desired_stamp, path)
        end
      end
    end

    context 'when in production environment' do
      before do
        allow(Settings).to receive(:vsp_environment).and_return('production')
        allow(described_class).to receive(:stamp).and_return(true)
        allow(Rails.logger).to receive(:info)
      end

      it 'does not log the desired stamp text even when flipper is enabled' do
        stamp_signature

        form.desired_stamps.each do |desired_stamp|
          expect(Rails.logger).not_to have_received(:info).with(
            "IVC Champva Forms - PdfStamper: desired stamp text: #{desired_stamp[:text]}"
          )
        end
      end

      it 'still calls stamp for each desired stamp' do
        stamp_signature

        form.desired_stamps.each do |desired_stamp|
          expect(described_class).to have_received(:stamp).with(desired_stamp, path)
        end
      end
    end
  end

  describe '.multistamp' do
    subject(:multistamp) { described_class.multistamp(stamped_template_path, signature_text, page_configuration) }

    let(:stamped_template_path) { 'path/to/stamped_template.pdf' }
    let(:random_path) { 'tmp/000033337777BBBB111144448888CCCC' }
    let(:signature_text) { 'Signature Text' }
    let(:page_configuration) do
      [
        { type: :text, position: [40, 105] },
        { type: :new_page },
        { type: :new_page },
        { type: :new_page },
        { type: :new_page }
      ]
    end

    context 'when an error occurs during stamping' do
      before do
        allow(Prawn::Document).to receive(:generate).and_yield(pdf)
        allow(pdf).to receive(:draw_text).and_raise(StandardError, 'error drawing text')
        allow(pdf).to receive(:start_new_page)
        allow(Common::FileHelpers).to receive(:random_file_path).and_return(random_path)
        allow(Common::FileHelpers).to receive(:delete_file_if_exists)
      end

      let(:pdf) { instance_double(Prawn::Document) }

      it 'attempts to delete the temporary stamping file' do
        expect(Common::FileHelpers).to receive(:delete_file_if_exists).with(random_path)
        expect { multistamp }.to raise_error(StandardError, 'error drawing text')
      end

      context 'when deleting the temporary stamping file fails' do
        before do
          allow(Common::FileHelpers).to receive(:delete_file_if_exists).and_raise(Errno::ENOENT, random_path)
        end

        it 'proceeds gracefully' do
          expect { multistamp }.to raise_error(StandardError, 'error drawing text')
        end
      end
    end
  end

  describe '.stamp' do
    subject(:stamp) { described_class.stamp(desired_stamp, stamped_template_path) }

    let(:stamped_template_path) { 'path/to/stamped_template.pdf' }
    let(:current_file_path) { 'path/to/current_file.pdf' }
    let(:desired_stamp) do
      {
        coords: [10, 10],
        text: 'Sample Text',
        page: nil,
        font_size: 12
      }
    end

    context 'when an error occurs during stamping' do
      before do
        allow(PDFUtilities::DatestampPdf).to receive(:new).and_return(datestamp_instance)
        allow(datestamp_instance).to receive(:run).and_return(current_file_path)
        allow(File).to receive(:rename).and_raise(StandardError, 'rename error')
        allow(Common::FileHelpers).to receive(:delete_file_if_exists)
      end

      let(:datestamp_instance) { instance_double(PDFUtilities::DatestampPdf) }

      it 'attempts to delete the temporary stamping file' do
        expect(Common::FileHelpers).to receive(:delete_file_if_exists).with(current_file_path)
        expect { stamp }.to raise_error(StandardError, 'rename error')
      end

      context 'when deleting the temporary stamping file fails' do
        before do
          allow(Common::FileHelpers).to receive(:delete_file_if_exists).and_raise(Errno::ENOENT, current_file_path)
        end

        it 'proceeds gracefully' do
          expect { stamp }.to raise_error(StandardError, 'rename error')
        end
      end
    end
  end

  describe '.perform_multistamp' do
    subject(:perform_multistamp) { described_class.perform_multistamp(stamped_template_path, stamp_path) }

    let(:stamped_template_path) { 'path/to/stamped_template.pdf' }
    let(:stamp_path) { 'path/to/stamp.pdf' }
    let(:random_path) { 'tmp/000033337777BBBB111144448888CCCC' }
    let(:out_path) { "#{random_path}.pdf" }
    let(:pdftk_error_message) { 'java.lang.ClassCastException: pdftk crashed' }

    context 'when champva_pdf_stamper_use_hexapdf is enabled' do
      before do
        allow(Flipper).to receive(:enabled?).with(:champva_pdf_stamper_use_hexapdf).and_return(true)
        allow(Common::FileHelpers).to receive(:random_file_path).and_return(random_path)
        allow(described_class).to receive(:perform_multistamp_with_hexapdf)
        allow(File).to receive(:delete)
        allow(File).to receive(:rename)
      end

      it 'stamps the pdf using HexaPDF directly, without calling pdftk' do
        expect(PdfFill::Filler::PDF_FORMS).not_to receive(:multistamp)
        expect { perform_multistamp }.not_to raise_error

        expect(described_class).to have_received(:perform_multistamp_with_hexapdf).with(
          stamped_template_path, stamp_path, out_path
        )
        expect(File).to have_received(:delete).with(stamped_template_path)
        expect(File).to have_received(:rename).with(out_path, stamped_template_path)
      end

      context 'when an error occurs during stamping' do
        before do
          allow(Common::FileHelpers).to receive(:delete_file_if_exists)
          allow(described_class).to receive(:perform_multistamp_with_hexapdf)
            .and_raise(StandardError, 'hexapdf error')
        end

        it 'attempts to delete the temporary stamping file' do
          expect(Common::FileHelpers).to receive(:delete_file_if_exists).with(out_path)
          expect { perform_multistamp }.to raise_error(StandardError, 'hexapdf error')
        end

        context 'when deleting the temporary stamping file fails' do
          before do
            allow(Common::FileHelpers).to receive(:delete_file_if_exists).and_raise(Errno::ENOENT, out_path)
          end

          it 'proceeds gracefully' do
            expect { perform_multistamp }.to raise_error(StandardError, 'hexapdf error')
          end
        end
      end
    end

    context 'when champva_pdf_stamper_use_hexapdf is disabled' do
      before do
        allow(Flipper).to receive(:enabled?).with(:champva_pdf_stamper_use_hexapdf).and_return(false)
        allow(Common::FileHelpers).to receive(:random_file_path).and_return(random_path)
      end

      context 'when pdftk succeeds' do
        before do
          allow(PdfFill::Filler::PDF_FORMS).to receive(:multistamp)
          allow(described_class).to receive(:perform_multistamp_with_hexapdf)
          allow(File).to receive(:delete)
          allow(File).to receive(:rename)
        end

        it 'stamps via pdftk and does not fall back to HexaPDF' do
          expect { perform_multistamp }.not_to raise_error

          expect(PdfFill::Filler::PDF_FORMS).to have_received(:multistamp).with(
            stamped_template_path, stamp_path, out_path
          )
          expect(described_class).not_to have_received(:perform_multistamp_with_hexapdf)
          expect(File).to have_received(:delete).with(stamped_template_path)
          expect(File).to have_received(:rename).with(out_path, stamped_template_path)
        end
      end

      context 'when an error occurs during stamping' do
        before do
          allow(Common::FileHelpers).to receive(:delete_file_if_exists)
          allow(PdfFill::Filler::PDF_FORMS).to receive(:multistamp).and_raise(StandardError, 'pdftk error')
        end

        it 'attempts to delete the temporary stamping file' do
          expect(Common::FileHelpers).to receive(:delete_file_if_exists).with(out_path)
          expect { perform_multistamp }.to raise_error(StandardError, 'pdftk error')
        end

        context 'when deleting the temporary stamping file fails' do
          before do
            allow(Common::FileHelpers).to receive(:delete_file_if_exists).and_raise(Errno::ENOENT, out_path)
          end

          it 'proceeds gracefully' do
            expect { perform_multistamp }.to raise_error(StandardError, 'pdftk error')
          end
        end
      end

      context 'when pdftk raises PdfForms::PdftkError' do
        before do
          allow(Common::FileHelpers).to receive(:delete_file_if_exists)
          allow(PdfFill::Filler::PDF_FORMS).to receive(:multistamp)
            .and_raise(PdfForms::PdftkError, pdftk_error_message)
          allow(StatsD).to receive(:increment)
          allow(described_class).to receive(:perform_multistamp_with_hexapdf)
          allow(File).to receive(:delete)
          allow(File).to receive(:rename)
        end

        it 'falls back to HexaPDF watermark stamping instead of raising' do
          expect { perform_multistamp }.not_to raise_error

          expect(described_class).to have_received(:perform_multistamp_with_hexapdf).with(
            stamped_template_path, stamp_path, out_path
          )
          expect(StatsD).to have_received(:increment).with('api.ivc_champva.pdftk_fallback')
          expect(File).to have_received(:delete).with(stamped_template_path)
          expect(File).to have_received(:rename).with(out_path, stamped_template_path)
        end
      end

      context 'when the HexaPDF fallback itself fails' do
        before do
          allow(Common::FileHelpers).to receive(:delete_file_if_exists)
          allow(PdfFill::Filler::PDF_FORMS).to receive(:multistamp)
            .and_raise(PdfForms::PdftkError, pdftk_error_message)
          allow(StatsD).to receive(:increment)
          allow(described_class).to receive(:perform_multistamp_with_hexapdf)
            .and_raise(StandardError, 'hexapdf also failed')
        end

        it 'still cleans up and reraises, same as any other stamping failure' do
          expect(Common::FileHelpers).to receive(:delete_file_if_exists).with(out_path)
          expect { perform_multistamp }.to raise_error(StandardError, 'hexapdf also failed')
        end
      end
    end
  end

  describe '.verify' do
    subject(:verify) { described_class.verify('template_path') { double } }

    before { allow(File).to receive(:size).and_return(orig_size, stamped_size) }

    describe 'when verifying a stamp' do
      let(:orig_size) { 10_000 }

      context 'when the stamped file size is larger than the original' do
        let(:stamped_size) { orig_size + 1 }

        it 'succeeds' do
          expect { verify }.not_to raise_error
        end
      end

      context 'when the stamped file size is the same as the original' do
        let(:stamped_size) { orig_size }

        it 'raises an error message' do
          expect { verify }.to raise_error(
            'An error occurred while verifying stamp: The PDF remained unchanged upon stamping.'
          )
        end
      end

      context 'when the stamped file size is less than the original' do
        let(:stamped_size) { orig_size - 1 }

        it 'succeeds, since HexaPDF may recompress and shrink the file even when content was added' do
          expect { verify }.not_to raise_error
        end
      end
    end
  end

  describe '.verified_multistamp' do
    subject(:verified_multistamp) { described_class.verified_multistamp(path, signature_text, config) }

    before { allow(described_class).to receive(:verify).and_return(true) }

    context 'when signature_text is blank' do
      let(:path) { nil }
      let(:signature_text) { nil }
      let(:config) { nil }

      it 'raises an error' do
        expect { verified_multistamp }.to raise_error('The provided stamp content was empty.')
      end
    end
  end

  describe '.stamp_metadata_items' do
    let(:pdf_path) { 'tmp/test_stamp_metadata.pdf' }
    let(:stamp_path) { 'tmp/test_stamp_overlay' }
    let(:metadata) do
      {
        'provider_name' => 'Dr. Smith',
        'provider_phone' => '555-123-4567',
        'additional_comments' => 'Patient needs follow-up care'
      }
    end

    before do
      FileUtils.mkdir_p(File.dirname(pdf_path))
      Prawn::Document.generate(pdf_path) {}
      allow(Common::FileHelpers).to receive(:random_file_path).and_return(stamp_path)
      allow(Common::FileHelpers).to receive(:delete_file_if_exists).and_call_original
    end

    after do
      FileUtils.rm_f(pdf_path)
      FileUtils.rm_f(stamp_path)
    end

    it 'stamps all short metadata items successfully' do
      stamped, remaining = described_class.stamp_metadata_items(pdf_path, metadata)

      expect(stamped).to eq(%w[provider_name provider_phone additional_comments])
      expect(remaining).to eq({})
    end

    it 'handles long additional_comments with text wrapping' do
      long_metadata = metadata.merge('additional_comments' => 'A' * 300)

      stamped, remaining = described_class.stamp_metadata_items(pdf_path, long_metadata)

      expect(stamped).to include('additional_comments')
      expect(remaining).to be_empty
    end

    it 'respects the bottom margin and returns remaining items' do
      many_items = (1..50).each_with_object({}) { |i, h| h["field_#{i}"] = 'x' * 100 }

      stamped, remaining = described_class.stamp_metadata_items(pdf_path, many_items)

      expect(stamped.length).to be < 50
      expect(remaining).not_to be_empty
    end

    it 'cleans up the temp file' do
      described_class.stamp_metadata_items(pdf_path, metadata)

      expect(Common::FileHelpers).to have_received(:delete_file_if_exists).with(stamp_path)
    end

    it 'cleans up the temp file even when an error occurs during Prawn generation' do
      allow(Prawn::Document).to receive(:generate).and_raise(StandardError, 'prawn error')

      expect do
        described_class.stamp_metadata_items(pdf_path, metadata)
      end.to raise_error(StandardError, 'prawn error')

      expect(Common::FileHelpers).to have_received(:delete_file_if_exists).with(stamp_path)
    end
  end
end
