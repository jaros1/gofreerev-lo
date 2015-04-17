class ServerUsersRenameColumnSha256MessageReceivedAt < ActiveRecord::Migration
  def change
    rename_column :server_users, :sha256_message_received_at, :sha256_signature_received_at
  end
end
