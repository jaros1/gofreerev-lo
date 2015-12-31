class PingsAddColumnMicroIntervalAdjustments < ActiveRecord::Migration
  def up
    add_column :pings, :micro_interval_adjustments, :string
  end
  def down
    remove_column :pings, :micro_interval_adjustments
  end
end
