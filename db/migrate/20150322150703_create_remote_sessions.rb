class CreateRemoteSessions < ActiveRecord::Migration
  def change
    create_table :remote_sessions do |t|
      t.string :session_id, :limit => 32, :null => false
      t.integer :pseudo_session_id, :null => false
      t.timestamps
    end
    add_index "remote_sessions", ["session_id"], name: "index_remote_session_pk", unique: true, using: :btree
  end
end
