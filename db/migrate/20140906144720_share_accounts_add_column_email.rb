class ShareAccountsAddColumnEmail < ActiveRecord::Migration
  def up
    add_column :share_accounts, :share_account_id, :string, :limit => 20
    add_column :share_accounts, :email, :text
    ShareAccount.all.each do |sa|
      loop do
        sa.share_account_id = String.generate_random_string(20)
        break unless ShareAccount.find_by_share_account_id(sa.share_account_id)
      end
      sa.save!
    end
    change_column :share_accounts, :share_account_id, :string, :null => false
    add_index "share_accounts", ["share_account_id"], name: "index_share_accounts_accountid", unique: true
  end
  def down
    remove_index :share_accounts, name: "index_share_accounts_accountid"
    remove_column :share_accounts, :share_account_id
    remove_column :share_accounts, :email
  end
end
