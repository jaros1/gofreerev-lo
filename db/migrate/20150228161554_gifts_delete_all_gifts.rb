class GiftsDeleteAllGifts < ActiveRecord::Migration
  # empty fields removed from end of all sha256 signatures - regenerate all server side sha256 signatures
  def change
    Gift.delete_all
  end
end
