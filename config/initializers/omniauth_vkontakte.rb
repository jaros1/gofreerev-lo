class OmniAuth::AuthHash
  def get_profile_url_vkontakte
    profile_url = self[:info][:urls][:Vkontakte] if self[:info] and self[:info][:urls]
    profile_url.gsub!(/^http:/, 'https:') if profile_url # protect cookies
    profile_url
  end
  def get_image_vkontakte
    image = self[:extra][:raw_info][:photo_100] if self[:extra] and self[:extra][:raw_info]
    image
  end
end

