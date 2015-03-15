class ServersAddColumnKey < ActiveRecord::Migration
  def change
    add_column :servers, :key, :text
  end
end
