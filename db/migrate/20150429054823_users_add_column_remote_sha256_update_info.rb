class UsersAddColumnRemoteSha256UpdateInfo < ActiveRecord::Migration
  def change
    add_column :users, :remote_sha256_update_info, :text
  end
end
