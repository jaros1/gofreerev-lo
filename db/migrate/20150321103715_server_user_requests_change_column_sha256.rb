class ServerUserRequestsChangeColumnSha256 < ActiveRecord::Migration

  # old:
  # create_table "server_user_requests", force: true do |t|
  #   t.integer  "user_id",               null: false
  #   t.string   "sha256",     limit: 45, null: false
  #   t.datetime "created_at"
  #   t.datetime "updated_at"
  #   t.integer  "server_id"
  # end

  def up
    change_column :server_user_requests, :sha256, :string, :null => true
  end
  def down
    change_column :server_user_requests, :sha256, :string, :null => false
  end

end
