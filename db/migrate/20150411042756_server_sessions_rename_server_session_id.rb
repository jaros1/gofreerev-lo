class ServerSessionsRenameServerSessionId < ActiveRecord::Migration

  # old 1:
  # create_table "server_sessions", force: true do |t|
  #   t.integer  "server_id",         null: false
  #   t.integer  "session_id",        null: false
  #   t.integer  "server_session_id", null: false
  #   t.datetime "created_at"
  #   t.datetime "updated_at"
  # end
  # add_index "server_sessions", ["server_id", "server_session_id"], name: "index_server_session_pk", unique: true, using: :btree
  # add_index "server_sessions", ["session_id"], name: "index_server_session_uk", unique: true, using: :btree

  def up
    remove_index "server_sessions", :name => "index_server_session_pk"
    rename_column "server_sessions", "server_session_id", "remote_session_id"
    add_index "server_sessions", ["server_id", "remote_session_id"], name: "index_server_session_pk", unique: true, using: :btree
  end
  def down
    remove_index "server_sessions", :name => "index_server_session_pk"
    rename_column "server_sessions", "remote_session_id", "server_session_id"
    add_index "server_sessions", ["server_id", "server_session_id"], name: "index_server_session_pk", unique: true, using: :btree
  end

end
