class UsersRenameColumnUserCombination < ActiveRecord::Migration
  def up
    remove_index :users, :name => "index_users_user_combination"
    rename_column :users, :user_combination, :share_account_id
    add_index "users", ["share_account_id"], name: "index_users_share_account_id"
  end
  def down
    remove_index :users, :name => "index_users_share_account_id"
    rename_column :users, :share_account_id, :user_combination
    add_index "users", ["user_combination"], name: "index_users_user_combination"
  end
end
