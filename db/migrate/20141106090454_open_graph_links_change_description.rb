class OpenGraphLinksChangeDescription < ActiveRecord::Migration
  def change
    change_column :open_graph_links, :description, :text
  end
end
