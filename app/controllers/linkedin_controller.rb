require 'linkedin'

class LinkedinController < ApplicationController

  # reauthorize linkedin user with scope r_basicprofile r_network rw_nus
  # that is - allow gofreerev to post on linkedin wall if user wants it
  # http://developer.linkedin.com/documents/authentication
  # http://railscarma.com/blog/rails-3/how-to-use-linkedin-api-in-rails-applications/
  # signatures:
  # 1) callback with rw_nus:
  #    Parameters: {"oauth_token"=>"75--62450be1-6396-45a9-b26f-050a2b471a9d", "oauth_verifier"=>"15521"}
  def index
    # linkedin oauth client was saved in util.post_on_linkedin after "(403): Access to posting shares denied" error
    api_client = get_linkedin_api_client
    if !api_client
      # linkedin client temporary saved in task queue in util.post_on_linkedin was not found
      # maybe client was deleted by cleanup rutine (clients older than 10 minutes are deleted)
      # maybe used has reloaded this page after an exception
      save_flash_key '.no_client', :apiname => provider_downcase('linkedin'), :appname => APP_NAME
      redirect_to :controller => :gifts
      return
    end
    begin
      token = api_client.authorize_from_request(api_client.request_token.token, api_client.request_token.secret, params[:oauth_verifier])
      # note. minor change to linkedin-0.4.4 gem. expires_in is saved in a instance variable
      expires_in = api_client.instance_variable_get('@auth_expires_in') # seconds from now
      if expires_in.to_s == ''
        logger.error2 "expires_at timestamp was not received from linkedin gem authorize_from_request method."
        logger.debug2 "add line \"@auth_expires_in = access_token.instance_variable_get('@params')[:oauth_expires_in]\" to authorize_from_request method"
        logger.debug2 "expires_at was set to 2 months from now"
        expires_at = 2.months.from_now.to_i
      else
        expires_at = expires_in.to_i.seconds.from_now.to_i # unix timestamp
      end
      logger.debug2 "expires_in = #{expires_in}, expires_at = #{expires_at}"
    rescue => e
      logger.debug2 "Exception: #{e.message} (#{e.class})"
      save_flash_key '.auth_failed', :apiname => provider_downcase('linkedin'), :appname => APP_NAME, :error => e.message
      raise
    end
    # logger.debug2  "x = #{token} (#{token.class})"
    if token.class == Array and token.length == 2 and token[0].class == String and token[1].class == String and token[0] != "" and token[1] != ''
      logger.debug2  "login ok. Get name, .... from linkedin"
      # get basic user information from linkedin before 2. login with write permission (rw_nus) to linkedin wall
      api_client = init_api_client_linkedin(token) # token and secret
      res1 = api_client.profile(:fields => %w(id,first-name,last-name,picture-url,public-profile-url))
      logger.debug2 "res1.public_profile_url = #{res1.public_profile_url}"
      # index: res1.public_profile_url = http://www.linkedin.com/pub/jan-test-account-roslind/87/b08/27a
      # new login with write permission to linkedin wall
      res2 = login :provider => provider,
                  :token => token,
                  :expires_at => expires_at,
                  :uid => res1.id,
                  :name => "#{res1.first_name} #{res1.last_name}",
                  :image => res1.picture_url,
                  :country => nil,
                  :language => nil,
                  :profile_url => res1.public_profile_url,
                  :permissions => 'r_basicprofile,r_network,rw_nus'
      # logger.debug2  "res2 = #{res2}"
      if !res2
        # login ok with extra rw_nus priv
        user_id = "#{res1.id}/#{provider}"
        user = User.find_by_user_id(user_id)
        # user.permissions = "r_basicprofile,r_network,rw_nus"
        # user.save!
        save_flash_key ".ok_rw_nus", user.app_and_apiname_hash
        redirect_to :controller => :gifts
      else
        # login failed
        key, options = res2
        begin
          save_flash_key key, options
        rescue => e
          logger.debug2  "invalid response from login. Must be nil or a valid input to translate. Response: #{res2}"
          save_flash_key '.find_or_create_from_auth_hash', :response => res2, :exception => e.message.to_s
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
    "linkedin"
  end

end
