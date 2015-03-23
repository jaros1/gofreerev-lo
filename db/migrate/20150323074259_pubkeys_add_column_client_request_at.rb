class PubkeysAddColumnClientRequestAt < ActiveRecord::Migration
  def change
    add_column :pubkeys, :client_request_at, :datetime
  end
end
