class GiftsAddColumnExternalLink < ActiveRecord::Migration
  def change
    add_column :gifts, :external_link, :text
  end
end
