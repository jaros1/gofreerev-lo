class SessionsAddColumnUid < ActiveRecord::Migration
  def up
    add_column :sessions, :uid, :text
  end
  def down
    remove_column :sessions, :uid
  end
end
