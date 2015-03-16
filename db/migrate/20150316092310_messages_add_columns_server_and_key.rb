class MessagesAddColumnsServerAndKey < ActiveRecord::Migration
  # change message to support server to server messages
  def up
    Message.delete_all
    add_column :messages, :server, :boolean, :null => false
    add_column :messages, :key, :text
    change_column :messages, :from_sha256, :string, :limit => 45, :null => true
    change_column :messages, :to_sha256, :string, :limit => 45, :null => true
  end
  def down
    Message.delete_all
    change_column :messages, :to_sha256, :string, :limit => 45, :null => false
    change_column :messages, :from_sha256, :string, :limit => 45, :null => false
    remove_column :messages, :key
    remove_column :messages, :server
  end
end
