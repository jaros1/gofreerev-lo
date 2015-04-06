class ServerUsersAddPseudoUserIdColumns < ActiveRecord::Migration
  def change
    add_column :server_users, :pseudo_user_id, :integer
    add_column :server_users, :remote_pseudo_user_id, :integer
  end
end
