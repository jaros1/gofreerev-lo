class UsersAddSha256UpdatedAtIndex < ActiveRecord::Migration
  def change
    add_index "users", ["sha256_updated_at"], name: "index_users_on_sha256_updated", using: :btree
  end
end
