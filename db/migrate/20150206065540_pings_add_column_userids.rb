class PingsAddColumnUserids < ActiveRecord::Migration
  def up
    add_column :pings, :user_ids, :text
  end
  def down
    remove_column :pings, :user_ids
  end
end
