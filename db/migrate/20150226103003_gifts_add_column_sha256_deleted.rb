class GiftsAddColumnSha256Deleted < ActiveRecord::Migration
  def up
    add_column :gifts, :sha256_deleted, :string, :limit => 45
  end
end
