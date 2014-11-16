class UsersAddColumnApiProfileUrl < ActiveRecord::Migration
  def change
    add_column :users, :api_profile_url, :text
  end
end
