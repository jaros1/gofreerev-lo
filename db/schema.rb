# encoding: UTF-8
# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# Note that this schema.rb definition is the authoritative source for your
# database schema. If you need to create the application database on another
# system, you should be using db:schema:load, not running all the migrations
# from scratch. The latter is a flawed and unsustainable approach (the more migrations
# you'll amass, the slower it'll run and the greater likelihood for issues).
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema.define(version: 20150709160027) do

  create_table "ajax_comments", force: true do |t|
    t.string   "user_id",    limit: 40, null: false
    t.string   "comment_id", limit: 20, null: false
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  add_index "ajax_comments", ["user_id"], name: "index_ajax_comments_on_user_id", using: :btree

  create_table "api_comments", force: true do |t|
    t.string   "gid",                   null: false
    t.string   "comment_id", limit: 20
    t.string   "provider",   limit: 20
    t.string   "user_id",    limit: 40
    t.datetime "created_at"
    t.datetime "updated_at"
    t.datetime "deleted_at"
  end

  add_index "api_comments", ["comment_id"], name: "index_api_comments_on_comm_id", using: :btree
  add_index "api_comments", ["gid"], name: "index_api_comments_on_gid", using: :btree
  add_index "api_comments", ["user_id"], name: "index_api_comments_on_user_id", using: :btree

  create_table "api_comments_notifications", id: false, force: true do |t|
    t.integer "notification_id"
    t.integer "api_comment_id"
  end

  add_index "api_comments_notifications", ["api_comment_id", "notification_id"], name: "index_api_com_no_on_api_com_id", unique: true, using: :btree
  add_index "api_comments_notifications", ["notification_id"], name: "index_comm_noti_on_noti_id", using: :btree

  create_table "api_gifts", force: true do |t|
    t.string   "gid",                                    null: false
    t.string   "provider",                    limit: 20
    t.string   "user_id_giver",               limit: 40
    t.string   "user_id_receiver",            limit: 40
    t.string   "picture",                     limit: 1
    t.text     "api_gift_id"
    t.text     "api_picture_url"
    t.text     "api_picture_url_updated_at"
    t.text     "api_picture_url_on_error_at"
    t.string   "deleted_at_api",              limit: 1
    t.datetime "created_at"
    t.datetime "updated_at"
    t.string   "deep_link_id",                limit: 20
    t.text     "deep_link_pw"
    t.integer  "deep_link_errors"
    t.text     "api_gift_url"
    t.datetime "deleted_at"
  end

  add_index "api_gifts", ["deep_link_id"], name: "index_api_gifts_deep_link_id", using: :btree
  add_index "api_gifts", ["gid", "provider"], name: "index_api_gifts_on_gid", unique: true, using: :btree
  add_index "api_gifts", ["user_id_giver"], name: "index_api_gifts_on_giver", using: :btree
  add_index "api_gifts", ["user_id_receiver"], name: "index_api_gifts_on_receiver", using: :btree

  create_table "comments", force: true do |t|
    t.datetime "created_at"
    t.datetime "updated_at"
    t.string   "cid",                       null: false
    t.string   "sha256",         limit: 45, null: false
    t.string   "sha256_action",  limit: 45
    t.string   "sha256_deleted", limit: 45
  end

  add_index "comments", ["cid"], name: "index_comments_on_cid", unique: true, using: :btree

  create_table "exchange_rates", force: true do |t|
    t.string   "from_currency", limit: 3,                          null: false
    t.string   "to_currency",   limit: 3,                          null: false
    t.decimal  "exchange_rate",           precision: 10, scale: 0
    t.datetime "created_at"
    t.datetime "updated_at"
    t.string   "date",          limit: 8,                          null: false
  end

  add_index "exchange_rates", ["from_currency", "to_currency", "date"], name: "index_exchange_rates_pk", unique: true, using: :btree

  create_table "flashes", force: true do |t|
    t.text     "message"
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  create_table "friends", force: true do |t|
    t.string   "user_id_giver",    limit: 40
    t.string   "user_id_receiver", limit: 40
    t.datetime "created_at"
    t.datetime "updated_at"
    t.text     "api_friend"
    t.text     "app_friend"
    t.string   "friend_id",        limit: 20
  end

  add_index "friends", ["friend_id"], name: "index_friends_on_friend_id", unique: true, using: :btree
  add_index "friends", ["user_id_giver", "user_id_receiver"], name: "index_friends_on_giver", unique: true, using: :btree
  add_index "friends", ["user_id_receiver", "user_id_giver"], name: "index_friends_on_receiver", unique: true, using: :btree

  create_table "gifts", force: true do |t|
    t.string "gid",             limit: 20, null: false
    t.string "sha256",          limit: 45, null: false
    t.string "sha256_deleted",  limit: 45
    t.string "sha256_accepted", limit: 45
    t.date   "last_request_at"
  end

  add_index "gifts", ["gid"], name: "index_gifts_on_gid", unique: true, using: :btree

  create_table "messages", force: true do |t|
    t.string   "from_did",    limit: 20,       null: false
    t.string   "from_sha256", limit: 45
    t.string   "to_did",      limit: 20,       null: false
    t.string   "to_sha256",   limit: 45
    t.text     "message",     limit: 16777215, null: false
    t.datetime "created_at"
    t.datetime "updated_at"
    t.string   "encryption",  limit: 3,        null: false
    t.boolean  "server",                       null: false
    t.text     "key"
    t.integer  "mid"
  end

  add_index "messages", ["from_did", "created_at"], name: "index_messages_from_did", using: :btree
  add_index "messages", ["to_did", "created_at"], name: "index_messages_to_did", using: :btree

  create_table "notifications", force: true do |t|
    t.string   "noti_id",      limit: 20, null: false
    t.string   "to_user_id",   limit: 40, null: false
    t.string   "from_user_id", limit: 40
    t.string   "internal",     limit: 1,  null: false
    t.text     "noti_key",                null: false
    t.text     "noti_options"
    t.string   "noti_read",    limit: 1,  null: false
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  add_index "notifications", ["noti_id"], name: "index_noti_on_noti_id", unique: true, using: :btree
  add_index "notifications", ["to_user_id"], name: "index_noti_on_to_user_id", using: :btree

  create_table "open_graph_links", force: true do |t|
    t.text     "url"
    t.string   "title"
    t.text     "description", limit: 255
    t.text     "image"
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  create_table "pings", force: true do |t|
    t.string  "session_id",    limit: 32
    t.integer "client_userid"
    t.string  "client_sid",    limit: 20
    t.decimal "last_ping_at",             precision: 13, scale: 3
    t.decimal "next_ping_at",             precision: 13, scale: 3
    t.string  "did"
    t.text    "user_ids"
    t.string  "sha256",        limit: 45
    t.integer "server_id"
  end

  add_index "pings", ["session_id", "client_userid", "client_sid"], name: "index_ping_pk", unique: true, using: :btree

  create_table "pubkeys", force: true do |t|
    t.text     "pubkey"
    t.datetime "created_at"
    t.datetime "updated_at"
    t.string   "did",                limit: 20, null: false
    t.integer  "server_id"
    t.datetime "client_request_at"
    t.datetime "server_response_at"
  end

  add_index "pubkeys", ["did"], name: "index_pubkey_did", unique: true, using: :btree

  create_table "remote_sessions", force: true do |t|
    t.string   "session_id",        limit: 32, null: false
    t.integer  "pseudo_session_id",            null: false
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  add_index "remote_sessions", ["session_id"], name: "index_remote_session_pk", unique: true, using: :btree

  create_table "sequences", force: true do |t|
    t.string   "name",       null: false
    t.integer  "value",      null: false
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  add_index "sequences", ["name"], name: "index_sequences_on_name", unique: true, using: :btree

  create_table "server_pubkey_requests", force: true do |t|
    t.integer  "server_id"
    t.string   "did"
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  create_table "server_sessions", force: true do |t|
    t.integer  "server_id",         null: false
    t.integer  "session_id",        null: false
    t.integer  "remote_session_id", null: false
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  add_index "server_sessions", ["server_id", "remote_session_id"], name: "index_server_session_pk", unique: true, using: :btree
  add_index "server_sessions", ["session_id"], name: "index_server_session_uk", unique: true, using: :btree

  create_table "server_user_requests", force: true do |t|
    t.integer  "pseudo_user_id", null: false
    t.string   "sha256"
    t.datetime "created_at"
    t.datetime "updated_at"
    t.integer  "server_id",      null: false
    t.integer  "user_id"
  end

  add_index "server_user_requests", ["server_id", "pseudo_user_id"], name: "index_server_user_requests_pk", unique: true, using: :btree

  create_table "server_users", force: true do |t|
    t.integer  "server_id"
    t.integer  "user_id"
    t.datetime "verified_at"
    t.datetime "created_at"
    t.datetime "updated_at"
    t.integer  "pseudo_user_id"
    t.integer  "remote_pseudo_user_id"
    t.datetime "remote_sha256_updated_at"
    t.datetime "sha256_message_sent_at"
    t.datetime "sha256_signature_received_at"
  end

  add_index "server_users", ["server_id", "user_id"], name: "index_server_users_pk", unique: true, using: :btree

  create_table "servers", force: true do |t|
    t.string   "site_url"
    t.datetime "created_at"
    t.datetime "updated_at"
    t.string   "new_did",                     limit: 20
    t.decimal  "last_ping_at",                           precision: 13, scale: 3
    t.decimal  "next_ping_at",                           precision: 13, scale: 3
    t.boolean  "secure",                                                          default: true
    t.string   "old_did",                     limit: 20
    t.text     "old_pubkey"
    t.text     "new_pubkey"
    t.text     "key"
    t.string   "secret"
    t.integer  "last_checked_user_id"
    t.datetime "last_changed_user_sha256_at"
  end

  add_index "servers", ["site_url"], name: "index_servers_url", unique: true, using: :btree

  create_table "sessions", force: true do |t|
    t.string   "session_id",                 limit: 32
    t.integer  "client_userid",                         default: 0
    t.text     "created"
    t.text     "expires_at"
    t.text     "flash_id"
    t.text     "language"
    t.text     "last_row_at"
    t.text     "last_row_id"
    t.text     "refresh_tokens"
    t.text     "state"
    t.text     "tokens"
    t.text     "user_ids"
    t.datetime "created_at"
    t.datetime "updated_at"
    t.text     "did"
    t.text     "client_timestamp"
    t.text     "client_secret"
    t.text     "sha256"
    t.boolean  "server"
    t.datetime "system_secret_updated_at"
    t.datetime "last_short_friends_list_at"
  end

  add_index "sessions", ["session_id", "client_userid"], name: "index_session_session_id", unique: true, using: :btree

  create_table "system_parameters", force: true do |t|
    t.string   "name"
    t.text     "value"
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  add_index "system_parameters", ["name"], name: "index_system_parameters_name", unique: true, using: :btree

  create_table "tasks", force: true do |t|
    t.string   "session_id", limit: 32,               null: false
    t.text     "task",                                null: false
    t.datetime "created_at"
    t.datetime "updated_at"
    t.integer  "priority",              default: 5
    t.string   "ajax",       limit: 1,  default: "Y"
    t.text     "task_data"
  end

  add_index "tasks", ["session_id"], name: "index_tasks_on_session_id", using: :btree

  create_table "unsubscribes", force: true do |t|
    t.string   "email",                 null: false
    t.string   "user_id",    limit: 40
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  create_table "users", force: true do |t|
    t.string   "user_id",                   limit: 40
    t.text     "user_name"
    t.datetime "created_at"
    t.datetime "updated_at"
    t.text     "currency"
    t.text     "balance"
    t.date     "balance_at"
    t.text     "no_api_friends"
    t.text     "negative_interest"
    t.text     "api_profile_url"
    t.text     "api_profile_picture_url"
    t.datetime "deleted_at"
    t.datetime "last_login_at"
    t.datetime "deauthorized_at"
    t.datetime "last_friends_find_at"
    t.string   "language",                  limit: 2
    t.text     "access_token"
    t.text     "access_token_expires"
    t.text     "refresh_token"
    t.string   "sha256",                    limit: 45
    t.string   "old_sha256",                limit: 45
    t.datetime "sha256_updated_at"
    t.datetime "friend_sha256_updated_at"
    t.datetime "remote_sha256_updated_at"
    t.text     "remote_sha256_update_info"
  end

  add_index "users", ["sha256"], name: "index_users_sha256", unique: true, using: :btree
  add_index "users", ["sha256_updated_at"], name: "index_users_on_sha256_updated", using: :btree
  add_index "users", ["user_id"], name: "index_users_on_user_id", unique: true, using: :btree

  create_table "verify_comments", force: true do |t|
    t.string   "client_sid",         limit: 20, null: false
    t.string   "client_sha256",      limit: 45, null: false
    t.integer  "client_seq",                    null: false
    t.integer  "server_id",                     null: false
    t.string   "cid",                limit: 20, null: false
    t.integer  "server_seq",                    null: false
    t.boolean  "verified_at_server"
    t.datetime "created_at"
    t.datetime "updated_at"
    t.string   "error"
    t.integer  "request_mid"
    t.integer  "response_mid"
  end

  add_index "verify_comments", ["client_sid", "client_sha256", "client_seq"], name: "index_verify_comment_pk", unique: true, using: :btree
  add_index "verify_comments", ["server_seq"], name: "index_verify_comment_uk", unique: true, using: :btree

  create_table "verify_gifts", force: true do |t|
    t.string   "client_sid",              limit: 20, null: false
    t.string   "client_sha256",           limit: 45, null: false
    t.integer  "client_seq",                         null: false
    t.integer  "server_id",                          null: false
    t.string   "gid",                     limit: 20, null: false
    t.integer  "server_seq",                         null: false
    t.boolean  "verified_at_server"
    t.datetime "created_at"
    t.datetime "updated_at"
    t.string   "error"
    t.integer  "request_mid"
    t.integer  "response_mid"
    t.string   "original_client_request"
  end

  add_index "verify_gifts", ["client_sid", "client_sha256", "client_seq"], name: "index_verify_gift_pk", unique: true, using: :btree
  add_index "verify_gifts", ["server_seq"], name: "index_verify_gift_uk", unique: true, using: :btree

end
