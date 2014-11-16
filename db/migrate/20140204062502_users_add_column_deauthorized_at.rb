class UsersAddColumnDeauthorizedAt < ActiveRecord::Migration
  def change
    add_column :users, :deauthorized_at, :datetime
  end
end
