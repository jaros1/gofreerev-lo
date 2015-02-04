class CommentsRenameGiftIdToGid < ActiveRecord::Migration

  # old:
  # create_table "comments", force: true do |t|
  #   t.string   "comment_id",       limit: 20, null: false
  #   t.text     "comment",                     null: false
  #   t.datetime "created_at"
  #   t.datetime "updated_at"
  #   t.string   "gift_id",          limit: 20
  #   t.text     "currency"
  #   t.text     "price"
  #   t.string   "new_deal_yn",      limit: 1
  #   t.string   "accepted_yn",      limit: 1
  #   t.integer  "status_update_at",            null: false
  #   t.datetime "deleted_at"
  #   t.string   "updated_by"
  # end
  # add_index "comments", ["comment_id"], name: "index_comments_on_comment_id", unique: true, using: :btree
  # add_index "comments", ["deleted_at"], name: "index_comments_on_deleted_at", using: :btree
  # add_index "comments", ["gift_id"], name: "index_comments_on_gift_id", using: :btree

  # new:
  # create_table "comments", force: true do |t|
  #   t.string   "comment_id",       limit: 20, null: false
  #   t.text     "comment",                     null: false
  #   t.datetime "created_at"
  #   t.datetime "updated_at"
  #   t.string   "gid",          limit: 20, null: false
  #   t.text     "currency"
  #   t.text     "price"
  #   t.string   "new_deal_yn",      limit: 1
  #   t.string   "accepted_yn",      limit: 1
  #   t.integer  "status_update_at",            null: false
  #   t.datetime "deleted_at"
  #   t.string   "updated_by"
  # end
  # add_index "comments", ["comment_id"], name: "index_comments_on_comment_id", unique: true, using: :btree
  # add_index "comments", ["deleted_at"], name: "index_comments_on_deleted_at", using: :btree
  # add_index "comments", ["gid"], name: "index_comments_on_gid", using: :btree

  def up
    remove_index :comments, :name => "index_comments_on_gift_id"
    rename_column :comments, :gift_id, :gid
    change_column :comments, :gid, :string, :null => false
    add_index "comments", ["gid"], name: "index_comments_on_gid", using: :btree
  end

  def down
    remove_index :comments, :name => "index_comments_on_gid"
    change_column :comments, :gid, :string, :null => true
    rename_column :comments, :gid, :gift_id
    add_index "comments", ["gift_id"], name: "index_comments_on_gift_id", using: :btree
  end

end
