class UsersChangeColumnShareAccountId < ActiveRecord::Migration
  # integer => string
  def up
    remove_index "users", name: "index_users_share_account_id"
    change_column :users, :share_account_id, :string, :limit => 20
    User.all.each do |u|
      next unless u.share_account_id
      share_account_id = ShareAccount.find(u.share_account_id).share_account_id
      u.update_attribute(:share_account_id, share_account_id)
    end
    add_index "users", ["share_account_id"], name: "index_users_share_account_id"
  end
  # string => integer
  def down
    remove_index "users", name: "index_users_share_account_id"
    rename_column :users, :share_account_id, :share_account_id_string
    add_column :users, :share_account_id, :integer
    User.all.each do |u|
      next unless u.share_account_id_string
      sa = ShareAccount.find_by_share_account_id(u.share_account_id_string)
      u.update_attribute(:share_account_id, sa.id)
    end
    remove_column :users, :share_account_id_string
    add_index "users", ["share_account_id"], name: "index_users_share_account_id"
  end
end
