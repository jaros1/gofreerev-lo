class MessagesChangeColumnsKeyAndMessageToNotNull < ActiveRecord::Migration

  # create_table "messages", force: true do |t|
  #   t.string   "from_did",    limit: 20,       null: false
  #   t.string   "from_sha256", limit: 45
  #   t.string   "to_did",      limit: 20,       null: false
  #   t.string   "to_sha256",   limit: 45
  #   t.text     "message",     limit: 16777215
  #   t.datetime "created_at"
  #   t.datetime "updated_at"
  #   t.boolean  "server",                       null: false
  #   t.text     "key"
  #   t.integer  "mid"
  # end

  def up
    change_column :messages, :key, :text, :null => false
    change_column :messages, :message, :text, :limit => 16777215, :null => false
  end

  def down
    change_column :messages, :key, :text, :null => true
    change_column :messages, :message, :text, :limit => 16777215, :null => true
  end

end
