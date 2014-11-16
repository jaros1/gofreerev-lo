class UsersAddColumnApiProfilePictureUrl < ActiveRecord::Migration
  def change
    add_column :users, :api_profile_picture_url, :text
  end
end
