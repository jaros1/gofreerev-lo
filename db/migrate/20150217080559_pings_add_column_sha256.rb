class PingsAddColumnSha256 < ActiveRecord::Migration
  def up
    add_column :pings, :sha256, :string, :limit => 45
  end
  def down
    remove_column :pings, :sha256
  end
end
