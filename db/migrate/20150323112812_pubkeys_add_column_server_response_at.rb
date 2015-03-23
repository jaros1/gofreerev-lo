class PubkeysAddColumnServerResponseAt < ActiveRecord::Migration
  def change
    add_column :pubkeys, :server_response_at, :datetime
  end
end
