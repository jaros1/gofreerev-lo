class SessionsDropColumnPostOnWallColumns < ActiveRecord::Migration
  def up
    remove_column :sessions, :post_on_wall_authorized
    remove_column :sessions, :post_on_wall_selected
  end
  def down
    add_column :sessions, :post_on_wall_authorized, :text
    add_column :sessions, :post_on_wall_selected, :text
  end
end
