class ShareAccountsInitialize < ActiveRecord::Migration
  def change
    share_accounts = User.where('share_account_id is not null').collect { |u| u.share_account_id }.uniq
    share_accounts.each do |share_account_id|
      sa = ShareAccount.new
      sa.id = share_account_id
      sa.share_level = 2
      sa.save!
    end
  end
end
