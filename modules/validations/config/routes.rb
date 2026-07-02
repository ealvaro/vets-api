# frozen_string_literal: true

Validations::Engine.routes.draw do
  namespace :v0, defaults: { format: 'json' } do
    get 'zipcode/:zipcode', to: 'zipcode#validate'
  end
end
