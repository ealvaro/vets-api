# frozen_string_literal: true

module AppInfo
  GIT_REVISION = ENV.fetch('GIT_REVISION', 'MISSING_GIT_REVISION')
  GITHUB_URL   = 'https://va.ghe.com/software/vets-api'
end
