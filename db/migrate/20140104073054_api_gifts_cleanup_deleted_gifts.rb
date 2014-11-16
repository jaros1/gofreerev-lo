class ApiGiftsCleanupDeletedGifts < ActiveRecord::Migration
  def change
    gift_ids = ApiGift.all.collect { |ag| ag.gift_id } - Gift.all.collect { |g| g.gift_id }
    gift_ids.each do |gift_id|
      ApiGift.delete_all("gift_id = '#{gift_id}'")
    end
  end
end
