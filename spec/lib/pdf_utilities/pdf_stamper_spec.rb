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

      it 'logs and raises error in #stamp_pdf' do
        allow(HexaPDF::CLI::Application).to receive(:new).and_raise(error_message)
        expect(logging_monitor_double).not_to receive(:track_request)
        expect do
          instance.run random_pdf
        end.to raise_error(SystemExit).and output(/might indicate a faulty PDF/).to_stderr
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
      end
    end
  end
end
