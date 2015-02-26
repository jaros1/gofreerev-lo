class GiftsDropColumnDeletedAt < ActiveRecord::Migration
  def up
    remove_column :gifts, :deleted_at
  end
  def down
    add_column :gifts, :deleted_at, :datetime
  end
end
