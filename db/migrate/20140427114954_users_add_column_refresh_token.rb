class UsersAddColumnRefreshToken < ActiveRecord::Migration
  def change
    add_column :users, :refresh_token, :text
  end
end
