class CreateServerSessions < ActiveRecord::Migration
  def change
    create_table :server_sessions do |t|
      t.integer :server_id, :null => false
      t.integer :session_id, :null => false
      t.integer :server_session_id, :null => false
      t.timestamps
    end
    # from pseudo session id received from other Gofreerev server to pseudo session id used on this server
    add_index "server_sessions", ["server_id", "server_session_id"], name: "index_server_session_pk", unique: true, using: :btree
    # from pseudo session id used on this Gofreerev server.
    add_index "server_sessions", ["session_id"], name: "index_server_session_uk", unique: true, using: :btree
  end
end
