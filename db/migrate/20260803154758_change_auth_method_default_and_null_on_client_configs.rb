# frozen_string_literal: true

class ChangeAuthMethodDefaultAndNullOnClientConfigs < ActiveRecord::Migration[8.1]
  def up
    change_column_default :client_configs, :auth_method, 'pkce'

    safety_assured do
      change_column_null :client_configs, :auth_method, false
    end
  end

  def down
    change_column_null :client_configs, :auth_method, true
    change_column_default :client_configs, :auth_method, nil
  end
end
