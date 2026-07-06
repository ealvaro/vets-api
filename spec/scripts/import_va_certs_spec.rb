# frozen_string_literal: true

require 'rails_helper'
require 'tmpdir'
require 'fileutils'
require 'open3'
require 'puma'
require 'rack'
require 'timeout'

RSpec.describe 'import-va-certs' do # rubocop:disable RSpec/DescribeClass
  let(:script_path) { Rails.root.join('import-va-certs.sh') }
  let(:temp_dir) { Dir.mktmpdir }
  let(:mock_cert_dir) { File.join(temp_dir, 'ca-certificates') }

  before do
    FileUtils.mkdir_p(mock_cert_dir)
  end

  after do
    FileUtils.rm_rf(temp_dir)
  end

  describe 'script execution' do
    context 'when script exists and is executable' do
      it 'exists in the root directory' do
        expect(File.exist?(script_path)).to be true
      end

      it 'is executable' do
        expect(File.executable?(script_path)).to be true
      end

      it 'starts with proper shebang' do
        first_line = File.open(script_path, &:readline).chomp
        expect(first_line).to eq('#!/usr/bin/env bash')
      end

      it 'has set -euo pipefail for safety' do
        script_content = File.read(script_path)
        expect(script_content).to include('set -euo pipefail')
      end
    end
  end

  describe 'DoD ECA certificate handling' do
    it 'implements multiple fallback mechanisms for DoD certificates' do
      script_content = File.read(script_path)

      # Verify primary HTTPS attempt with proper flags including --fail
      expect(script_content).to include(
        'curl --fail --show-error --location --connect-timeout 10 --max-time 60 --retry 3 --retry-delay 5'
      )
      expect(script_content).to include(
        'https://dl.dod.cyber.mil/wp-content/uploads/pki-pke/zip/unclass-certificates_pkcs7_ECA.zip'
      )
      expect(script_content).to include('DOD_ECA_HTTPS_URL=')

      # Verify HTTP fallback with --fail
      expect(script_content).to include(
        'elif curl --fail --show-error --location --connect-timeout 10'
      )

      # Verify proper if/elif structure
      expect(script_content).to include('elif curl')
    end

    it 'includes comprehensive error handling and logging for DoD certificates' do
      script_content = File.read(script_path)

      # Verify logging messages are present
      expect(script_content).to include('Downloading DoD ECA certificates...')
      expect(script_content).to include('✓ DoD ECA downloaded via HTTPS')
      expect(script_content).to include('✓ DoD ECA downloaded via HTTP fallback')
      expect(script_content).to include('✗ All DoD ECA download attempts failed')
      expect(script_content).to include('✓ DoD ECA certificates processed successfully')
      expect(script_content).to include('✗ DoD ECA zip file not found after download attempts')
    end

    it 'processes DoD PKCS7 certificates correctly' do
      script_content = File.read(script_path)

      expect(script_content).to include('unzip ./unclass-certificates_pkcs7_ECA.zip -d ECA_CA')
      expect(script_content).to include('cd ECA_CA/certificates_pkcs7_v5_12_eca/')
      expect(script_content).to include('awk \'/BEGIN/{i++} {print > ("eca_cert" i ".pem")}\'')
      expect(script_content).to include('rm -f eca_cert.pem')
      expect(script_content).to include('cp *.pem ../../')
    end

    it 'fails the build when DoD certificate downloads fail' do
      script_content = File.read(script_path)

      # Verify it checks for zip file existence before processing
      expect(script_content).to include('if [ -f "unclass-certificates_pkcs7_ECA.zip" ]; then')

      # Verify it exits on download failure
      dod_download_block = script_content[/else\s+echo "✗ All DoD ECA download attempts failed".*?fi/m]
      expect(dod_download_block).to include('exit 1')

      # Verify it exits when zip file is missing
      dod_zip_block = script_content[/else\s+echo "✗ DoD ECA zip file not found after download attempts".*?fi/m]
      expect(dod_zip_block).to include('exit 1')
    end

    it 'exits non-zero when DoD cert endpoints return non-200' do
      app = Rack::Builder.new do
        map '/DigiCertTLSRSASHA2562020CA1-1.crt.pem' do
          run ->(_env) { [200, { 'Content-Type' => 'application/octet-stream' }, ["dummy cert\n"]] }
        end
        map '/DigiCertGlobalG2TLSRSASHA2562020CA1.crt' do
          run ->(_env) { [200, { 'Content-Type' => 'application/octet-stream' }, ["dummy cert\n"]] }
        end
        map '/unclass-certificates_pkcs7_ECA.zip' do
          run ->(_env) { [404, { 'Content-Type' => 'text/plain' }, ['Not Found']] }
        end
      end.to_app

      server = Puma::Server.new(app)
      server.add_tcp_listener('127.0.0.1', 0)
      server_thread = server.run
      Timeout.timeout(2) { sleep 0.01 until server.connected_ports.any? }
      port = server.connected_ports.first

      output, status = Open3.capture2e(
        {
          'CA_CERT_DIR' => mock_cert_dir,
          'DIGICERT_TLS_RSA_URL' => "http://127.0.0.1:#{port}/DigiCertTLSRSASHA2562020CA1-1.crt.pem",
          'DIGICERT_GLOBAL_G2_URL' => "http://127.0.0.1:#{port}/DigiCertGlobalG2TLSRSASHA2562020CA1.crt",
          'DOD_ECA_HTTPS_URL' => "http://127.0.0.1:#{port}/unclass-certificates_pkcs7_ECA.zip",
          'DOD_ECA_HTTP_URL' => "http://127.0.0.1:#{port}/unclass-certificates_pkcs7_ECA.zip"
        },
        script_path.to_s
      )

      expect(status).not_to be_success
      expect(output).to include('All DoD ECA download attempts failed')
    ensure
      server&.stop(true)
      server_thread&.join(5)
    end
  end

  describe 'VA certificate download' do
    it 'downloads VA certificates with wget and falls back to GHEC-US mirror' do
      script_content = File.read(script_path)

      # Verify wget command with proper options
      expect(script_content).to include('wget')
      expect(script_content).to include('--level=1')
      expect(script_content).to include('--recursive')
      expect(script_content).to include('--no-parent')
      expect(script_content).to include('--no-host-directories')
      expect(script_content).to include('--no-directories')
      expect(script_content).to include('--accept="VA*.cer"')
      expect(script_content).to include('http://aia.pki.va.gov/PKI/AIA/VA/')

      # Verify retry/backoff flags are present
      expect(script_content).to include('--tries=3')
      expect(script_content).to include('--timeout=60')
      expect(script_content).to include('--waitretry=5')

      # Verify GHEC-US mirror fallback URL and auth pattern
      expect(script_content).to include('falling back to GHEC-US mirror')
      expect(script_content).to include('raw.va.ghe.com/software/platform-va-ca-certificate/main')
      expect(script_content).to include('VA_CERT_REPO="${VA_CERT_REPO:-${VA_CERT_REPO_DEFAULT}}"')
      expect(script_content).to include('BUNDLE_VA__GHE__COM')
      expect(script_content).to include('Authorization: token')
      expect(script_content).to include('BUNDLE_VA__GHE__COM is not set')

      # Verify build fails when no cert files found after both attempts
      expect(script_content).to include('No certificate files found after download')
    end

    it 'includes VA certificate download logging' do
      script_content = File.read(script_path)
      expect(script_content).to include('Downloading VA certificates...')
    end

    it 'verifies wget actually downloaded VA*.cer files before declaring success' do
      script_content = File.read(script_path)

      # Verify nullglob is used to safely expand the VA*.cer glob
      expect(script_content).to include('shopt -s nullglob')
      expect(script_content).to include('va_files=(VA*.cer)')
      expect(script_content).to include('shopt -u nullglob')

      # Verify the file count check gates the success declaration
      expect(script_content).to include('if [ ${#va_files[@]} -gt 0 ]; then')

      # Verify the warning message for the wget-exits-0-but-no-files case
      expect(script_content).to include('wget succeeded but no VA*.cer files were downloaded')
    end

    it 'exits on individual cert download failure in GitHub mirror fallback' do
      script_content = File.read(script_path)
      expect(script_content).to include('Failed to download ${cert}.cer')
      expect(script_content).not_to include('Warning: Failed to download ${cert}.cer')
    end

    it 'exits non-zero when a configured cert endpoint returns non-200' do
      # Executes the real script with endpoint overrides and a local cert directory.
      app = proc { |_env| [404, { 'Content-Type' => 'text/plain' }, ['Not Found']] }

      server = Puma::Server.new(app)
      server.add_tcp_listener('127.0.0.1', 0)
      server_thread = server.run
      Timeout.timeout(2) { sleep 0.01 until server.connected_ports.any? }
      port = server.connected_ports.first

      output, status = Open3.capture2e(
        {
          'CA_CERT_DIR' => mock_cert_dir,
          'DIGICERT_TLS_RSA_URL' => "http://127.0.0.1:#{port}/DigiCertTLSRSASHA2562020CA1-1.crt.pem"
        },
        script_path.to_s
      )

      expect(status).not_to be_success
      expect(output).to include('DigiCert TLS RSA SHA256 2020 CA1-1 download failed')
    ensure
      server&.stop(true)
      server_thread&.join(5)
    end

    it 'exits non-zero when a VA mirror cert endpoint returns non-200' do
      # Executes the real script through the VA mirror fallback branch while faking only the
      # commands that would otherwise require a real DoD certificate bundle.
      skip 'wget not available in PATH for integration script test' unless system('command -v wget >/dev/null 2>&1')

      fake_bin_dir = File.join(temp_dir, 'fake-bin')
      FileUtils.mkdir_p(fake_bin_dir)

      File.write(
        File.join(fake_bin_dir, 'unzip'),
        <<~'BASH'
          #!/usr/bin/env bash
          set -euo pipefail

          mkdir -p ECA_CA/certificates_pkcs7_v5_12_eca
          cat > ECA_CA/certificates_pkcs7_v5_12_eca/certificates_pkcs7_v5_12_eca_ECA_Root_CA_5_der.p7b <<'EOF'
          fake-doD-content
          EOF
        BASH
      )

      File.write(
        File.join(fake_bin_dir, 'openssl'),
        <<~'BASH'
          #!/usr/bin/env bash
          set -euo pipefail

          if [ "${1:-}" = "pkcs7" ]; then
            out_file=''
            prev=''
            for arg in "$@"; do
              if [ "$prev" = "-out" ]; then
                out_file="$arg"
                break
              fi
              prev="$arg"
            done

            if [ -n "$out_file" ]; then
              cat > "$out_file" <<'EOF'
          -----BEGIN CERTIFICATE-----
          Tm90UmVhbENlcnRpZmljYXRl
          -----END CERTIFICATE-----
          EOF
            else
              cat <<'EOF'
          -----BEGIN CERTIFICATE-----
          Tm90UmVhbENlcnRpZmljYXRl
          -----END CERTIFICATE-----
          EOF
            fi
          else
            echo "unsupported openssl invocation: $*" >&2
            exit 1
          fi
        BASH
      )

      FileUtils.chmod('+x', File.join(fake_bin_dir, 'unzip'))
      FileUtils.chmod('+x', File.join(fake_bin_dir, 'openssl'))

      pem_cert = <<~PEM
        -----BEGIN CERTIFICATE-----
        Tm90UmVhbENlcnRpZmljYXRl
        -----END CERTIFICATE-----
      PEM

      server = Puma::Server.new(
        Rack::Builder.new do
          map '/DigiCertTLSRSASHA2562020CA1-1.crt.pem' do
            run ->(_env) { [200, { 'Content-Type' => 'application/x-pem-file' }, [pem_cert]] }
          end
          map '/DigiCertGlobalG2TLSRSASHA2562020CA1.crt' do
            run ->(_env) { [200, { 'Content-Type' => 'application/x-pem-file' }, [pem_cert]] }
          end
          map '/unclass-certificates_pkcs7_ECA.zip' do
            run ->(_env) { [200, { 'Content-Type' => 'application/zip' }, ['fake-zip']] }
          end
          map '/PKI/AIA/VA/' do
            run lambda { |_env|
              [200, { 'Content-Type' => 'text/html' },
               ['<html><body><h1>VA AIA</h1><p>No cert links here.</p></body></html>']]
            }
          end
        end.to_app
      )
      server.add_tcp_listener('127.0.0.1', 0)
      server_thread = server.run
      Timeout.timeout(2) { sleep 0.01 until server.connected_ports.any? }
      port = server.connected_ports.first

      output, status = Open3.capture2e(
        {
          'CA_CERT_DIR' => mock_cert_dir,
          'PATH' => "#{fake_bin_dir}:#{ENV.fetch('PATH')}",
          'DIGICERT_TLS_RSA_URL' => "http://127.0.0.1:#{port}/DigiCertTLSRSASHA2562020CA1-1.crt.pem",
          'DIGICERT_GLOBAL_G2_URL' => "http://127.0.0.1:#{port}/DigiCertGlobalG2TLSRSASHA2562020CA1.crt",
          'DOD_ECA_HTTPS_URL' => "http://127.0.0.1:#{port}/unclass-certificates_pkcs7_ECA.zip",
          'DOD_ECA_HTTP_URL' => "http://127.0.0.1:#{port}/unclass-certificates_pkcs7_ECA.zip",
          'VA_AIA_URL' => "http://127.0.0.1:#{port}/PKI/AIA/VA/",
          'VA_CERT_REPO' => "http://127.0.0.1:#{port}",
          'BUNDLE_VA__GHE__COM' => 'prefix:mirror-token'
        },
        script_path.to_s
      )

      expect(status).not_to be_success
      expect(output).to include('Failed to download VA-Internal-S2-ICA1-v1.cer')
    ensure
      server&.stop(true)
      server_thread&.join(5)
    end
  end

  describe 'certificate processing' do
    let(:test_cert_dir) { File.join(temp_dir, 'test-certs') }

    before do
      FileUtils.mkdir_p(test_cert_dir)
    end

    it 'contains correct certificate processing logic' do
      script_content = File.read(script_path)

      # Verify the certificate processing logic is present
      expect(script_content).to include('for cert in *.{cer,pem}')
      expect(script_content).to include('if file "${cert}" | grep -q \'PEM\'')
      expect(script_content).to include('cp "${cert}" "${cert}.crt"')
      expect(script_content).to include('openssl x509 -in "${cert}" -inform der -outform pem -out "${cert}.crt"')
      expect(script_content).to include('rm "${cert}"')
    end

    it 'has correct DER to PEM conversion logic' do
      script_content = File.read(script_path)

      # Verify the script structure contains the correct commands for conversion
      expect(script_content).to include('openssl x509 -in "${cert}" -inform der -outform pem -out "${cert}.crt"')
      expect(script_content).to include('if file "${cert}" | grep -q \'PEM\'')

      # Verify base64-encoded DER handling
      expect(script_content).to include('elif file "${cert}" | grep -q \'ASCII text\'')
      expect(script_content).to include('base64 -d "${cert}" > "${cert}.der"')

      # Verify the else branch for binary DER conversion is present
      expect(script_content).to match(/else\s+.*openssl x509.*-inform der -outform pem/m)
    end
  end

  describe 'external certificate sources' do
    it 'downloads DigiCert certificates with validation and retries' do
      script_content = File.read(script_path)

      expect(script_content).to include('https://cacerts.digicert.com/DigiCertTLSRSASHA2562020CA1-1.crt.pem')
      expect(script_content).to include('https://digicert.tbs-certificats.com/DigiCertGlobalG2TLSRSASHA2562020CA1.crt')
      expect(script_content).to include('DIGICERT_TLS_RSA_URL=')
      expect(script_content).to include('DIGICERT_GLOBAL_G2_URL=')

      # Verify curl uses --fail to catch HTTP errors
      expect(script_content).to include('curl --fail')

      # Verify build fails on DigiCert download failure
      expect(script_content).to include('DigiCert TLS RSA SHA256 2020 CA1-1 download failed')
      expect(script_content).to include('DigiCert Global G2 TLS RSA SHA256 2020 CA1 download failed')
    end
  end

  describe 'security and safety features' do
    it 'uses safe bash options' do
      script_content = File.read(script_path)
      expect(script_content).to include('set -euo pipefail')
    end

    it 'runs in a subshell to contain directory changes' do
      script_content = File.read(script_path)
      expect(script_content).to match(/^\(/)
      expect(script_content).to match(/\)$/)
    end

    it 'includes certificate verification at the end' do
      script_content = File.read(script_path)
      expect(script_content).to include('update-ca-certificates --fresh')
      expect(script_content).to include("grep -iE '(VA-Internal|DigiCert)'")
    end

    it 'cleans up temporary files' do
      script_content = File.read(script_path)
      expect(script_content).to include('rm "${cert}"')
      expect(script_content).to include('rm -f eca_cert.pem')
    end

    it 'uses proper error handling with curl --fail flag' do
      script_content = File.read(script_path)

      # Verify all curl commands use --fail to catch HTTP errors
      expect(script_content).to include('curl --fail --show-error')

      # Verify it's used in an if statement for proper error handling
      expect(script_content).to match(/if curl .*then/m)
      expect(script_content).to match(/if ! curl .*then/m)
    end
  end

  describe 'system certificate store update' do
    it 'updates the system certificate store' do
      script_content = File.read(script_path)
      expect(script_content).to include('update-ca-certificates --fresh')
    end

    it 'displays trusted certificates after update' do
      script_content = File.read(script_path)
      expect(script_content).to include('awk -v cmd=\'openssl x509 -noout -subject\'')
      expect(script_content).to include('/etc/ssl/certs/ca-certificates.crt')
    end
  end
end
