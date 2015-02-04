class GiftsRemoveColumnsCurrencyAndPrice < ActiveRecord::Migration

  # t.text     "currency",                          null: false
  # t.text     "price"

  def up
    remove_column :gifts, :currency
    remove_column :gifts, :price
  end
  def down
    add_column :gifts, :currency, :text, :default => 'DKK', :null => false
    add_column :gifts, :currency, :price
  end
end
