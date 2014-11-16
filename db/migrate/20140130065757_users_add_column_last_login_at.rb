class UsersAddColumnLastLoginAt < ActiveRecord::Migration
  def change
    add_column :users, :last_login_at, :datetime
    (User.where(:user_id => ApiGift.select("user_id_giver")) + User.where(:user_id => ApiGift.select("user_id_receiver"))).uniq.each do |u|
      u.update_attribute(:last_login_at, u.updated_at)
    end
  end
end
