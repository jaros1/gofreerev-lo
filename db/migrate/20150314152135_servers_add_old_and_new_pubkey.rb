class ServersAddOldAndNewPubkey < ActiveRecord::Migration
  def change
    add_column :servers, :old_pubkey, :text
    add_column :servers, :new_pubkey, :text
  end
end
