class GiftsUndeleteGifts < ActiveRecord::Migration
  # gift.sha256_deleted signature changed. undelete old gifts in db
  def up
    Gift.where('sha256_deleted is not null').update_all('sha256_deleted = null')
  end
  def down
  end
end
