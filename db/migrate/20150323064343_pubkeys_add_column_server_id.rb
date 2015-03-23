class PubkeysAddColumnServerId < ActiveRecord::Migration

  # old:
  # create_table "pubkeys", force: true do |t|
  #   t.text     "pubkey"
  #   t.datetime "created_at"
  #   t.datetime "updated_at"
  #   t.string   "did"
  # end
  # add_index "pubkeys", ["did"], name: "index_pubkey_did", unique: true, using: :btree

  def up
    Pubkey.all.find_all { |p| p.did.size > 20}.each { |p| p.destroy! }
    add_column :pubkeys, :server_id, :integer
    change_column :pubkeys, :did, :string, :limit => 20, :null => false
  end
  def down
    change_column :pubkeys, :did, :string, :limit => nil, :null => true
    remove_column :pubkeys, :server_id
  end

end
