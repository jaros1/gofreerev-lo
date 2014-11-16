class OpenGraphLink < ActiveRecord::Base

  # create_table "open_graphs", force: true do |t|
  #   t.text     "url"
  #   t.string   "title"
  #   t.string   "description"
  #   t.text     "image"
  #   t.datetime "created_at"
  #   t.datetime "updated_at"
  #   t.datetime "last_usage_at"
  # end

  # cache Open Graph tags (http://ogp.me/) for gifts.external_url
  # use embed.ly API (EMBEDLY=true) or opengraph_parser gem get open graph meta-tags from html pages (EMBEDLY=false).

  # returns nil if url does not exists or if there are issues with html page
  def self.find_or_create_link (url)
    url = url.to_s.strip
    return nil if url == ""
    return nil unless url =~ /^https?:\/\//
    og = OpenGraphLink.find_by_url(url)
    return og if og and og.updated_at > 1.week.ago
    # todo: check if url exists
    # get open graph meta tags. Embed,ly API or parse html response
    if !og
      og = OpenGraphLink.new
      og.url = url
    end
    if EMBEDLY
      # use embed.ly API to parse html page for open graph metatags. free for <5000 API requests per month
      # used on dev1 server where there is an issue with nokogiri dependencies
      # todo: add error handling
      api_client = Embedly::API.new :key => EMBEDLY_KEY
      response = api_client.oembed :url => url
      # todo: use url from embedly?
      og.title       = response[0].title
      og.description = response[0].description
      og.image       = response[0].thumbnail_url
      og.updated_at  = Time.now
    else
      # use opengraph_parser gem - used in development  environment
      response = OpenGraph.new(url)
      return nil unless response.title
      if !response.description
        # check if page exists
        response2 = ApiGift.http_get(url, 3) # timeout 3 seconds
        return nil unless response2.code == '200'
      end
      og.url = response.url
      og.title = response.title
      og.description = response.description
      og.image = response.images.first
      og.updated_at  = Time.now
      og = og.clone if !og.new_record? and og.url_changed?
    end
    # replace blank with nil
    og.title = nil if og.title and og.title.to_s.strip == ''
    og.description = nil if og.description and og.description.to_s.strip == ''
    og.image = nil if og.image and og.image.to_s.strip == ''
    # replace ' with "
    og.title = og.title.gsub("'", '"') if og.title
    og.description = og.description.gsub("'", '"') if og.description
    # check image
    if og.image
      filetype = FastImage.type(og.image).to_s
      og.image = nil unless %w(jpg jpeg gif png bmp).index(filetype)
    end
    # save and return record
    og.save!
    og
  end # self.find_or_create_link

end
