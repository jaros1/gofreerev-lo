class MessageDropColumnEncryption < ActiveRecord::Migration
  def up
    remove_column :messages, :encryption
    change_column :messages, :message, :text, :null => true, :limit => 16777215
  end
  def down
    change_column :messages, :message, :text, :null => false, :limit => 16777215
    add_column :messages, :encryption, :string, :null => false, :limit => 3
  end
end
