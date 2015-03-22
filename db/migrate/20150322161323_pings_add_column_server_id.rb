class PingsAddColumnServerId < ActiveRecord::Migration
  def change
    add_column :pings, :server_id, :integer
  end
end
