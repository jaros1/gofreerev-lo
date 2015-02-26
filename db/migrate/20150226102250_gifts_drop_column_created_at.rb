class GiftsDropColumnCreatedAt < ActiveRecord::Migration
  def up
    remove_column :gifts, :created_at
  end
  def down
    add_column :gifts, :created_at, :datetime
  end
end
