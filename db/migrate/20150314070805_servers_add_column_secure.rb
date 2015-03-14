class ServersAddColumnSecure < ActiveRecord::Migration
  def change
    add_column :servers, :secure, :boolean
  end
end
