class UsersDropColumnProfilePictureName < ActiveRecord::Migration
  def up
    remove_column :users, :profile_picture_name
  end
  def down
    add_column :users, :profile_picture_name, :string, :limit => 20
  end
end
