class OpenGraphsRenameTableToOpenGraphLinks < ActiveRecord::Migration
  def change
    rename_table :open_graphs, :open_graph_links
  end
end
