ARG IMAGEMAGICK_IMAGE=008577686731.dkr.ecr.us-gov-west-1.amazonaws.com/dpokidov/imagemagick:7.1.1-47-bookworm
ARG RUBY_IMAGE=008577686731.dkr.ecr.us-gov-west-1.amazonaws.com/ruby:3.4.10-slim-bookworm
ARG CERTS_IMAGE=008577686731.dkr.ecr.us-gov-west-1.amazonaws.com/dsva/va-certs:v0.14.2

FROM ${RUBY_IMAGE} AS rubyimg
FROM rubyimg AS modules

WORKDIR /tmp

# Copy each module's Gemfile, gemspec, and version.rb files
COPY modules/ modules/
RUN find modules -type f ! \( -name Gemfile -o -name "*.gemspec" -o -path "*/lib/*/version.rb" \) -delete && \
    find modules -type d -empty -delete

# ImageMagick 7 is not available on Bookworm
# This can be replaced with the imagemagick-7 package if using Trixie
FROM ${IMAGEMAGICK_IMAGE} AS imagemagick

# Escape hatch for developers without ECR access: building with CERTS_IMAGE=certs_none
# resolves the certs stage to this empty directory instead of the va-certs image, which is
# what the Makefile does for every local target — see the CERTS_IMAGE note there. The
# resulting image does NOT trust VA's internal PKI, so TLS to any real VA service fails
# certificate verification — fine for mocked local development, and bin/fetch-va-certs
# supplies the anchors when they're needed. `scratch` cannot be used here: it has no
# filesystem, so the COPY below fails with
# "lstat /usr/local/share/ca-certificates: no such file or directory".
FROM rubyimg AS certs_none
RUN mkdir -p /usr/local/share/ca-certificates

FROM ${CERTS_IMAGE} AS certs

FROM rubyimg

# Allow for setting ENV vars via --build-arg
ARG BUNDLE_ENTERPRISE__CONTRIBSYS__COM \
  BUNDLE_VA__GHE__COM \
  CERTS_IMAGE \
  RAILS_ENV=development \
  USER_ID=1000
ENV RAILS_ENV=$RAILS_ENV \
  BUNDLE_ENTERPRISE__CONTRIBSYS__COM=$BUNDLE_ENTERPRISE__CONTRIBSYS__COM \
  BUNDLE_VA__GHE__COM=$BUNDLE_VA__GHE__COM \
  BUNDLER_VERSION=2.5.23

RUN groupadd --gid $USER_ID nonroot \
  && useradd --uid $USER_ID --gid nonroot --shell /bin/bash --create-home nonroot --home-dir /app

WORKDIR /app

RUN apt-get update --fix-missing \
  && apt-get install -y poppler-utils build-essential libpq-dev libffi-dev libyaml-dev git curl wget unzip ca-certificates ca-certificates-java openssl file \
  pdftk tesseract-ocr libjemalloc2 procps \
  libpng16-16 libjpeg62-turbo libtiff6 libfreetype6 libfontconfig1 ghostscript libgomp1 libomp5 libde265-0 libx265-199 liblcms2-2 libgif7 libbrotli1 libxext6 \
  && ln -sf "$(dpkg -L libjemalloc2 | grep 'libjemalloc.so.2$')" /usr/local/lib/libjemalloc.so.2 \
  && apt-get clean \
  && rm -rf /var/cache/apt/archives/* /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Copy ImageMagick 7 and its dependencies from the ImageMagick build stage
COPY --from=imagemagick /usr/local/bin/magick /usr/local/bin/magick
COPY --from=imagemagick /usr/local/lib/ /usr/local/lib/
COPY --from=imagemagick /usr/local/etc/ImageMagick-7/ /usr/local/etc/ImageMagick-7/
COPY --from=imagemagick /usr/local/share/ImageMagick-7/ /usr/local/share/ImageMagick-7/
RUN ln -s /usr/local/bin/magick /usr/local/bin/convert \
  && ln -s /usr/local/bin/magick /usr/local/bin/identify \
  && ln -s /usr/local/bin/magick /usr/local/bin/mogrify \
  && ldconfig

# Relax ImageMagick PDF security. See https://stackoverflow.com/a/59193253.
RUN sed -i '/rights="none" pattern="PDF"/d' /usr/local/etc/ImageMagick-7/policy.xml


# Install fwdproxy.crt into trust store. Anything else a developer has dropped into
# config/ca-trust/ comes along too — see bin/fetch-va-certs, which populates VA anchors
# there for builds that can't pull the cert image.
COPY config/ca-trust/*.crt /usr/local/share/ca-certificates/

# Copy VA certs from the prebuilt vsp-platform-va-certs image (CERTS_IMAGE). No runtime
# downloads — the build fails if VA certs are absent from both this image and
# config/ca-trust/, unless CERTS_IMAGE is explicitly certs_none.
COPY --from=certs /usr/local/share/ca-certificates/ /usr/local/share/ca-certificates/

# update-ca-certificates only ingests files with a .crt extension, so normalize any .pem-extension
# certs to .crt first — otherwise PEM-only anchors (e.g. DigiCert TLS RSA SHA256 2020 CA1,
# Federal Common Policy CA) are silently dropped from the trust bundle.
RUN set -eu && \
    for f in /usr/local/share/ca-certificates/*.pem; do \
      [ -e "$f" ] || continue; \
      base=$(basename "$f" .pem); \
      mv -n -- "$f" "/usr/local/share/ca-certificates/${base}.crt"; \
    done && \
    if [ -n "$(find /usr/local/share/ca-certificates -maxdepth 1 -name 'VA-Internal*.crt' -print -quit)" ]; then \
      update-ca-certificates --fresh && \
      subjects=$(find /usr/local/share/ca-certificates -maxdepth 1 -name '*.crt' \
        -exec openssl x509 -in {} -noout -subject \; 2>/dev/null) && \
      if ! echo "$subjects" | grep -qiE 'VA-Internal|DigiCert'; then \
        echo "✗ Expected VA-Internal/DigiCert anchors not found after installing certs from CERTS_IMAGE"; \
        exit 1; \
      fi && \
      echo "✓ VA certificates installed and validated"; \
    elif [ "${CERTS_IMAGE:-}" = "certs_none" ]; then \
      update-ca-certificates --fresh; \
      echo "⚠ No VA-Internal CAs in this image: CERTS_IMAGE=certs_none and none found in config/ca-trust/."; \
      echo "⚠ TLS to any VA service will fail certificate verification — including a service"; \
      echo "⚠ reached over an SSM port-forward, which presents a VA-Internal certificate."; \
      echo "⚠ Run bin/fetch-va-certs and rebuild to install the anchors without ECR access."; \
    else \
      echo "✗ No VA-Internal certificates copied from CERTS_IMAGE — build cannot continue without VA certs"; \
      exit 1; \
    fi

COPY config/clamd.conf /etc/clamav/clamd.conf

RUN mkdir -p /clamav_tmp && \
    chown -R nonroot:nonroot /clamav_tmp && \
    chmod 777 /clamav_tmp

ENV LANG=C.UTF-8 \
   BUNDLE_JOBS=4 \
   BUNDLE_PATH=/usr/local/bundle/cache \
   BUNDLE_RETRY=3 \
   LD_PRELOAD=/usr/local/lib/libjemalloc.so.2

RUN gem install bundler:${BUNDLER_VERSION} --no-document

COPY --from=modules /tmp/modules modules/
COPY Gemfile Gemfile.lock ./
RUN bundle install \
  && rm -rf /usr/local/bundle/cache/*.gem \
  && find /usr/local/bundle/gems/ -name "*.c" -delete \
  && find /usr/local/bundle/gems/ -name "*.o" -delete \
  && find /usr/local/bundle/gems/ -name ".git" -type d -prune -execdir rm -rf {} + \
  # 🔧 fix bad permissions from Nokogiri 1.18.7 (only if installed)
  && for d in /usr/local/bundle/gems/nokogiri-*; do \
       if [ -d "$d" ]; then \
         find "$d" -type f -exec chmod a+r {} \; && \
         find "$d" -type d -exec chmod a+rx {} \; ; \
       fi \
     done

COPY --chown=nonroot:nonroot . .

# Make the ImageMagick script executable
RUN chmod +x bin/merge_imagemagick_policy

# Execute the merge policy script for ImageMagick
RUN ruby -rbundler/setup bin/merge_imagemagick_policy

EXPOSE 3000

USER nonroot

CMD ["bundle", "exec", "rails", "server", "-b", "0.0.0.0"]
