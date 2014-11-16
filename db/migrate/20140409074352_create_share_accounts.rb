class CreateShareAccounts < ActiveRecord::Migration
  def change
    create_table :share_accounts do |t|
      t.integer :share_level
      t.timestamps
    end
  end
end
