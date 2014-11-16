class UsersAddColumnProfilePictureUrl < ActiveRecord::Migration
  def change
    add_column :users, :new_profile_picture_url, :text
  end
end
