# frozen_string_literal: true

require 'rails_helper'
require 'common/file_helpers'
require 'pdf_utilities/pdf_stamper'

RSpec.describe PDFUtilities::PDFStamper do
  let(:random_pdf) { "#{Common::FileHelpers.random_file_path}.pdf" }
  let(:logging_monitor_double) { instance_double(Logging::Monitor, track_request: true) }
  let(:stamps) do
    [
      { text: 'VA.GOV', x: 5, y: 5, append_to_stamp: 'FOOBAR' }
    ]
  end

  before do
    HexaPDF::Composer.create(random_pdf)
    PDFUtilities::PDFStamper.register_stamps('TEST', stamps)

    allow(Logging::Monitor).to receive(:new).and_return(logging_monitor_double)
    allow(Flipper).to receive(:enabled?).with(:enable_hexapdf_watermark_direct_processing).and_return(false)
  end

  after do
    Common::FileHelpers.delete_file_if_exists(random_pdf)
  end

  describe '#run' do
    let(:instance) { PDFUtilities::PDFStamper.new('TEST') }

    def assert_pdf_stamp(file, stamp)
      pdf_reader = PDF::Reader.new(file)
      expect(pdf_reader.pages[0].text).to eq(stamp)
      File.delete(file)
    end

    it 'adds text with a datestamp at the given location' do
      Timecop.travel(Time.zone.local(1999, 12, 31, 23, 59, 59)) do
        out_path = instance.run random_pdf
        assert_pdf_stamp(out_path, 'VA.GOV 1999-12-31 11:59 PM UTC. FOOBAR')
      end
    end

    it 'applies a template to watermark the pdf' do
      Timecop.travel(Time.zone.local(1999, 12, 31, 23, 59, 59)) do
        stamp_template = [{ text: 'VA.GOV', x: 5, y: 5, append_to_stamp: 'FOOBAR', page_number: 0,
                            template: random_pdf, multistamp: true }]
        with_template = PDFUtilities::PDFStamper.new(stamp_template)
        out_path = with_template.run random_pdf
        assert_pdf_stamp(out_path, 'VA.GOV 1999-12-31 11:59 PM UTC. FOOBAR')
      end
    end

    context 'with alternate processing flag enabled' do
      before do
        allow(Flipper).to receive(:enabled?).with(:enable_hexapdf_watermark_direct_processing).and_return(true)
      end

      it 'adds text with a datestamp at the given location' do
        Timecop.travel(Time.zone.local(1999, 12, 31, 23, 59, 59)) do
          out_path = instance.run random_pdf
          assert_pdf_stamp(out_path, 'VA.GOV 1999-12-31 11:59 PM UTC. FOOBAR')
        end
      end
    end

    context 'error handling' do
      let(:error_message) { 'bad news bears' }

      it 'logs and raises error' do
        expect(logging_monitor_double).to receive(:track_request).at_least(:once).with(
          :error,
          /Failed to generate/,
          PDFUtilities::PDFStamper::STATS_KEY,
          anything
        )
        expect(instance).not_to receive(:generate_stamp)
        expect(instance).not_to receive(:stamp_pdf)
        expect do
          instance.run 'bad-pdf-path'
        end.to raise_error PDFUtilities::ExceptionHandling::PdfMissingError,
                           /Original PDF is missing/
      end

      it 'logs and raises error in #generate_stamp' do
        allow(HexaPDF::Composer).to receive(:create).and_raise(error_message)
        expect(logging_monitor_double).to receive(:track_request).at_least(:once).with(
          :error,
          /Failed to generate/,
          PDFUtilities::PDFStamper::STATS_KEY,
          anything
        )
        expect(instance).not_to receive(:stamp_pdf)
        expect { instance.run random_pdf }.to raise_error RuntimeError, /bad news bears/
      end

      it 'catches SystemExit errors in #stamp_pdf' do
        allow(HexaPDF::CLI::Application).to receive(:new).and_raise(SystemExit.new('oh no'))
        expect(logging_monitor_double).to receive(:track_request).at_least(:once).with(
          :error,
          /oh no/,
          PDFUtilities::PDFStamper::STATS_KEY,
          anything
        )
        expect do
          instance.run random_pdf
        end.to raise_error(StandardError, /oh no/)
      end

      context 'with alternate processing flag enabled' do
        before do
          allow(Flipper).to receive(:enabled?).with(:enable_hexapdf_watermark_direct_processing).and_return(true)
        end

        it 'catches the error, logs, and re-raises' do
          allow(HexaPDF::CLI::Application).to receive(:new).and_raise(error_message)

          expect(Common::FileHelpers).to receive(:delete_file_if_exists).at_least(:once)
          expect(logging_monitor_double).to receive(:track_request).with(:error,
                                                                         'Failed to generate stamp: bad news bears',
                                                                         'api.pdf_stamper.error',
                                                                         exception: RuntimeError,
                                                                         backtrace: Array)

          expect { instance.run random_pdf }.to raise_error RuntimeError, /bad news bears/
        end

        context 'when HexaPDF fails to serialize the watermarked pdf' do
          let(:hexapdf_error) { HexaPDF::Error.new("Can't serialize PDF stream without object identifier") }

          before do
            allow_any_instance_of(HexaPDF::CLI::Application).to receive(:parse).and_raise(hexapdf_error)
          end

          context 'when the pdftk fallback flag is off' do
            before do
              allow(Flipper).to receive(:enabled?).with(:enable_pdf_stamper_pdftk_fallback).and_return(false)
            end

            it 'raises the original HexaPDF error without attempting a fallback' do
              expect(PDFUtilities::PDFTK).not_to receive(:stamp)
              expect(PDFUtilities::PDFTK).not_to receive(:multistamp)

              expect { instance.run random_pdf }.to raise_error(HexaPDF::Error, /Can't serialize PDF stream/)
            end
          end

          context 'when the pdftk fallback flag is on' do
            before do
              allow(Flipper).to receive(:enabled?).with(:enable_pdf_stamper_pdftk_fallback).and_return(true)
            end

            it 'falls back to pdftk and succeeds' do
              expect(PDFUtilities::PDFTK).to receive(:stamp) do |_pdf_path, _stamp_path, stamped_pdf|
                FileUtils.touch(stamped_pdf)
              end
              expect(StatsD).to receive(:increment).with(PDFUtilities::PDFStamper::PDFTK_FALLBACK_STATS_KEY)

              out_path = instance.run(random_pdf)

              expect(File.exist?(out_path)).to be true
              File.delete(out_path)
            end

            it 'uses multistamp when the stamp set is a multistamp' do
              stamp_template = [{ text: 'VA.GOV', x: 5, y: 5, page_number: 0, template: random_pdf,
                                  multistamp: true }]
              with_template = PDFUtilities::PDFStamper.new(stamp_template)

              expect(PDFUtilities::PDFTK).to receive(:multistamp) do |_pdf_path, _stamp_path, stamped_pdf|
                FileUtils.touch(stamped_pdf)
              end

              out_path = with_template.run(random_pdf)

              expect(File.exist?(out_path)).to be true
              File.delete(out_path)
            end

            it 'still raises if the pdftk fallback also fails' do
              expect(PDFUtilities::PDFTK).to receive(:stamp).and_raise(PdfForms::PdftkError, 'still broken')

              expect { instance.run random_pdf }.to raise_error(PdfForms::PdftkError, /still broken/)
            end

            it 'logs a warning with the underlying exception alongside the fallback' do
              allow(PDFUtilities::PDFTK).to receive(:stamp) do |_pdf_path, _stamp_path, stamped_pdf|
                FileUtils.touch(stamped_pdf)
              end

              expect(Rails.logger).to receive(:warn).with(
                'PDFStamper: HexaPDF watermark failed, falling back to pdftk stamping',
                exception: hexapdf_error
              )

              out_path = instance.run(random_pdf)
              File.delete(out_path)
            end
          end
        end

        context 'when the HexaPDF watermark call hangs' do
          before do
            stub_const('PDFUtilities::PDFStamper::HEXAPDF_TIMEOUT', 0.1)
            allow_any_instance_of(HexaPDF::CLI::Application).to receive(:parse) { sleep 1 }
          end

          context 'when the pdftk fallback flag is off' do
            before do
              allow(Flipper).to receive(:enabled?).with(:enable_pdf_stamper_pdftk_fallback).and_return(false)
            end

            it 'raises a HexaPDF::Error instead of hanging indefinitely' do
              expect { instance.run random_pdf }.to raise_error(HexaPDF::Error, /timed out/)
            end
          end

          context 'when the pdftk fallback flag is on' do
            before do
              allow(Flipper).to receive(:enabled?).with(:enable_pdf_stamper_pdftk_fallback).and_return(true)
            end

            it 'falls back to pdftk instead of hanging indefinitely' do
              expect(PDFUtilities::PDFTK).to receive(:stamp) do |_pdf_path, _stamp_path, stamped_pdf|
                FileUtils.touch(stamped_pdf)
              end

              out_path = instance.run(random_pdf)

              expect(File.exist?(out_path)).to be true
              File.delete(out_path)
            end
          end
        end
      end
    end
  end
end
