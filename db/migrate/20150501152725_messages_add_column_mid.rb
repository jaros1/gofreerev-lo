class MessagesAddColumnMid < ActiveRecord::Migration
  def change
    add_column :messages, :mid, :integer
  end
end
