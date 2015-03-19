class SessionsAddColumnServer < ActiveRecord::Migration
  def change
    add_column :sessions, :server, :boolean
  end
end
