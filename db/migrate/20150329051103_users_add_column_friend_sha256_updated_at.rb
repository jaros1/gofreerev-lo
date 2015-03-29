class UsersAddColumnFriendSha256UpdatedAt < ActiveRecord::Migration
  def change
    add_column :users, :friend_sha256_updated_at, :datetime
  end
end
