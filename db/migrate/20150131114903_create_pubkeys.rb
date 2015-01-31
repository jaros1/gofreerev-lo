class CreatePubkeys < ActiveRecord::Migration
  def change
    create_table :pubkeys do |t|
      t.string :uid
      t.text :pubkey

      t.timestamps
    end
  end
end
