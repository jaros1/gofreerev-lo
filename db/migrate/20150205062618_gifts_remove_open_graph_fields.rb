class GiftsRemoveOpenGraphFields < ActiveRecord::Migration

  # t.text     "app_picture_rel_path"
  # t.text     "open_graph_url"
  # t.string   "open_graph_title"
  # t.text     "open_graph_description"
  # t.text     "open_graph_image"

  def up
    remove_column :gifts, "app_picture_rel_path"
    remove_column :gifts, "open_graph_url"
    remove_column :gifts, "open_graph_title"
    remove_column :gifts, "open_graph_description"
    remove_column :gifts, "open_graph_image"
  end
  def down
    add_column :gifts, "app_picture_rel_path", :text
    add_column :gifts, "open_graph_url", :text
    add_column :gifts, "open_graph_title", :string
    add_column :gifts, "open_graph_description", :text
    add_column :gifts, "open_graph_image", :text
  end
end
