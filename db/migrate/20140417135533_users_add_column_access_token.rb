class UsersAddColumnAccessToken < ActiveRecord::Migration
  def change
    add_column :users, :access_token, :text # 43
    add_column :users, :access_token_expires, :text # 44
  end
end
