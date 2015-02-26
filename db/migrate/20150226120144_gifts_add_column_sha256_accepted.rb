class GiftsAddColumnSha256Accepted < ActiveRecord::Migration
  def up
    add_column :gifts, :sha256_accepted, :string, :limit => 45
  end
  def down
    remove_column :gifts, :sha256_accepted
  end
end
