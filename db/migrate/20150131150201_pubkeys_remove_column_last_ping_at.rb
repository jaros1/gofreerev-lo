class PubkeysRemoveColumnLastPingAt < ActiveRecord::Migration
  def up
    remove_column :pubkeys, :last_ping_at
  end
  def down
    add_column :pubkeys, :last_ping_at, :datetime
  end
end
