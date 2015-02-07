class GiftsAddColumnSha256Signature < ActiveRecord::Migration
  def up
    add_column :gifts, :sha256, :string, :limit => 32
    change_column :gifts, :gid, :string, :limit => 20
  end
  def down
    remove_column :gifts, :sha256
    change_column :gifts, :gid, :string, :limit => nil
  end
end
