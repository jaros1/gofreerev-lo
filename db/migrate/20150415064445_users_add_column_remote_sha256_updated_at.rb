class UsersAddColumnRemoteSha256UpdatedAt < ActiveRecord::Migration
  def change
    add_column :users, :remote_sha256_updated_at, :datetime
  end
end
