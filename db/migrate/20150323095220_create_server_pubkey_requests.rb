class CreateServerPubkeyRequests < ActiveRecord::Migration
  def change
    create_table :server_pubkey_requests do |t|
      t.integer :server_id
      t.string :did

      t.timestamps
    end
  end
end
