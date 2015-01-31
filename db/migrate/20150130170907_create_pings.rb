class CreatePings < ActiveRecord::Migration
  def change
    create_table :pings do |t|
      t.string :session_id, limit: 32
      t.integer :client_userid
      t.integer :client_sid
      t.datetime :last_ping_at
      t.datetime :next_ping_at
    end
    add_index "pings", ["session_id", "client_userid", "client_sid"], name: "index_ping_pk", unique: true, using: :btree

  end
end
