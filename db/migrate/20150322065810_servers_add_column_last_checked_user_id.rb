class ServersAddColumnLastCheckedUserId < ActiveRecord::Migration
  def change
    add_column :servers, :last_checked_user_id, :integer
  end
end
