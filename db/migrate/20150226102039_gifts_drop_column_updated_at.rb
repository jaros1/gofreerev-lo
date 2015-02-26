class GiftsDropColumnUpdatedAt < ActiveRecord::Migration
  def up
    remove_column :gifts, :updated_at
  end
  def down
    add_column :gifts, :updated_at, :datetime
  end
end
