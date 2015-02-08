class PingsChangeSidLimit < ActiveRecord::Migration

  # t.string   "client_sid",    limit: 15

  def up
    change_column :pings, :client_sid, :string, :limit => 20
  end
  def down
    change_column :pings, :client_sid, :string, :limit => 15
  end

end
