class ServerSession < ActiveRecord::Base

  # translate pseudo session id received from other gofreerev server to pseudo session id used on this gofreerev server
  # (online users message)

  # create_table "server_sessions", force: true do |t|
  #   t.integer  "server_id",         null: false
  #   t.integer  "session_id",        null: false
  #   t.integer  "remote_session_id", null: false
  #   t.datetime "created_at"
  #   t.datetime "updated_at"
  # end
  # add_index "server_sessions", ["server_id", "remote_session_id"], name: "index_server_session_pk", unique: true, using: :btree
  # add_index "server_sessions", ["session_id"], name: "index_server_session_uk", unique: true, using: :btree

  # 1: server_id
  validates_presence_of :server_id

  # 2: session_id - pseudo session id used on this Gofreerev server
  # generated when receiving online users message from other gofreerev servers
  validates_presence_of :session_id
  validates_uniqueness_of :session_id, :allow_blank => true, :scope => :server_id

  # 3: remote_session_id - pseudo session id received in online users message from other Gofreerev server
  # must be translated to pseudo session id on this gofreerev server
  validates_presence_of :remote_session_id
  validates_uniqueness_of :remote_session_id, :allow_blank => true

end
