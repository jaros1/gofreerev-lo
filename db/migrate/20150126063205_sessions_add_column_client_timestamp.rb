class SessionsAddColumnClientTimestamp < ActiveRecord::Migration
  def change
    add_column :sessions, :client_timestamp, :text
  end
end
