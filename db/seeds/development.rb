# frozen_string_literal: true

Rails.root.glob("db/seeds/#{Rails.env}/**/*.rb").sort.each do |file|
  load file
end

if Settings.review_instance_slug
  load(Rails.root.join('db', 'seeds', 'review_instance', 'identity', 'client_configs.rb'))
end
