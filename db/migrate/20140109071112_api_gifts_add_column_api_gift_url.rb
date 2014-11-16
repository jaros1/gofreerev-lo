class ApiGiftsAddColumnApiGiftUrl < ActiveRecord::Migration
  def change
    add_column :api_gifts, :api_gift_url, :text
  end
end
