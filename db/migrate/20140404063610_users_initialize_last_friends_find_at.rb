class UsersInitializeLastFriendsFindAt < ActiveRecord::Migration
  def change
    User.where('last_login_at is not null and ' +
                   'last_friends_find_at is null').update_all("last_friends_find_at = last_login_at")
  end
end
