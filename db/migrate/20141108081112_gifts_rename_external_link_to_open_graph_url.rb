class GiftsRenameExternalLinkToOpenGraphUrl < ActiveRecord::Migration
  def change
    rename_column :gifts, :external_link, :open_graph_url
  end
end
