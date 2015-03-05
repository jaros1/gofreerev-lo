class SessionsChangeSha256ToText < ActiveRecord::Migration

  # old: t.string   "sha256",           limit: 45

  def up
    change_column :sessions, :sha256, :text, :limit => nil
    Session.delete_all
  end
  def down
    change_column :sessions, :sha256, :string, :limit => 45
  end

end
