class UsersAddColumnPostOnWallYn < ActiveRecord::Migration
  def change
    add_column :users, :post_on_wall_yn, :string, :limit => 1
    User.all.each do |u|
      u.update_attribute(:post_on_wall_yn, (API_POST_PERMITTED[u.provider] ? 'Y' : 'N'))
    end
  end
end
