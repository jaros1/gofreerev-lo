class GiftsRemoveCreatedBy < ActiveRecord::Migration

  # t.string   "created_by",       limit: 10

  def up
    remove_column :gifts, :created_by
  end
  def down
    add_column :gifts, :created_by, :string, :limit => 10
  end
end
