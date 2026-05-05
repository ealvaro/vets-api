## Common

This library provides shared utilities, base classes, and infrastructure used across vets-api. The components here are designed to be composable — most can be used independently or together.

## Components

### Common::Exceptions

A library of serializable exception classes designed to render JSONAPI-compliant error responses. Exceptions are divided into internal exceptions (raised within models and controllers) and external exceptions (raised by backend service middleware). Messages and HTTP status codes are configured via i18n locales.

See [exceptions/README.md](exceptions/README.md) for the full class hierarchy and usage.

### Common::Client

A library for building backend service integrations. Provides a base client class, configuration conventions, Faraday middleware for key casing and error handling, and optional Redis-backed token session management.

See [client/README.md](client/README.md) for setup and usage.

### Common::Models

Base classes and mixins for non-ActiveRecord models: attribute declaration via Virtus, filterable and sortable collections with optional Redis caching, a Redis-backed persistence class, and an immutable value object base via Dry::Struct.

See [models/README.md](models/README.md) for the full class reference.

### Common::FileHelpers

Utility methods for working with temporary files, particularly in the context of file uploads and ClamAV virus scanning.

```ruby
path = Common::FileHelpers.random_file_path('.pdf')
path = Common::FileHelpers.generate_random_file(file_bytes, '.pdf')
path = Common::FileHelpers.generate_clamav_temp_file(file_bytes, file_name)
Common::FileHelpers.delete_file_if_exists(path)
```

`generate_clamav_temp_file` writes to `clamav_tmp/` specifically, which is the directory ClamAV has permission to scan.

### Common::HashHelpers

Utilities for deep transformations on nested hashes, arrays, and `ActionController::Parameters`.

```ruby
Common::HashHelpers.deep_transform_parameters!(params) { |k| k.underscore }
Common::HashHelpers.deep_remove_blanks(hash)   # removes blank values (but not false)
Common::HashHelpers.deep_compact(hash)          # removes nil values
Common::HashHelpers.deep_to_h(open_struct)      # recursively converts OpenStructs to hashes
```

### Common::PdfHelpers

Utilities for working with PDF files. Currently provides PDF unlocking/decryption via HexaPDF. Raises `Common::Exceptions::UnprocessableEntity` on invalid password or corrupt PDF, with the error detail drawn from i18n.

```ruby
Common::PdfHelpers.unlock_pdf(input_file, password, output_file)
```

### Common::S3Helpers

Handles S3 file uploads, using `Aws::S3::TransferManager` when available and falling back to a basic upload otherwise.

```ruby
Common::S3Helpers.upload_file(
  s3_resource: s3,
  bucket: 'my-bucket',
  key: 'path/to/file.pdf',
  file_path: '/tmp/local_file.pdf',
  content_type: 'application/pdf',
  server_side_encryption: 'AES256'
)
```

Pass `return_object: true` to get the `Aws::S3::Object` back instead of `true`.

### Common::VirusScan

ClamAV-based virus scanning for uploaded files. Scans files from `clamav_tmp/` directly, or copies files from other locations when the `clamav_scan_file_from_other_location` Flipper flag is enabled. Emits structured audit log entries for every scan attempt, including file metadata, scan result, duration, and upload context.

```ruby
is_safe = Common::VirusScan.scan(file_path, upload_context: 'form_526')
```

Returns `true` only when the file is confirmed clean. Returns `false` when the file is not confirmed clean, including when it is infected and when scanning is skipped or blocked (for example, if the file is outside `clamav_tmp/` and `clamav_scan_file_from_other_location` is disabled).

Mock mode can be enabled via `Settings.clamav.mock`, but because Settings/Parameter Store values may arrive as strings or integers, callers should cast it to a real boolean before use (for example, `ActiveModel::Type::Boolean.new.cast(Settings.clamav.mock)`).

### Common::ConvertToPdf

Converts image files to PDF using MiniMagick. Always writes the uploaded content to a ClamAV temp file first. For files that are already PDFs, returns the path to that temp-file copy (the caller is responsible for cleaning it up). For image files, converts to PDF and returns the output path (the intermediate temp file is cleaned up automatically). Raises `IOError` for unsupported file types.

```ruby
output_path = Common::ConvertToPdf.new(uploaded_file).run
```

The output file is written to a random temp path. The caller is responsible for cleaning it up after use.
