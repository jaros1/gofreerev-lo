class GiftsChangeSha256NotNull < ActiveRecord::Migration
  def up
    Gift.where("sha256 is null").delete_all
    change_column :gifts, :sha256, :string, :limit => 45, :null => false
  end
  def down
    change_column :gifts, :sha256, :string, :limit => 45, :null => true
  end
end
