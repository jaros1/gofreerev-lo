class GiftsAddLastRequestAt < ActiveRecord::Migration
  def up
    add_column :gifts, :last_request_at, :date
  end
  def down
    remove_column :gifts, :last_request_at
  end
end
