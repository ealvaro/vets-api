# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Vass::V0::Session, type: :model do
  let(:redis_client) { instance_double(Vass::RedisClient) }
  let(:valid_email) { 'veteran@example.com' }
  let(:valid_phone) { '5555551234' }
  let(:uuid) { SecureRandom.uuid }
  let(:otp_code) { '123456' }
  let(:last_name) { 'Smith' }
  let(:date_of_birth) { '1990-01-15' }
  let(:jwt_secret) { 'test-jwt-secret' }

  before do
    allow(Settings).to receive(:vass).and_return(
      OpenStruct.new(jwt_secret:)
    )
  end

  describe '.build' do
    it 'creates a new session instance' do
      session = described_class.build(uuid:, last_name: 'Smith', date_of_birth: '1990-01-15')
      expect(session).to be_a(described_class)
    end
  end

  describe '#initialize' do
    context 'with direct parameters' do
      it 'sets attributes from direct parameters' do
        session = described_class.new(
          uuid:,
          last_name: 'Smith',
          date_of_birth: '1990-01-15',
          otp_code:,
          edipi: '1234567890',
          veteran_id: uuid
        )

        expect(session.uuid).to eq(uuid)
        expect(session.last_name).to eq('Smith')
        expect(session.date_of_birth).to eq('1990-01-15')
        expect(session.otp_code).to eq(otp_code)
        expect(session.edipi).to eq('1234567890')
        expect(session.veteran_id).to eq(uuid)
      end
    end

    context 'with data hash' do
      it 'sets attributes from data hash' do
        session = described_class.new(
          data: { uuid:, last_name: 'Smith', date_of_birth: '1990-01-15' }
        )

        expect(session.uuid).to eq(uuid)
        expect(session.last_name).to eq('Smith')
        expect(session.date_of_birth).to eq('1990-01-15')
      end
    end

    it 'generates a UUID if not provided' do
      session = described_class.new
      expect(session.uuid).to match(/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/)
    end

    it 'creates a RedisClient if not provided' do
      session = described_class.new
      expect(session.redis_client).to be_a(Vass::RedisClient)
    end
  end

  describe '#valid_for_creation?' do
    context 'with valid parameters' do
      it 'returns true when uuid, last_name, and date_of_birth are present' do
        session = described_class.new(uuid:, last_name: 'Smith', date_of_birth: '1990-01-15')
        expect(session.valid_for_creation?).to be true
      end
    end

    context 'with missing uuid' do
      it 'returns false' do
        session = described_class.new(uuid: nil, last_name: 'Smith', date_of_birth: '1990-01-15')
        session.instance_variable_set(:@uuid, nil)
        expect(session.valid_for_creation?).to be false
      end
    end

    context 'with missing last_name' do
      it 'returns false' do
        session = described_class.new(uuid:, date_of_birth: '1990-01-15')
        expect(session.valid_for_creation?).to be false
      end
    end

    context 'with missing date_of_birth' do
      it 'returns false' do
        session = described_class.new(uuid:, last_name: 'Smith')
        expect(session.valid_for_creation?).to be false
      end
    end

    context 'with blank values' do
      it 'returns false for blank uuid' do
        session = described_class.new(uuid: '', last_name: 'Smith', date_of_birth: '1990-01-15')
        expect(session.valid_for_creation?).to be false
      end

      it 'returns false for blank last_name' do
        session = described_class.new(uuid:, last_name: '', date_of_birth: '1990-01-15')
        expect(session.valid_for_creation?).to be false
      end

      it 'returns false for blank date_of_birth' do
        session = described_class.new(uuid:, last_name: 'Smith', date_of_birth: '')
        expect(session.valid_for_creation?).to be false
      end
    end
  end

  describe '#valid_veteran_contact_email_format?' do
    it 'returns true for a valid email' do
      session = described_class.new(uuid:, veteran_contact_email: 'vet@example.com')
      expect(session.valid_veteran_contact_email_format?).to be true
    end

    it 'returns false when veteran_contact_email is nil' do
      session = described_class.new(uuid:, veteran_contact_email: nil)
      expect(session.valid_veteran_contact_email_format?).to be false
    end

    it 'returns false when email format is invalid' do
      session = described_class.new(uuid:, veteran_contact_email: 'not-an-email')
      expect(session.valid_veteran_contact_email_format?).to be false
    end
  end

  describe '#valid_invitation_data_param?' do
    it 'returns true when data decodes to an allowed GetVeteran email field key' do
      session = described_class.new(uuid:, invitation_data: Base64.strict_encode64('emailAddress1'))
      expect(session.valid_invitation_data_param?).to be true
    end

    it 'returns true for emailAddress2 and emailAddress3' do
      %w[emailAddress2 emailAddress3].each do |key|
        session = described_class.new(uuid:, invitation_data: Base64.strict_encode64(key))
        expect(session.valid_invitation_data_param?).to be true
      end
    end

    it 'returns false when invitation_data is nil' do
      session = described_class.new(uuid:, invitation_data: nil)
      expect(session.valid_invitation_data_param?).to be false
    end

    it 'returns false when decoded value is not allowed' do
      session = described_class.new(uuid:, invitation_data: Base64.strict_encode64('emailAddress4'))
      expect(session.valid_invitation_data_param?).to be false
    end

    it 'returns false when not valid base64' do
      session = described_class.new(uuid:, invitation_data: '!!!')
      expect(session.valid_invitation_data_param?).to be false
    end
  end

  describe '#invitation_params_error' do
    it 'returns nil for a valid legacy invitation email' do
      session = described_class.new(uuid:, veteran_contact_email: 'vet@example.com')
      expect(session.invitation_params_error(data_param_enabled: false)).to be_nil
    end

    it 'returns nil for a valid data param when enabled' do
      session = described_class.new(uuid:, invitation_data: Base64.strict_encode64('emailAddress1'))
      expect(session.invitation_params_error(data_param_enabled: true)).to be_nil
    end

    it 'returns both when legacy email and data are present' do
      session = described_class.new(
        uuid:,
        veteran_contact_email: 'vet@example.com',
        invitation_data: Base64.strict_encode64('emailAddress1')
      )
      expect(session.invitation_params_error(data_param_enabled: true)).to eq(
        described_class::INVITATION_PARAM_ERROR_DETAILS[:both]
      )
    end

    it 'returns missing when neither invitation param is present' do
      session = described_class.new(uuid:)
      expect(session.invitation_params_error(data_param_enabled: true)).to eq(
        described_class::INVITATION_PARAM_ERROR_DETAILS[:missing]
      )
    end

    it 'returns data_disabled when data param is used without the flag' do
      session = described_class.new(uuid:, invitation_data: Base64.strict_encode64('emailAddress1'))
      expect(session.invitation_params_error(data_param_enabled: false)).to eq(
        described_class::INVITATION_PARAM_ERROR_DETAILS[:data_disabled]
      )
    end

    it 'returns invalid_data when data does not decode to an allowed field' do
      session = described_class.new(uuid:, invitation_data: Base64.strict_encode64('emailAddress4'))
      expect(session.invitation_params_error(data_param_enabled: true)).to eq(
        described_class::INVITATION_PARAM_ERROR_DETAILS[:invalid_data]
      )
    end

    it 'returns invalid_email when legacy email format is invalid' do
      session = described_class.new(uuid:, veteran_contact_email: 'not-an-email')
      expect(session.invitation_params_error(data_param_enabled: false)).to eq(
        described_class::INVITATION_PARAM_ERROR_DETAILS[:invalid_email]
      )
    end
  end

  describe '#valid_for_validation?' do
    context 'with valid UUID and OTP' do
      it 'returns true' do
        session = described_class.new(uuid:, otp_code:)
        expect(session.valid_for_validation?).to be true
      end
    end

    context 'without UUID' do
      it 'returns false' do
        # UUID is auto-generated, so we need to explicitly set it to nil after initialization
        session = described_class.new(otp_code:)
        session.instance_variable_set(:@uuid, nil)
        expect(session.valid_for_validation?).to be false
      end
    end

    context 'without OTP code' do
      it 'returns false' do
        session = described_class.new(uuid:, otp_code: nil)
        expect(session.valid_for_validation?).to be false
      end
    end

    context 'with invalid OTP format' do
      it 'returns false for non-numeric code' do
        session = described_class.new(uuid:, otp_code: 'abcdef')
        expect(session.valid_for_validation?).to be false
      end

      it 'returns false for wrong length' do
        session = described_class.new(uuid:, otp_code: '123')
        expect(session.valid_for_validation?).to be false
      end
    end
  end

  describe '#generate_otp' do
    it 'generates a 6-digit numeric code' do
      session = described_class.new
      otp = session.generate_otp
      expect(otp).to match(/^\d{6}$/)
    end

    it 'pads with leading zeros' do
      session = described_class.new
      allow(SecureRandom).to receive(:random_number).and_return(123)
      otp = session.generate_otp
      expect(otp).to eq('000123')
    end
  end

  describe '#save_otp' do
    it 'saves the OTP to Redis with identity data' do
      session = described_class.new(uuid:, last_name:, date_of_birth:, redis_client:)
      expect(redis_client).to receive(:save_otp).with(uuid:, code: otp_code, last_name:, dob: date_of_birth)
      session.save_otp(otp_code)
    end
  end

  describe '#valid_otp?' do
    let(:stored_data) { { code: otp_code, last_name:, dob: date_of_birth } }
    let(:session) { described_class.new(uuid:, otp_code:, last_name:, date_of_birth:, redis_client:) }

    context 'when OTP and identity match' do
      it 'returns true' do
        allow(redis_client).to receive(:otp_data).with(uuid:).and_return(stored_data)
        expect(session.valid_otp?).to be true
      end
    end

    context 'when OTP does not match' do
      it 'returns false' do
        allow(redis_client).to receive(:otp_data).with(uuid:).and_return(stored_data.merge(code: '999999'))
        expect(session.valid_otp?).to be false
      end
    end

    context 'when last_name does not match' do
      it 'returns false' do
        allow(redis_client).to receive(:otp_data).with(uuid:).and_return(stored_data)
        session_wrong_name = described_class.new(uuid:, otp_code:, last_name: 'Jones', date_of_birth:, redis_client:)
        expect(session_wrong_name.valid_otp?).to be false
      end
    end

    context 'when dob does not match' do
      it 'returns false' do
        allow(redis_client).to receive(:otp_data).with(uuid:).and_return(stored_data)
        session_wrong_dob = described_class.new(
          uuid:, otp_code:, last_name:, date_of_birth: '2000-12-25', redis_client:
        )
        expect(session_wrong_dob.valid_otp?).to be false
      end
    end

    context 'when OTP is not found in Redis' do
      it 'returns false' do
        allow(redis_client).to receive(:otp_data).with(uuid:).and_return(nil)
        expect(session.valid_otp?).to be false
      end
    end

    context 'when session is not valid for validation' do
      it 'returns false' do
        invalid_session = described_class.new(uuid: nil, otp_code: nil, redis_client:)
        expect(invalid_session.valid_otp?).to be false
      end
    end

    it 'uses constant-time comparison to prevent timing attacks' do
      allow(redis_client).to receive(:otp_data).with(uuid:).and_return(stored_data)
      expect(ActiveSupport::SecurityUtils).to receive(:secure_compare).with(otp_code, otp_code).and_call_original
      session.valid_otp?
    end

    it 'validates identity case-insensitively for last name' do
      allow(redis_client).to receive(:otp_data).with(uuid:).and_return(stored_data.merge(last_name: 'SMITH'))
      expect(session.valid_otp?).to be true
    end

    context 'with corrupted or invalid stored data' do
      it 'returns false when stored code is nil' do
        allow(redis_client).to receive(:otp_data).with(uuid:).and_return(stored_data.merge(code: nil))
        expect(session.valid_otp?).to be false
      end

      it 'returns false when stored code is empty string' do
        allow(redis_client).to receive(:otp_data).with(uuid:).and_return(stored_data.merge(code: ''))
        expect(session.valid_otp?).to be false
      end

      it 'returns false when stored code is not a string' do
        allow(redis_client).to receive(:otp_data).with(uuid:).and_return(stored_data.merge(code: 123_456))
        expect(session.valid_otp?).to be false
      end

      it 'returns false when stored code key is missing' do
        allow(redis_client).to receive(:otp_data).with(uuid:).and_return({ last_name:, dob: date_of_birth })
        expect(session.valid_otp?).to be false
      end
    end

    context 'with invalid provided OTP' do
      it 'returns false when provided OTP is nil' do
        session_nil_otp = described_class.new(uuid:, otp_code: nil, last_name:, date_of_birth:, redis_client:)
        allow(redis_client).to receive(:otp_data).with(uuid:).and_return(stored_data)
        expect(session_nil_otp.valid_otp?).to be false
      end

      it 'returns false when provided OTP is empty string' do
        session_empty_otp = described_class.new(uuid:, otp_code: '', last_name:, date_of_birth:, redis_client:)
        allow(redis_client).to receive(:otp_data).with(uuid:).and_return(stored_data)
        expect(session_empty_otp.valid_otp?).to be false
      end
    end
  end

  describe '#delete_otp' do
    it 'deletes the OTP from Redis' do
      session = described_class.new(uuid:, redis_client:)
      expect(redis_client).to receive(:delete_otp).with(uuid:)
      session.delete_otp
    end
  end

  describe '#validate_and_generate_jwt' do
    let(:otp_code) { '123456' }
    let(:stored_data) { { code: otp_code, last_name:, dob: date_of_birth } }

    context 'with valid OTP' do
      it 'validates OTP, deletes it, and returns hash with token and jti' do
        session = described_class.new(uuid:, otp_code:, last_name:, date_of_birth:, redis_client:)
        allow(redis_client).to receive(:otp_data).with(uuid:).and_return(stored_data)
        allow(redis_client).to receive(:delete_otp).with(uuid:)

        result = session.validate_and_generate_jwt

        expect(result).to be_a(Hash)
        expect(result[:token]).to be_a(String)
        expect(result[:token]).not_to be_empty
        expect(result[:jti]).to be_a(String)
        expect(result[:jti]).to match(/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/)
        expect(redis_client).to have_received(:delete_otp).with(uuid:)
      end

      it 'generates a valid JWT token with correct payload' do
        session = described_class.new(uuid:, otp_code:, last_name:, date_of_birth:, redis_client:)
        allow(redis_client).to receive(:otp_data).with(uuid:).and_return(stored_data)
        allow(redis_client).to receive(:delete_otp).with(uuid:)

        result = session.validate_and_generate_jwt
        decoded = JWT.decode(result[:token], jwt_secret, true, { algorithm: 'HS256' })
        payload = decoded[0]

        expect(payload['sub']).to eq(uuid)
        expect(payload['jti']).to eq(result[:jti])
        expect(payload['iat']).to be_present
        expect(payload['exp']).to be_present
      end

      it 'returns jti that matches the token payload' do
        session = described_class.new(uuid:, otp_code:, last_name:, date_of_birth:, redis_client:)
        allow(redis_client).to receive(:otp_data).with(uuid:).and_return(stored_data)
        allow(redis_client).to receive(:delete_otp).with(uuid:)

        result = session.validate_and_generate_jwt
        decoded = JWT.decode(result[:token], jwt_secret, true, { algorithm: 'HS256' })
        payload = decoded[0]

        expect(result[:jti]).to eq(payload['jti'])
      end
    end

    context 'with invalid OTP' do
      it 'raises AuthenticationError and does not delete OTP' do
        session = described_class.new(uuid:, otp_code: 'wrong', last_name:, date_of_birth:, redis_client:)
        allow(redis_client).to receive(:otp_data).with(uuid:).and_return(stored_data)
        allow(redis_client).to receive(:delete_otp)

        expect { session.validate_and_generate_jwt }
          .to raise_error(Vass::Errors::AuthenticationError, 'Invalid OTP')
        expect(redis_client).not_to have_received(:delete_otp)
      end
    end

    context 'with missing OTP' do
      it 'raises AuthenticationError when OTP not found in Redis' do
        session = described_class.new(uuid:, otp_code:, last_name:, date_of_birth:, redis_client:)
        allow(redis_client).to receive(:otp_data).with(uuid:).and_return(nil)

        expect { session.validate_and_generate_jwt }
          .to raise_error(Vass::Errors::AuthenticationError, 'Invalid OTP')
      end
    end
  end

  describe '#generate_jwt_token' do
    it 'returns hash with token and jti' do
      session = described_class.new(uuid:)
      result = session.generate_jwt_token

      expect(result).to be_a(Hash)
      expect(result).to have_key(:token)
      expect(result).to have_key(:jti)
    end

    it 'generates a valid JWT token' do
      session = described_class.new(uuid:)
      result = session.generate_jwt_token

      decoded = JWT.decode(result[:token], jwt_secret, true, { algorithm: 'HS256' })
      payload = decoded[0]

      expect(payload['sub']).to eq(uuid)
      expect(payload['jti']).to be_present
      expect(payload['iat']).to be_present
      expect(payload['exp']).to be_present
    end

    it 'returns jti that matches the token payload' do
      session = described_class.new(uuid:)
      result = session.generate_jwt_token

      decoded = JWT.decode(result[:token], jwt_secret, true, { algorithm: 'HS256' })
      payload = decoded[0]

      expect(result[:jti]).to eq(payload['jti'])
    end

    it 'generates unique jti for each call' do
      session = described_class.new(uuid:)
      result1 = session.generate_jwt_token
      result2 = session.generate_jwt_token

      expect(result1[:jti]).not_to eq(result2[:jti])
    end
  end

  describe '#generate_session_token' do
    it 'generates a UUID session token' do
      session = described_class.new
      token = session.generate_session_token
      expect(token).to match(/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/)
    end
  end

  describe '#creation_response' do
    it 'returns success response with UUID' do
      session = described_class.new(uuid:)
      response = session.creation_response
      expect(response).to eq({
                               uuid:,
                               message: 'OTP generated successfully'
                             })
    end
  end

  describe '#validation_response' do
    it 'returns success response with session token' do
      session = described_class.new
      token = SecureRandom.uuid
      response = session.validation_response(session_token: token)
      expect(response).to eq({
                               session_token: token,
                               message: 'OTP validated successfully'
                             })
    end
  end

  describe '#validation_error_response' do
    it 'returns error response' do
      session = described_class.new
      response = session.validation_error_response
      expect(response).to eq({
                               error: true,
                               message: 'Invalid session parameters'
                             })
    end
  end

  describe '#invalid_otp_response' do
    it 'returns error response' do
      session = described_class.new
      response = session.invalid_otp_response
      expect(response).to eq({
                               error: true,
                               message: 'Invalid OTP code'
                             })
    end
  end

  describe '#set_contact_from_veteran_data' do
    let(:invitation_email) { 'invitation@example.com' }
    let(:veteran_data) do
      {
        'success' => true,
        'data' => {
          'edipi' => '1234567890',
          'firstName' => 'John',
          'lastName' => 'Smith',
          'email_address1' => invitation_email,
          'email_address2' => 'other@example.com'
        }
      }
    end

    it 'sets email contact from legacy veteran_contact_email and EDIPI from VASS' do
      session = described_class.new(uuid:, veteran_contact_email: invitation_email, redis_client:)
      allow(redis_client).to receive(:save_veteran_metadata)
      session.set_contact_from_veteran_data(veteran_data)

      expect(session.contact_method).to eq('email')
      expect(session.contact_value).to eq(invitation_email)
      expect(session.edipi).to eq('1234567890')
      expect(session.veteran_id).to eq(uuid)
    end

    it 'resolves email from GetVeteran using decoded data param' do
      session = described_class.new(
        uuid:,
        invitation_data: Base64.strict_encode64('emailAddress1'),
        redis_client:
      )
      allow(redis_client).to receive(:save_veteran_metadata)
      session.set_contact_from_veteran_data(veteran_data)

      expect(session.contact_value).to eq(invitation_email)
    end

    it 'uses the email slot matching the data param field key' do
      session = described_class.new(
        uuid:,
        invitation_data: Base64.strict_encode64('emailAddress2'),
        redis_client:
      )
      allow(redis_client).to receive(:save_veteran_metadata)
      session.set_contact_from_veteran_data(veteran_data)

      expect(session.contact_value).to eq('other@example.com')
    end

    it 'raises ValidationError when the invitation email slot is missing' do
      session = described_class.new(
        uuid:,
        invitation_data: Base64.strict_encode64('emailAddress3'),
        redis_client:
      )
      expect do
        session.set_contact_from_veteran_data(veteran_data)
      end.to raise_error(Vass::Errors::ValidationError, /Missing contact email/)
    end

    it 'saves veteran metadata when edipi is present' do
      session = described_class.new(
        uuid:,
        edipi: '1234567890',
        veteran_contact_email: invitation_email,
        redis_client:
      )
      expect(redis_client).to receive(:save_veteran_metadata).with(
        hash_including(
          uuid:,
          edipi: '1234567890',
          veteran_id: uuid,
          email: invitation_email
        )
      )
      session.set_contact_from_veteran_data(veteran_data)
    end

    it 'does not save metadata when edipi is not present' do
      veteran_data_no_edipi = veteran_data.merge(
        'data' => { 'firstName' => 'John', 'email_address1' => invitation_email }
      )
      session = described_class.new(uuid:, veteran_contact_email: invitation_email, redis_client:)
      expect(redis_client).not_to receive(:save_veteran_metadata)
      session.set_contact_from_veteran_data(veteran_data_no_edipi)
      expect(session.contact_value).to eq(invitation_email)
    end
  end

  describe '#save_veteran_metadata_for_session' do
    it 'persists contact_value as email in Redis' do
      invitation_email = 'invitation@example.com'
      session = described_class.new(
        uuid:,
        edipi: '1234567890',
        contact_value: invitation_email,
        redis_client:
      )
      expect(redis_client).to receive(:save_veteran_metadata).with(
        hash_including(
          uuid:,
          edipi: '1234567890',
          veteran_id: uuid,
          email: invitation_email
        )
      )
      session.save_veteran_metadata_for_session
    end

    it 'returns false when edipi is not present' do
      session = described_class.new(uuid:, redis_client:)
      expect(redis_client).not_to receive(:save_veteran_metadata)
      expect(session.save_veteran_metadata_for_session).to be false
    end

    it 'returns false when edipi is blank' do
      session = described_class.new(uuid:, edipi: '', redis_client:)
      expect(redis_client).not_to receive(:save_veteran_metadata)
      expect(session.save_veteran_metadata_for_session).to be false
    end
  end

  describe '#create_authenticated_session' do
    let(:jti) { SecureRandom.uuid }
    let(:metadata) { { edipi: '1234567890', veteran_id: uuid, email: 'veteran@example.com' } }

    it 'creates session with veteran metadata, email, and jti from Redis' do
      session = described_class.new(uuid:, redis_client:)
      allow(redis_client).to receive(:veteran_metadata).with(uuid:).and_return(metadata)
      expect(redis_client).to receive(:save_session).with(
        uuid:,
        jti:,
        edipi: '1234567890',
        veteran_id: uuid,
        email: 'veteran@example.com'
      )
      session.create_authenticated_session(jti:)
    end

    it 'returns false when metadata is not found' do
      session = described_class.new(uuid:, redis_client:)
      allow(redis_client).to receive(:veteran_metadata).with(uuid:).and_return(nil)

      allow(Rails.logger).to receive(:error).and_call_original
      expect(Rails.logger).to receive(:error)
        .with(a_string_including('"service":"vass"',
                                 '"class_name":"Vass::V0::Session"',
                                 '"error_code":"metadata_not_found"'))
        .and_call_original

      expect(redis_client).not_to receive(:save_session)
      expect(session.create_authenticated_session(jti:)).to be false
    end
  end
end
