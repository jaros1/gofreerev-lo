class ServerUserRequest < ActiveRecord::Base

  # buffer used in server to server users message (comparing user information with help of sha256 signatures)
  # "reserve" request/response cycle
  # user_id < 0: received from "server" in ping response. Response in next ping request
  # user_id > 0: send to "client" in ping response. Response in next ping request

  # create_table "server_user_requests", force: true do |t|
  #   t.integer  "server_id",  null: false
  #   t.integer  "user_id",    null: false
  #   t.string   "sha256"
  #   t.datetime "created_at"
  #   t.datetime "updated_at"
  # end
  # add_index "server_user_requests", ["server_id", "user_id"], name: "index_server_user_requests_pk", unique: true, using: :btree

  # 1: server_id. required.
  validates_presence_of :server_id

  # 2: user_id. required. positive if received in ping request. negative if received in ping response
  # user_id is sequence or user_id on other gofreeerev server. Not foreign key to users table on this server
  # todo: rename to seq. don't send internal user_id in server to server communication
  validates_presence_of :user_id

  # sha256. required if user_id < 0
  validates_presence_of :sha256, :if => Proc.new { |rec| rec.user_id and rec.user_id < 0 }
  validates_absence_of :sha256, :if => Proc.new { |rec| rec.user_id and rec.user_id >= 0 }

end
