#!/usr/bin/env bash
#
# import-va-certs.sh — Downloads and installs VA internal CA certificates
#
# Called during the Docker build (see Dockerfile). Downloads certificates from:
#   1. DigiCert (TLS RSA SHA256 2020 CA1-1, Global G2)
#   2. DoD ECA (Enterprise CA root, with HTTPS→HTTP fallback)
#   3. VA PKI (VA-Internal certs from aia.pki.va.gov)
#
# IMPORTANT: This script will FAIL THE BUILD if any cert download is unsuccessful.
# This is intentional — deploying an image without VA internal certs causes
# SSL_connect certificate verification failures against VA internal services.
#
# If the build fails here:
#   - Check network connectivity to the cert CDNs (digicert.com, dl.dod.cyber.mil, aia.pki.va.gov)
#   - Retry the build — transient CDN/network issues are the most common cause
#   - If a cert URL has permanently changed, update this script and the corresponding
#     specs in spec/scripts/import_va_certs_spec.rb
#
# Related: https://va.ghe.com/software/va.gov-team/issues/136662
#

set -euo pipefail

(
    cd /usr/local/share/ca-certificates/

    echo "Downloading DigiCert certificates..."
    if ! curl --fail --show-error --connect-timeout 10 --max-time 60 --retry 3 --retry-delay 5 -LO https://cacerts.digicert.com/DigiCertTLSRSASHA2562020CA1-1.crt.pem; then
        echo "✗ DigiCert TLS RSA SHA256 2020 CA1-1 download failed"
        exit 1
    fi
    if ! curl --fail --show-error --connect-timeout 10 --max-time 60 --retry 3 --retry-delay 5 -LO https://digicert.tbs-certificats.com/DigiCertGlobalG2TLSRSASHA2562020CA1.crt; then
        echo "✗ DigiCert Global G2 TLS RSA SHA256 2020 CA1 download failed"
        exit 1
    fi
    echo "✓ DigiCert certificates downloaded"

    # DoD ECA with multiple fallback mechanisms
    (
        echo "Downloading DoD ECA certificates..."

        # Primary: HTTPS with timeout and retries
        if curl --fail --show-error --location --connect-timeout 10 --max-time 60 --retry 3 --retry-delay 5 -o unclass-certificates_pkcs7_ECA.zip https://dl.dod.cyber.mil/wp-content/uploads/pki-pke/zip/unclass-certificates_pkcs7_ECA.zip; then
            echo "✓ DoD ECA downloaded via HTTPS"
        # Fallback 1: HTTP with timeout and retries
        ## Uncomment in case the https call fails again
        ## Last time we got this error: Failed to connect to dl.dod.cyber.mil port 443
        elif curl --fail --show-error --location --connect-timeout 10 --max-time 60 --retry 3 --retry-delay 5 -o unclass-certificates_pkcs7_ECA.zip http://dl.dod.cyber.mil/wp-content/uploads/pki-pke/zip/unclass-certificates_pkcs7_ECA.zip; then
            echo "✓ DoD ECA downloaded via HTTP fallback"
        else
            echo "✗ All DoD ECA download attempts failed"
            exit 1
        fi
        # Process the downloaded certificates
        if [ -f "unclass-certificates_pkcs7_ECA.zip" ]; then
            unzip ./unclass-certificates_pkcs7_ECA.zip -d ECA_CA
            cd ECA_CA/certificates_pkcs7_v5_12_eca/
            openssl pkcs7 -inform DER -in ./certificates_pkcs7_v5_12_eca_ECA_Root_CA_5_der.p7b -print_certs | awk '/BEGIN/{i++} {print > ("eca_cert" i ".pem")}'
            rm -f eca_cert.pem # first one is always invalid because of how awk is breaking it up
            cp *.pem ../../
            echo "✓ DoD ECA certificates processed successfully"
        else
            echo "✗ DoD ECA zip file not found after download attempts"
            exit 1
        fi
    )

    echo "Downloading VA certificates..."
    if wget \
        --level=1 \
        --recursive \
        --no-parent \
        --no-host-directories \
        --no-directories \
        --accept="VA*.cer" \
        http://aia.pki.va.gov/PKI/AIA/VA/; then
        echo "✓ VA certificates downloaded from aia.pki.va.gov"
    else
        echo "⚠ aia.pki.va.gov unreachable, falling back to GHEC-US mirror..."
        VA_CERT_REPO="https://raw.va.ghe.com/software/platform-va-ca-certificate/main"
        CERT_TOKEN="${BUNDLE_VA__GHE__COM:-}"
        CERT_TOKEN="${CERT_TOKEN##*:}"
        if [ -z "${CERT_TOKEN}" ]; then
            echo "✗ BUNDLE_VA__GHE__COM is not set — cannot authenticate to GHEC-US mirror"
            exit 1
        fi
        curl_auth=(-H "Authorization: token ${CERT_TOKEN}")
        for cert in \
            VA-Internal-S2-ICA1-v1 VA-Internal-S2-ICA2-v1 VA-Internal-S2-ICA3-v1 \
            VA-Internal-S2-ICA4 VA-Internal-S2-ICA5 VA-Internal-S2-ICA6 \
            VA-Internal-S2-ICA7 VA-Internal-S2-ICA8 VA-Internal-S2-ICA9 \
            VA-Internal-S2-ICA10 VA-Internal-S2-ICA11 VA-Internal-S2-ICA12 \
            VA-Internal-S2-ICA13 VA-Internal-S2-ICA14 VA-Internal-S2-ICA15 \
            VA-Internal-S2-ICA16 VA-Internal-S2-ICA17 VA-Internal-S2-ICA18 \
            VA-Internal-S2-ICA19 VA-Internal-S2-ICA20 VA-Internal-S2-ICA21 \
            VA-Internal-S2-ICA22 VA-Internal-S2-ICA23 VA-Internal-S2-ICA24 \
            VA-Internal-S2-ICA25 VA-Internal-S2-ICA26 VA-Internal-S2-ICA27 \
            VA-Internal-S2-ICA28 VA-Internal-S2-ICA29 VA-Internal-S2-ICA30 \
            VA-Internal-S2-ICA31 VA-Internal-S2-ICA32 VA-Internal-S2-ICA33 \
            VA-Internal-S2-ICA34 \
            VA-Internal-S2-RCA1-v1 VA-Internal-S2-RCA2 VA-Internal-S2-RCA3
        do
            if ! curl --silent --show-error --fail --connect-timeout 10 --max-time 30 --retry 2 \
                "${curl_auth[@]}" \
                -o "${cert}.cer" "${VA_CERT_REPO}/${cert}.cer"; then
                echo "✗ Failed to download ${cert}.cer"
                exit 1
            fi
        done
        echo "✓ VA certificates downloaded from GHEC-US mirror"
    fi

    # Check if any certificate files exist before processing
    shopt -s nullglob
    cert_files=(*.cer *.pem)
    shopt -u nullglob

    if [ ${#cert_files[@]} -eq 0 ]; then
        echo "✗ No certificate files found after download — build cannot continue without VA certs"
        exit 1
    else
        echo "Processing ${#cert_files[@]} certificate files..."
    fi

    for cert in *.{cer,pem}
    do
        # Process certificate file
        [ ! -f "$cert" ] && continue

        if file "${cert}" | grep -q 'PEM'
        then
            cp "${cert}" "${cert}.crt"
        elif file "${cert}" | grep -q 'ASCII text'
        then
            # Handle base64-encoded DER (like VA-Internal-S2-ICA22.cer)
            if base64 -d "${cert}" > "${cert}.der" && [ -s "${cert}.der" ]
            then
                if openssl x509 -in "${cert}.der" -inform der -outform pem -out "${cert}.crt"
                then
                    rm "${cert}.der"
                else
                    echo "Error: Failed to convert ${cert} from DER to PEM format"
                    rm -f "${cert}.der" "${cert}.crt"
                    exit 1
                fi
            else
                echo "Error: Failed to decode base64 data in ${cert}"
                rm -f "${cert}.der"
                exit 1
            fi
        else
            # Binary DER format
            openssl x509 -in "${cert}" -inform der -outform pem -out "${cert}.crt"
        fi
        rm "${cert}"
    done

    update-ca-certificates --fresh

    # Display VA Internal certificates that are now trusted
    awk -v cmd='openssl x509 -noout -subject' '/BEGIN/{close(cmd)};{print | cmd}' < /etc/ssl/certs/ca-certificates.crt \
    | grep -iE '(VA-Internal|DigiCert)'
)