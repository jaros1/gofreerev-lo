class CreateVerifyGifts < ActiveRecord::Migration
  def change
    create_table :verify_gifts do |t|
      t.string :client_sid, :null => false, :limit => 20
      t.string :client_sha256, :null => false, :limit => 45
      t.integer :client_seq, :null => false
      t.integer :server_id, :null => false
      t.string :gid, :null => false, :limit => 20
      t.integer :server_seq, :null => false
      t.boolean :verified_at_server
      t.timestamps
    end
    add_index "verify_gifts", ["client_sid", "client_sha256", "client_seq"], name: "index_verify_gift_pk", unique: true, using: :btree
    add_index "verify_gifts", ["server_seq"], name: "index_verify_gift_uk", unique: true, using: :btree
  end
end
