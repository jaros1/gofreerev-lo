class GiftsRemoveColumnDescription < ActiveRecord::Migration

  # old: t.text     "description",                       null: false

  def up
    remove_column :gifts, :description
  end

  def down
    add_column :gifts, :description, :text
  end

end
