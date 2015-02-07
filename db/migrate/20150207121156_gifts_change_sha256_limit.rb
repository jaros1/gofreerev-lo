class GiftsChangeSha256Limit < ActiveRecord::Migration

  # t.string   "sha256",      limit: 32

  def up
    change_column :gifts, :sha256, :string, :limit => 45
  end
  def down
    change_column :gifts, :sha256, :string, :limit => 32
  end

end
