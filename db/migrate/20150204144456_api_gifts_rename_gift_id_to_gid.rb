class ApiGiftsRenameGiftIdToGid < ActiveRecord::Migration

  # old:
  # create_table "api_gifts", force: true do |t|
  #   t.string   "gift_id",                     limit: 20
  #   t.string   "provider",                    limit: 20
  #   t.string   "user_id_giver",               limit: 40
  #   t.string   "user_id_receiver",            limit: 40
  #   t.string   "picture",                     limit: 1
  #   t.text     "api_gift_id"
  #   t.text     "api_picture_url"
  #   t.text     "api_picture_url_updated_at"
  #   t.text     "api_picture_url_on_error_at"
  #   t.string   "deleted_at_api",              limit: 1
  #   t.datetime "created_at"
  #   t.datetime "updated_at"
  #   t.string   "deep_link_id",                limit: 20
  #   t.text     "deep_link_pw"
  #   t.integer  "deep_link_errors"
  #   t.text     "api_gift_url"
  #   t.datetime "deleted_at"
  # end
  # add_index "api_gifts", ["deep_link_id"], name: "index_api_gifts_deep_link_id", using: :btree
  # add_index "api_gifts", ["gift_id", "provider"], name: "index_api_gifts_on_gift_id", unique: true, using: :btree
  # add_index "api_gifts", ["user_id_giver"], name: "index_api_gifts_on_giver", using: :btree
  # add_index "api_gifts", ["user_id_receiver"], name: "index_api_gifts_on_receiver", using: :btree

  # new:
  # create_table "api_gifts", force: true do |t|
  #   t.string   "gid",                     limit: 20, :null: false
  #   t.string   "provider",                    limit: 20
  #   t.string   "user_id_giver",               limit: 40
  #   t.string   "user_id_receiver",            limit: 40
  #   t.string   "picture",                     limit: 1
  #   t.text     "api_gift_id"
  #   t.text     "api_picture_url"
  #   t.text     "api_picture_url_updated_at"
  #   t.text     "api_picture_url_on_error_at"
  #   t.string   "deleted_at_api",              limit: 1
  #   t.datetime "created_at"
  #   t.datetime "updated_at"
  #   t.string   "deep_link_id",                limit: 20
  #   t.text     "deep_link_pw"
  #   t.integer  "deep_link_errors"
  #   t.text     "api_gift_url"
  #   t.datetime "deleted_at"
  # end
  # add_index "api_gifts", ["deep_link_id"], name: "index_api_gifts_deep_link_id", using: :btree
  # add_index "api_gifts", ["gid", "provider"], name: "index_api_gifts_on_gid", unique: true, using: :btree
  # add_index "api_gifts", ["user_id_giver"], name: "index_api_gifts_on_giver", using: :btree
  # add_index "api_gifts", ["user_id_receiver"], name: "index_api_gifts_on_receiver", using: :btree

  def up
    remove_index :api_gifts, :name => "index_api_gifts_on_gift_id"
    rename_column :api_gifts, :gift_id, :gid
    change_column :api_gifts, :gid, :string, :null => false
    add_index "api_gifts", ["gid", "provider"], name: "index_api_gifts_on_gid", unique: true, using: :btree
  end
  def down
    remove_index :api_gifts, :name => "index_api_gifts_on_gid"
    change_column :api_gifts, :gid, :string, :null => true
    rename_column :api_gifts, :gid, :gift_id
    add_index "api_gifts", ["gift_id", "provider"], name: "index_api_gifts_on_gift_id", unique: true, using: :btree
  end

end
