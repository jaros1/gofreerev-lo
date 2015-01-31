class CreatePubkeys < ActiveRecord::Migration
  def change
    create_table :pubkeys do |t|
      t.string :uid
      t.text :pubkey
      t.datetime :last_ping_at
      t.timestamps
    end
    add_index "pubkeys", "uid", name: "index_pubkey_uid", unique: true, using: :btree

  end
end
