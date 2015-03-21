class ServerUserRequest < ActiveRecord::Base

  # buffer used in server to server users message (comparing user information with help of sha256 signatures)
  # used in "reserve" request/response cycle
  # client-side: pseudo_user_id < 0 without user_id: received from "server" in ping response. Response in next ping request to "server"
  # server-side: pseudo_user_id > 0 with user_id: send from "server" to "client" in ping response. Response in next ping request

  # create_table "server_user_requests", force: true do |t|
  #   t.integer  "server_id",      null: false
  #   t.integer  "pseudo_user_id", null: false
  #   t.integer  "user_id"
  #   t.string   "sha256"
  #   t.datetime "created_at"
  #   t.datetime "updated_at"
  # end
  # add_index "server_user_requests", ["server_id", "pseudo_user_id"], name: "index_server_user_requests_pk", unique: true, using: :btree

  # 1: server_id. required.
  validates_presence_of :server_id

  # 2: pseudo_user_id. required. positive if received in ping request. negative if received in ping response. from sequence
  validates_presence_of :pseudo_user_id

  # 3: user_id. server-side. required if user_id > 0. save on "server" in ping response. received from "client" in next ping request
  validates_presence_of :user_id, :if => Proc.new { |rec| rec.pseudo_user_id and rec.pseudo_user_id >= 0 }
  validates_absence_of :user_id, :if => Proc.new { |rec| rec.pseudo_user_id and rec.pseudo_user_id < 0 }

  # 4: sha256. client-side. required if user_id < 0. save on "client" in ping response. sent to "server" in ping request
  validates_presence_of :sha256, :if => Proc.new { |rec| rec.pseudo_user_id and rec.pseudo_user_id < 0 }
  validates_absence_of :sha256, :if => Proc.new { |rec| rec.pseudo_user_id and rec.pseudo_user_id >= 0 }

end
