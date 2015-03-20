class ServerUserRequestsAddColumnServerId < ActiveRecord::Migration
  def change
    add_column :server_user_requests, :server_id, :integer
    add_index "server_user_requests", ["server_id", "user_id"], name: "index_server_user_requests_pk", unique: true, using: :btree
  end
end
