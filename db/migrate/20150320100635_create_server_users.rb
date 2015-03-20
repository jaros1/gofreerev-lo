class CreateServerUsers < ActiveRecord::Migration
  def change
    create_table :server_users do |t|
      t.integer :server_id
      t.integer :user_id
      t.datetime :verified_at
      t.timestamps
    end
    add_index "server_users", ["server_id", "user_id"], name: "index_server_users_pk", unique: true, using: :btree
  end
end
