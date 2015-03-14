class ServersRenameUrl < ActiveRecord::Migration
  def change
    rename_column :servers, :url, :site_url
  end
end
