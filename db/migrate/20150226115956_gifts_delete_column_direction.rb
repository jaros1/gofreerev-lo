class GiftsDeleteColumnDirection < ActiveRecord::Migration
  def up
    remove_column :gifts, :direction
  end
  def down
    add_column :gifts, :direction, :string, :limit => 10
  end
end
