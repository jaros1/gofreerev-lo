class OmniAuth::AuthHash
  def get_image_google_oauth2
    # full size profile picture is received from google+ login
    # add ?sz=50 to url received from in omniauth login
    # http://stackoverflow.com/questions/9128700/getting-google-profile-picture-url-with-user-id
    image = self[:info][:image] if self[:info]
    image = nil if image.to_s == ""
    image = nil if image and image !~ /^https?:/
    return nil unless image
    image.split('?').first + '?sz=100' # # profile picture size 100 x 100
  end
  def get_refresh_token_google_oauth2
    # refresh token is only used for google+ where access token expires after 1 hour
    refresh_token = self[:credentials][:refresh_token] if self[:credentials]
    refresh_token = nil if refresh_token.to_s == ""
    refresh_token
  end
end