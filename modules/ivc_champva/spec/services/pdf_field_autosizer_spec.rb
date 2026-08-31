# frozen_string_literal: true

require 'rails_helper'
require 'hexapdf'

describe IvcChampva::PdfFieldAutosizer do
  let(:template_base) { IvcChampva::PdfFiller::TEMPLATE_BASE }

  describe '.apply!' do
    context 'when the form has known overflow-prone fields' do
      it 'sets the field font size to auto (0) so pdftk can shrink long addresses to fit' do
        Dir.mktmpdir do |dir|
          tmp_path = File.join(dir, 'vha_10_10d_2027.pdf')
          FileUtils.cp("#{template_base}/vha_10_10d_2027.pdf", tmp_path)

          described_class.apply!(tmp_path, 'vha_10_10d_2027')

          doc = HexaPDF::Document.open(tmp_path)
          field = doc.acro_form.each_field.find do |f|
            f.full_field_name == 'form1[0].#subform[0].STREETADDRESS[0]'
          end

          expect(field[:DA]).to match(%r{\A/\S+ 0 Tf})
        end
      end
    end

    context 'when the form has no configured fields' do
      it 'does not modify the file' do
        Dir.mktmpdir do |dir|
          tmp_path = File.join(dir, 'vha_10_7959a_2027.pdf')
          FileUtils.cp("#{template_base}/vha_10_7959a_2027.pdf", tmp_path)
          original_contents = File.binread(tmp_path)

          described_class.apply!(tmp_path, 'vha_10_7959a_2027')

          expect(File.binread(tmp_path)).to eq(original_contents)
        end
      end
    end
  end
end
