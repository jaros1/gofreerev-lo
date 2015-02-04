class ApiCommentsRenameGiftIdToGid < ActiveRecord::Migration

  # old:
  # create_table "api_comments", force: true do |t|
  #   t.string   "gift_id",    limit: 20
  #   t.string   "comment_id", limit: 20
  #   t.string   "provider",   limit: 20
  #   t.string   "user_id",    limit: 40
  #   t.datetime "created_at"
  #   t.datetime "updated_at"
  #   t.datetime "deleted_at"
  # end
  # add_index "api_comments", ["comment_id"], name: "index_api_comments_on_comm_id", using: :btree
  # add_index "api_comments", ["gift_id"], name: "index_api_comments_on_gift_id", using: :btree
  # add_index "api_comments", ["user_id"], name: "index_api_comments_on_user_id", using: :btree

  # new:
  # create_table "api_comments", force: true do |t|
  #   t.string   "gid",    limit: 20, null: false
  #   t.string   "comment_id", limit: 20
  #   t.string   "provider",   limit: 20
  #   t.string   "user_id",    limit: 40
  #   t.datetime "created_at"
  #   t.datetime "updated_at"
  #   t.datetime "deleted_at"
  # end
  # add_index "api_comments", ["comment_id"], name: "index_api_comments_on_comm_id", using: :btree
  # add_index "api_comments", ["gid"], name: "index_api_comments_on_gid", using: :btree
  # add_index "api_comments", ["user_id"], name: "index_api_comments_on_user_id", using: :btree
  
  def up
    remove_index :api_comments, :name => "index_api_comments_on_gift_id"
    rename_column :api_comments, :gift_id, :gid
    change_column :api_comments, :gid, :string, :null => false
    add_index "api_comments", ["gid"], name: "index_api_comments_on_gid", using: :btree
  end
  def down
    remove_index :api_comments, :name => "index_api_comments_on_gid"
    rename_column :api_comments, :gid, :gift_id
    change_column :api_comments, :gift_id, :string, :null => true
    add_index "api_comments", ["gift_id"], name: "index_api_comments_on_gift_id", using: :btree
  end

end
