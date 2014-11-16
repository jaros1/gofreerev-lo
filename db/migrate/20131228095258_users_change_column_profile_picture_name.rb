class UsersChangeColumnProfilePictureName < ActiveRecord::Migration
  def up
    change_column :users, :profile_picture_name, :string, :limit => 20
  end
  def down
    change_column :users, :profile_picture_name, :string, :limit => 10
  end
end
