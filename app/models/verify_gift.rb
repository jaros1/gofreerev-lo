class VerifyGift < ActiveRecord::Base

  # table with remote gift verification
  # client_sid, client_sha256, client_seq, server_id and gid from client verify_gifts request
  # server_seq from server sequence and used as seq in server to server verify gift message
  # verified_at_server is response from server to server verify gifts message to be returned to client in next ping request

  create_table "verify_gifts", force: true do |t|
    t.string   "client_sid",         limit: 20, null: false
    t.string   "client_sha256",      limit: 45, null: false
    t.integer  "client_seq",                    null: false
    t.integer  "server_id",                     null: false
    t.string   "gid",                limit: 20, null: false
    t.integer  "server_seq",                    null: false
    t.boolean  "verified_at_server"
    t.datetime "created_at"
    t.datetime "updated_at"
  end
  add_index "verify_gifts", ["client_sid", "client_sha256", "client_seq"], name: "index_verify_gift_pk", unique: true, using: :btree
  add_index "verify_gifts", ["server_seq"], name: "index_verify_gift_uk", unique: true, using: :btree

  # 1) client_sid - unique session id from browser client ( = a browser tab )
  validates_presence_of :client_sid

  # 2) client_sha256 - sha256 signature for unique device - changes if client login changes
  validates_presence_of :client_sha256

  # 3) client_seq - unique client seq from client verify_gifts request - always negative for remote gift verification
  validates_presence_of :client_seq
  validates_uniqueness_of :client_seq, :scope => %w(client_sid client_sha), :allow_blank => true

  # 4) server_id - server id from client verify gifts request
  validates_presence_of :server_id

  # 5) gid - unique gift ud from client verify gifts request
  validates_presence_of :gid

  # 6) server_seq - unique - server sequence - used in server to server verify gifts message
  validates_presence_of :server_seq
  validates_uniqueness_of :server_seq, :allow_blank => true

  # 7) verified_at_server boolean - response from gift verification
  validates_inclusion_of :verified_at_server, :in => [true, false]

end
