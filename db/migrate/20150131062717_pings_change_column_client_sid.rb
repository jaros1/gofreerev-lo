class PingsChangeColumnClientSid < ActiveRecord::Migration
  def up
    change_column :pings, :client_sid, :string, :limit => 15
  end
  def down
    change_column :pings, :client_sid, :integer, :limit => nil
  end
end
