class OmniAuth::AuthHash
  def get_user_name
    return self.info.nickname if self.info.nickname.to_s != ""
    self.info.name
  end
  def get_profile_url_flickr
    profile_url = self.info.urls.Profile._content if self.info and self.info.urls and self.info.urls.Profile
    profile_url.gsub!(/^http:/, 'https:') if profile_url # protect cookies
    profile_url
  end
  # return array with token AND secret for flickr - token AND secret are required for flickraw gem (oauth 1)
  def get_token_flickr
    token = self.credentials.token if self.credentials
    secret = self.credentials.secret if self.credentials
    return nil unless token.to_s != "" and secret.to_s != ""
    [ token, secret]
  end
  def get_expires_at_flickr
    # it looks like flickr access token does not expire!
    1.year.from_now.to_i
  end

end