class RemoteSession < ActiveRecord::Base

  # translate session id to pseudo session id before sending online users message to other Gofreerev server

  # create_table "remote_sessions", force: true do |t|
  #   t.string   "session_id",        limit: 32, null: false
  #   t.integer  "pseudo_session_id",            null: false
  #   t.datetime "created_at"
  #   t.datetime "updated_at"
  # end
  # add_index "remote_sessions", ["session_id"], name: "index_remote_session_pk", unique: true, using: :btree

  # 1) session_id. session_id on this Gofreerev server
  validates_presence_of :session_id
  validates_uniqueness_of :session_id, :allow_blank => true

  # 2) pseudo_session_id: pseudo session_id for pings sent to other Gofreerev servers. From sequence
  # used in online users server to server message
  validates_presence_of :pseudo_session_id

end
