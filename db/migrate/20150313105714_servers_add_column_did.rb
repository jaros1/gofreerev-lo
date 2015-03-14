class ServersAddColumnDid < ActiveRecord::Migration
  def change
    add_column :servers, :did, :string, :limit => 20
  end
end
