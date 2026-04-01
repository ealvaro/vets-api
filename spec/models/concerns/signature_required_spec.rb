# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SignatureRequired do
  subject { dummy_class.new(name:) }

  let(:dummy_class) do
    Class.new do
      include Vets::Model
      include SignatureRequired

      attribute :name, String
    end
  end

  describe '#signature_required' do
    context 'when name matches Privacy Issue Admin pattern' do
      let(:name) { 'Some Privacy Issue Admin Team' }

      it 'returns true' do
        expect(subject.signature_required).to be true
      end
    end

    context 'when name matches Privacy Issues (plural) Admin pattern' do
      let(:name) { 'Privacy Issues Admin' }

      it 'returns true' do
        expect(subject.signature_required).to be true
      end
    end

    context 'when name matches Release of Information Medical Records Admin pattern' do
      let(:name) { 'Release of Information Medical Records Admin' }

      it 'returns true' do
        expect(subject.signature_required).to be true
      end
    end

    context 'when name matches Record Amendment Admin pattern' do
      let(:name) { 'Record Amendment Admin' }

      it 'returns true' do
        expect(subject.signature_required).to be true
      end
    end

    context 'when name matches Release of Information pattern' do
      let(:name) { 'Release of Information' }

      it 'returns true' do
        expect(subject.signature_required).to be true
      end
    end

    context 'when name uses underscores for Release_of_Information' do
      let(:name) { 'Release_of_Information' }

      it 'returns true' do
        expect(subject.signature_required).to be true
      end
    end

    context 'when name is case-insensitive match' do
      let(:name) { 'privacy issue admin' }

      it 'returns true' do
        expect(subject.signature_required).to be true
      end
    end

    context 'when name is a regular team' do
      let(:name) { 'Primary Care Team' }

      it 'returns false' do
        expect(subject.signature_required).to be false
      end
    end

    context 'when name is nil' do
      let(:name) { nil }

      it 'returns false' do
        expect(subject.signature_required).to be false
      end
    end

    context 'when name is empty' do
      let(:name) { '' }

      it 'returns false' do
        expect(subject.signature_required).to be false
      end
    end

    context 'when name contains Privacy Issue but not Admin' do
      let(:name) { 'Privacy Issue Team' }

      it 'returns false' do
        expect(subject.signature_required).to be false
      end
    end

    context 'when name is Release of Information Medical Records without Admin' do
      let(:name) { 'Release of Information Medical Records' }

      it 'returns true via Release of Information match' do
        expect(subject.signature_required).to be true
      end
    end
  end
end
