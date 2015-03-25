class UsersAddColumnOldSha256 < ActiveRecord::Migration
  def change
    add_column :users, :old_sha256, :string, :limit => 45
  end
end
