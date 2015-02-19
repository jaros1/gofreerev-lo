class MessagesAddColumnEncryption < ActiveRecord::Migration
  def up
    Message.delete_all
    add_column :messages, :encryption, :string, :null => false, :limit => 3
  end
  def down
    remove_column :messages, :encryption
  end
end
