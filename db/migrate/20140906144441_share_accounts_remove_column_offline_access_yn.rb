class ShareAccountsRemoveColumnOfflineAccessYn < ActiveRecord::Migration
  def up
    remove_column :share_accounts, :offline_access_yn
  end
  def down
    add_column :share_accounts, :offfline_acceses_yn, :limit => 1, :default => "N"
  end
end
