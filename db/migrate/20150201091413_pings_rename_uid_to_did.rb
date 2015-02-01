class PingsRenameUidToDid < ActiveRecord::Migration
  def change
    rename_column :pings, :uid, :did
  end
end
