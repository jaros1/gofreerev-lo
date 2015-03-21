class ServerUserRequestsAddColumnPseudoUserId < ActiveRecord::Migration

  # old:
  # create_table "server_user_requests", force: true do |t|
  #   t.integer  "user_id",    null: false
  #   t.string   "sha256"
  #   t.datetime "created_at"
  #   t.datetime "updated_at"
  #   t.integer  "server_id",  null: false
  # end
  # add_index "server_user_requests", ["server_id", "user_id"], name: "index_server_user_requests_pk", unique: true, using: :btree

  # new:
  # create_table "server_user_requests", force: true do |t|
  #   t.integer  "pseudo_user_id", null: false
  #   t.string   "sha256"
  #   t.datetime "created_at"
  #   t.datetime "updated_at"
  #   t.integer  "server_id",      null: false
  #   t.integer  "user_id"
  # end
  # add_index "server_user_requests", ["server_id", "pseudo_user_id"], name: "index_server_user_requests_pk", unique: true, using: :btree

  def up
    remove_index :server_user_requests, :name => "index_server_user_requests_pk"
    rename_column :server_user_requests, :user_id, :pseudo_user_id
    add_index "server_user_requests", ["server_id", "pseudo_user_id"], name: "index_server_user_requests_pk", unique: true, using: :btree
    add_column :server_user_requests, :user_id, :integer
  end
  def down
    remove_column :server_user_requests, :user_id
    remove_index :server_user_requests, :name => "index_server_user_requests_pk"
    rename_column :server_user_requests, :user_id, :pseudo_user_id
    add_index "server_user_requests", ["server_id", "user_id"], name: "index_server_user_requests_pk", unique: true, using: :btree
  end

end
