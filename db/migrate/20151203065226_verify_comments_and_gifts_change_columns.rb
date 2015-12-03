class VerifyCommentsAndGiftsChangeColumns < ActiveRecord::Migration

  # create_table "verify_comments", force: true do |t|
  #   t.string   "client_sid",              limit: 20, null: false
  #   t.string   "client_sha256",           limit: 45, null: false
  #   t.integer  "client_seq",                         null: false
  #   t.integer  "server_id",                          null: false
  #   t.string   "cid",                     limit: 20, null: false
  #   t.integer  "server_seq",                         null: false
  #   t.boolean  "verified_at_server"
  #   t.datetime "created_at"
  #   t.datetime "updated_at"
  #   t.string   "error"
  #   t.integer  "request_mid",                        null: false
  #   t.integer  "response_mid"
  #   t.text     "original_client_request",            null: false
  # end
  # create_table "verify_gifts", force: true do |t|
  #   t.string   "client_sid",              limit: 20, null: false
  #   t.string   "client_sha256",           limit: 45, null: false
  #   t.integer  "client_seq",                         null: false
  #   t.integer  "server_id",                          null: false
  #   t.string   "gid",                     limit: 20, null: false
  #   t.integer  "server_seq",                         null: false
  #   t.boolean  "verified_at_server"
  #   t.datetime "created_at"
  #   t.datetime "updated_at"
  #   t.string   "error"
  #   t.integer  "request_mid"
  #   t.integer  "response_mid"
  #   t.string   "original_client_request"
  # end
  #
  # add_index "verify_gifts", ["client_sid", "client_sha256", "client_seq"], name: "index_verify_gift_pk", unique: true, using: :btree
  # add_index "verify_gifts", ["server_seq"], name: "index_verify_gift_uk", unique: true, using: :btree

  def up
    change_column :verify_comments, :error, :text
    change_column :verify_gifts, :error, :text
    change_column :verify_gifts, :original_client_request, :text, :null => false
  end
  def down
    change_column :verify_comments, :error, :string
    change_column :verify_gifts, :error, :string
    change_column :verify_gifts, :original_client_request, :string, :null => true
  end

end
