class CommentsAddColumnSha256 < ActiveRecord::Migration

  # old:
  # create_table "comments", force: true do |t|
  #   t.datetime "created_at"
  #   t.datetime "updated_at"
  #   t.string   "cid",        limit: 20
  # end
  # add_index "comments", ["cid"], name: "index_comments_on_cid", unique: true, using: :btree

  def up
    change_column :comments, :cid, :string, :null => false
    add_column :comments, :sha256, :string, :null => false, :limit => 45
  end
  def down
    remove_column :comments, :sha256
    change_column :comments, :cid, :string, :null => true
  end

end
