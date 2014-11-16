class OmniAuth::AuthHash
  def get_profile_url_instagram
    # http://instagram.com/gofreerev#
    nickname = self[:info][:nickname] if self[:info]
    profile_url = "#{API_URL[:instagram]}#{nickname}#" if nickname
    profile_url.gsub!(/^http:/, 'https:') if profile_url # instagram redirects back to http. maybe instagram has a cookie security problem
    profile_url
  end
end