class ShareAccountsAddColumnOfflineAccessYn < ActiveRecord::Migration
  def change
    add_column :share_accounts, :offline_access_yn, :string, :limit => 1, :default => 'N'
    ShareAccount.update_all("offline_access_yn = 'N'")
  end
end
