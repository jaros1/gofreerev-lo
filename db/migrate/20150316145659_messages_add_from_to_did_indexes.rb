class MessagesAddFromToDidIndexes < ActiveRecord::Migration
  def change
    add_index :messages, [:from_did, :created_at], name: "index_messages_from_did", unique: false, using: :btree
    add_index :messages, [:to_did, :created_at], name: "index_messages_to_did", unique: false, using: :btree
  end
end
