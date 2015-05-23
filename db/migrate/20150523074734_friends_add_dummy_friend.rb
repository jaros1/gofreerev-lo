class FriendsAddDummyFriend < ActiveRecord::Migration
  def change
    User.all.each do |u|
      next if u.provider == 'gofreerev'
      f = Friend.find_by_user_id_giver_and_user_id_receiver(u.user_id, u.user_id)
      next if f
      f = Friend.new
      f.user_id_giver = u.user_id
      f.user_id_receiver = u.user_id
      f.api_friend = 'Y'
      f.app_friend = nil
      f.save!
    end
  end
end
