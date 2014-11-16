class UsersAddColumnLastFriendsFindAt < ActiveRecord::Migration
  def change
    add_column :users, :last_friends_find_at, :datetime
  end
end
