# encoding: utf-8
require 'google/api_client'
require 'money/bank/google_currency'

#noinspection RubyResolve
class ApplicationController < ActionController::Base

  before_action :setup_json_and_errors
  before_action :request_start_time

  # protect cookie information on public web servers
  force_ssl if: :ssl_configured?

  # Prevent CSRF attacks by raising an exception.
  # For APIs, you may want to use :null_session instead.
  protect_from_forgery with: :exception
  before_action :request_url_for_header
  before_action :get_client_userid
  before_action :fetch_users
  before_action :set_locale_from_params
  before_action :get_timezone

  # generic session setter/getter
  # some data are stored in different sections for each client_userid
  # some data are stored encrypted in database
  # see /config/initializers/action_controller_extensions.rb
  helper_method :get_session_value
  helper_method :get_sessionid

  # render to language specific pages.
  # viewname=create, session[:language] = da => call create-da.html.erb if the page exists
  private
  def render_with_language(viewname)
    language = set_session_value(:language)
    # logger.debug2  "language = #{language}"
    if !language or language == BASE_LANGUAGE
      # logger.debug2 "Render #{viewname}"
      render :action => viewname
      return
    end
    viewname2 = "#{viewname}_#{language}"
    filename = Rails.root.join('app', 'views', controller_name, "#{viewname2}.html.erb").to_s
    # logger.debug2  "filename = #{filename}"
    viewname2 = viewname unless File.exists?(filename)
    # logger.debug2 "Render #{viewname2}"
    render :action => viewname2
  end # render_with_language

  private
  def debug_session (msg)
    [:oauth, :language, :country, :state, :access_token, :user_id].each do |name|
      logger.debug2  "#{msg}: session[:#{name}] = #{session[name]}"
    end
  end

  private
  # used in page header for currency change
  def request_url_for_header
    @request_fullpath = request.fullpath
  end

  private
  # get start time for request for show-more-rows check
  def request_start_time
    @request_start_time = Time.new.seconds_since_midnight
  end

  private
  def add_dummy_user
    @users << User.find_or_create_dummy_user('gofreerev') if @users.size == 0
  end

  # split session storage in a section for each client userid
  # done to bring rails session storage more in sync with JS sessionStorage
  # not 100% bulletproof as there can be simultaneous transactions in two different browser tabs
  private
  def get_client_userid
    if params[:client_userid].to_s =~ /^[1-9][0-9]*$/
      set_session_value(:client_userid, params[:client_userid].to_s.to_i)
    elsif env['omniauth.params'] and (env['omniauth.params']["client_userid"].to_s =~ /^[1-9][0-9]*$/)
      set_session_value(:client_userid, env['omniauth.params']["client_userid"].to_s.to_i)
    else
      logger.debug2 'client_userid was not found'
    end
    logger.debug2 "session[:client_userid] = #{get_session_value(:client_userid)}"
    get_session_value(:client_userid)
  end

  # check expired access tokens
  # use google refresh token if possible to get a new google access token (refresh_tokens parameter)
  # called from fetch_users and util/ping
  # returns a list with expired providers
  # context is :ping if called from util/ping or :login if called from util/login
  private
  def check_expired_tokens (context, refresh_tokens=nil)
    refresh_tokens=[] unless refresh_tokens
    logger.secret2 "context = #{context}, refresh_tokens = #{refresh_tokens}"
    if context == :login
      # called from util/login and fetch_users - get refresh_tokens (google+ only) from sessions table
      refresh_tokens_hash = get_session_value(:refresh_tokens) || {}
      refresh_tokens = refresh_tokens_hash.collect { |key, value| { "provider" => key.to_s, "refresh_token" => value} }
      logger.secret2 "context=login. refresh_tokens from session = #{refresh_tokens}"
    end

    oauth = nil # only used for google+

    if context == :ping and refresh_tokens.size > 0
      # received refresh token for expired google+ token on client
      # return dummy google+ oauth without refresh token if not logged in with google+ on server
      # as a kind of log out signal to client
      refresh_token_not_logged_in = false
      refresh_tokens.each do |hash|
        refresh_token_not_logged_in = true unless login_user_ids.find { |user_id| user_id.split('/').last == hash['provider'] }
      end
      logger.debug2 'refresh providers = ' + refresh_tokens.collect { |hash| hash['provider'] }.join(', ')
      logger.debug2 "login_user_ids    = #{login_user_ids.join(', ')}"
      if refresh_token_not_logged_in
        # return dummy google+ oauth - force client log off
        logger.warn2 "received refresh tokens from not logged user (google+ only)"
        oauth = [{:provider => 'google_oauth2', :user_id => 'unknown_user/google_oauth2', :token => 'expired', :expires_at => 1.day.ago.to_i}]
      end
    end

    # todo: expires_at check. how to handle uic time dif between server and client. not expired on client + expired on server!
    client_timestamp = (params[:client_timestamp].to_i / 1000).floor
    server_timestamp = Time.zone.now.to_i
    timestamp_dif = server_timestamp - client_timestamp
    if timestamp_dif.abs < 120
      # little dif between server time and client time - use client timestamp when checking for expired access tokens
      now = client_timestamp
    else
      # big dif between server time and client time - use server timestamp when checking for expired access tokens
      now = server_timestamp
    end
    logger.debug2 "client_timestamp = #{client_timestamp}, server_timestamp = #{server_timestamp}, timestamp_dif = #{timestamp_dif}, now = #{now}"

    # remove logged in users with expired access token
    expired_tokens = []
    login_user_ids.each do |user_id|
      uid, provider = user_id.split('/')
      next if uid == 'gofreerev' # dummy user for not connected session

      expires_at = get_session_array_value(:expires_at, provider)
      # logger.debug2 "expires_at[#{provider}] = #{expires_at}"

      # refresh google+ access token once every hour
      # http://stackoverflow.com/questions/12572723/rails-google-client-api-unable-to-exchange-a-refresh-token-for-access-token
      if expires_at and (expires_at <= now) and (provider == 'google_oauth2')
        logger.debug2 "refreshing expired google+ access token. expires_at[#{provider}] = #{expires_at}"
        # get refresh token from ping or login request
        refresh_token = nil
        refresh_tokens.each { |hash| refresh_token = hash["refresh_token"] if hash["provider"] == provider }
        logger.secret2 "refresh_token = #{refresh_token}"
        if refresh_token
          api_client = Google::APIClient.new(
              :application_name => 'Gofreerev',
              :application_version => '0.1'
          )
          api_client.authorization.client_id = API_ID[provider]
          api_client.authorization.client_secret = API_SECRET[provider]
          api_client.authorization.grant_type = 'refresh_token'
          api_client.authorization.refresh_token = refresh_token
          logger.secret2 "refresh_token = #{refresh_token}"
          begin
            res1 = api_client.authorization.fetch_access_token!
          rescue Signet::AuthorizationError => e
            # Signet::AuthorizationError (Authorization failed. Server message: { "error" : "invalid_grant" })
            logger.debug2 "Google+: could not use refresh_token to get a new access_token"
            logger.debug2 "error: #{e.message}"
            add_error_key 'auth.destroy.refresh_token_error1', :apiname => provider_downcase(provider)
            res1 = nil
            expires_at = nil
            delete_session_array_value(:refresh_tokens, provider)
            # return dummy google+ oauth without refresh token
            logger.debug2 "return dummy google+ oauth without refresh token"
            oauth = [{:provider => provider, :user_id => user_id, :token => 'expired', :expires_at => 1.day.ago.to_i}]
          rescue => e
            # other errors.
            logger.debug2 "Google+: could not use refresh_token to get a new access_token"
            logger.debug2 "error: #{e.message}"
            add_error_key 'auth.destroy.refresh_token_error2', :apiname => provider_downcase(provider), :error => e.message
            res1 = nil
            expires_at = nil
            delete_session_array_value(:refresh_tokens, provider)
            # return dummy google+ oauth without refresh token
            logger.debug2 "return dummy google+ oauth without refresh token"
            oauth = [{:provider => provider, :user_id => user_id, :token => 'expired', :expires_at => 1.day.ago.to_i}]
          end
          if res1
            logger.secret2 "res1 = #{res1}"
            res2 = api_client.authorization
            logger.secret2 "res2 = #{res2}"
            logger.secret2 "res2.access_token = #{res2.access_token}"
            logger.debug2 "res2.expires_at = #{res2.expires_at}"
            expires_at = res2.expires_at.to_i
            set_session_array_value(:expires_at, expires_at, provider)
            logger.debug2 'google+ access token was refreshed'
            oauth = [{
                :provider => provider,
                :user_id => user_id,
                :token => res2.access_token,
                :expires_at => expires_at,
                :refresh_token => refresh_token
            }]
            if context == :login
              # google+ oauth was refreshed doing login process. oauth info is temporary saved in sessions table and will be used for friend list download
              # the information in sessions table will be deleted after friend list download
              logger.debug2 "context is login. copy new google+ oauth to sessions table. to be used in following friend list download"
              set_session_array_value(:tokens, oauth[0][:token], provider)
              set_session_array_value(:expires_at, oauth[0][:expires_at], provider)
              set_session_array_value(:refresh_tokens, oauth[0][:refresh_token], provider)
            end
          end
        else
          logger.warn2 'no refresh token was found for google+. unable to refresh google+ access token'
        end
      end
      if !expires_at or (expires_at < Time.now.to_i)
        # found login with missing or expired access token
        # this message is also used after single sign-on with one or more expired access tokens
        if provider == 'google_oauth2' and context == :ping and !refresh_token
          # google+ is expired on server but client did not send google+ refresh token in last ping.
          # return google+ as expired login provider but keep server login
          logger.warn2 "google+ is expired on server. Requests google+ refresh token in next ping request from client"
        else
          logger.debug2 "found login user with missing or expired access token. provider = #{provider}, expires_at = #{expires_at}"
          add_error_key 'auth.destroy.expired_access_token',
                        :provider => provider, :apiname => provider_downcase(provider), :appname => APP_NAME
          delete_session_array_value(:user_ids, user_id)
          delete_session_array_value(:tokens, provider)
          delete_session_array_value(:expires_at, provider)
        end
        expired_tokens << provider
      end
    end # each user_id
    expired_tokens = expired_tokens.size == 0 ? nil : expired_tokens

    [expired_tokens, oauth]

  end # check_expired_tokens


  # fetch user info. initialize @users array. One user with each login API. Used in page heading, security etc
  private
  def fetch_users (context=nil)
    logger.debug2 "start"
    # language support
    # logger.debug2  "start. sessionid = #{request.session_options[:id]}"
    # logger.debug2  "I18n.locale = #{I18n.locale}"

    # cookie note in page header for the first 30 seconds for a new session
    # eu cookie law - also called Directive on Privacy and Electronic Communications
    # accepted cookie is a permanent cookie set if user accepts cookies
    if SHOW_COOKIE_NOTE and SHOW_COOKIE_NOTE > 0 and cookies[:cookies] != 'accepted'
      set_session_value(:created, Time.new) unless get_session_value(:created).class == Time
      cookie_note = SHOW_COOKIE_NOTE - (Time.new - get_session_value(:created))
      @cookie_note = cookie_note if cookie_note >= 0.5
    end

    # initialize empty session variables for new session
    set_session_value(:user_ids, []) unless get_session_value(:user_ids) # array with user_ids
    set_session_value(:tokens, {}) unless get_session_value(:tokens) # hash with oauth access token index by provider
    set_session_value(:expires_at, {}) unless get_session_value(:expires_at) # hash with unix expire timestamp for oauth access token index by provider
    set_session_value(:refresh_tokens, {}) unless get_session_value(:refresh_tokens) # hash with "refresh token" (google+ only ) index by provider

    # check for expired api access tokens
    expired_providers, oauths = check_expired_tokens context

    # fetch user(s)
    if login_user_ids.length > 0
      @users = User.where("user_id in (?)", login_user_ids)
    else
      @users = []
    end

    # check for deleted users - user(s) deleted in an other session/browser
    if login_user_ids.length != @users.length
      login_user_ids_tmp = @users.collect { |user| user.user_id }
      tokens = get_session_value(:tokens) || {}
      new_tokens = {}
      @users.each { |user| new_tokens[user.provider] = tokens[user.provider] }
      set_session_value(:user_ids, login_user_ids_tmp)
      set_session_value(:tokens, new_tokens)
    end

    # friends information is used many different places
    # cache friends information once and for all in @users array (user.friends_hash)
    # friends categories:
    # 1) logged in user
    # 2) mutual friends         - show detailed info
    # 3) follows (F)            - show few info
    # 4) stalked by (S)         - show few info
    # 5) deselected api friends - show few info
    # 6) friends of friends     - show few info
    # 7) friends proposals      - not clickable user div
    # 8) others                 - not clickable user div - for example comments from other login providers
    User.cache_friend_info(@users)

    # add sort_by_provider method instance method to @users array.
    # used in a few views (invite users, auth/index)
    # todo: should use provider_downcase method, but application controller methods are not available in Array class
    # todo: move provider_downcase to constant?
    @users.define_singleton_method :sort_by_provider do
      self.sort_by { |u| API_CAMELIZE_NAME[u.provider] || u.provider }
    end

    # add remove_deleted_users
    @users.define_singleton_method :remove_deleted_users do
      self.delete_if { |u| u.deleted_at }
    end
    user = @users.first

    # debugging
    if @users.length == 0
      logger.debug2 "found none logged in users"
    else
      @users.each do |user|
        logger.debug2 "user_id = #{user.user_id}, user_name = #{user.user_name}, currency = #{user.currency}"
      end
    end

    # check currencies. all logged in users must use same currency
    currencies = @users.collect { |user| user.currency }.uniq
    logger.warn2 "more when one currency found for logged in users: #{}" if currencies.length > 1

    # add some instance variables
    if user
      begin
        Money.default_currency = Money::Currency.new(user.currency)
      rescue Money::Currency::UnknownCurrency => e
        # todo: this is only a workaround - fix missing or invalid currency at login time
        logger.warn2 "#{e.class}: #{e.message}"
        logger.warn2 "User #{user.debug_info} with invalid currency #{user.currency}"
        user.currency = Money.default_currency = BASE_CURRENCY
        user.save!
      end
      # todo: set decimal mark and thousands separator from language - not from currency
      @user_currency_separator = Money::Currency.table[user.currency.downcase.to_sym][:decimal_mark]
      @user_currency_delimiter = Money::Currency.table[user.currency.downcase.to_sym][:thousands_separator]
    end
    logger.debug2 "@user_currency_separator = #{@user_currency_separator}, @user_currency_delimiter = #{@user_currency_delimiter}"

    # add dummy user for page header
    add_dummy_user if @users.size == 0

    # get new exchange rates? add to task queue
    add_task 'fetch_exchange_rates', 10 if logged_in? and ExchangeRate.fetch_exchange_rates?

    # only used in util/login
    return [expired_providers, oauths]

  end # fetch_user


  # 1. priority is locale from url - 2. priority is locale from session - 3. priority is default locale (en)
  # locale is also saved in session for language support in api provider callbacks
  private
  def set_locale_from_params
    return if request.path_parameters[:format] == 'json' # skip for angularJS json requests
    logger.debug2 "start"
    params[:locale] = nil if params.has_key?(:locale) and xhr?
    language = valid_locale(params[:locale]) || get_session_value(:language)
    set_session_value(:language, language)
    I18n.locale = valid_locale(params[:locale]) || valid_locale(language) || valid_locale(I18n.default_locale) || 'en'
    # logger.debug2  "I18n.locale = #{I18n.locale}. params[:locale] = #{params[:locale]}, session[:language] = #{session[:language]}, "

    # save language for batch notifications - for example friends find with friends suggestions
    return if xhr?
    return unless logged_in?
    @users.each do |user|
      user.update_attribute :language, I18n.locale unless user.language == I18n.locale
    end
  end # set_locale_from_params

  private
  def default_url_options(options={})
    # logger.debug2  "options: #{options}."
    # logger.debug2  "I18n.locale = #{I18n.locale} (#{I18n.locale.class})"
    # logger.debug2  "I18n.default_locale = #{I18n.default_locale} (#{I18n.default_locale.class})"
    # logger.debug2  "controller = #{params[:controller]}"
    { locale: I18n.locale }
  end

  # check get-more-rows ajax request for errors before fetching users or gifts
  # called in start of gifts/index, users/index and users/show and before calling get_next_set_of_rows
  # last_low_id must be correct - max one get-more-rows ajax request every GET_MORE_ROWS_INTERVAL seconds
  # todo: remove
  private
  def get_next_set_of_rows_error?(last_row_id)
    return false
  end # get_next_set_of_rows_error?

  # used in ajax expanding pages (gifts/index, users/index and users/show pages)
  private
  def get_next_set_of_rows (rows, last_row_id, no_rows=nil)
    logger.debug2  "last_row_id (input) = #{last_row_id}"
    ajax_request = (last_row_id != nil)
    no_rows = ajax_request ? 10 : 1 unless no_rows # default - return 1 row in first http request - return 10 rows in ajax requests
    total_no_rows = rows.size
    if ajax_request
      # ajax request
      # check if last_row_id is valid - row could have been deleted between two requests
      # logger.debug2  "ajax request - check if last_row_id still is valid"
      from = rows.index { |u| u.last_row_id == last_row_id }
      if !from
        logger.debug2  "invalid last_row_id - or row is no longer in rows - ignore error and return first 10 rows"
        last_row_id = nil
      end
      last_row_id = nil unless from # invalid last_row_id - deleted row or changed permissions - ignore error and return first 10 rows
    end
    rows = rows[from+1..-1] if from # valid ajax request - ignore first from rows - already in client page
    if rows.size > no_rows
      rows = rows.first(no_rows)
      last_row_id = rows.last.last_row_id # return next 10 rows in next ajax request
    else
      last_row_id = nil # last row - no more ajax requests
    end
    logger.debug2  "returning next #{rows.size} of #{total_no_rows} rows . last_row_id = #{last_row_id}"
    # keep last_row_id and timestamp - checked in get_next_set_of_rows_error? before calling this method
    set_last_row_id(last_row_id) # control - is checked in next ajax request
    logger.debug2  "last_row_id (output) = #{last_row_id}"
    [ rows, last_row_id]
  end # get_next_set_of_rows

  # provider helpers

  # list of valid providers from /config/initializers/omniauth.rb
  # that is social networks with API, friend list and a wall
  private
  def valid_omniauth_provider? (provider)
    User.valid_omniauth_provider?(provider)
  end
  helper_method 'valid_omniauth_provider?'

  # provider name used in text (error messages, mouse over titles etc) - normal lowercase
  private
  def provider_downcase (provider)
    return t 'shared.providers.blank' if provider.to_s == '' # generic provider text
    return provider if !valid_omniauth_provider?(provider) # unknown provider or already translated
    API_DOWNCASE_NAME[provider] || provider
  end
  helper_method :provider_downcase

  # formal provider name - used in views
  private
  def provider_camelize (provider)
    return t 'shared.providers.blank' if provider.to_s == '' # generic provider text
    return provider if !valid_omniauth_provider?(provider) # unknown provider or already translated
    API_CAMELIZE_NAME[provider] || provider
  end
  helper_method :provider_camelize

  # redirect urls used in views and controllers
  private
  def provider_url (provider)
    return nil if !valid_omniauth_provider?(provider) # unknown provider or already translated
    API_URL[provider]
  end
  helper_method :provider_url




  private
  def add_task (task, priority=5)
    Task.add_task(get_sessionid, task, priority)
  end

  private
  def debug_ajax?
    DEBUG_AJAX
  end
  helper_method "debug_ajax?"

  # is FB amount logged in users?
  # only show email field in share accounts dialog form if no FB account
  private
  def fb_user?
    return false unless logged_in?
    login_user_ids.find { |user_id| user_id.split('/').last == 'facebook' } ? true : false
  end
  helper_method "fb_user?"

  # helper methods to return ajax (error) messages
  private
  def format_ajax_response
    respond_to do |format|
      # fix for ie8/ie9 error:
      #  "to help protect your security internet explorer blocked this site from downloading files to your computer"
      # (x.js.erb response is being downloaded instead of being executed)
      # only a problem in remote forms (new gifts and new comments)
      format.js { render :content_type => "text/plain" }
      # format.js {  }
    end
    nil
  end

  private
  def logged_in?
    logger.debug2 "login_user_ids.class = #{login_user_ids.class}"
    return false unless login_user_ids.class == Array
    return false if login_user_ids.size == 0
    return false if login_user_ids.first.split('/').first == 'gofreerev' # login with dummy user
    true
  end
  helper_method "logged_in?"

  # note that login_required? check filter is skipped in many ajax requests
  # ( customized error messages for not logged in users )
  private
  def login_required
    return true if logged_in?
    if !xhr?
      save_flash_key 'shared.not_logged_in.redirect_flash'
      redirect_to :controller => :auth, :action => :index
      return
    end
    # ajax request and not logged in.
    table = nil
    tasks_errors = 'tasks_errors'
    controller = params[:controller]
    action = params[:action]
    logger.debug2 "controller = #{controller}, action = #{action}"
    # todo: add case with controller and actions to be handled here
    #case controller
    #  when 'gifts'
    #    case action
    #      when  'create'
    #        table = tasks_errors
    #    end # case action gifts controller
    #end # case controller
    key = 'shared.not_logged_in.ajax_' + (request.get? ? 'get' : 'post')
    if table
      add_error_key key, :id => table
    else
      logger.error2 "not logged in ajax response not implemented for controller = #{params[:controller]}, action = #{params[:action]}"
      save_flash_key key
      redirect_to :controller => :auth, :action => :index
      # JS error: ....: "SyntaxError: syntax error. check server log for more information"
    end
  end # login_required

  private
  def login (options)
    # get params
    provider = options[:provider]
    token = options[:token]
    expires_at = options[:expires_at]
    uid = options[:uid]
    name = options[:name]
    image = options[:image]
    country = options[:country]
    language = options[:language]
    profile_url = options[:profile_url]
    permissions = options[:permissions]
    # create/update user from information received from login provider
    # returns user (ok) or an array with translate key and options for error message
    user = User.find_or_create_user :provider => provider,
                                    :token => token,
                                    :expires_at => expires_at,
                                    :uid => uid,
                                    :name => name,
                                    :image => image,
                                    :country => country,
                                    :language => language,
                                    :profile_url => profile_url,
                                    :permissions => permissions
    return user unless user.class == User # error: key + options
    # user login ok
    first_login = !logged_in?
    # save user id, access token and expires_at - multiple logins allowed - one for each login provider

    # todo: 1) must split session storage in one section for each client_userid / each local browser account
    # todo: 2) cookie limit 4kb. Should save few data in session cookie and bigger data encrypted in session table

    login_user_ids = login_user_ids().clone
    login_user_ids.delete_if { |user_id2| user_id2.split('/').last == provider }
    login_user_ids << user.user_id
    tokens = get_session_value(:tokens) || {}
    tokens[provider] = token
    expires = get_session_value(:expires_at) || {}
    expires[provider] = expires_at.to_i # positive sign for current login user
    logger.debug2 "set_session_value: user_ids = #{login_user_ids.join(', ')}"
    set_session_value(:user_ids, login_user_ids)
    set_session_value(:tokens, tokens)
    set_session_value(:expires_at, expires)
    logger.secret2 "expires_at = #{expires}"
    # refresh token is only used for google+
    set_session_array_value(:refresh_tokens, options[:refresh_token], provider)  if options[:refresh_token] # only google+
    logger.debug2 "session[:refresh_tokens] = #{get_session_value(:refresh_tokens)}"
    # fix invalid or missing language for translate
    set_session_value(:language, valid_locale(language)) unless valid_locale(get_session_value(:language))
    set_locale_from_params

    return nil if user.deleted_at # no post login tasks for delete marked users

    # Clear any old auth information in db
    user.access_token = nil
    user.access_token_expires = nil
    user.refresh_token = nil
    user.save!

    # check currency after new login - keep current currency
    @users = User.where('user_id in (?)', login_user_ids)
    currencies = @users.collect { |user2| user2.currency }.uniq
    if currencies.length > 1
      old_user = @users.find { |user2| user2.user_id != user.user_id }
      user.currency = currency = old_user.currency
      user.save!
    else
      currency = currencies.first
    end

    # flash with login message. Login messages:
    # a) normal login without any special messages
    # b) first login for new user,
    # e) facebook: special read-stream and status-update messages
    # f) flickr: special write priv. message
    # g) linkedin: special rw_nus priv. message
    # a)-d) is handled here. e)-g) is handled in facebook, flickr and linkedin controllers
    # default message - login ok
    flash_key, flash_options = '.login_ok', user.app_and_apiname_hash # a) normal login without any special messages
    if user.friends.size == 1
      # new user login
      flash_key, flash_options = '.login_ok_new_user', user.app_and_apiname_hash # a) normal login without any special messages
    end
    save_flash_key flash_key, flash_options

    # schedule post login ajax tasks
    # 1) profile image for currency user
    if image.to_s != ""
      if image =~ /^http/ and !image.index("''") and !image.index('"')
        # todo: other characters to filter? for example characters with a special os function
        # facebook: profile picture from login is not used - profile picture from koala request in post login task is used
        # see util_controller.post_login_update_friends / facebook api client gofreerev_get_user instance method
        add_task "User.update_profile_image('#{user.user_id}', '#{image}')", 5 unless provider == 'facebook'
      else
        logger.debug2 "invalid picture received from #{provider}. image = #{image}"
      end
    end
    # 2) post_login for provider
    post_login_task_provider = "post_login_#{provider}" # private method in UtilController
    if UtilController.new.private_methods.index(post_login_task_provider.to_sym)
      add_task post_login_task_provider, 5
    else
      add_task "generic_post_login('#{provider}')", 5
      logger.debug2 "no post_login_#{provider} method was found in util controller - using generic post login task"
    end

    # 4) refresh user(s) balance
    today = Date.parse(Sequence.get_last_exchange_rate_date)
    if !user.balance_at or user.balance_at != today
      add_task "recalculate_user_balance(#{user.id})", 5
    end
    # 5) send friends_find notifications once a week for active users.
    # first login is used as a trigger for this batch job
    add_task 'find_friends_batch', 5 if first_login
    # ok
    nil
  end # login


  # todo: logout in application controller is overwritten by logout in util controller. temporary using session_logout in util controller
  #
  def logout (provider=nil)
    if !provider
      session.delete(:user_ids)
      session.delete(:tokens)
      session.delete(:expires_at)
      @users = []
      add_dummy_user
      return
    end
    user_ids_tmp = get_session_value(:user_ids)
    user_ids_tmp = user_ids_tmp.delete_if { |user_id| user_id.split('/').last == provider}
    set_session_value(:user_ids, user_ids_tmp)
    delete_session_array_value(:tokens, provider)
    delete_session_array_value(:expires_at, provider)
    @users.delete_if { |user| user.provider == provider }
    add_dummy_user if @users.size == 0
  end # logout

  def session_logout (provider=nil)
    if !provider
      session.delete(:user_ids)
      session.delete(:tokens)
      session.delete(:expires_at)
      @users = []
      add_dummy_user
      return
    end
    user_ids_tmp = get_session_value(:user_ids)
    user_ids_tmp = user_ids_tmp.delete_if { |user_id| user_id.split('/').last == provider}
    set_session_value(:user_ids, user_ids_tmp)
    delete_session_array_value(:tokens, provider)
    delete_session_array_value(:expires_at, provider)
    @users.delete_if { |user| user.provider == provider }
    add_dummy_user if @users.size == 0
  end # session_logout



  # protection from Cross-site Request Forgery
  # state is set before calling login provider
  # state is checked when returning from login provider
  # used in LinkedInController
  # todo: ajax set state in links (request publish_actions and read_stream) so
  #       that old pages (used has used back bottom in browser) still is working
  # three methods that saves state in session cookie store
  private
  def set_state_cookie_store (context)
    state = get_session_value(:state).to_s
    state = String.generate_random_string(30) unless state.length == 30
    set_session_value(:state, state)
    logger.debug2 "session[:session_id] = #{get_sessionid}, session[:state] = #{get_session_value(:state)}"
    "#{state}-#{context}"
  end
  def clear_state_cookie_store
    logger.debug2 "clear state"
    session.delete(:state)
    get_linkedin_api_client() if logged_in?
  end
  def invalid_state_cookie_store?
    logger.debug2 "session[:session_id] = #{get_sessionid}, session[:state] = #{get_session_value(:state)}, params[:state] = #{params[:state]}"
    state = params[:state].to_s
    return true unless get_session_value(:state).to_s == state.first(30)
    false
  end


  # special store for state when login starts from facebook (facebook/create => facebok/autologin => .. => facebook/index )
  # the problem is that for example IE10 does not update session cookie before redirection to facebook for login
  # save state in tasks table with sessionid and a simple device fingerprint (user agent + ip adr)
  private
  def set_state_tasks_store (context)
    task_name = 'facebook_state'
    t = Task.find_by_session_id_and_task(get_sessionid, task_name)
    t.destroy if t
    t = Task.new
    t.session_id = get_sessionid
    t.task = task_name
    t.priority = 5
    t.ajax = 'N'
    state = String.generate_random_string(30)
    t.task_data = { :user_agent => request.user_agent, :remote_ip => request.remote_ip, :state => state }.to_yaml
    t.save!
    "#{state}-#{context}"
  end # set_state_tasks_store
  def invalid_state_tasks_store?
    task_name = 'facebook_state'
    t = Task.find_by_session_id_and_task(get_sessionid, task_name)
    t.destroy if t
    return true unless t
    return true if t.created_at < 1.minute.ago
    task_data = YAML::load(t.task_data)
    logger.debug2 "task_data = #{task_data}"
    logger.debug2 "params[:state] = #{params[:state]}, user agent = #{request.user_agent}, remote_ip = #{request.remote_ip}"
    return true unless task_data[:state].to_s.first(30) == params[:state].to_s.first(30)
    return true unless task_data[:user_agent].to_s == request.user_agent.to_s
    return true unless task_data[:remote_ip].to_s == request.remote_ip.to_s
    false
  end # invalid_state_tasks_store?



  # save/get flickr oauth client
  # save is called after gifts/create and todo: exception from flickr - post in flickr wall not allowed
  # get is called from flickr/index when user returns from flickr after allowing write access to flickr wall
  private
  def save_flickr_api_client (client, token)
    logger.debug2 "start #{Time.now}"
    task_name = 'flickr_write'
    t = Task.find_by_session_id_and_task(get_sessionid, task_name)
    t.destroy if t
    t = Task.new
    t.session_id = get_sessionid
    t.task = task_name
    t.priority = 5
    t.ajax = 'N'
    t.task_data = [client, token].to_yaml
    t.save!
    logger.debug2 "end #{Time.now}"
  end # save_flickr_client
  def get_flickr_api_client
    logger.debug2 "start #{Time.now}"
    task_name = 'flickr_write'
    t = Task.where("session_id = ? and task = ? and created_at > ?", get_sessionid, task_name, 10.minutes.ago).first
    return nil unless t
    client = YAML::load(t.task_data)
    t.destroy
    logger.debug2 "end #{Time.now}"
    client
  end # get_flickr_client


  # save/get linkedin oauth client
  # save is called after gifts/create and LinkedIn::Errors::AccessDeniedError from linkedin - post in linkedin wall not allowed
  # get is called from linkedin/index when user returns from linkedin after allowing write access to linkedin wall
  private
  def save_linkedin_api_client (client)
    task_name = 'linkedin_rw_nus'
    t = Task.find_by_session_id_and_task(get_sessionid, task_name)
    t.destroy if t
    t = Task.new
    t.session_id = get_sessionid
    t.task = task_name
    t.priority = 5
    t.ajax = 'N'
    t.task_data = client.to_yaml
    t.save!
  end # save_linkedin_client
  def get_linkedin_api_client
    task_name = 'linkedin_rw_nus'
    t = Task.where("session_id = ? and task = ? and created_at > ?", get_sessionid, task_name, 10.minutes.ago).first
    return nil unless t
    client = YAML::load(t.task_data)
    t.destroy
    client
  end # get_linkedin_client


  # save/get "state" -
  private

  private
  def login_user_ids
    set_session_value(:user_ids, []) unless get_session_value(:user_ids)
    get_session_value(:user_ids)
  end
  helper_method :login_user_ids

  # valid: return locale, :invalid: return nil
  private
  def valid_locale (locale)
    available_locales = Rails.application.config.i18n.available_locales.collect { |locale| locale.to_s }
    return nil unless available_locales.index(locale.to_s)
    locale
  end
  
  # session get/set methods
  # session cookie store is used now, but there is problems with session updates and multiple ajax requests
  # for example last_row_id set is updated in one ajax request and reset to old value in an other ajax request
  # maybe move some session variable to a db table
  
  # set timezone used in views
  private
  def get_timezone
    # logger.debug2 "before: Time.zone = #{Time.zone}, Time.now = #{Time.now}, Time.zone.now = #{Time.zone.now}"
    # logger.debug2 "session[:timezone] = #{session[:timezone]}"
    Time.zone = get_session_value(:timezone) if get_session_value(:timezone)
    # logger.debug2 "after: Time.zone = #{Time.zone}, Time.now = #{Time.now}, Time.zone.now = #{Time.zone.now}"
  end

  # save timezone received from JS or from login provider
  # ajax error message if JS timezone does not match a rails timezone
  # Rails timezones:
  #           - ActiveSupport::TimeZone.all.collect { |tz| (tz.tzinfo.current_period.utc_offset / 60.0 / 60.0).to_s }.uniq
  # - ["-11.0", "-10.0", "-9.0", "-8.0", "-7.0", "-6.0", "-5.0", "-4.5", "-4.0", "-3.5", "-3.0", "-2.0", "-1.0",
  #    "0.0", "1.0", "2.0", "3.0", "3.5", "4.0", "4.5", "5.0", "5.5", "5.75", "6.0", "6.5", "7.0", "8.0", "9.0",
  #    "9.5", "10.0", "11.0", "12.0", "12.75", "13.0"]
  # http://api.rubyonrails.org/classes/ActiveSupport/TimeZone.html
  # The version of TZInfo bundled with Active Support only includes the definitions necessary to support the zones
  # defined by the TimeZone class. If you need to use zones that aren't defined by TimeZone, you'll need to install
  # the TZInfo gem (if a recent version of the gem is installed locally, this will be used instead of the bundled version
  # javascript timezones:
  # wiki: http://en.wikipedia.org/wiki/Time_zone#List_of_UTC_offsets
  # wiki/rails problems: -9.5, 10.5, 11.5 and 14 is defined in wiki, but not in rails
  private
  def set_timezone(timezone)
    timezone = "#{timezone}.0" unless timezone.to_s.index('.')
    timezones = ActiveSupport::TimeZone.all.collect { |tz| (tz.tzinfo.current_period.utc_offset / 60.0 / 60.0).to_s }.uniq
    return add_error_key '.unknown_timezone', :timezone => timezone unless timezones.index(timezone)
    logger.debug2  "timezone = #{timezone}"
    timezone_f = timezone.to_f
    set_session_value(:timezone, timezone_f)
    Time.zone = timezone_f
  end

  # get/set last_row_id
  # has been moved from cookie session store to sessions table
  # ( problem with concurrent ajax requests and session store update )
  private
  def set_last_row_id (last_row_id)
    session.delete(:last_row_id) if session.has_key?(:last_row_id)
    s = Session.find_by_session_id(get_sessionid)
    if !s
      s = Session.new
      s.session_id = get_sessionid
    end
    s.last_row_id = last_row_id
    s.save!
    last_row_id
  end
  def get_last_row_id
    set_last_row_id(get_session_value(:last_row_id)) if get_session_value(:last_row_id).to_s != ''
    s = Session.find_by_session_id(get_sessionid)
    return nil unless s
    s.last_row_id
  end

  # used in gifts/index
  # todo: moved to AngularJS GiftsCtrl, formatDirection filter
  private
  def format_direction_with_user (api_gift)
    gift = api_gift.gift
    case gift.direction
      when 'giver'
        t 'gifts.api_gift.direction_giver', :username => api_gift.giver.short_or_full_user_name(@users)
      when 'receiver'
        t 'gifts.api_gift.direction_receiver', :username => api_gift.receiver.short_or_full_user_name(@users)
      when 'both'
        t 'gifts.api_gift.direction_giver_and_receiver', :givername => api_gift.giver.short_user_name, :receivername => api_gift.receiver.short_user_name
      else
        raise "invalid direction for gift #{gift.id}"
    end # case
  end # format_direction
  helper_method :format_direction_with_user

  private
  def deep_link?
    deep_link = (params[:controller] == 'gifts' and params[:action] == 'show' and params[:id].to_s =~ /^[a-zA-Z0-9]{30}$/) ? true : false
    # logger.debug2 "deep_link = #{deep_link}, controller = #{params[:controller]}, action = #{params[:action]}, id = #{params[:id]}"
    deep_link
  end
  helper_method "deep_link?"

  # define api clients. There must be one init_api_client_<provider> method for each provider
  # structure: initialize api_client, add one or more gofreerev_xxx instance methods, return api_client
  # instance method gofreerev_get_friends is required (download friend list)
  # instance method gofreerev_post_on_wall is required if provider should support post on api wall
  # instance method gofreerev_get_user can be added if user info. should be updated after login (facebook)

  private
  def init_api_client_facebook (token)
    provider = 'facebook'
    # create facebook api client
    api_client = Koala::Facebook::API.new(token)
    # add helper methods to facebook api client
    # get a few login user fields that was not updated doing login
    api_client.define_singleton_method :gofreerev_get_user do |logger|
      user_hash = {}
      key, options = nil
      # get user information - picture
      api_request = 'me?fields=picture.width(100).height(100)'
      logger.debug2  "api_request = #{api_request}"
      api_response = api_client.get_object api_request
      logger.debug2  "api_response = #{api_response}"
      image = api_response['picture']['data']['url'] if api_response['picture'] and api_response['picture']['data']
      user_hash[:api_profile_picture_url] = image if image
      # return user_hash to generic_post_login - see also user.update_api_user_from_hash
      [user_hash, key, options]
    end
    # add gofreerev_get_friends - used on post_login_<provider>
    api_client.define_singleton_method :gofreerev_get_friends do |logger|
      # get facebook friends list (name and url for profile picture for each facebook friend)
      # note that friends list has been changed in facebook oauth 2.2 api. Only friends that also area app friends are returned.
      # ( that is empty in must cases )
      api_request = 'me/friends?fields=name,id,picture.width(100).height(100)'
      # logger.debug2  "api_request = #{api_request}"
      friends = self.get_object api_request
      # logger.debug2  "friends = #{friends}"
      # copy friends from api to friends_hash
      friends_hash = {}
      friends.each do |friend|
        # logger.debug2 "friend = #{friend}"
        friend_user_id = friend["id"] + '/facebook'
        name = friend["name"].force_encoding('UTF-8')
        if friend["picture"] and friend["picture"]["data"]
          api_profile_picture_url = friend["picture"]["data"]["url"]
        else
          api_profile_picture_url = nil
        end
        friends_hash[friend_user_id] = {:name => name,
                                        :api_profile_picture_url => api_profile_picture_url }
      end # each
      # return friends has to post_login_<provider> - see also Friend.update_api_friends_from_hash
      [friends_hash, nil, nil]
    end # gofreerev_get_friends
    # return api client
    api_client
  end # init_api_client_facebook

  private
  def init_api_client_flickr (token)
    provider = 'flickr'
    # create flickr api client
    FlickRaw.api_key = API_ID[provider]
    FlickRaw.shared_secret = API_SECRET[provider]
    api_client = flickr
    api_client.access_token = token[0]
    api_client.access_secret = token[1]
    # add helper methods to flickr api client
    # add gofreerev_get_friends - used on post_login_<provider>
    api_client.define_singleton_method :gofreerev_get_friends do |logger|
      # get flickr friends (follows)
      friends = self.contacts.getList
      # copy follows into friends_hashs
      friends_hash = {}
      friends.each do |contact|
        logger.debug2 "contact = #{contact} (#{contact.class})"
        # copy friend to friends_hash
        friend_user_id = "#{contact.nsid}/#{provider}"
        friend_name = (contact.realname == '' ? contact.username : contact.realname).force_encoding('UTF-8')
        friend_api_profile_url = "#{API_URL[:flickr]}people/#{contact.nsid}"
        if contact.iconfarm.to_s == '0' and contact.iconserver.to_s == '0'
          friend_api_profile_picture_url = nil
        else
          friend_api_profile_picture_url = "http://farm#{contact.iconfarm}.static.flickr.com/#{contact.iconserver}/buddyicons/#{contact.nsid}.jpg"
        end
        friends_hash[friend_user_id] = {:name => friend_name,
                                        :api_profile_url => friend_api_profile_url,
                                        :api_profile_picture_url => friend_api_profile_picture_url}
      end
      # return friends has to post_login_<provider> - see also Friend.update_api_friends_from_hash
      [friends_hash, nil, nil]
    end # gofreerev_get_friends

    # return api client
    api_client
  end # init_api_client_flickr

  private
  def init_api_client_foursquare (token)
    provider = 'foursquare'
    # create foursquare api client
    api_client = Foursquare2::Client.new(:oauth_token => token)
    # add helper methods to foursquare api client
    # add gofreerev_get_friends - used on post_login_<provider>
    api_client.define_singleton_method :gofreerev_get_friends do |logger|
      # get foursquare friends
      friends = self.user_friends 'self', :v => '20140214'
      # copy friends list to hash
      friends_hash = {}
      friends["items"].each do |friend|
        # logger.debug2 "friend = #{friend}"
        friend_user_id = "#{friend.id}/#{provider}"
        name = "#{friend.firstName} #{friend.lastName}".force_encoding('UTF-8')
        api_profile_url = "#{API_URL[provider]}/user/#{friend.id}"
        api_profile_picture_url = "#{friend.photo.prefix}100x100#{friend.photo.suffix}"
        friends_hash[friend_user_id] = {:name => name,
                                        :api_profile_url => api_profile_url,
                                        :api_profile_picture_url => api_profile_picture_url }
      end # each
      # return friends has to post_login_<provider> - see also Friend.update_api_friends_from_hash
      [friends_hash, nil, nil]
    end # gofreerev_get_friends
    # return api client
    api_client
  end # init_api_client_foursquare

  private
  def init_api_client_google_oauth2 (token)
    provider = 'google_oauth2'
    # create google+ api client
    api_client = Google::APIClient.new(
        :application_name => 'Gofreerev',
        :application_version => '0.1'
    )
    api_client.authorization.client_id = API_ID[provider]
    api_client.authorization.client_secret = API_SECRET[provider]
    api_client.authorization.access_token = token
    # add helper methods to google+ api client
    # add gofreerev_get_friends - used on post_login_<provider>
    api_client.define_singleton_method :gofreerev_get_friends do |logger|
      # get methods for google+ api calls
      plus = self.discovered_api('plus')
      # find people in login user circles
      # https://developers.google.com/api-client-library/ruby/guide/pagination
      friends_hash = {}
      request = {:api_method => plus.people.list,
                 :parameters => {'collection' => 'visible', 'userId' => 'me'}}
      # loop for all google+ friends - one or more pages with friends
      loop do
        # get first/next page of google+ follows
        result = self.execute(request)
        # logger.debug2  "result = #{result}"
        # logger.debug2  "result.error_message.class = #{result.error_message.class}"
        logger.debug2  "result.error_message = #{result.error_message}"
        # known errors from Google API
        return [friends_hash, 'util.do_tasks.google_access_not_configured', {:provider => provider}] if result.error_message.to_s == 'Access Not Configured'
        return [friends_hash, 'util.do_tasks.google_insufficient_permission', {:provider => provider}] if result.error_message.to_s == 'Insufficient Permission'
        raise AppNotAuthorized if result.error_message.to_s == 'Invalid Credentials'
        # other errors from Google API
        return [friends_hash, 'util.do_tasks.google_other_errors', {:provider => provider, :error => result.error_message}] if !result.data.total_items
        # xxx
        # copy friends to hash.
        # logger.debug2  "result.data.items = #{result.data.items}"
        # todo: check friend.kind = plus#person - maybe ignore rows with friend.kind != plus#person
        # todo: returns profile picture urls with size 50 x 50 (?sz=50) - replace with ?sz=100 ?
        for friend in result.data.items do
          # logger.debug2  "friend = #{friend} (#{friend.class})"
          # copy friend to friends_hash
          friend_user_id = "#{friend.id}/#{provider}"
          friends_hash[friend_user_id] = { :name => friend.display_name.force_encoding('UTF-8'),
                                           :api_profile_url => friend.url,
                                           :api_profile_picture_url => friend.image.url }
        end # item
        # next page - get more friends if any
        break unless result.next_page_token
        request = result.next_page
      end # loop for all google+ friends
      # return friends has to post_login_<provider> - see also Friend.update_api_friends_from_hash
      logger.debug2 "friends_hash..size = #{friends_hash.size}"
      [friends_hash, nil, nil]
    end # gofreerev_get_friends
    # return api client
    api_client
  end # init_api_client_google_oauth2

  private
  def init_api_client_instagram (token)
    provider = 'instagram'
    # create instagram api client
    Instagram.configure do |config|
      config.client_id = API_ID[provider]
      config.client_secret = API_SECRET[provider]
    end
    api_client = Instagram.client(:access_token => token)
    # add helper methods to instagram api client
    # add gofreerev_get_friends - used on post_login_<provider>
    api_client.define_singleton_method :gofreerev_get_friends do |logger|
      # get arrays with follows and followers
      begin
        follows = self.user_follows
      rescue Instagram::BadRequest => e
        # 400: The access_token provided is invalid. (Instagram::BadRequest) gives stack dump:
        # D, [2014-12-09T08:46:34.301990 #11628] DEBUG -- : rescue in generic_post_login: Exception: GET https://api.instagram.com/v1/users/self/follows.json?access_token=1092213433.11b9d9c.c6f8442384e64ba2a03f387b3ce8971d: 400: The access_token provided is invalid. (Instagram::BadRequest)
        # D, [2014-12-09T08:46:34.304499 #11628] DEBUG -- : rescue in generic_post_login: Backtrace: /mnt/plugdisk/railsapps/gofreerev-fb/shared/bundle/ruby/2.0.0/gems/instagram-1.1.3/lib/faraday/raise_http_exception.rb:11:in `block in call'
        # /mnt/plugdisk/railsapps/gofreerev-fb/shared/bundle/ruby/2.0.0/gems/faraday-0.9.0/lib/faraday/response.rb:57:in `on_complete'
        # /mnt/plugdisk/railsapps/gofreerev-fb/shared/bundle/ruby/2.0.0/gems/instagram-1.1.3/lib/faraday/raise_http_exception.rb:8:in `call'
        # /mnt/plugdisk/railsapps/gofreerev-fb/shared/bundle/ruby/2.0.0/gems/faraday_middleware-0.9.1/lib/faraday_middleware/response_middleware.rb:30:in `call'
        # /mnt/plugdisk/railsapps/gofreerev-fb/shared/bundle/ruby/2.0.0/gems/faraday-0.9.0/lib/faraday/response.rb:8:in `call'
        # /mnt/plugdisk/railsapps/gofreerev-fb/shared/bundle/ruby/2.0.0/gems/faraday-0.9.0/lib/faraday/request/url_encoded.rb:15:in `call'
        # /mnt/plugdisk/railsapps/gofreerev-fb/shared/bundle/ruby/2.0.0/gems/instagram-1.1.3/lib/faraday/oauth2.rb:33:in `call'
        # /mnt/plugdisk/railsapps/gofreerev-fb/shared/bundle/ruby/2.0.0/gems/faraday-0.9.0/lib/faraday/rack_builder.rb:139:in `build_response'
        # /mnt/plugdisk/railsapps/gofreerev-fb/shared/bundle/ruby/2.0.0/gems/faraday-0.9.0/lib/faraday/connection.rb:377:in `run_request'
        # /mnt/plugdisk/railsapps/gofreerev-fb/shared/bundle/ruby/2.0.0/gems/faraday-0.9.0/lib/faraday/connection.rb:140:in `get'
        # /mnt/plugdisk/railsapps/gofreerev-fb/shared/bundle/ruby/2.0.0/gems/instagram-1.1.3/lib/instagram/request.rb:31:in `request'
        # /mnt/plugdisk/railsapps/gofreerev-fb/shared/bundle/ruby/2.0.0/gems/instagram-1.1.3/lib/instagram/request.rb:9:in `get'
        # /mnt/plugdisk/railsapps/gofreerev-fb/shared/bundle/ruby/2.0.0/gems/instagram-1.1.3/lib/instagram/client/users.rb:66:in `user_follows'
        # /mnt/plugdisk/railsapps/gofreerev-fb/releases/20141114142829/app/controllers/application_controller.rb:1542:in `block in init_api_client_instagram'
        if e.message =~ /The access_token provided is invalid/
          raise AppNotAuthorized
        else
          raise
        end
      end
      followed_by = self.user_followed_by

      # api_friend: Y: mutual friends, F follows, S Stalked by = followed_by
      api_friends = {}
      follows.each { |f| api_friends[f.id] = 'F' }
      followed_by.delete_if { |f| api_friends[f.id] = api_friends.has_key?(f.id) ? 'Y' : 'S' ; api_friends[f.id] == 'Y' }
      # initialise friends_hash for Friend.update_api_friends_from_hash request
      friends_hash = {}
      (follows + followed_by).each do |friend|
        # logger.debug2 "friend = #{friend} (#{friend.class})"
        # copy friend to friends_hash
        friend_user_id = "#{friend.id}/#{provider}"
        friend_name = (friend.full_name.to_s == '' ? friend.username : friend.full_name).force_encoding('UTF-8')
        friends_hash[friend_user_id] = { :name => friend_name,
                                         :api_profile_url => "#{API_URL[:instagram]}#{friend.username}#",
                                         :api_profile_picture_url => friend.profile_picture,
                                         :api_friend => api_friends[friend.id] }
      end # each friend
      # return friends has to post_login_<provider> - see also Friend.update_api_friends_from_hash
      [friends_hash, nil, nil]
    end # gofreerev_get_friends
    # return api client
    api_client
  end # init_api_client_instagram

  private
  def init_api_client_linkedin (token)
    provider = 'linkedin'
    # create linkedin api client
    api_client = LinkedIn::Client.new API_ID[provider], API_SECRET[provider]
    api_client.authorize_from_access token
    # add helper methods to linkedin api client

    # add gofreerev_get_friends - used on post_login_<provider>
    api_client.define_singleton_method :gofreerev_get_friends do |logger|
      # get array with linkedin connections
      # http://developer.linkedin.com/documents/profile-fields#profile
      # fields = %w(id,first-name,last-name,public-profile-url,picture-url,num-connections)
      fields = %w(id first-name last-name public-profile-url picture-url num-connections)
      begin
        friends = self.connections(:fields => fields).data
      rescue LinkedIn::Errors::UnauthorizedError => e
        # user has removed app from app settings page https://www.linkedin.com/secure/settings?userAgree=&goback=.nas_*1_*1_*1
        raise AppNotAuthorized
      end
      logger.debug2 "friends = #{friends}"
      # copy array with linkedin connections into gofreerev friends_hash
      friends_hash = {}
      friends.each do |connection|
        # logger.debug2 "connection = #{connection} (#{connection.class})"
        # logger.debug2 "connection.public_profile_url = #{connection.public_profile_url}"
        # copy friend to friends_hash
        friend_user_id = "#{connection.id}/#{provider}"
        friend_name = "#{connection.first_name} #{connection.last_name}".force_encoding('UTF-8')
        friends_hash[friend_user_id] = {:name => friend_name,
                                        :api_profile_url => connection.public_profile_url,
                                        :api_profile_picture_url => connection.picture_url,
                                        :no_api_friends => connection.num_connections.to_i}
      end # connection loop
      # return friends has to post_login_<provider> - see also Friend.update_api_friends_from_hash
      [friends_hash, nil, nil]
    end # gofreerev_get_friends

    # return api client
    api_client
  end # init_api_client_linkedin

  private
  def init_api_client_twitter (token)
    provider = 'twitter'
    # logger.debug2  "token = #{token.join(', ')}"
    # create twitter api client
    api_client = Twitter::REST::Client.new do |config|
    # api_client = Twitter::Client.new do |config|
      config.consumer_key        = API_ID[provider]
      config.consumer_secret     = API_SECRET[provider]
      config.access_token        = token[0]
      config.access_token_secret = token[1]
    end
    # add helper methods to twitter api client
    # add gofreerev_get_friends - used on post_login_<provider>
    api_client.define_singleton_method :gofreerev_get_friends do |logger|
      # get array with twitter friends (follows)
      friends = self.friends.to_a
      # logger.debug2 "friends = #{friends}"
      # copy vk friends hash array into gofreerev friends_hash
      friends_hash = {}
      begin
        friends.each do |friend|
          # logger.debug2 "friend.url = #{friend.url} (#{friend.url.class})"
          # copy friend to friends_hash
          friend_user_id = "#{friend.id}/#{provider}"
          friend_name = friend.name.dup.force_encoding('UTF-8')
          friends_hash[friend_user_id] = { :name => friend_name,
                                           :api_profile_url => friend.url.to_s,
                                           :api_profile_picture_url => friend.profile_image_url.to_s,
                                           :no_api_friends => friend.friends_count }
        end # connection loop
      end
      # return friends has to post_login_<provider> - see also Friend.update_api_friends_from_hash
      [friends_hash, nil, nil]
    end # gofreerev_get_friends

    # return api client
    api_client
  end # init_api_client_twitter

  private
  def init_api_client_vkontakte (token)
    provider = 'vkontakte'
    login_user = @users.find { |u| u.provider == provider }
    # create vkontakte api client
    Vkontakte.setup do |config|
      config.app_id = API_ID[:vkontakte]
      config.app_secret = API_SECRET[:vkontakte]
      config.format = :json
      config.debug = true
      config.logger = nil # File.open(Rails.root.join('log', "#{Rails.env}.log").to_s, 'a')
    end
    api_client = Vkontakte::App::User.new(login_user.uid, :access_token => token)
    # add helper methods to vkontakte api client
    # add gofreerev_get_friends - used on post_login_<provider>
    api_client.define_singleton_method :gofreerev_get_friends do |logger|
      # get array with vkontakte friends
      # VK also have follows/followers but information is not available for web site api
      # http://vk.com/developers.php?oid=-17680044&p=friends.get
      friends = self.friends.get :fields => "photo_medium,screen_name"
      # logger.debug2 "friends = #{friends}"
      # copy vk friends hash array into gofreerev friends_hash
      friends_hash = {}
      begin
        friends.each do |friend|
          # logger.debug2 "friend.url = #{friend.url} (#{friend.url.class})"
          # copy friend to friends_hash
          friend_user_id = "#{friend['uid']}/#{provider}"
          friend_name = "#{friend['first_name']} #{friend['last_name']}".force_encoding('UTF-8')
          logger.debug2 "api_profile_url = #{API_URL[:vkontakte]}#{friend['screen_name']}"
          friends_hash[friend_user_id] = { :name => friend_name,
                                           :api_profile_url => "#{API_URL[:vkontakte]}#{friend['screen_name']}",
                                           :api_profile_picture_url => friend['photo_medium'] }
        end # connection loop
      end
      # return friends has to post_login_<provider> - see also Friend.update_api_friends_from_hash
      [friends_hash, nil, nil]
    end # gofreerev_get_friends
    # return api client
    api_client
  end # init_api_client_vkontakte

  private
  def init_api_client (provider, token)
    method = "init_api_client_#{provider}".to_sym
    return ['util.do_tasks.init_api_client_missing', :provider => provider] unless private_methods.index(method)
    send(method, token)
  end


  # use flash table to prevent CookieOverflow for big flash messages when using session cookie
  # use save_flash before redirect
  # use add_error_key or add_error_text for flash messages in page header without redirect
  # todo: add_flash_key for append multiple flash messages?
  private
  def save_flash_key (key, options = {})
    # delete old flash
    flash_id = get_session_value(:flash_id)
    if flash_id
      f = Flash.find_by_id(flash_id)
      f.destroy if f
      session.delete(:flash_id)
    end
    # create new flash
    f = Flash.new
    f.message = t key, options
    f.save!
    set_session_value(:flash_id, f.id)
    logger.debug2 "flash.id = #{f.id}, session[:flash_id] = #{get_session_value(:flash_id)}, message = #{f.message}"
  end

  private
  def save_flash_text (text)
    # delete old flash
    flash_id = get_session_value(:flash_id)
    if flash_id
      f = Flash.find_by_id(flash_id)
      f.destroy if f
      session.delete(:flash_id)
    end
    # create new flash
    f = Flash.new
    f.message = text
    f.save!
    set_session_value(:flash_id, f.id)
    logger.debug2 "flash.id = #{f.id}, session[:flash_id] = #{get_session_value(:flash_id)}, message = #{f.message}"
  end


  private
  def get_flash
    flash_id = get_session_value(:flash_id)
    logger.debug "flash_id = #{flash_id}"
    return nil unless flash_id
    f = Flash.find_by_id(flash_id)
    session.delete(:flash_id)
    return nil unless f
    message = f.message
    f.destroy!
    logger.debug2 "message = #{message}"
    message
  end
  helper_method :get_flash

  # generic error methods add_error_key, add_error_text, format_response, format_response_key and format_response_text
  # all errors and messages are stored on @errors array with { :id => id, :msg => msg}
  # html request errors and messages are returned in notification div in page header as a "flash" message
  # ajax errors are injected in tasks_errors table in page header or error tables within page (:table option)
  # ( see layouts/application.js.erb and JS method move_tasks_errors2 method (gofreerev.js) )
  # add_error_xxx adds error to @errors. format_response_xxx adds any error to @errors and format js or html response
  # note that all ajax calls must set format and datatype: :remote => true, :data => { :type => :script }, :format => :js
  private
  def add_error_key (key, options = nil)
    raise "invalid call. key is missing" if key.class != String or key == ''
    options = {} unless options
    table = options.delete(:table) || 'tasks_errors'
    options[:raise] = I18n::MissingTranslationData if xhr? # force stack dump
    @errors << { :msg => t(key, options), :id => table }
    nil
  end

  private
  def add_error_text (text, options = {})
    table = options.delete(:table) || 'tasks_errors'
    @errors << { :msg => text, :id => table }
    nil
  end

  # ie8 fix for blank HTTP_X_REQUESTED_WITH / jquery.ajaxForm
  private
  def xhr?
    return true if request.xhr?
    # ie8 fix
    return true if request.headers['HTTP_X_REQUESTED_WITH'].to_s == '' and request.format.to_s == 'text/javascript'
    false
  end

  private
  def format_response (options = {})
    # logger.debug2 "options = #{options}"
    # logger.debug2 "request.path_parameters[:format] = #{request.path_parameters[:format]}"
    action = options.delete(:action) if options
    action = params[:action] unless action
    respond_to do |format|
      # logger.debug2 "format = #{format}, request.xhr? = #{request.xhr?}, xhr? = #{xhr?}" +
      #                   ", HTTP_X_REQUESTED_WITH = #{request.headers['HTTP_X_REQUESTED_WITH']}" +
      #                   ", request.format = #{request.format}"
      if xhr?
        # fix for ie8/ie9 error:
        #  "to help protect your security internet explorer blocked this site from downloading files to your computer"
        # (x.js.erb response is being downloaded instead of being executed)
        # only a problem in remote forms (new gifts and new comments)
        # logger.debug2 "format.js: action = #{action}"
        format.js {render action, :content_type => "text/plain" }
      else
        # html or json
        # merge any flash message with any @errors messages into a (new) flash message
        if @errors.size > 0
          flash_id = get_session_value(:flash_id)
          f = Flash.find_by_id(flash_id) if flash_id
          errors = []
          errors = errors + get_flash.to_s.split('<br>') if f
          errors = errors + @errors.collect { |x| x[:msg] }
          # create new flash
          f = Flash.new
          f.message = errors.join('<br>')
          f.save!
          set_session_value(:flash_id, f.id)
          @errors = []
        end
        if request.path_parameters[:format] == 'json'
          if f
            @json[:error] = f.message
            f.destroy
            set_session_value(:flash_id, nil)
          end
          # todo: encrypt response using client public key
          #       required for an insecure http connection. and could be used as extra security in a https connection
          #       signature { encryption: 'mix', key: key, message: message } where key is an rsa encrypted random symmetric password
          format.json { render json: @json }
        else
          format.html
        end
      end
    end
    nil
  end # format_response

  private
  def format_response_key (key = nil, options = {})
    add_error_key(key, options) if key
    format_response options
  end # format_response

  private
  def format_response_text (text = nil, options = {})
    add_error_text(text, options) if text
    format_response options
  end # format_response

  # protect cookie information on public web servers
  private
  def ssl_configured?
    FORCE_SSL
  end

  # use @errors array to report ajax errors
  private
  def setup_json_and_errors
    # logger.debug2 "request.xhr? = #{request.xhr?}, HTTP_X_REQUESTED_WITH = #{request.headers['HTTP_X_REQUESTED_WITH']}"
    @errors = []
    @json = {}
  end

  # show/hide find friends link
  # used in shared/share_account partial in auth/index and users/index pages
  private
  def show_find_friends_link?
    (@users.size > 1)
  end
  helper_method :show_find_friends_link?


  # <==


  # post_on_wall privs. have been moved to session
  # call methods Picture.find_picture_store and Picture.new_temp_or_perm_rel_path have been moved to application controller
  # ==>



  # called from partial /shared/user_div - check if balance for friend should be recalculated
  private
  def check_old_balance (user)
    return unless user.last_login_at # ignore non app users
    return if user.balance_at == Date.parse(Sequence.get_last_exchange_rate_date)
    add_task "User.recalculate_balance_task(#{user.id})", 9
  end # check_old_balance
  helper_method :check_old_balance


end # ApplicationController
