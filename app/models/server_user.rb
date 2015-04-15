class ServerUser < ActiveRecord::Base

  # create_table "server_users", force: true do |t|
  #   t.integer  "server_id"
  #   t.integer  "user_id"
  #   t.datetime "verified_at"
  #   t.datetime "created_at"
  #   t.datetime "updated_at"
  #   t.integer  "pseudo_user_id"
  #   t.integer  "remote_pseudo_user_id"
  #   t.datetime "remote_sha256_updated_at"
  #   t.datetime "sha256_message_sent_at"
  #   t.datetime "sha256_message_received_at"
  # end
  # add_index "server_users", ["server_id", "user_id"], name: "index_server_users_pk", unique: true, using: :btree

  belongs_to :server
  belongs_to :user

  # 1) server_id. foreign key to servers
  validates_presence_of :server_id

  # 2) user_id. foreign key to users
  validates_presence_of :user_id

  # 3) verified_at timestamp for confirmed user match in compare users message.
  # sent user remote sha256 signature to other Gofreerev server and received correct user sha256 signature on this server
  # selected user information are identical on the two gofreerev servers - see User.calc_sha256

  # 4) pseudo_user_id. used as fallback user id in case of changed sha256 signatures ( changed user information )
  # one or both gofreerev servers must download and update user information to bring sha256 signatures in sync

  # 5) remote_pseudo_user_id. used as fallback user id in case of changed sha256 signatures ( changed user information )
  # one or both gofreerev servers must download and update user information to bring sha256 signatures in sync

  # 6) remote_sha256_updated_at. sha256_updated_at timestamp received from other gofreerev server

  # 7) sha256_message_sent_at. timestamp for last outgoing changed sha256 user signature message

  # 8) sha256_message_received_at. timestamp for last ingoing changed sha256 user signature message

end
