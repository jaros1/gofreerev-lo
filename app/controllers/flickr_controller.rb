class FlickrController < ApplicationController

  # reauthorize flickr user with scope r_basicprofile r_network rw_nus
  # that is - allow gofreerev to post on flickr wall if user wants it
  # http://developer.flickr.com/documents/authentication
  # http://railscarma.com/blog/rails-3/how-to-use-flickr-api-in-rails-applications/
  # signatures:
  # 1) callback with rw_nus:
  #    Parameters: {"oauth_token"=>"75--62450be1-6396-45a9-b26f-050a2b471a9d", "oauth_verifier"=>"15521"}
  def index
    # flickr oauth client was saved in util.post_on_flickr after "(403): Access to posting shares denied" error
    api_client, request_token = get_flickr_api_client
    if !api_client
      # flickr client temporary saved in task queue in util.post_on_flickr was not found
      # maybe client was deleted by cleanup rutine (clients older than 10 minutes are deleted)
      # maybe used has reloaded this page after an exception
      save_flash_key '.no_client', :apiname => provider_downcase('flickr'), :appname => APP_NAME
      redirect_to :controller => :gifts
      return
    end
    res1 = nil
    begin
      logger.debug2 "request_token = #{request_token}"
      token = api_client.get_access_token(request_token['oauth_token'], request_token['oauth_token_secret'], params[:oauth_verifier])
      logger.debug2 "after get_access_token - before test.login"
      res1 = api_client.test.login
    rescue => e
      logger.debug2 "Exception: #{e.message} (#{e.class})"
      save_flash_key '.auth_failed', :apiname => provider_downcase('flickr'), :appname => APP_NAME, :error => e.message
      redirect_to :controller => :gifts
      return
    end
    logger.debug2 "token = #{token} (#{token.class})"
    # index: token = {"fullname"=>"Jan%20R", "oauth_token"=>"72157641010653023-da33ffc353c6998a", "oauth_token_secret"=>"d933e5a8ac1c73ff", "user_nsid"=>"117614965%
    logger.debug2 "token['user_nsid'] = #{token['user_nsid']}"
    logger.debug2 "res1 = #{res1} (#{res1.class})"
    logger.debug2 "res1.as_json = #{res1.as_json}"
    logger.debug2 "res1.id = #{res1.id}"
    logger.debug2 "res1.username = #{res1.username}"
    if token.class == Hash and token.has_key?('user_nsid') and
        token.has_key?('oauth_token') and token['oauth_token'].class == String and token['oauth_token'] != '' and
        token.has_key?('oauth_token_secret') and token['oauth_token_secret'].class == String and token['oauth_token_secret'] != ''
      # token hash ok
      uid = res1.id # used uid from api_client.test.login (user_nsid in token is escaped)
      logger.debug2 "uid = #{uid}"
      token = [token['oauth_token'], token['oauth_token_secret']]
      logger.debug2 "token"
      logger.debug2  "login ok. Get name, .... from flickr"
      # get basic user information from flickr before second login with write permission (write) to flickr wall
      api_client = init_api_client_flickr(token) # token and secret
      res2 = api_client.people.getInfo :user_id => uid
      logger.debug2 "res2 = #{res2}"
      logger.debug2 "res2.methods = #{res2.methods.sort.join(', ')}"
      logger.debug2 "res2.as_json = #{res2.as_json}"
      name = res2.realname.to_s == '' ? res2.username : res2.realname
      logger.debug2 "name = #{name}, realname = #{res2.realname}, username = #{res2.username}"
      if res2.iconfarm.to_s == '0' and res2.iconserver.to_s == '0'
        picture_url = nil
      else
        picture_url = "http://farm#{res2.iconfarm}.static.flickr.com/#{res2.iconserver}/buddyicons/#{uid}.jpg"
      end
      logger.debug2 "picture_url = #{picture_url}, iconfarm = #{res2.iconfarm}, iconserver = #{res2.iconserver}, uid = #{uid}"
      # index: res1.public_profile_url = http://www.flickr.com/pub/jan-test-account-roslind/87/b08/27a
      # new login with write permission to flickr wall
      res3 = login :provider => provider,
                  :token => token,
                  :expires_at => 1.year.from_now.to_i,
                  :uid => uid,
                  :name => name,
                  :image => picture_url,
                  :country => nil,
                  :language => nil,
                  :profile_url => res2.profileurl,
                  :permissions => 'write'
      logger.debug2  "res3 = #{res3}"
      if !res3
        # login ok with write priv
        user_id = "#{uid}/#{provider}"
        user = User.find_by_user_id(user_id)
        # user.permissions = "write"
        # user.save!
        save_flash_key ".ok_write", user.app_and_apiname_hash
        redirect_to :controller => :gifts
      else
        # login failed
        key, options = res3
        begin
          save_flash_key key, options
        rescue => e
          logger.debug2  "invalid response from login. Must be nil or a valid input to translate. Response: #{res3}"
          save_flash_key '.find_or_create_from_auth_hash', :response => res3, :exception => e.message.to_s
        end
        redirect_to :controller => :auth
      end

    else
      # todo: add error and redirect to gifts/index page
      logger.debug2  "login not ok."
    end

  end # index


  private
  def provider
    "flickr"
  end

end
