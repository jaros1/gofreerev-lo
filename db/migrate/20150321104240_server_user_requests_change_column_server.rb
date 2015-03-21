class ServerUserRequestsChangeColumnServer < ActiveRecord::Migration

  # old:
  # create_table "server_user_requests", force: true do |t|
  #   t.integer  "user_id",    null: false
  #   t.string   "sha256"
  #   t.datetime "created_at"
  #   t.datetime "updated_at"
  #   t.integer  "server_id"
  # end

  def up
    change_column :server_user_requests, :server_id, :integer, :null => false
  end
  def down
    change_column :server_user_requests, :server_id, :integer, :null => true
  end

end
