class SessionsAddPostOnWallColumns < ActiveRecord::Migration
  # move two post_on_wall from session cookie to session table
  def change
    add_column :sessions, :post_on_wall_selected, :text
    add_column :sessions, :post_on_wall_authorized, :text
  end
end
