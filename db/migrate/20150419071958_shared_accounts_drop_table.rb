class SharedAccountsDropTable < ActiveRecord::Migration
  def up
    drop_table :share_accounts
    remove_index :users, :name => 'index_users_share_account_id'
    remove_columns :users, :share_account_id
  end
  def down
    add_column :users, :share_account_id, :string, :limit => 20
    add_index "users", ["share_account_id"], name: "index_users_share_account_id", using: :btree
    create_table "share_accounts", force: true do |t|
      t.integer  "share_level"
      t.datetime "created_at"
      t.datetime "updated_at"
      t.integer  "no_users"
      t.string   "share_account_id", limit: 20, null: false
      t.text     "email"
    end
    add_index "share_accounts", ["share_account_id"], name: "index_share_accounts_accountid", unique: true, using: :btree
  end
end
