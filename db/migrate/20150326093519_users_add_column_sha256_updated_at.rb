class UsersAddColumnSha256UpdatedAt < ActiveRecord::Migration
  def change
    add_column :users, :sha256_updated_at, :datetime
  end
end
