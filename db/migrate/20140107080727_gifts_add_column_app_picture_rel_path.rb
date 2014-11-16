class GiftsAddColumnAppPictureRelPath < ActiveRecord::Migration
  def change
    add_column :gifts, :app_picture_rel_path, :text
  end
end
