class ServersAddColumnSecret < ActiveRecord::Migration
  def change
    add_column :servers, :secret, :string
  end
end
