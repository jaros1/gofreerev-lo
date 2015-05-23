class ServersAddDefaultForSecure < ActiveRecord::Migration
  def up
    change_column :servers, :secure, :boolean, :default => 1
  end
  def down
    change_column :servers, :secure, :boolean, :default => nil
  end
end
