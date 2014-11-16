class OmniAuth::AuthHash
  def get_user_name_foursquare
    # http://instagram.com/gofreerev#
    first_name = self[:info][:first_name] if self[:info]
    last_name = self[:info][:last_name] if self[:info]
    "#{first_name} #{last_name}"
  end
  def get_image_foursquare
    prefix = self["info"]["image"]["prefix"] if self["info"] and self["info"]["image"]
    return nil unless prefix
    suffix = self["info"]["image"]["suffix"] if self["info"] and self["info"]["image"]
    return nil unless suffix
    "#{prefix}100x100#{suffix}"
  end
  def get_profile_url_foursquare
    uid = self.get_uid
    "#{API_URL[:foursquare]}/user/#{uid}"
  end
end