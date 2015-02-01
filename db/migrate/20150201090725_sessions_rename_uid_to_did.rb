class SessionsRenameUidToDid < ActiveRecord::Migration
  def change
    rename_column :sessions, :uid, :did
  end
end
