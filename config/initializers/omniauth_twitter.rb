class OmniAuth::AuthHash
  # return array with token AND secret for twitter - token AND secret are required for twitter gem -
  def get_token_twitter
    token = self[:credentials][:token] if self[:credentials]
    secret = self[:credentials][:secret] if self[:credentials]
    return nil unless token.to_s != "" and secret.to_s != ""
    [ token, secret]
  end # get_token_linkedin
  def get_profile_url_twitter
    profile_url = self[:info][:urls][:Twitter] if self[:info] and self[:info][:urls]
    profile_url
  end
  def get_expires_at_twitter
    # it looks like twitter access token does not expire!
    1.year.from_now.to_i
  end

end