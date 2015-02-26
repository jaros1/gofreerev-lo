class GiftsDropColumnReceivedAt < ActiveRecord::Migration
  def up
    remove_column :gifts, :received_at
  end
  def down
    add_column :gifts, :received_at, :text
  end
end
