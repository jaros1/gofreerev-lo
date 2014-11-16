class GiftsRemoveColumnTempPictureFilename < ActiveRecord::Migration
  def up
    remove_column :gifts, :temp_picture_filename
  end
  def down
    add_column :gifts, :temp_picture_filename, :string, :limit => 20
  end
end