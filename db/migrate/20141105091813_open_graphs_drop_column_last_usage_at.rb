class OpenGraphsDropColumnLastUsageAt < ActiveRecord::Migration
  def change
    remove_column :open_graphs, :last_usage_at
  end
end
