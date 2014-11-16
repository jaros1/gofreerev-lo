class ApiGiftsFixInvalidApiPictureUrl < ActiveRecord::Migration
  def change
    # fixed problem with invalid texts in api_picture_url
    ApiGift.all.each do |ag|
      next if ag.valid?
      ag.api_picture_url = nil unless Picture.app_url?(ag.api_picture_url) or Picture.api_url?(ag.api_picture_url)
      ag.picture = ag.api_picture_url.to_s == '' ? 'N' : 'Y'
      ag.save!
    end
    # remove http:// from old format app urls
    site_url1 = SITE_URL.gsub('http://','https://')[0..-2]
    site_url2 = SITE_URL.gsub('https://','http://')[0..-2]
    ApiGift.where('api_picture_url is not null').each do |ag|
      ag.api_picture_url.gsub(site_url1,'')
      ag.api_picture_url.gsub(site_url2,'')
      ag.save!
    end
  end
end
