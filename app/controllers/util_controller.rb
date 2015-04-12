require 'google/api_client'
require 'linkedin'

class UtilController < ApplicationController

  before_action :login_required, :except => [:do_tasks, :open_graph, :logout, :login, :ping]
  skip_filter :fetch_users, :only => [:ping, :login, :logout]
  before_action :validate_json_request, :only => [:do_tasks, :open_graph, :login, :logout, :ping]

  #
  # gift link ajax methods
  #

  private
  def check_gift_action (action)
    gift = nil
    actions = %w(like unlike follow unfollow hide delete)
    if !actions.index(action)
      logger.error2 "Invalid call. action #{action}. allowed actions are #{actions.join(', ')}"
      return [gift, '.invalid_action', {:action => action, :raise => I18n::MissingTranslationData}]
    end
    gift_id = params[:gift_id]
    gift = Gift.find_by_id(gift_id)
    if !gift
      logger.debug2 "Gift with id #{gift_id} was not found"
      return [gift, '.gift_not_found', {:raise => I18n::MissingTranslationData}]
    end
    logger.debug2 "logged_in? = #{logged_in?}"
    return [gift, '.not_logged_in', {:raise => I18n::MissingTranslationData}] unless logged_in?
    return [gift, '.gift_deleted', {:raise => I18n::MissingTranslationData}] if gift.deleted_at
    if !gift.visible_for?(@users)
      logger.debug2 "#{User.debug_info(@users)} is/are not allowed to see gift id #{gift_id}"
      return [gift, '.not_authorized', {:raise => I18n::MissingTranslationData}]
    end
    @users.remove_deleted_users
    if !gift.visible_for?(@users)
      logger.debug2 "Found one or more deleted accounts. Remaining users #{User.debug_info(@users)} is/are not allowed to see gift id #{gift_id}"
      return [gift, '.deleted_user', {:raise => I18n::MissingTranslationData}]
    end
    method_name = "show_#{action}_gift_link?".to_sym
    show_action = gift.send(method_name, @users)
    if !show_action
      logger.debug2 "#{action} link no longer active for gift with id #{gift_id}"
      return [gift, '.not_allowed', {:raise => I18n::MissingTranslationData}]
    end
    # ok
    gift
  end # check_gift_action


  # before action filter. validate json request against json schema definition
  # used in do_tasks, login, logout and ping
  private
  def validate_json_request
    logger.debug2 "params = #{params.to_json}"
    json_schema = "#{params[:action]}_request".to_sym
    if !JSON_SCHEMA.has_key? json_schema
      # abort action and report error
      @json[:error] = "Could not JSON validate #{params[:action]} request. JSON schema definition #{json_schema} was not found."
      logger.error2 @json[:error]
      format_response
      return
    end
    # validate request
    json_request = params.clone
    %w(controller action format util).each { |key| json_request.delete(key) }

    # todo: decrypt encrypted rsa or mix request. signature {:encryption => 'rsa', :message => xxx} or
    #       {:encryption => 'mix', key => xxx, :message => xxx}
    #       use for insecure http or as extra security for https

    logger.secret2 "#{json_schema} = #{json_request}"
    json_errors = JSON::Validator.fully_validate(JSON_SCHEMA[json_schema], json_request)
    return true if json_errors.size == 0
    @json[:error] = "Invalid #{params[:action]} request: #{json_errors.join(', ')}"
    logger.error2 @json[:error]
    # stop or continue?
    if %w(do_tasks login).index(params[:action].to_s)
      # error in login - abort action and report error
      format_response
      return
    end
    # error in ping and logout - continue
  end # validate_json_request

  # validate json response against json schema definition - used in do_tasks, login, logout and ping
  private
  def validate_json_response
    return if @json[:error]
    # check if json schema definition exists
    json_schema = "#{params[:action]}_response".to_sym
    if !JSON_SCHEMA.has_key? json_schema
      # abort action and report error
      @json[:error] = "Could not JSON validate #{params[:action]} response. JSON schema definition #{json_schema} was not found."
      logger.error2 @json[:error]
      return
    end
    # validate json response
    do_tasks_response_errors = JSON::Validator.fully_validate(JSON_SCHEMA[json_schema], @json)
    return if do_tasks_response_errors.size == 0
    logger.debug "Invalid #{params[:action]} json response:"
    logger.debug "response: #{@json.to_json}"
    logger.debug "schema: #{JSON_SCHEMA[json_schema].to_json}"
    logger.debug "errors: #{do_tasks_response_errors.join(', ')}"
    @json[:error] = "Invalid #{params[:action]} response: #{do_tasks_response_errors.join(', ')}"
  end # validate_json_response

  # process tasks from queue
  # that is tasks that could slow request/response cycle or information that is not available on server (client timezone)
  # tasks:
  # - download user profile image from login provider after login (ok)
  # - get permissions from login provider after login (todo: twitter)
  # - get friend lists from login provider after login (ok)
  # - get currency rates for a new date (ok)
  # - upload post and optional picture to login provider (ok)
  public
  def do_tasks
    begin

      # todo: debug why IE is not setting state before redirecting to facebook in facebook/autologin
      logger.debug2 "session[:session_id] = #{get_sessionid}, session[:state] = #{get_session_value(:state)}"
      # todo: debug problems with session[:last_row_id]
      logger.debug2 "session[:last_row_id] = #{get_last_row_id()}"
      # cleanup old tasks
      Task.where("created_at < ? and ajax = ?", 2.minute.ago, 'Y').destroy_all
      Task.where("created_at < ? and ajax = ?", 10.minute.ago, 'N').destroy_all
      Task.where("session_id = ? and ajax = ?", get_sessionid, 'Y').order('priority, id').each do |at|
        at.destroy
        if !logged_in?
          logger.warn2 "not logged in. Ignoring task #{at.task}"
          next
        end
        # all tasks must have exception handlers with backtrace.
        # Exception handler for eval will not display backtrace within the called task
        logger.debug2 ""
        logger.debug2 "executing task #{at.task}\n"
        begin
          eval(at.task)
        rescue => e
          logger.debug2 "error when processing task #{at.task}"
          logger.debug2 "Exception: #{e.message.to_s}"
          logger.debug2 "Backtrace: " + e.backtrace.join("\n")
          add_error_key '.do_task_exception', :task => at.task, :error => e.message.to_s
        end
      end
      logger.debug2 "@errors.size = #{@errors.size}"

      validate_json_response
      format_response
    rescue => e
      logger.debug2  "Exception: #{e.message.to_s} (#{e.class})"
      logger.debug2  "Backtrace: " + e.backtrace.join("\n")
      format_response_key '.do_tasks_exception', :error => e.message.to_s
    end
  end # do_tasks

  private
  def fetch_exchange_rates
    begin
      key, options = ExchangeRate.fetch_exchange_rates
      return add_error_key key, options if key
    rescue => e
      logger.debug2  "Exception: #{e.message.to_s} (#{e.class})"
      logger.debug2  "Backtrace: " + e.backtrace.join("\n")
      raise
    end
  end

  private
  def get_login_user_and_token (provider, task)
    login_user = token = nil
    # find user id and token for provider
    login_user = @users.find { |user| user.provider == provider }
    login_user_id = login_user.user_id if login_user
    return [login_user, token,
            'util.do_tasks.login_user_id_not_found',
            {:provider => provider, :apiname => provider_downcase(provider), :task => task}] unless login_user_id
    login_user = User.find_by_user_id(login_user_id)
    return [login_user, token,
            'util.do_tasks.login_user_id_unknown',
            {:provider => provider, :apiname => provider_downcase(provider), :user_id => login_user_id, :task => task}] unless login_user
    # get token for api requests
    token = (get_session_value(:tokens) || {})[provider]
    return [login_user, token,
            'util.do_tasks.login_token_not_found',
            {:provider => provider, :apiname => provider_downcase(provider), :task => task}] if token.to_s == ""
    # logger.debug2  "token = #{token}"
    # ok
    return [login_user, token]
  end # get_login_user_and_token

  private
  def get_login_user_and_api_client (provider, task)
    api_client = nil
    login_user, token, key, options = get_login_user_and_token(provider, task)
    return [login_user, api_client, key, options] if key
    logger.secret2 "provider = #{provider}, token = #{token}"

    key, options = init_api_client(provider, token) # returns [key, options] (error) or [api_client, nil] (ok)
    api_client, key = key, nil if key.class != String
    [login_user, api_client, key, options]
  end # get_login_user_and_api_client

  
  # returns [login_user, api_client, friends_hash, new_user, key, options] array
  # key + options are used as input to translate after errors
  private
  def post_login_update_friends (provider)
    friends_hash = new_user = nil
    login_user, api_client, key, options = get_login_user_and_api_client(provider, __method__)
    logger.debug2 "debug 1: key = #{key} (#{key.class})"
    return [login_user, api_client, friends_hash, new_user, key, options] if key
    login_user_id = login_user.user_id

    # return oauth authorization from temporary storage in rails session to client. stored encrypted in client localStorage
    @json[:oauths] = [] unless @json[:oauths]
    @json[:oauths].delete_if { |oauth| oauth[:provider] == provider }
    oauth = {:provider => provider,
             :user_id    => login_user.user_id,
             :token      => get_session_array_value(:tokens, provider),
             :expires_at => get_session_array_value(:expires_at, provider)}
    oauth[:refresh_token] = get_session_array_value(:refresh_tokens, provider) if provider == 'google_oauth2'
    @json[:oauths] << oauth

    # remove oauth authorization from rails session. keep expires_at timestamp in server session. used in access token expiration check
    delete_session_array_value(:tokens, provider)
    delete_session_array_value(:refresh_tokens, provider) if provider == 'google_oauth2'

    # update user
    # note what many fields are updated in User.find_or_create_user doing login
    # only use this method for fields that are not updated in login process
    if api_client.respond_to? :gofreerev_get_user
      # fetch info about login user from API
      user_hash, key, options = api_client.gofreerev_get_user logger
      logger.debug2 "user_hash = #{user_hash}, key = #{key}, options = #{options}"
      logger.debug2 "debug 2: key = #{key} (#{key.class})"
      return [login_user, api_client, friends_hash, new_user, key, options] if key
      # update user
      key, options = login_user.update_api_user_from_hash user_hash
      logger.debug2 "debug 3: key = #{key} (#{key.class})"
      return [login_user, api_client, friends_hash, new_user, key, options] if key
      login_user.reload
      logger.debug2 "api_profile_picture_url = #{login_user.api_profile_picture_url}"
    else
      logger.debug "no gofreerev_get_user method was found for #{provider} api client"
    end

    # get API friends
    if !api_client.respond_to? :gofreerev_get_friends
      # api client without gofreerev_get_friends method - cannot download and update friend list from api provider
      key, options = ['.api_client_gofreerev_get_friends', login_user.app_and_apiname_hash]
      logger.debug2 "debug 4: key = #{key} (#{key.class})"
      return [login_user, api_client, friends_hash, new_user, key, options]
    end
    begin
      friends_hash, key, options = api_client.gofreerev_get_friends logger
      logger.debug2 "debug 5: key = #{key} (#{key.class})"
    rescue AppNotAuthorized => e
      # app has been deauthorized after login and before executing post login task for this provider
      session_logout(provider)
      key, options = ['util.do_tasks.post_login_fl_not_authorized', login_user.app_and_apiname_hash]
      logger.debug2 "debug 6: key = #{key} (#{key.class})"
      return [login_user, api_client, friends_hash, new_user, key, options]
    rescue => e
      logger.debug2 "ecception: #{e.message}"
      raise
    end
    return [login_user, api_client, friends_hash, new_user, key, options] if key
    logger.debug2 "debug 7: key = #{key} (#{key.class})"

    # update friends list in db (api friend = Y/N)
    new_user, key, options = Friend.update_api_friends_from_hash :login_user_id => login_user_id, :friends_hash => friends_hash
    logger.debug2 "debug 8: key = #{key} (#{key.class})"
    [login_user, api_client, friends_hash, new_user, key, options]
  end # post_login_update_friends

  # generic post login task - used if post_login_<provider> does not exist
  # upload and updates friend list and updates user balance
  private
  def generic_post_login (provider)
    begin
      # get login user, initialize api client, get and update friends information
      # also initialized @json[:oauths] array with oauth information to client (stored encrypted in localStorage)
      login_user, api_client, friends_hash, new_user, key, options = post_login_update_friends(provider)
      #logger.debug2 "login_user   = #{login_user}"
      #logger.debug2 "api_client   = #{api_client}"
      logger.debug2 "friends_hash = #{friends_hash}"
      #logger.debug2 "new_user     = #{new_user}"
      #logger.debug2 "key          = #{key}"
      #logger.debug2 "options      = #{options}"
      return add_error_key(key, options) if key

      # return json object with relevant user info. see list with friends categories in User.cache_friend_info
      User.cache_friend_info([login_user])
      secret_just_changed = SystemParameter.where("name = 'secret' and updated_at > ?", 3.minutes.ago).first
      if secret_just_changed
        @json[:friends_sha256_update_at] = secret_just_changed.updated_at.to_i
      end
      users = User.where(:user_id => login_user.friends_hash.keys).includes(:server_users, :servers)
      @json[:friends] = [] unless @json[:friends]
      @json[:friends] += users.collect do |user|
        hash = { :user_id => user.id,
                 :uid => user.uid,
                 :provider => user.provider,
                 :user_name => user.user_name,
                 :friend => login_user.friends_hash[user.user_id] }
        hash[:api_profile_picture_url] = user.api_profile_picture_url if user.api_profile_picture_url
        # include sha256 signatures for friends on other Gofreerev servers.
        # used as user_id when sending and receiving messages to/from other Gofreerev servers
        verified_server_users = user.server_users.find_all { |su| su.verified_at }
        if verified_server_users.size > 0
          # friend on other Gofreerev server
          hash[:sha256] = user.sha256
          hash[:old_sha256] = user.old_sha256 if secret_just_changed
          hash[:remote_sha256] = verified_server_users.collect do |v|
            { :server_id => v.server_id,
              :sha256 => user.calc_sha256(v.server.secret) }
          end
        end
        hash
      end

      # update number of friends.
      # facebook: number of friends is not 100 % correct as not all friends are returned from facebook api
      # todo: how to set number of friends for follows/followed_by networks (twitter)
      # todo: is number of friends use for anything?
      login_user.update_attribute(:no_api_friends, friends_hash.size)

      # update balance
      today = Date.parse(Sequence.get_last_exchange_rate_date)
      login_user.recalculate_balance if today and login_user.balance_at != today

      # warning if empty friend list in post login
      # could be a new user - could be that app is not authorized to see friends
      # ignore empty friend list in facebook oauth 2.x facebook
      return add_error_key('.post_login_no_friends', login_user.app_and_apiname_hash) if friends_hash.size == 0 and !%w(facebook).index(provider)

      # special post login message to new users (refresh page when friend list has been downloaded)
      return add_error_key('.post_login_new_user', login_user.app_and_apiname_hash) if new_user

      # ok
      nil
    rescue AppNotAuthorized
      session_logout :provider => provider
      return add_error_key('.linkedin_access_denied', {:provider => provider})
    rescue LinkedIn::Errors::AccessDeniedError => e
      return add_error_key('.linkedin_access_denied', {:provider => provider}) if e.message.to_s =~ /Access to connections denied/
      logger.debug2  "Exception: #{e.message.to_s} (#{e.class})"
      logger.debug2  "Backtrace: " + e.backtrace.join("\n")
      raise
    rescue => e
      logger.debug2  "Exception: #{e.message.to_s} (#{e.class})"
      logger.debug2  "Backtrace: " + e.backtrace.join("\n")
      raise
    end
  end # generic_post_login


  # recalculate user balance
  # use after login, at new day, after new deal, after deleted deal etc
  def recalculate_user_balance (id)
    begin
      # check id
      user = User.find_by_id(id)
      return ['.recal_user_bal_unknown_id',{}] unless user
      return ['.recal_user_bal_invalid_id',{}] unless login_user_ids.index(user.user_id)

      # recalculate balance for user or for user combination
      today = Date.parse(Sequence.get_last_exchange_rate_date)
      if user.share_account_id
        users = User.where('share_account_id = ? and (balance_at is null or balance_at <> ?)', user.share_account_id, today)
        if users.size > 0
          # todo. User.recalculate_balance class method is not tested
          res = User.recalculate_balance(users)
        end
      else
        res = user.recalculate_balance if !user.balance_at or user.balance_at != today
      end
      ['.recal_user_cal_pending',{}] unless res

      nil

    rescue => e
      logger.debug2  "Exception: #{e.message.to_s} (#{e.class})"
      logger.debug2  "Backtrace: " + e.backtrace.join("\n")
      raise
    end
  end # recalculate_user_balance


  # get url for api gift picture on facebook wall - size >= 200 x 200
  # used in post_in_facebook and in missing_api_picture_urls
  # raises ApiPostNotFoundException if post/picture was not found (missing permission or post/picture has been deleted)
  # that is - get_api_picture_url_facebook is also used to check for missing read stream permission
  # return nil (ok) or [key, options] error input to translate
  # params:
  # - just_posted - true if called from post_on_facebook - false if called from missing_api_picture_urls
  # - api_client - koala api client
  private
  def get_api_picture_url_facebook (api_gift, just_posted=true, api_client) # api is Koala API client

    return nil if api_gift.deleted_at_api == 'Y' # ignore - post/picture has been deleted from facebook wall

    provider = "facebook"
    login_user, token, key, options = get_login_user_and_token(provider, __method__)
    return [key, options] if key

    #if !api_client
    #  # get access token and initialize koala api client
    #  raise "api_client is nil"
    #  api_client = init_api_client_facebook(token)
    #end

    # two koala api request. 1) get picture and object_id, 2) get an array with different size pictures

    # 1) get picture and object id
    object_id = nil
    begin
      # check read access to facebook wall and get object_id for next api request (only for post with picture)
      res1 = api_client.get_object api_gift.api_gift_id
      # logger.debug2 "res1 = #{res1}"
      api_gift.api_gift_url = res1['link']
      object_id, picture = res1['object_id'], res1['picture']
      image_type = FastImage.type(picture) if picture.to_s != ""
      logger.debug2 "first lookup: object_id = #{object_id}, picture = #{picture}, image type = #{image_type}"
      if api_gift.picture?
        if %w(jpg jpeg gif png bmp).index(image_type.to_s)
          # valid (small) picture url received from facebook
          api_gift.api_picture_url = picture
          api_gift.api_picture_url_updated_at = Time.now
          api_gift.api_picture_url_on_error_at = nil
        else
          # unexpected error - found post, but did not get a valid picture url
          logger.debug2 "Did not get a picture url from api. Must be problem with missing access token, picture != Y or deleted_at_api == Y"
          logger.debug2 "res1 = #{res1}"
          return ['.no_api_picture_url', {:apiname => login_user.apiname}]
        end
      end
      api_gift.save!
    rescue Koala::Facebook::ClientError => e
      if e.fb_error_type == 'GraphMethodException' and e.fb_error_code == 100
        # identical error response if picture is deleted or if user is not allowed to see picture
        # picture not found - maybe picture has been deleted - maybe a permission problem
        # granting read_stream or changing visibility of app setting to public can solve the problem
        # read_stream permission will be requested if error is raise when posting on facebook wall
        logger.debug2 "Handling Koala::Facebook::ClientError, GraphMethodException' with FB error code 100."
        logger.debug2 "just_posted = #{just_posted}"

        # problem with upload and permissions
        # could not get full_picture url for an uploaded picture
        # the problem appeared after changing app visibility from friends to only me
        # that is - app is not allowed to get info about the uploaded picture!!

        if !FACEBOOK_READ_STREAM
          # facebook oauth 2.2 - read_stream priv. requires special approval process - skip request.
          api_gift.deleted_at_api = 'Y'
          api_gift.save!
          if just_posted
            return ['.fb_pic_post_declined_permission_html', {:appname => APP_NAME, :apiname => login_user.apiname} ]
          else
            return nil
          end
        end

        # just display a warning and continue. Request read_stream permission from user if read_stream priv. is missing
        api_gift.deleted_at_api = 'Y' if just_posted
        api_gift.save!
        # (re)check permissions
        if login_user.read_gifts_allowed?
          # check if user has removed read stream priv.
          login_user.get_permissions_facebook(api_client)
        end
        if login_user.read_gifts_allowed?
          if !just_posted
            # called from missing_api_picture_urls - user has deleted post on api wall
            logger.debug2 "user has deleted post on api wall - ok"
            return nil
          end
          # just posted + read permission to call - error - this should not happen.
          logger.debug2 "just posted + read permission to call - error - this should not happen"
          key = api_gift.picture? ? '.fb_pic_post_unknown_problem' : '.fb_msg_post_unknown_problem'
          return [key, {:appname => APP_NAME, :apiname => login_user.apiname}]
        else
          # message with link to grant missing read stream priv.
          logger.debug2 "user.permissions = #{login_user.permissions}"
          # check if user has declined read_stream permission
          if api_gift.picture? and login_user.permissions.find { |p| p['permission'] == 'read_stream' and p['status'] == 'declined'}
            # used has declined read_stream permissions and fb dialog can not be used to get read_stream permission.
            key =  '.fb_pic_' + (just_posted ? 'post' : 'check') + '_declined_permission_html'
            return [key, {:appname => APP_NAME, :apiname => login_user.apiname }]
          end

          oauth = Koala::Facebook::OAuth.new(API_ID[provider], API_SECRET[provider], API_CALLBACK_URL[provider])
          url = oauth.url_for_oauth_code(:permissions => 'read_stream', :state => set_state_cookie_store('read_stream'))
          logger.debug2 "url = #{url}"
          # note: 4 translations:
          # - fb_msg_post_missing_permission_html - just posted - without picture
          # - fb_pic_post_missing_permission_html - just posted - with picture - missing read permission
          # - fb_msg_check_missing_permission_html - not used
          # - fb_pic_check_missing_permission_html - old post - check picture url - missing read permission
          key =  '.fb_' + (api_gift.picture? ? 'pic' : 'msg') + '_' + (just_posted ? 'post' : 'check') + '_missing_permission_html'
          return [key, {:appname => APP_NAME, :apiname => login_user.apiname, :url => url}]
        end

      elsif e.fb_error_type == 'OAuthException' and e.fb_error_code == 190 and [460, 458].index(e.fb_error_subcode)
        # Koala::Facebook::ClientError
        # 1) fb_error_type    = OAuthException (String)
        #    fb_error_code    = 190 (Fixnum)
        #    fb_error_subcode = 460 (Fixnum)
        #    fb_error_message = Error validating access token: The session has been invalidated because the user has changed the password. (String)
        #    http_status      = 400 (Fixnum)
        #    response_body    = {"error":{"message":"Error validating access token: The session has been invalidated because the user has changed the password.","type":"OAuthException","code":190,"error_subcode":460}}
        # 2) fb_error_type    = OAuthException (String)
        #    Koala::Facebook::ClientError
        #    fb_error_code    = 190 (Fixnum)
        #    fb_error_subcode = 458 (Fixnum)
        #    fb_error_message = Error validating access token: The user has not authorized application 391393607629383. (String)
        #    http_status      = 400 (Fixnum)
        #    response_body    = {"error":{"message":"Error validating access token: The user has not authorized application 391393607629383.","type":"OAuthException","code":190,"error_subcode":458}}
        raise AppNotAuthorized ;
      else
        # unhandled koala / facebook exception
        e.logger = logger
        e.puts_exception("#{__method__}: ")
        raise
      end
    end # rescue
    return nil unless object_id # post without picture

    if object_id
      # post with picture
      # 2) get best size picture from facebook. picture with size >= 200 x 200 or largest picture
      # picture must be min 200 x 200 for open graph links on facebook
      # https://developers.facebook.com/tools/debug)
      begin
        res2 = api_client.get_object object_id
        # logger.debug2 "res2 = #{res2}"
        images = res2["images"]
        if images.class == Array and images.size > 0
          logger.debug2 "second lookup: images = #{images}"
          image = nil
          images.each do |hash|
            image = hash["source"] if hash["height"].to_i >= 200 and hash["width"].to_i >= 200
          end
          image = images.first["source"] unless image
          logger.debug2 "image = #{image}"
          api_gift.api_picture_url = image
          api_gift.save!
        else
          logger.warn2 "second lookup: no images array was returned from facebook API request. Keeping old picture"
          logger.warn2 "res2 = #{res2}"
        end
      rescue Koala::Facebook::ClientError => e
        # unhandled koala / facebook exception
        e.logger = logger
        e.puts_exception("#{__method__}: ")
        raise
      end
    end

    # ok
    nil

  end # get_api_picture_url_facebook

  # get url for api gift picture on flickr wall - size >= 200 x 200
  # used in post_in_flickr and in missing_api_picture_urls
  # raises ApiPostNotFoundException if post/picture was not found (missing permission or post/picture has been deleted)
  # that is - get_api_picture_url_flickr is also used to check for missing read permission
  # return nil (ok) or [key, options] error input to translate
  # params:
  # - just_posted - true if called from post_on_flickr - false if called from missing_api_picture_urls
  # - api_client - flickraw api client
  private
  def get_api_picture_url_flickr (api_gift, just_posted, api_client) # api is flickraw API client

    provider = "flickr"

    images = nil
    begin
      # http://www.flickr.com/services/api/flickr.photos.getSizes.html
      images = api_client.photos.getSizes :photo_id => api_gift.api_gift_id
    rescue FlickRaw::FailedResponse => e
      #   1: Photo not found - The photo id passed was not a valid photo id.
      #   2: Permission denied - The calling user does not have permission to view the photo.
      # 100: Invalid API Key - The API key passed was not valid or has expired.
      # 105: Service currently unavailable - The requested service is temporarily unavailable.
      # 106: Write operation failed - The requested operation failed due to a temporary issue.
      # 111: Format "xxx" not found - The requested response format was not found.
      # 112: Method "xxx" not found - The requested method was not found.
      # 114: Invalid SOAP envelope - The SOAP envelope send in the request could not be parsed.
      # 115: Invalid XML-RPC Method Call - The XML-RPC request document could not be parsed.
      # 116: Bad URL found - One or more arguments contained a URL that has been used for abuse on Flickr.
      # exception: 'flickr.photos.getSizes' - Photo not found
      # e.methods = !, !=, !~, <=>, ==, ===, =~, __debug_binding, __debug_context, __debug_file, __debug_line, __id__, __send__, `, acts_like?, as_json, backtrace,
      # binding_n, blame_file!, blamed_files, blank?, breakpoint, capture, class, class_eval, clone, code, copy_blame!, debugger, deep_dup, define_singleton_method, describe_blame, display, dup,
      # duplicable?, enable_warnings, enum_for, eql?, equal?, exception, extend, freeze, frozen?, gem, hash, html_safe?, in?, inspect, instance_eval, instance_exec, instance_of?, instance_values,
      # instance_variable_defined?, instance_variable_get, instance_variable_names, instance_variable_set, instance_variables, is_a?, kind_of?, load, load_dependency, message, method, methods, msg,
      # nil?, object_id, presence, present?, pretty_inspect, pretty_print, pretty_print_cycle, pretty_print_inspect, pretty_print_instance_variables, private_methods, protected_methods, psych_to_yaml,
      # public_method, public_methods, public_send, quietly, remove_instance_variable, require, require_dependency, require_or_load, respond_to?, send, set_backtrace, silence, silence_stderr,
      # silence_stream, silence_warnings, singleton_class, singleton_methods, suppress, suppress_warnings, taint, tainted?, tap, to_enum, to_json, to_param, to_query, to_s, to_yaml,
      # to_yaml_properties, trust, try, try!, unloadable, untaint, untrust, untrusted?, with_options, with_warnings
      # e.code = 1
      if e.code == 1 and !just_posted
        # 1: Photo not found - The photo id passed was not a valid photo id.
        # mark api gift as deleted at api. util.missing_api_picture_urls may replace deleted flickr picture with picture from an other login provider
        logger.debug2 "user has deleted post on api wall - ok"
        api_gift.deleted_at_api = 'Y'
        api_gift.save!
        return nil
      end
      raise AppNotAuthorized if e.code == 100 # 100: Invalid API Key - The API key passed was not valid or has expired. Reconnect is required
      # other flickr exceptions - display flickr exception to user
      logger.error2 "exception: #{e.message}"
      logger.error2 "e.code = #{e.code}"
      raise
    end

    if images.class == FlickRaw::ResponseList and images.length > 0
      logger.debug2 "images = #{images}"
      image = nil
      images.reverse_each do |hash|
        image = hash.source if hash.height.to_i >= 200 and hash.width.to_i >= 200
      end
      image = images.last.source unless image
      logger.debug2 "image = #{image}"
      api_gift.api_picture_url = image
      api_gift.save!
    else
      logger.warn2 "no images array was returned from flickr API request. Keeping old picture"
      logger.warn2 "images = #{images}"
    end

    # ok
    nil

  end # get_api_picture_url_flickr


  # get_api_picture_url_linkedin is not relevant. Picture is stored in Gofreerev for Linkedin.


  # recheck post on twitter
  # mark as deleted if post has been deleted
  # get new api_picture_url if picture url has changed
  # called from missing_api_picture_urls if image has been moved or deleted
  private
  def get_api_picture_url_twitter (api_gift, just_posted=true, api_client) # api is twitter API client

    provider = "twitter"

    # check twitter post
    begin
      x = api_client.status api_gift.api_gift_id
      logger.debug2 "x = #{x}"
      logger.debug2 "x.class = #{x.class}"
      api_gift.api_picture_url = x.media.first.media_url.to_s if api_gift.picture?
    rescue Twitter::Error::NotFound => e # todo: other twitter exceptions?
      logger.debug2 "Exception: e = #{e.message} (#{e.class})"
      if just_posted
        raise
      else
        api_gift.deleted_at_api = 'Y'
      end
    end
    api_gift.save!

    # ok
    nil

  end # get_api_picture_url_twitter


  # recheck post on vkontakte
  # mark as deleted if post has been deleted
  # get new api_picture_url if picture url has changed
  # called from missing_api_picture_urls if image has been moved or deleted
  private
  def get_api_picture_url_vkontakte (api_gift, just_posted=true, api_client) # api is vkontakte API client

    # check vkontakte post
    begin
      x = api_client.photos.getById :photos => api_gift.api_gift_id
      if x.class != Array or x.length != 1
        raise VkontaktePhotoGet.new "Expected array with one photo. Response = #{x} (#{x.class})"
      end
      x = x.first
      if x.class != Hash or !x.has_key?('src_big')
        raise VkontaktePhotoGet.new "Expected hash with scr_big. Response = #{x} (#{x.class})"
      end
      api_gift.api_picture_url = x['src_big']
    rescue Vkontakte::App::VkException => e
      logger.debug2 "Exception: e = #{e.message} (#{e.class})"
      logger.debug2 "e.methods = #{e.methods.sort.join(', ')}"
      # todo: check exception. Only ok if picture has been deleted at VK and !just_posted
      api_gift.deleted_at_api = 'Y'
    end
    api_gift.save!
    logger.debug2 "api_gift.api_picture_url = #{api_gift.api_picture_url}"

    # ok
    nil

  end # get_api_picture_url_vkontakte
  
  
  # generic get_api_picture_url_<provider>
  # just_posted: true if called from generic_post_on_wall, false if called from missing_api_picture_urls
  private
  def get_api_picture_url (provider, api_gift, just_posted, api_client)

    return nil if api_gift.deleted_at_api == 'Y' # ignore - post/picture has been deleted

    method = "get_api_picture_url_#{provider}".to_sym
    if !private_methods.index(method)
      logger.error2 "System error. private method #{method} was not found in app. controller"
      return ['util.do_tasks.get_api_picture_url_missing',
              {:provider => provider, :apiname => provider_downcase(provider), :appname => APP_NAME} ]
    end
    logger.debug2 "calling #{method}"
    send(method, api_gift, just_posted, api_client)
  end # get_api_picture_url


  # wrapper for User.find_friends_batch
  # run as a batch task without login user array.
  # error message is not relevant for current login user(s)
  # write any error messages from User.find_friends_batch to log
  private
  def find_friends_batch
    begin
      key, options = User.find_friends_batch
      if key
        msg = t key, options
        logger.error2 msg
      end
      # ok
      nil
    rescue => e
      logger.debug2  "Exception: #{e.message.to_s} (#{e.class})"
      logger.debug2  "Backtrace: " + e.backtrace.join("\n")
      raise
    end
  end # find_friends_batch

  # check external url from gifts/index page (create new gift)
  # get open graph tags from html page and json with preview info or json with error message
  public
  def open_graph
    begin
      return format_response_key('.not_logged_in', {}) if !logged_in?

      # check url with embed.ly API or opengraph_parser
      url = params[:url]
      # logger.debug2 "url = #{url}"
      og = OpenGraphLink.find_or_create_link(url)
      if og
        @json[:url] = og.url
        @json[:title] = og.title.to_s.sanitize
        @json[:description] = og.description.to_s.sanitize
        @json[:image] = og.image
      end

      validate_json_response
      format_response
    rescue => e
      logger.debug2 "Exception: #{e.message.to_s} (#{e.class})"
      logger.debug2 "Backtrace: " + e.backtrace.join("\n")
      format_response_key '.exception', :error => e.message
    end
  end # open_graph

  public
  def upload
    logger.debug2 "params = #{params}"
  end

  # client login. receive oauth hash from client, insert oauth in server session and update/download friends information
  # server login. receive did, client_secret and
  public
  def login
    begin

      # remember unique device uid and client secret - used in sync. data between devices
      if params[:did].to_s == ''
        # debug. did is required in login json. This error should have been found in validate_json_request filter!
        @json[:error] = "login and did is empty"
        format_response
        return
      end
      # unique device id
      set_session_value :did, params[:did]
      # client secret - used in pings.sha256 - with did a unique client mailbox address
      set_session_value :client_secret, params[:client_secret]
      # timestamp for system secret. all clients must download updated sha256 signatures for friends on other gofreerev servers
      set_session_value :system_secret_updated_at, SystemParameter.secret_at

      if params[:site_url].to_s != ''
        # server login request
        set_session_value :server, true
        @json[:friends] = [] # todo: change :friends to not required in login request json schema
        # save did and public key from other gofreerev server - used in server to server communication
        # private key is saved in system_parameters table encrypted with 1-4 passwords
        # see private key security setup in config/initializers/constants.rb (PK_PASS_*)
        site_url = params[:site_url].to_s
        site_url = site_url.gsub(/^https/, 'http')
        s = Server.find_by_site_url(site_url)
        if (!s)
          s = Server.new
          s.site_url = site_url
          s.secure = true
        end
        # validate signature for incoming login request
        # - server must exists
        # - signature file must exists
        # - sha256 signature in signature file must match sha256 signature of incoming login request
        # logger.debug "signature url = #{s.signature_url(params[:client_timestamp])}"
        signature = Server.login_signature(params)
        # logger.debug "signature = #{signature}"
        if error = s.invalid_signature(params[:client_timestamp], signature)
          # server not responding or signature is invalid
          @json[:error] = error
          format_response
          return
        end
        # signature ok
        if error = s.save_new_did_and_public_key(params[:did], params[:pubkey])
          # invalid did change. cannot change did to an existing did
          @json[:error] = error
          format_response
          return
        end
        # save secret. used in user.sha256 signature when comparing users information between two gofreerev servers
        s.secret = params[:client_secret]
        s.save! if s.new_record? or s.changed?
        # use site_url as dummy user id user for gofreerev servers
        set_session_value :user_ids, [site_url]
        logger.debug2 "login user ids = #{login_user_ids}"
        # return public key for this gofreerev to other gofreerev server
        pubkey = SystemParameter.public_key
        if !pubkey
          # first server to server login - generate public/private key pair for rsa communication
          SystemParameter.generate_key_pair
          pubkey = SystemParameter.public_key
        end
        @json[:pubkey] = pubkey
        # return did for this gofreerev server to other gofreerev server
        # used as mailbox address in server to server communication
        @json[:did] = SystemParameter.did
        # return client secret for this gofreerev server to other gofreerev server
        # used as secret when comparing user information between two gofreerev servers
        @json[:client_secret] = SystemParameter.secret
        # ok
        format_response
        return
      end

      # client request
      set_session_value :server, false

      # save new public key from browser client - used in client to client communication
      # private key is saved key encrypted in browser localStorage and is only known by js client
      # see private key security in /app/assets/javascript/gofreerev.js getItem and setItem functions
      # private key in browser localStorage is encrypted with random key (80-120 characters)
      p = Pubkey.find_by_did(params[:did])
      if !p
        logger.debug2 "did = #{params[:did]}, pubkey = #{params[:pubkey]}"
        p = Pubkey.new
        p.did = params[:did]
      end
      p.pubkey = params[:pubkey]
      p.save! if p.new_record? or p.changed?

      if !params.has_key? :oauths
        # empty login
        logger.debug2 "empty device login without oauth"
        set_session_value :user_ids, []
        set_session_value :tokens, {}
        set_session_value :expires_at, {}
        set_session_value :refresh_tokens, {}
        @json[:friends] = []
        format_response
        return
      end

      oauths = params[:oauths] # array with oauth authorization
      tokens = get_session_value(:tokens)
      expires_at = get_session_value(:expires_at)
      refresh_tokens = get_session_value(:refresh_tokens)
      # logger.secret2 "old tokens = #{tokens}"
      # logger.debug2 "old expires_at = #{expires_at}"
      # logger.secret2 "old refresh_tokens = #{refresh_tokens}"

      # insert oauth received from client local storage into server session
      providers = []
      new_user_ids = []
      oauths.each do |oauth|
        provider = oauth['provider']
        if providers.index(provider)
          @json[:error] = "Dublicate provider #{provider} in oauths array"
          next
        end
        providers << provider
        # logger.secret2 "oauth[#{provider}] = #{oauth[provider]}"
        new_user_ids << oauth["user_id"]
        set_session_array_value(:tokens, oauth["token"], provider)
        set_session_array_value(:expires_at, oauth["expires_at"], provider)
        set_session_array_value(:refresh_tokens, oauth["refresh_token"], provider) if provider == 'google_oauth2'
      end
      set_session_value(:user_ids, new_user_ids)

      # remove any old not authorized providers from server session (missing or failed server logout)
      tokens = get_session_value(:tokens) || {}
      (tokens.keys - providers).each { |provider| delete_session_array_value(:tokens, provider) }
      expires_at = get_session_value(:expires_at) || {}
      (expires_at.keys - providers).each { |provider| delete_session_array_value(:expires_at, provider) }
      refresh_tokens = get_session_value(:refresh_tokens) || {}
      (refresh_tokens.keys - providers).each { |provider| delete_session_array_value(:refresh_tokens, provider) }
      # logger.secret2 "new tokens = #{tokens}"
      # logger.debug2 "new expires_at = #{expires_at}"
      # logger.secret2 "new refresh_tokens = #{refresh_tokens}"
      # update and download friends information

      # check tokens / get updated friends info after new login

      # get login users, check expired providers, refresh google access token
      expired_providers, oauths_response = fetch_users :login
      @json[:expired_tokens] = expired_providers if expired_providers
      if login_user_ids.size < providers.size
        logger.debug2 "One or more expired providers was removed from session user ids array."
        logger.debug2 "login_user_ids = #{login_user_ids.join(', ')}"
        logger.debug2 "old providers  = #{providers.join(', ')}"
        providers = login_user_ids.collect { |user_id| user_id.split('/').last }
        logger.debug2 "new providers  = #{providers.join(', ')}"
      end

      # update friend lists from login providers and return user info to client
      @json[:friends] = []
      providers.each do |provider|
        # get hash with user_id and friend category
        login_user, api_client, friends_hash, new_user, key, options = post_login_update_friends(provider)
        if key
          add_error_key(key, options)
          # check for AppNotAuthorized response in post_login_update_friends. user removed from user_ids.
          is_provider_logged_in = login_user_ids.find { |user_id| user_id.split('/').last == provider }
          if (!is_provider_logged_in)
            logger.debug2 "added provider #{provider} with authorization error to @json[:expired_tokens] response"
            @json[:expired_tokens] = [] unless @json[:expired_tokens]
            @json[:expired_tokens] << provider
          end
          next
        end
        # return json object with relevant user info. see list with friends categories in User.cache_friend_info
        User.cache_friend_info([login_user])
        secret_just_changed = SystemParameter.where("name = 'secret' and updated_at > ?", 3.minutes.ago).first
        if secret_just_changed
          @json[:friends_sha256_update_at] = secret_just_changed.updated_at.to_i
        end
        users = User.where(:user_id => login_user.friends_hash.keys).includes(:server_users, :servers)
        @json[:friends] += users.collect do |user|
          hash = {:user_id => user.id,
                  :uid => user.uid,
                  :provider => user.provider,
                  :user_name => user.user_name,
                  :friend => login_user.friends_hash[user.user_id]}
          hash[:api_profile_picture_url] = user.api_profile_picture_url if user.api_profile_picture_url
          # include sha256 signature for friends on other Gofreerev servers.
          # used as user_id when receiving messages from online users on other Gofreerev servers
          verified_server_users = user.server_users.find_all { |v| v.verified_at }
          if verified_server_users.size > 0
            hash[:sha256] = user.sha256
            hash[:old_sha256] = user.old_sha256 if secret_just_changed
            hash[:remote_sha256] = verified_server_users.collect do |v|
              { :server_id => v.server_id,
                :sha256 => user.calc_sha256(v.server.secret) }
            end
          end
          hash
        end
      end # each provider

      # todo: remove oauth authorization (tokens, expires_at and refresh_tokens) from sessions table
      # should only be used to download friend lists from apis
      # only exception could be google+ where refresh token is used to get a new token once every hour (old gofreerev-fb app)

      # oauths array (returned from post_login_update_friends) is irrelevant in this context
      @json.delete :oauths

      # but return new google+ oauth to client (see fetch_users => check_expired_tokens => google refresh token)
      @json[:oauths] = oauths_response if oauths_response # only google+

      validate_json_response
      format_response
    rescue => e
      logger.debug2 "Exception: #{e.message.to_s} (#{e.class})"
      logger.debug2 "Backtrace: " + e.backtrace.join("\n")
      @json[:interval] = 60000 unless @json[:interval]
      @json[:friends] = [] unless @json[:friends]
      format_response_key '.exception', :error => e.message
    end
  end # login

  # client logout. either global log out for all providers or log out for one login provider
  # remove oauth information from session
  # always an empty json response
  public
  def logout
    begin

      find_or_create_session
      return format_response if @s.new_record? # don't save and delete new session
      provider = params[:provider]
      provider = nil unless valid_omniauth_provider?(provider)
      if provider
        # api provider log out
        if get_session_array_value(:tokens, provider) or
            get_session_array_value(:expires_at, provider) or
            get_session_array_value(:refresh_tokens, provider)
          # oauth information should have been deleted from rails session in login or generic_post_login
          logger.warn2 "Found old not deleted oauth information for #{provider} in rails session"
        end
        delete_session_array_value :tokens, provider
        delete_session_array_value :expires_at, provider
        delete_session_array_value :refresh_tokens, provider
        # remove provider from user_ids array
        user_ids = get_session_value :user_ids
        logger.debug2 "session user_ids before #{provider} logout: " + user_ids.join(', ')
        user_ids = user_ids.delete_if { |user_id| (user_id.split('/').last == provider) }
        set_session_value :user_ids, user_ids
        logger.debug2 "session user_ids after #{provider} logout: " + user_ids.join(', ')
      else
        # local log out - log out for all providers
        @s.destroy unless @s.new_record?
      end

      validate_json_response
      format_response
    rescue => e
      logger.debug2 "Exception: #{e.message.to_s} (#{e.class})"
      logger.debug2 "Backtrace: " + e.backtrace.join("\n")
      format_response_key '.exception', :error => e.message
    end
  end # logout

  # client must ping server once every server ping cycle
  # total server ping interval cycle is adjusted to load average for the last 5 minutes (3.6 for a 4 core cpu / 0.6 for a 1 core cpu)
  # client pings are distributed equally over each server ping cycle with mini adjustments
  def ping
    begin

      # timestamp for ping adjustment. must that all timestamps are with milliseconds and
      # that ping.last_ping_at and ping.next_ping_at are saved in database as decimal(13,3)
      # ( unix timestamp with milliseconds )
      now = Time.now.round(3)

      # abort ping if from a not logged in client
      login_user_ids = get_session_value(:user_ids)
      if login_user_ids.class != Array or login_user_ids.size == 0
        logger.debug2 "login user ids = #{login_user_ids}"
        @json[:error] = 'Not logged in'
        logger.debug2 "@json[:error] = #{@json[:error]}"
        @json[:interval] = 10000
        validate_json_response
        format_response
        return
      end

      # server or client ping
      if login_user_ids.size == 1 and login_user_ids.first =~ /http:\/\//
        server = true
      else
        server = false
      end
      logger.debug2 "server = #{server}"

      if server
        logger.debug2 "validate signature for ping request"
        site_url = login_user_ids.first
        logger.debug2 "site_url = #{site_url}"
        signature = Server.ping_signature(get_session_value(:did), get_session_value(:client_secret), params)
        logger.debug "signature = #{signature}"
        s = Server.find_by_site_url(site_url)
        if error = s.invalid_signature(params[:client_timestamp], signature)
          # server not responding or signature is invalid
          # invalid signature error is returned if client did has been changed without a new login
          # invalid signature error is returned if client secret has been changed without a new login
          @json[:error] = error
          @json[:interval] = 10000
          format_response
          return
        end
        # signature ok
        logger.debug2 "signature is ok"
      end

      # check now >= ping.next_ping_at - force client to wait if server is called to early
      sid = params[:sid]
      pings = Ping.where(:session_id => get_sessionid, :client_userid => get_client_userid, :client_sid => sid).order(:last_ping_at => :desc)
      logger.warn2 "Warning: #{pings.size} pings was found for sid #{sid}" if pings.size > 1
      ping = pings.first
      now = Time.zone.now.round(3)
      if ping and ping.next_ping_at > now
        seconds = ping.next_ping_at - now
        seconds = 1 if seconds < 1 # minimum 1000 milliseconds in json schema.
        @json[:error] = "Ping too early. Please wait #{seconds} seconds."
        @json[:interval] = seconds*1000
        validate_json_response
        format_response
        return
      end

      # all client sessions should ping server once every server ping cycle
      # use server load average the last 5 minutes and increase/decrease server ping cycle
      # MAX_AVG_LOAD = number of cores - minus a constant 0.4. That is 0.6, 1.6, 2.6, 3.6 etc
      s = Sequence.get_server_ping_cycle
      old_server_ping_cycle = s.value
      avg5 = IO.read('/proc/loadavg').split[1].to_f # server average load the last 5 minutes
      if s.updated_at < 30.seconds.ago(now) and (((avg5 < MAX_AVG_LOAD - 0.1) and (s.value >= 3000)) or (avg5 > MAX_AVG_LOAD + 0.1))
        # only adjust server_ping_interval once every 30 seconds
        if avg5 < MAX_AVG_LOAD
          # low server load average - decrease interval between pings
          s.value = s.value - 1000
        else
          # height server load average - increase interval between pings
          s.value = s.value + 1000
        end
        s.save!
      end
      new_server_ping_cycle = s.value

      # find number of active sessions in pings table
      max_server_ping_cycle = [old_server_ping_cycle, new_server_ping_cycle].max + 2000;
      no_active_sessions = Ping.where('last_ping_at >= ? and server_id is null', (max_server_ping_cycle/1000).seconds.ago(now).to_f).count
      no_active_sessions = 1 if no_active_sessions == 0
      avg_ping_interval = new_server_ping_cycle.to_f / 1000 / no_active_sessions

      # keep track of pings. used when adjusting pings for individual sessions
      # Ping - one row for each client browser tab window
      if (rand*100).floor == 0
        # cleanup old sessions
        Ping.where('next_ping_at < ?', 1.hour.ago(now).to_f).delete_all
        ping = Ping.find_by_id(ping.id)
      end
      if !ping
        ping = Ping.new
        ping.session_id = get_sessionid
        ping.client_userid = get_client_userid
        ping.client_sid = sid
        ping.next_ping_at = now
        ping.last_ping_at = (old_server_ping_cycle/1000).seconds.ago(now)
        ping.save!
      end
      # todo: force logout if ping.did != sessions.did?
      ping.did = get_session_value(:did) # from login - online devices
      logger.debug2 "session.did = ping.did = #{ping.did}"
      @json[:error] = 'Did (unique device id) was not found.' unless ping.did

      # check for expired api access tokens + refresh google+ access token
      expired_providers, oauths = check_expired_tokens(:ping, params[:refresh_tokens]) unless server
      @json[:expired_tokens] = expired_providers if expired_providers
      @json[:oauths] = oauths if oauths # only google+

      # copy login user ids from sessions to pings table (user_ids is stored encrypted in sessions but unencrypted in pings)

      if login_user_ids.class == Array and login_user_ids.size > 0
        ping.user_ids = login_user_ids
      else
        logger.warn2 "Not logged in"
        @json[:error] = 'Authorization was not found on server. Please use device log out + log in to refresh server authorization' unless @json[:error]
        login_user_ids = []
      end
      # copy sha256 signature from sessions to pings table (stored encrypted in session but unencrypted in pings)
      ping.sha256 = get_session_value(:sha256)

      # debug info
      logger.debug2 "avg5 = #{avg5}, MAX_AVG_LOAD = #{MAX_AVG_LOAD}"
      logger.debug2 "old server ping interval = #{old_server_ping_cycle}, new server ping interval = #{new_server_ping_cycle}"
      logger.debug2 "no_active_sessions = #{no_active_sessions}, avg_ping_interval = #{avg_ping_interval}"
      # ping: avg5 = 0.88, MAX_AVG_LOAD = 3.6
      # ping: old server ping interval = 2000, new server ping interval = 2000
      # ping: no_active_sessions = 2, avg_ping_interval = 1.0

      # client timestamp - used by client to detect multiple logins with identical uid/user_clientid
      # refresh js users and gifts arrays from localStorage if interval between last client_timestamp and new client timestamp is less that old interval
      # see angularJS UserService.ping function (sync_friends and sync_gifts)
      old_timestamp = get_session_value(:client_timestamp)
      @json[:old_client_timestamp] = old_timestamp if old_timestamp
      new_timestamp = params[:client_timestamp].to_s.to_i
      set_session_value(:client_timestamp, new_timestamp)
      dif = new_timestamp - old_timestamp if new_timestamp and old_timestamp

      # adjust next ping for this session
      # (median of previous and next ping from other sessions - ignore old pings - ignore sessions on other servers)
      previous_ping = Ping.where('id <> ? and last_ping_at < ? and last_ping_at > ? and server_id is null',
                                 ping.id, now.to_f, (old_server_ping_cycle*2/1000).seconds.ago.to_f).order('last_ping_at desc').first
      logger.debug2 "no previous ping was found" unless previous_ping
      previous_ping_interval = now - previous_ping.last_ping_at if previous_ping
      previous_ping_interval = avg_ping_interval unless previous_ping_interval and previous_ping_interval <= 2 * avg_ping_interval

      # find next ping by other sessions - interval to next ping be should close to avg_ping_interval
      next_ping = Ping.where('id <> ? and next_ping_at > ? and server_id is null', ping.id, now.to_f).order('next_ping_at').first
      logger.debug2 "next ping was not found" unless next_ping
      next_ping_interval = next_ping ? next_ping.next_ping_at - now : avg_ping_interval # seconds
      logger.debug2 "next_ping_interval = #{next_ping_interval}"
      logger.debug2 "next_ping.next_ping_at = #{next_ping.next_ping_at} (#{next_ping.next_ping_at.class}), now = #{now} (#{now.class})" if next_ping
      logger.debug2 "avg_ping_interval = #{avg_ping_interval}"
      # ping:  next_ping_interval = -748.469, next_ping.next_ping_at = 2015-03-21 08:10:49 +0100, now = 2015-03-21 07:23:18 UTC, avg_ping_interval = 1.0

      # calc adjustment for this ping. Should be in middle between previous ping and next ping
      avg_ping_interval2 = (previous_ping_interval + next_ping_interval) / 2 # seconds
      adjust_this_ping = -previous_ping_interval + avg_ping_interval2 # seconds
      # next ping
      @json[:interval] = new_server_ping_cycle + (adjust_this_ping*1000).round # milliseconds

      # save ping timestamps. Used in next ping interval calculation
      ping.last_ping_at = now
      ping.next_ping_at = (@json[:interval] / 1000).seconds.since(now)
      ping.save!

      if !@json[:error]

        # ping stat
        logger.debug2 "old client timestamp = #{old_timestamp}, new client timestamp = #{new_timestamp}, dif = #{dif}"
        logger.debug2 "previous_ping_interval = #{previous_ping_interval}, next_ping_interval = #{next_ping_interval}, avg_ping_interval2 = #{avg_ping_interval2}, adjust_this_ping = #{adjust_this_ping}"

        # return list of online devices - ignore current session(s) - only pings from friends are relevant
        # note that pings from other gofreerev servers (server_id is not null) can be older than pings from local users
        # local users must ping server once every server ping cycle ( *2 = allow delayed pings )
        # pings from remote users must max be one minute old. received in online_users server to server message
        # todo: user must accept or reject communication with user on other gofreerev server before replicating gifts info
        # note - timestamps in pings table are decimal(13,3) - always use number timestamps in compare
        pings = Ping.where('(session_id <> ? or client_userid <> ?) and ' +
                           '(server_id is null and last_ping_at > ? or server_id is not null and last_ping_at > ?)',
                           ping.session_id, ping.client_userid, (2*old_server_ping_cycle/1000).seconds.ago.to_f, 1.minute.ago.to_f).
            includes(:server)
        if pings.size > 0
          # found other online devices
          login_users_friends = Friend.where(:user_id_giver => login_user_ids)
                                    .find_all { |f| f.friend_status_code == 'Y' }
                                    .collect { |f| f.user_id_receiver }
          pings = pings.delete_if do |p|
            logger.error2 "login_user_ids not an array" unless login_user_ids.class == Array
            logger.error2 "p.user_ids is not an array. p.id = #{p.id}" unless p.user_ids.class == Array
            logger.error2 "login_users_friends is not an array" unless login_users_friends.class == Array
            if (login_user_ids & p.user_ids).size == 0 and (login_users_friends & p.user_ids).size == 0
              # no shared login users and not friends - remove from list
              true
            elsif !p.did or !p.sha256
              # ignore pings without did/sha256. did er received at login and added to ping after first ping
              logger.error2 "ignoring ping id #{p.id} without pid or sha256."
              true
            else
              # get user ids for other session
              # p.internal_user_ids = User.where(:user_id => p.user_ids).collect { |u| u.id }
              # include a list of mutual friends between this and other session
              # ( devices sync gifts for mutual friends )
              other_session_friends = Friend.where(:user_id_giver => p.user_ids)
                                          .find_all { |f| f.friend_status_code == 'Y' }
                                          .collect { |f| f.user_id_receiver }
              mutual_friends = User.where(:user_id => login_users_friends & other_session_friends)
              p.mutual_friends = mutual_friends.collect { |u| u.id }
              logger.debug2 "login_user_ids = #{login_user_ids.join(', ')}"
              logger.debug2 "login_users_friends = #{login_users_friends.join(', ')}"
              logger.debug2 "p.user_ids = #{p.user_ids.join(', ')}"
              logger.debug2 "p.friends = #{other_session_friends.join(', ')}"
              logger.debug2 "p.mutual_friends = #{p.mutual_friends.join(', ')}"
              # keep in list
              false
            end
          end.collect do |p|
            hash = {:did => p.did,
                    :sha256 => p.sha256,
                    :mutual_friends => p.mutual_friends}
            # only relevant for remote online devices. client must know that it is communication with user on an other server
            # and internal user ids for mutual friends cannot be used in cross Gofreerev server communication
            hash[:server_id] = p.server_id if p.server_id
            hash
          end
        end
        # logger.debug2 "pings.size (after) = #{pings.size}"
        # pings.each { |p| logger.debug2 "p.mutual_friends.size = #{p[:mutual_friends].size}, mutual_friends = #{p[:mutual_friends]}" }
        if pings.size > 0
          @json[:online] = pings
          logger.debug2 "@json[:online] = #{@json[:online]}"
        end

        # return short friends list with sha256 signatures (signatures for users on one or more other gofreerev servers)
        # 1) return short friends list after changed system secret
        # 2) return short friends list after changed sha256 values for login users, friends of login users or friend of friends of login users
        system_secret_changed = false
        users_sha256_values_changed = false
        if !server
          system_secret_at = SystemParameter.secret_at
          system_secret_changed = (system_secret_at != get_session_value(:system_secret_updated_at))
          if !system_secret_changed
            # check if user sha256 signatures have changed since list short friends list download
            last_short_friends_list_at = get_session_value(:last_short_friends_list_at)
            if last_short_friends_list_at
              login_users = User.where(:user_id => login_user_ids)
              login_users.each do |user|
                users_sha256_values_changed = true if user.sha256_updated_at and user.sha256_updated_at >= last_short_friends_list_at
                users_sha256_values_changed = true if user.friend_sha256_updated_at and user.friend_sha256_updated_at >= last_short_friends_list_at
                break if users_sha256_values_changed
              end
            else
              users_sha256_values_changed = true
            end
          end
        end
        if system_secret_changed or users_sha256_values_changed
          time1 = Time.zone.now
          # system secret and/or sha256 signatures for users has changed since last client ping
          # return SHORT friend list (only friends on other gofreerev servers - must have a verified_at row in server_users)

          # todo: should also return this short friend list when secret changes on other gofreerev servers

          login_users = User.where(:user_id => login_user_ids) unless login_users
          # cache friends info. for friends and people in network
          User.cache_friend_info(login_users)
          # find friends on other Gofreerev servers (must have minimum one verified user in server_users table)
          friends_hash = {}
          login_users.each { |login_user| friends_hash.merge!(login_user.friends_hash)}
          set_session_value(:last_short_friends_list_at, Time.zone.now)
          users = User.where(:user_id => friends_hash.keys).includes(:server_users, :servers).where('server_users.verified_at is not null').references(:server_users)
          # return json
          @json[:friends] = users.collect do |user|
            hash = { :user_id => user.id,
                     :uid => user.uid,
                     :provider => user.provider,
                     :user_name => user.user_name,
                     :friend => friends_hash[user.user_id],
                     :sha256 => user.sha256 } # signature on this Gofreerev server
            hash[:old_sha256] = user.old_sha256 if user.old_sha256 # old signature on this gofreerev server
            hash[:api_profile_picture_url] = user.api_profile_picture_url if user.api_profile_picture_url
            # add array with signatures on other Gofreerev servers
            hash[:remote_sha256] = user.server_users.collect do |v|
              { :server_id => v.server_id,
                :sha256 => user.calc_sha256(v.server.secret) }
            end
            hash
          end
          # old sha256 signatures are valid for 3 minutes after update of system secret
          set_session_value :system_secret_updated_at, system_secret_at if system_secret_changed
          @json[:friends_sha256_update_at] = system_secret_at.to_i
          time2 = Time.zone.now
          elapsed = (time2-time1)
          logger.debug2 "elapsed = #{elapsed}"
        end # short friends list

        # process additional ping operations (new gifts, public keys, sync gifts between clients etc)

        # 1) public keys. used in client to client communication (public/private key encryption) for short messages (symmetric password exchange)
        pubkeys_response = Ping.pubkeys params[:pubkeys] unless server
        @json[:pubkeys] = pubkeys_response if pubkeys_response

        # 2) new gifts. create gifts (gid and sha256 signature) and return created_at_server timestamps to client
        # sha256 signature should ensure that gift information is not unauthorized updated on client
        # logger.debug2 "new_gifts = #{params[:new_gifts]} (#{params[:new_gifts].class})"
        new_gifts_response = Gift.new_gifts(params[:new_gifts], login_user_ids) unless server
        @json[:new_gifts] = new_gifts_response if new_gifts_response

        # 3) new comments. create comments (cid and sha256 signature) and return created_at_server timestamps to client
        # sha256 signature should ensure that comment information is not unauthorized updated on client
        # logger.debug2 "new_comments = #{params[:new_comments]} (#{params[:new_comments].class})"
        new_comments_response = Comment.new_comments(params[:new_comments], login_user_ids) unless server
        @json[:new_comments] = new_comments_response if new_comments_response

        # 4) todo: add accept_gifts request and response

        # 5) delete gifts. mark gifts as deleted with a server side sha256_deleted signature. Returns deleted_at_server = true or an error message for each gift
        # signatures (sha256 and sha256_deleted) should ensure that gift information is not unauthorized updated on client
        logger.debug2 "delete_gifts = #{params[:delete_gifts]} (#{params[:delete_gifts].class})" unless server
        delete_gifts_response = Gift.delete_gifts(params[:delete_gifts], login_user_ids) unless server
        @json[:delete_gifts] = delete_gifts_response if delete_gifts_response

        # 6) new servers. Gofreerev.rails['SERVERS'] hash with known Gofreerev servers are downloaded at page start in /assets/ruby_to.js
        # new_servers request is used when receiving new gifts from unknown Gofreerev servers (first contact)
        logger.debug2 "new_servers = #{params[:new_servers]} (#{params[:new_servers].class})" unless server
        new_servers_response = Server.new_servers(params[:new_servers]) unless server
        @json[:new_servers] = new_servers_response if new_servers_response

        # 7) verify gifts. check server side signature for existing gifts. used when receiving gifts from other devices. Return created_at_server timestamps (or null) to client
        # login user must be friend with giver or receiver of gift
        # client must reject gift if created_at_server timestamp is null or does not match
        # sha256 signature should ensure that gift information is not unauthorized updated on client
        logger.debug2 "verify_gifts = #{params[:verify_gifts]} (#{params[:verify_gifts].class})"
        verify_gifts_response = Gift.verify_gifts(params[:verify_gifts], login_user_ids, ping.client_sid, ping.sha256) unless server
        @json[:verify_gifts] = verify_gifts_response if verify_gifts_response

        # 8) client to client messages or server or server messages
        # client to client:
        #   input: buffered messages (JS array) from actual client to other clients - saved in messages table
        #   output: messages to actual client from other clients - from messages table - saved in a JS array
        # server to server:
        #   input: messages from client Gofreerev server - saved in messages table
        #   process any messages to this Gofreerev server
        #   output: messages to client Gofreerev server - from messages table
        if params[:messages].class == Array
          # check: server to server or client to client communication
          params[:messages].each do |message|
            if message['server'] != server
              if server
                @json[:error] = "invalid message received from server. server must be true in server to server communication"
              else
                @json[:error] = "Invalid message received from client. server must be false in client to client communication"
              end
              break
            end
          end
        end
        if !@json[:error]
          error, messages_response = Message.messages ping.did, ping.sha256, params[:messages]
          @json[:error] = error if error
          @json[:messages] = messages_response if messages_response
        end
        logger.debug2 "@json = #{@json}"
      end

      validate_json_response
      format_response
    rescue => e
      logger.debug2 "Exception: #{e.message.to_s} (#{e.class})"
      logger.debug2 "Backtrace: " + e.backtrace.join("\n")
      format_response_key '.exception', :error => e.message
    end
  end # ping

end # UtilController
