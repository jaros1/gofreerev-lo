class PingsAddColumnsRequestIntervalAndRequestIntervalStat < ActiveRecord::Migration
  def up
    add_column :pings, :request_interval, :integer
    add_column :pings, :request_interval_stat, :string
  end
  def down
    remove_column :pings, :request_interval_stat
    remove_column :pings, :request_interval
  end
end
