class GiftsAddOpenGraphAttributes < ActiveRecord::Migration

  # add open graph attributes to gifts. the 4 open graph attributes are used as an external reference and as an alternative to a picture attachment
  def change
    add_column :gifts, :open_graph_title, :string
    add_column :gifts, :open_graph_description, :text
    add_column :gifts, :open_graph_image, :text
  end

end
