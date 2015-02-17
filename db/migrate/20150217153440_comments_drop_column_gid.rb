class CommentsDropColumnGid < ActiveRecord::Migration

  # t.string   "gid",                         null: false

  def up
    remove_index :comments, :name => "index_comments_on_gid"
    remove_column :comments, :gid
  end
  def down
    add_column :comments, :gid, :string
    add_index "comments", ["gid"], name: "index_comments_on_gid", using: :btree
  end

end
