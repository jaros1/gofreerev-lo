class SessionsAddColumnSystemSecretUpdatedAt < ActiveRecord::Migration
  def change
    add_column :sessions, :system_secret_updated_at, :datetime
  end
end
