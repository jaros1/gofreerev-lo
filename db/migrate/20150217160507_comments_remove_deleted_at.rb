class CommentsRemoveDeletedAt < ActiveRecord::Migration

  # old:
  # create_table "comments", force: true do |t|
  #   t.datetime "created_at"
  #   t.datetime "updated_at"
  #   t.string   "new_deal_yn",      limit: 1
  #   t.string   "accepted_yn",      limit: 1
  #   t.integer  "status_update_at",            null: false
  #   t.datetime "deleted_at"
  #   t.string   "updated_by"
  #   t.string   "cid",              limit: 20
  # end
  # add_index "comments", ["cid"], name: "index_comments_on_cid", unique: true, using: :btree
  # add_index "comments", ["deleted_at"], name: "index_comments_on_deleted_at", using: :btree

  def up
    remove_index :comments, :name => "index_comments_on_deleted_at"
    remove_column :comments, :deleted_at
  end
  def down
    add_column :comments, :deleted_at, :datetime
    add_index "comments", ["deleted_at"], name: "index_comments_on_deleted_at", using: :btree
  end

end
