class Pubkey < ActiveRecord::Base

  # create_table "pubkeys", force: true do |t|
  #   t.string   "did",        limit: 20, null: false
  #   t.text     "pubkey"
  #   t.integer  "server_id"
  #   t.datetime "client_request_at"
  #   t.datetime "created_at"
  #   t.datetime "updated_at"
  # end
  # add_index "pubkeys", ["did"], name: "index_pubkey_did", unique: true, using: :btree

  belongs_to :server

  # 1) did - unique device id - unix timestamp with milliseconds (13) + 7 random decimals
  validates_presence_of :did
  validates_format_of :did, :with => /\A[0-9]{20}\z/, :allow_blank => true

  # 2) pubkey - public key - used in client to client rsa encryption
  # required for clients on current Gofreerev server. optional for clients on other gofreerev servers
  validates_presence_of :pubkey, :if => Proc.new { |rec| !rec.server_id }

  # 3) server_id - optional server id - used if device on an other gofreerev server.
  # did previous received in a online users server to server message
  # pubkey

  # 4) optional client_request_at - only used for public keys for devices on other gofreerev servers
  # a client has requested public key for did
  # should be returned in a later server to server ping message
  validates_absence_of :client_request_at, :if => Proc.new { |rec| !rec.server_id }

end
