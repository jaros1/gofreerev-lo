class CommentsRenameCommentIdToCid < ActiveRecord::Migration

  # old:     t.string   "comment_id",       limit: 20, null: false
  # new:     t.string   "cid",       limit: 20, null: false

  def up
    Comment.delete_all
    remove_index :comments, :name => "index_comments_on_comment_id"
    rename_column :comments, :comment_id, :cid
    add_index "comments", ["cid"], name: "index_comments_on_cid", unique: true, using: :btree
  end
  def down
    Comment.delete_all
    remove_index :comments, :name => "index_comments_on_cid"
    rename_column :comments, :cid, :comment_id
    add_index "comments", ["comment_id"], name: "index_comments_on_comment_id", unique: true, using: :btree
  end

end
