class VerifyCommentsChangeClientSidAndClientSha256ToNullColumns < ActiveRecord::Migration

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
  #   t.text     "error"
  #   t.integer  "request_mid",                        null: false
  #   t.integer  "response_mid"
  #   t.text     "original_client_request",            null: false
  # end

  def up
    change_column :verify_comments, :client_sid, :string, :limit => 20, :null => true
    change_column :verify_comments, :client_sha256, :string, :limit => 45, :null => true
  end
  def down
    change_column :verify_comments, :client_sid, :string, :limit => 20, :null => false
    change_column :verify_comments, :client_sha256, :string, :limit => 45, :null => false
  end

end
