class FacebookController < ApplicationController

  skip_before_filter :verify_authenticity_token, :only => [:create] # no crsf token when facebook starts the App with post /facebook
  after_filter :allow_iframe


  # post /facebook = facebook/create is called when facebook starts the APP.
  # / will route to this method if :fb_locale and :signed_request are in params (see routes.rb root and /lib/role_constraints.rb)
  # Signature 1: when an unauthorized user starts the app from facebook
  #   input: signed_request encoded JSON hash with (user, issued_at and algorithm)
  #          1) user 	      A JSON array containing the locale string, country string and the age object (containing the min and max numbers of the age range) for the current person using the app.
  #          2) algorithm 	A JSON string containing the mechanism used to sign the request.
  #          3) issued_at 	A JSON number containing the Unix timestamp when the request was signed.
  #   example: hash = { "algorithm"=>"HMAC-SHA256",
  #                     "issued_at"=>1373284394,
  #                     "user"=>{"country"=>"dk", "locale"=>"da_DK", "age"=>{"min"=>21}}}
  #   action: redirect to https://www.facebook.com/dialog/oauth?client_id=<client_id>&redirect_uri=<current_url>&scope=read_stream for FB app logn / authorization
  #           must be a redirect to top frame (top.location.href)
  # Signature 2: when an authorized user starts the app from facebook
  #   Parameters: {"signed_request"=>"8AsUxKh02db56T9oVjnCe3EfaNUXw8qqHNHmcQaDhgA.eyJhbGdvcml0aG0iOiJITUFDLVNIQTI1NiIsImV4cGlyZXMiOjEzOTY0MjU2MDAsImlzc3VlZF9hdCI6MTM5NjQyMTM1Miwib2F1dGhfdG9rZW4iOiJDQUFGalpCR3p6T2tjQkFQSkNMUXZma3BoNjBmbUl1WkJJUUVpeFpDa1ByQXQzbURJRnpiUHUxeGpxMlZlNkZqUldvM3huUWdXWW1EM3V3ekJzWkJzRGFRNzNXeFZQbDNaQkVzTVpCREFGQm9lR0VKWkJ2SHdmS2hiblZQWkJVVExNRWdXREJSUXBjTUp2Ym1UWkMyR0VNelZzMDcyVlczWkFkS3BYY0owZENuWkNsM1d1QVVXdFlLVjh0c00xOVFzbWowZzZFWkQiLCJ1c2VyIjp7ImNvdW50cnkiOiJkayIsImxvY2FsZSI6ImVuX0dCIiwiYWdlIjp7Im1pbiI6MjF9fSwidXNlcl9pZCI6IjE3MDU0ODEwNzUifQ",
  #                "fb_locale"=>"en_GB"}
  #   input: signed_request encoded JSON hash with (user, issued_at, algorithm, expires, oauth_token and user_id)
  #   example: hash = { "algorithm"=>"HMAC-SHA256",
  #                     "expires"=>1373374800,
  #                     "issued_at"=>1373370798,
  #                     "oauth_token"=>"CAAFjZBGzzOkcBAM3vNXbvDtDm3qcV7RQ3HwSRZAC9PRUiSvA8zLAnFFUwEmuV5t6fWohIPn8ZCDUrTZCUFtlUdOK1aSPhL1nvobmEBNucZBu9KLWqb4wRcB6jZBy6K49pZCQOaXRl0C8cj4ZCAYfdZC9tZCLC8wZAFhs9GWJMGIkO91AwZDZD",
  #                     "user"=>{"country"=>"dk", "locale"=>"da_DK", "age"=>{"min"=>21}},
  #                     "user_id"=>"1705481075"}
  #   note that signed_request signature is identical in signature 2 and signature 4. Only params signature is different.
  #   action:
  # Signature 3: when an authorized user deauthorise gofreerev in facebook (advanced settings - deauthorise dallback url)
  #   input: signed_request encoded JSON hash with (user, issued_at, algorithm, and user_id)
  #   example: hash = {"algorithm"=>"HMAC-SHA256",
  #                    "issued_at"=>1391445050,
  #                    "user"=>{"country"=>"dk", "locale"=>"en_GB"},
  #                    "user_id"=>"1705481075"}
  #   action:
  # Signature 4: when app starts from a friends_find facebook notification. See User.find_friends_batch
  #   Parameters: {"signed_request"=>"6xbhSI-JNpGOf7Ye54gft7kF4Tmxdr0AQVA0Iy0hw34.eyJhbGdvcml0aG0iOiJITUFDLVNIQTI1NiIsImV4cGlyZXMiOjEzOTY0MjIwMDAsImlzc3VlZF9hdCI6MTM5NjQxNzY4Mywib2F1dGhfdG9rZW4iOiJDQUFGalpCR3p6T2tjQkFQUGoyakJtVTc2UkxkODFjcG0xSTVqMDlZcWNZNjFSOFRwYnRoa3l0QlNkb0JoalNrQWh0UFBhaTN3VmlCekZRM2dsb1pCVUtxTVhXV0tlTkVqeVk3U2pOTXJRZXUzWkI4MVRoVEhwTEtBZzMyRzlLaVpCaFpCR1pBbEdROFpBQThnN3R5aDZVREpRS0pqY3dnek52djZqaE9lR00yUlUyTEk1MkZDWkFIZUJaQWdSWVVWZXVTRHNzamdrYjVKcTNBWkRaRCIsInVzZXIiOnsiY291bnRyeSI6ImRrIiwibG9jYWxlIjoiZW5fR0IiLCJhZ2UiOnsibWluIjoyMX19LCJ1c2VyX2lkIjoiMTcwNTQ4MTA3NSJ9",
  #                "fb_locale"=>"en_GB", "fb_source"=>"notification", "fb_ref"=>"friends_find",
  #                "ref"=>"notif", "notif_t"=>"app_notification"}
  #   signed_request encoded JSON hash with (user, issued_at, algorithm, expires, oauth_token and user_id)
  #   example: hash = {"algorithm"=>"HMAC-SHA256",
  #                    "expires"=>1396422000,
  #                    "issued_at"=>1396417683,
  #                    "oauth_token"=>"CAAFjZBGzzOkcBAPPj2jBmU76RLd81cpm1I5j09YqcY61R8TpbthkytBSdoBhjSkAhtPPai3wViBzFQ3gloZBUKqMXWWKeNEjyY7SjNMrQeu3ZB81ThTHpLKAg32G9KiZBhZBGZAlGQ8ZAA8g7tyh6UDJQKJjcwgzNvv6jhOeGM2RU2LI52FCZAHeBZAgRYUVeuSDssjgkb5Jq3AZDZD",
  #                    "user"=>{"country"=>"dk", "locale"=>"en_GB", "age"=>{"min"=>21}},
  #                    "user_id"=>"1705481075"}
  #   note that signed_request signature is identical in signature 2 and signature 4. Only params signature is different.
  #   action:

  def create
    # logout any old facebook user before (new) login
    logout(provider)

    signed_request = params[:signed_request]
    logger.debug2  "signed_request = #{signed_request}"
    # signed_request = 9m_Xew0oojeuzMjIZFqwx9lI_UI4AqC-vMWXL9o45g4.eyJhbGdvcml0aG0iOiJITUFDLVNIQTI1NiIsImlzc3VlZF9hdCI6MTM3MzI4NDA4OCwidXNlciI6eyJjb3VudHJ5IjoiZGsiLCJsb2NhbGUiOiJkYV9ESyIsImFnZSI6eyJtaW4iOjIxfX19
    if signed_request.to_s == ''
      # fatal error - signed_request parameter was missing in request
      logger.debug2  'fatal error - signed_request parameter was missing in request'
      render_with_language('cross_site_forgery')
      return
    end

    # unpack unsigned request
    oauth = Koala::Facebook::OAuth.new(API_ID[provider], API_SECRET[provider], API_CALLBACK_URL[provider])
    hash = oauth.parse_signed_request(signed_request)
    logger.debug2  "hash = #{hash}"
    # hash = {"algorithm"=>"HMAC-SHA256", "issued_at"=>1373284394, "user"=>{"country"=>"dk", "locale"=>"da_DK", "age"=>{"min"=>21}}}

    # fix invalid or missing language for translate
    locale = hash['user']['locale']
    language = locale.to_s.first(2)
    session[:language] = valid_locale(language) unless valid_locale(session[:language])
    logger.debug2  "session[:language] = #{session[:language]}"

    # todo: check if user already has authorized the required FB privileges
    # hash: hash = {"algorithm"=>"HMAC-SHA256", "expires"=>1373374800, "issued_at"=>1373370798,
    #               "oauth_token"=>"CAAFjZBGzzOkcBAM3vNXbvDtDm3qcV7RQ3HwSRZAC9PRUiSvA8zLAnFFUwEmuV5t6fWohIPn8ZCDUrTZCUFtlUdOK1aSPhL1nvobmEBNucZBu9KLWqb4wRcB6jZBy6K49pZCQOaXRl0C8cj4ZCAYfdZC9tZCLC8wZAFhs9GWJMGIkO91AwZDZD",
    #               "user"=>{"country"=>"dk", "locale"=>"da_DK", "age"=>{"min"=>21}}, "user_id"=>"1705481075"}
    if hash.has_key?('oauth_token') && hash.has_key?('user_id')
      # signature 2 - authorization in progress - show autologin page and redirect to facebook to complete authorization
      # signature 4 - as signature 2 - but redirect to users/index?friends=find after login
      if params[:fb_ref].to_s == 'friends_find'
        signature = 4 # login and redirect to users/index?friends=find page
      else
        signature = 2 # login and redirect to gifts/index page
      end
      logger.debug2  'user has already authorized gofreerev'
      # logger.debug2  "oauth_token = #{hash['oauth_token']}"
      logger.debug2  "user_id #{hash['user_id']}"
      # oauth_token = CAAFjZBGzzOkcBAB0GGUE4i4O9ZAT6FJ1N3U3mhl7S1TELLRl514fdEZAMuyMY4iUmFt74bBUWRH9WM4LYafsxs6osDzJc0ARo1yhRZCbAeQo0A9RXh5yEEW9cC3SjKC4LqbeO8x2Qy6JINJGO1pSkTllmQp5jPMZD
      # user_id  = 1705481075
      # autologin redirect to https://www.facebook.com/dialog/oauth? to get code without showing create.html erb page
      viewname = 'autologin'
      # wait with post login tasks to gifts/index page
      @disable_ajax_tasks = true
    elsif hash.has_key?('user_id')
      # signature 3 - used has deauthorization gofreerev in facebook
      signature = 3
      viewname = 'deauthorize'
    else
      # signature 1 - new unauthorized user
      signature = 1
      # create.html.erb shows an intro page with an authorize link
      viewname = __method__
    end

    if signature == 3
      # FB deauthorize - user has removed Gofreerev from app settings page in facebook
      # a deleted marked user account (users/edit delete link) will be deleted within 6 minutes (CLEANUP_USER_DELETED)
      # a deauthorized user acccount will be deleted after 14 days (CLEANUP_USER_DEAUTHORIZED)
      # a inactive user account will be deleted after 1 year (CLEANUP_USER_INACTIVE)
      # todo: double check that user has deauthorized gofreerev. http://stackoverflow.com/questions/5623035/facebook-app-users-list. Maybe user.is_app_user can be used
      user_id = "#{hash['user_id']}/facebook"
      user = User.find_by_user_id(user_id)
      user.update_attribute(:deauthorized_at, Time.new) if user
    else
      # FB authorization with minimal permissions (information already public)
      # More permissions will be requested later when they are needed and the user can understand why
      # note that there are problems with cookie store and IE10 when login starts from facebook (session[:state] not preserved)
      # tasks table is used for temporary store of state in facebook/index => autologin => FB => facebook/index sequence
      # @auth_url =  oauth.url_for_oauth_code(:permissions=>"read_stream")
      if signature == 4
        context = 'friends_find'
      else
        context = 'login'
      end
      @auth_url =  oauth.url_for_oauth_code :state => set_state_tasks_store(context)
      @auth_url = @auth_url.gsub('&amp;', '&') # fix invalid escape in auth url
      logger.debug2  "@auth_url = #{@auth_url}"
    end

    # show_friend page with an introduction and a authorize link - use create-<language>.html.erb if the view exists
    render_with_language viewname

  end # create


  # get /facebook - is called after authorization (create)
  # rejected: Parameters: {"error_reason"=>"user_denied", "error"=>"access_denied", "error_description"=>"The user denied your request."}
  # accepted: Parameters: {"code"=>"AQA6165EwuVn3EVKkzy2TOocej1wBb_t-9jEuhJQFFK7GH2PDkDbbSOOd9lhoqIYibusDfPpWOwaUg6XYiR2lcmP2tLgG0RPgRxL6qwFBZalg0j6wXSO8bZmjKn-yf9O_GOH9wm5ugMKLUihU7mjfLAbR58FrJ8wdgnej2aG9KLQvKNenb16Hf_ULI016u3DGHM-zGvmyb8xAgAAabOHkDQNT5C3lIO0eXTGMwo66zLrnn0jkENguAnAUuZrVym9OMiBV1f9ocg8WfgprflPq-BHOSHdhuHgYISHxO_nTs1dT7Ku5z551ZyBq1hG15aG4"}
  # skip: Parameters: {"code"=>"AQAtCrQaVuq5JP7MG5etjX617luFDULxxaJdn656mOE5nNT6xI6NTzC-FChcdTKlZH88ARb9ZFOKOYq4y_kS1C54fknXOUsaMjquPqfKLnaDB2ycRu30OS905EzgQKR0VEWm0xSR2NUR5GTdiet4keMgGt-CNvLlp9eKZWP94eoSr7EQyIFlw28pr5EL1FnSi6gW3gDuh64SmdBr86xDMMBdkyU-V-iZOW0cmP6YuzGFmszBwpZ5XL-PqOKEDWFSzJmOvYWDMFjrnKymoO-vyeNBQUiOp2tZFrTJJ-IRc8pr6tc1L-0qnJ5Y8HMakMRxJqI", "state"=>"UvhxJSQP6WV1JAR2k8cjENHjmolqSG-publish_actions"}
  # error: Parameters: {"error_code"=>"2", "error_message"=>"Denne funktion er desværre ikke tilgængelig i øjeblikkket: Der opstod en fejl under behandling af denne forespørgsel. Prøv igen senere.", "state"=>"BlGyeeW7Nd5lebhCkNeUCCo26hdpQY-publish_actions"}
  def index

    # where is request comming from?
    # login - login starter from facebook - previous request was post facebook/create
    # publish_actions - return from publish_actions priv. request (link in gifts/index page - inserted from util.post_on_facebook)
    # read_stream - return from read_stream priv. request (link in gifts/index page - inserted from util.post_on_facebook)
    context = params[:state].to_s.from(31)
    context = 'other' unless %w(login friends_find publish_actions read_stream).index(context)

    # Cross-site Request Forgery check
    # note that there are problems with cookie store and IE10 when login starts from facebook (session[:state] not preserved)
    # tasks table is used for temporary store of state in facebook/index => autologin => FB => facebook/index sequence
    # use special "tasks" session store for login. use normal session cookie store for add. mission privs. actions
    if %w(login friends_find).index(context) and invalid_state_tasks_store? or # state in tasks store (special IE10 workaround)
      !%w(login friends_find).index(context) and invalid_state_cookie_store? # state in normal session cookie store
      save_flash_key ".invalid_state_#{context}", :appname => APP_NAME
      redirect_to :controller => (%w(login other).index(context) ? :auth : :gifts)
      logout(provider)
      return
    end # if invalid_state?
    clear_state_cookie_store

    if params[:error_code] == '2' and context != 'login'
      # Parameters: {"error_code"=>"2",
      #              "error_message"=>"This feature is temporarily unavailable at the moment: There was an error processing this request. Please try again later",
      #              "state"=>"BlGyeeW7Nd5lebhCkNeUCCo26hdpQY-publish_actions"}
      # grant extra privs. failed (publish_actions or read_stream)
      save_flash_key ".#{context}_failed", :appname => APP_NAME, :error => params[:error_message]
      redirect_to :controller => :gifts
      return
    end

    if params[:error_reason] == 'user_denied'
      # user cancelled or denied api request
      save_flash_key ".user_denied_#{context}", :appname => APP_NAME
      redirect_to :controller => (%w(login other).index(context) ? :auth : :gifts)
      logout(provider) if context == 'login'
      return
    end

    if params[:code]
      # code received from FB - login in progress - exchange code for an access token
      # todo: error handling?!
      logger.debug2  "code = #{params[:code]}"
      oauth = Koala::Facebook::OAuth.new(API_ID[provider], API_SECRET[provider], API_CALLBACK_URL[provider])
      begin
        info = oauth.get_access_token_info(params[:code])
        logger.secret2 "info = #{info}"
        access_token, expires_at = info["access_token"], info["expires"] if info
        expires_at = expires_at.to_i.seconds.from_now.to_i # convert seconds to unix timestamp
      rescue Koala::Facebook::OAuthTokenRequestError => e
        if e.message =~ /authorization code has expired/
          save_flash_key ".auth_code_expired", :appname => APP_NAME
        else
          save_flash_key ".auth_code_error", :appname => APP_NAME, :error => e.message
        end
        redirect_to :controller => :auth
        return
      rescue => e
        logger.debug2 "exception: #{e.message} (#{e.class})"
        save_flash_key ".auth_code_error_", :appname => APP_NAME, :error => e.message
        redirect_to :controller => :auth
        return
      end
      # logger.debug2  "access_token = #{access_token}"
      # login completed. access token is saved.
    end

    unless access_token
      # access token was not found. Eg if FB app login page not was used
      # todo: change to flash message
      render_with_language 'cross_site_forgery'
      return
    end

    # FB login completed
    logger.debug2 "login completed. context = #{context}"

    # get some basic user information
    logger.debug2  'get user id and name'
    api_client = init_api_client(provider, access_token)
    api_request = 'me?fields=name,locale,link,picture.width(100).height(100),permissions'
    # logger.debug2  "api_request = #{api_request}"
    api_response = api_client.get_object api_request
    # logger.debug2  "api_response = #{api_response.to_s}"
    image = api_response['picture']['data']['url'] if api_response['picture'] and api_response['picture']['data']
    # fb_locale was received in FacebookController.create post request from facebook
    # add to api_response hash - is used for user.currency
    # api_response["language"] = session[:language]
    res = login :provider => provider,
                :token => access_token,
                :expires_at => expires_at,
                :uid => api_response["id"],
                :name => api_response['name'],
                :image => image, # only used for new facebook users
                :country => api_response['locale'].to_s.last(2),
                :language => api_response['locale'].to_s.first(2),
                :profile_url => api_response['link'],
                :permissions => api_response['permissions']['data']
    if !res
      # login ok
      user_id = "#{api_response['id']}/#{provider}"
      user = User.find_by_user_id(user_id)
      if context == 'login'
        no_friends = user.friends.size-1
        context = 'login_new_user' if no_friends == 0
      end
      if context == 'read_stream'
        # logger.debug2  "api_response = #{api_response.to_s}"
        # api_response = {"name"=>"Jan Roslind", "locale"=>"en_GB", "link"=>"http://www.facebook.com/1705481075",
        #                 "picture"=>{"data"=>{"height"=>100, "is_silhouette"=>false, "url"=>"https://fbcdn-profile-a.akamaihd.net/hprofile-ak-xpf1/v/t1.0-1/p100x100/996138_4574555377673_8850863452088448507_n.jpg?oh=ad61040224149a3f56f2c0b4e1bf9519&oe=54DB6127&__gda__=1424339048_6c52fc9e2b892549f0c907b075124494", "width"=>100}},
        #                 "permissions"=>{"data"=>[{"permission"=>"public_profile", "status"=>"granted"}, {"permission"=>"read_stream", "status"=>"granted"}, {"permission"=>"publish_actions", "status"=>"granted"}, {"permission"=>"user_friends", "status"=>"granted"}]},
        #                 "id"=>"1705481075"}
        permissions = api_response["permissions"]["data"] if api_response["permissions"]
        # logger.debug2 "permissions = #{permissions}"
        permission = permissions.find { |h| h["permission"] == 'read_stream'}
        logger.debug2 "permission = #{permission}"
        # permission = {"permission"=>"read_stream", "status"=>"declined"}
        status = permission["status"] if permission.class == Hash
        # logger.debug2 "status = #{status}"
        # user.permissions = api_response['permissions']['data']
        # user.save
        context = 'read_stream_skip' unless status == 'granted'
      end
      if context == 'publish_actions'
        # add publish_actions to facebook user before redirecting to gifts/index page
        # permissions will be updated in post_login_facebook task, but that is to late for this redirect
        # adding publish_actions enables file upload in gifts/index page now
        # permissions["publish_actions"] = 1
        # user.permissions = api_response['permissions']['data']
        # user.save!
        # permissions = [{"permission"=>"public_profile", "status"=>"granted"}, {"permission"=>"user_friends", "status"=>"granted"}]
        context = 'publish_actions_skip' unless get_post_on_wall_authorized(user.provider)
      end
      save_flash_key ".ok_#{context}", user.app_and_apiname_hash
      if context == 'friends_find'
        redirect_to :controller => :users, :friends => 'find'
      else
        redirect_to :controller => :gifts
      end
    else
      # login failed
      key, options = res
      begin
        save_flash_key key, options
      rescue => e
        logger.debug2  "invalid response from User.find_or_create_from_auth_hash. Must be nil or a valid input to translate. Response: #{user}"
        save_flash_key '.find_or_create_from_auth_hash', :response => user, :exception => e.message.to_s
      end
      redirect_to :controller => :auth
    end

  end # index



  # fix blank canvas in facebook - https://coderwall.com/p/toddiq
  private
  def allow_iframe
    response.headers['X-Frame-Options'] = 'GOFORIT'
  end

  private
  def provider
    "facebook"
  end

end
