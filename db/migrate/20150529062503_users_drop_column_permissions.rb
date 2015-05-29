class UsersDropColumnPermissions < ActiveRecord::Migration
  def up
    remove_column :users, :permissions
  end
  def down
    add_column :users, :permissions, :text
  end
end
