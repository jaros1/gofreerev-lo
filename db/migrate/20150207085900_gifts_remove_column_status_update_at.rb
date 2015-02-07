class GiftsRemoveColumnStatusUpdateAt < ActiveRecord::Migration

  # t.integer  "status_update_at",            null: false

  def up
    remove_column :gifts, :status_update_at
  end
  def down
    add_column :gifts, :status_update_at, :integer
  end

end
