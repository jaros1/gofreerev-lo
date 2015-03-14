class ServersAddPingTimestamps < ActiveRecord::Migration
  def change
    add_column :servers, :last_ping_at, :datetime
    add_column :servers, :next_ping_at, :datetime
  end
end
