class ServersRenameDidAndAddOldDid < ActiveRecord::Migration
  def up
    rename_column :servers, :did, :new_did
    add_column :servers, :old_did, :string, :limit => 20
  end
  def down
    remove_column :servers, :old_did
    rename_column :servers, :new_did, :did
  end
end
