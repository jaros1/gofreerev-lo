class SessionsAddColumnLastShortFriendsListAt < ActiveRecord::Migration
  def change
    add_column :sessions, :last_short_friends_list_at, :datetime
  end
end
