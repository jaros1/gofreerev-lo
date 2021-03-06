class PingsChangeTimestampColumnsToStrings < ActiveRecord::Migration
  # change timestamp columns to support time with milliseconds (unix timestamp with milliseconds)
  def up
    Ping.delete_all
    change_column :pings, :last_ping_at, :decimal, :precision => 13, :scale => 3
    change_column :pings, :next_ping_at, :decimal, :precision => 13, :scale => 3
  end
  def down
    Ping.delete_all
    change_column :pings, :last_ping_at, :datetime
    change_column :pings, :next_ping_at, :datetime
  end
end
