class UsersAddColumnSha256 < ActiveRecord::Migration
  def change
    add_column :users, :sha256, :string, :limit => 45
    add_index "users", ["sha256"], name: "index_users_sha256", unique: true, using: :btree
  end
end
