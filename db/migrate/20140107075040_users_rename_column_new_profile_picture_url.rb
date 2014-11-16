class UsersRenameColumnNewProfilePictureUrl < ActiveRecord::Migration
  def change
    rename_column :users, :new_profile_picture_url, :profile_picture_url
  end
end
