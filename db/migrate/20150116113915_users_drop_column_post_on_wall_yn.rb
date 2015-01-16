class UsersDropColumnPostOnWallYn < ActiveRecord::Migration
  def up
    remove_column :users, :post_on_wall_yn
  end
  def down
    add_column :users, :post_on_wall_yn, :string, :limit => 1
  end
end
