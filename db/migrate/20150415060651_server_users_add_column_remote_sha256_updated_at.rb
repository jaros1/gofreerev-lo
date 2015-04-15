class ServerUsersAddColumnRemoteSha256UpdatedAt < ActiveRecord::Migration
  def change
    add_column :server_users, :remote_sha256_updated_at, :datetime
    add_column :server_users, :sha256_message_sent_at, :datetime
    add_column :server_users, :sha256_message_received_at, :datetime
  end
end
