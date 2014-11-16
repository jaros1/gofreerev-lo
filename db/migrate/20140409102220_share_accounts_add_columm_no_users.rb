class ShareAccountsAddColummNoUsers < ActiveRecord::Migration
  def change
    add_column :share_accounts, :no_users, :integer
    ShareAccount.all.includes(:users).each do |sa|
      sa.no_users = sa.users.size
      sa.save!
    end
  end
end
