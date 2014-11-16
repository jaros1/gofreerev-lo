class UserDropColumnProfilePictureUrl < ActiveRecord::Migration
  def up
    remove_column :users, :profile_picture_url
  end
  def down
    add_column :users, :profile_picture_url, :text
  end
end
