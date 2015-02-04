class GiftsRenameGiftIdToGid < ActiveRecord::Migration
  
  # old:
  # create_table "gifts", force: true do |t|
  #   t.string   "gift_id",                limit: 20
  #   t.text     "description",                       null: false
  #   t.text     "currency",                          null: false
  #   t.text     "price"
  #   t.text     "received_at"
  #   t.datetime "created_at"
  #   t.datetime "updated_at"
  #   t.integer  "status_update_at",                  null: false
  #   t.datetime "deleted_at"
  #   t.string   "direction",              limit: 10
  #   t.string   "created_by",             limit: 10
  #   t.text     "balance_giver"
  #   t.text     "balance_receiver"
  #   t.text     "balance_doc_giver"
  #   t.text     "balance_doc_receiver"
  #   t.text     "app_picture_rel_path"
  #   t.text     "open_graph_url"
  #   t.string   "open_graph_title"
  #   t.text     "open_graph_description"
  #   t.text     "open_graph_image"
  # end
  # add_index "gifts", ["gift_id"], name: "index_gifts_on_gift_id", unique: true, using: :btree
  # add_index "gifts", ["status_update_at"], name: "index_gifts_on_status_updateat", unique: true, using: :btree

  # new:
  # create_table "gifts", force: true do |t|
  #   t.string   "gid",                limit: 20      null: false
  #   t.text     "description",                       null: false
  #   t.text     "currency",                          null: false
  #   t.text     "price"
  #   t.text     "received_at"
  #   t.datetime "created_at"
  #   t.datetime "updated_at"
  #   t.integer  "status_update_at",                  null: false
  #   t.datetime "deleted_at"
  #   t.string   "direction",              limit: 10
  #   t.string   "created_by",             limit: 10
  #   t.text     "balance_giver"
  #   t.text     "balance_receiver"
  #   t.text     "balance_doc_giver"
  #   t.text     "balance_doc_receiver"
  #   t.text     "app_picture_rel_path"
  #   t.text     "open_graph_url"
  #   t.string   "open_graph_title"
  #   t.text     "open_graph_description"
  #   t.text     "open_graph_image"
  # end
  # add_index "gifts", ["gid"], name: "index_gifts_on_gid", unique: true, using: :btree
  # add_index "gifts", ["status_update_at"], name: "index_gifts_on_status_updateat", unique: true, using: :btree

  def up
    remove_index :gifts, :name => "index_gifts_on_gift_id"
    rename_column :gifts, :gift_id, :gid
    change_column :gifts, :gid, :string, :null => false
    add_index "gifts", ["gid"], name: "index_gifts_on_gid", unique: true, using: :btree
  end
  def down
    remove_index :gifts, :name => "index_gifts_on_gid"
    rename_column :gifts, :gid, :gift_id
    change_column :gifts, :gift_id, :string, :null => true
    add_index "gifts", ["gift_id"], name: "index_gifts_on_gift_id", unique: true, using: :btree
  end

end
