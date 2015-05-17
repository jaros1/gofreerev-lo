class CreateVerifyComments < ActiveRecord::Migration
  def change
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
  end
end
