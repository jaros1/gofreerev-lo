class GiftsRemoveBalanceFields < ActiveRecord::Migration

  # t.text     "balance_giver"
  # t.text     "balance_receiver"
  # t.text     "balance_doc_giver"
  # t.text     "balance_doc_receiver"

  def up
    remove_column :gifts, :balance_giver
    remove_column :gifts, :balance_receiver
    remove_column :gifts, :balance_doc_giver
    remove_column :gifts, :balance_doc_receiver
  end

  def down
    add_column :gifts, :balance_giver, :text
    add_column :gifts, :balance_receiver, :text
    add_column :gifts, :balance_doc_giver, :text
    add_column :gifts, :balance_doc_receiver, :text
  end
  
end
