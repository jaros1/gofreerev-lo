class SessionsAddColumnClientSecret < ActiveRecord::Migration
  def up
    add_column :sessions, :client_secret, :text
  end
  def down
    remove_column :sessions, :client_secret
  end
end
