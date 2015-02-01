class PubkeysRenameUidToDid < ActiveRecord::Migration
  def up
    remove_index "pubkeys", :name => "index_pubkey_uid"
    rename_column "pubkeys", :uid, :did
    add_index "pubkeys", ["did"], name: "index_pubkey_did", unique: true, using: :btree
  end
  def down
    remove_index "pubkeys", :name => "index_pubkey_did"
    rename_column "pubkeys", :did, :uid
    add_index "pubkeys", ["uid"], name: "index_pubkey_uid", unique: true, using: :btree
  end
end
