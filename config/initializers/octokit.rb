# frozen_string_literal: true

Octokit.configure do |c|
  c.api_endpoint = 'https://api.va.ghe.com/'
  c.web_endpoint = 'https://va.ghe.com/'
end
