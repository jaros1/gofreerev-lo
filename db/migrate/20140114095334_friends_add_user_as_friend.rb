class FriendsAddUserAsFriend < ActiveRecord::Migration
  def up
    User.all.each do |u|
      f = Friend.new
      f.user_id_giver = u.user_id
      f.user_id_receiver = u.user_id
      f.api_friend = 'Y'
      f.save!
    end
  end
  def down
    Friend.where('user_id_giver = user_id_receiver').delete_all
  end
end
