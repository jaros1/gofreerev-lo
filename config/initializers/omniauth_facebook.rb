class OmniAuth::AuthHash
  def get_image_facebook
    # profile image from omniauth login is normally not used (wrong picture dimensions)
    # profile image from koala request in post login task (post_login_update_friends) is used
    # only exception is for new facebook users where profile picture from omniauth is used temporary
    image = self.info.image if self.info
    image
  end
  def get_country_facebook
    locale = self[:extra][:raw_info][:locale] if self[:extra] and self[:extra][:raw_info]
    locale = "#{locale}".last(2)
    locale = BASE_COUNTRY if locale.to_s == ""
    locale
  end
  def get_profile_url_facebook
    "#{API_URL[:facebook]}/#{self.uid}"
  end
end