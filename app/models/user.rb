# require 'open4'

class User < ActiveRecord::Base

  FRIEND_REQUEST_NOTI_KEY = 'request_for_app_friendship_v1'
=begin
  create_table "users", force: true do |t|
    t.string   "user_id",    limit: 20
    t.text     "user_name"
    t.datetime "created_at"
    t.datetime "updated_at"
    t.text     "currency"
    t.text     "balance"
    t.date     "balance_at"
  end
=end


  # relations
  has_many :offers, :class_name => 'ApiGift', :primary_key => :user_id, :foreign_key => :user_id_giver, :dependent => :destroy
  has_many :wishes, :class_name => 'ApiGift', :primary_key => :user_id, :foreign_key => :user_id_receiver, :dependent => :destroy
  has_many :friends, :class_name => 'Friend', :primary_key => :user_id, :foreign_key => :user_id_giver, :dependent => :destroy
  # has_many :users, :through => :friends # user record for each friend
  has_many :sent_notifications, :class_name => 'Notification', :primary_key => :user_id, :foreign_key => :from_user_id, :dependent => :destroy
  has_many :received_notifications, :class_name => 'Notification', :primary_key => :user_id, :foreign_key => :to_user_id, :dependent => :destroy
  has_many :api_comments, :class_name => 'ApiComment', :primary_key => :user_id, :foreign_key => :user_id, :dependent => :destroy
  has_many :gift_likes, :class_name => 'GiftLike', :primary_key => :user_id, :foreign_key => :user_id, :dependent => :destroy
  belongs_to :share_account, :class_name => 'ShareAccount', :primary_key => :share_account_id, :foreign_key => :share_account_id, :counter_cache => :no_users

  # https://github.com/jmazzi/crypt_keeper - text columns are encrypted in database
  # encrypt_add_pre_and_postfix/encrypt_remove_pre_and_postfix added in setters/getters for better encryption
  # this is different encrypt for each attribute and each db row
  crypt_keeper :user_name, :currency, :balance, :permissions, :no_api_friends, :negative_interest,
               :api_profile_url, :api_profile_picture_url, :encryptor => :aes, :key => ENCRYPT_KEYS[0]


  ##############
  # attributes #
  ##############

  # 1) user_id. required unique USER id, fx. 1234567890/facebook. Not encrypted. PK and user in encryption
  validates_presence_of :user_id
  attr_readonly :user_id

  def user_id=(new_user_id)
    return self['user_id'] if self['user_id']
    self['user_id'] = new_user_id
  end

  # user_id=

  # 2) user_name. User name. String in model. Encrypted text in db. required. is updated when the user logs in.
  validates_presence_of :user_name

  def user_name
    return nil unless (extended_user_name = read_attribute(:user_name))
    encrypt_remove_pre_and_postfix(extended_user_name, 'user_name', 9)
  end

  # user_name
  def user_name=(new_user_name)
    if new_user_name
      # logger.debug2  "new_user_name = #{new_user_name} (#{new_user_name.class.name})"
      check_type('user_name', new_user_name, 'String')
      write_attribute :user_name, encrypt_add_pre_and_postfix(new_user_name, 'user_name', 9)
    else
      write_attribute :user_name, nil
    end
  end

  # user_name=
  alias_method :user_name_before_type_cast, :user_name

  def user_name_was
    return user_name unless user_name_changed?
    return nil unless (extended_user_name = attribute_was(:user_name))
    encrypt_remove_pre_and_postfix(extended_user_name, 'user_name', 9)
  end

  # user_name_was

  # 3) currency. Required. String in model. Encrypted text in db.
  # validates_presence_of :currency # todo: only required for gofreerev users / not required for friends not using gofreerev
  def currency
    return nil unless (extended_currency = read_attribute(:currency))
    encrypt_remove_pre_and_postfix(extended_currency, 'currency', 10)
  end

  def currency=(new_currency)
    if new_currency
      check_type('currency', new_currency, 'String')
      write_attribute :currency, encrypt_add_pre_and_postfix(new_currency, 'currency', 10)
    else
      write_attribute :currency, nil
    end
  end

  # currency
  alias_method :currency_before_type_cast, :currency

  def currency_was
    return currency unless currency_changed?
    return nil unless (extended_currency = attribute_was(:currency))
    encrypt_remove_pre_and_postfix(extended_currency, 'currency', 10)
  end

  # currency_was

  # 4) balance. Balance. Required. Multi-currency Hash in model. Encrypted text in db
  # Keys is ISO code for currency USD, EUR, GBP etc.
  # Key BALANCE is sum of all currencies exchanged to users actual currency
  # validates_presence_of :balance # todo: only required for gofreerev users / not required for friends not using gofreerev
  def balance
    return nil unless (temp_extended_balance = read_attribute(:balance))
    # logger.debug2  "temp_extended_balance = #{temp_extended_balance}"
    temp_balance = YAML::load encrypt_remove_pre_and_postfix(temp_extended_balance, 'balance', 11)
    temp_balance[BALANCE_KEY] = nil unless temp_balance.has_key?(BALANCE_KEY)
    temp_balance
  end

  # balance
  def balance=(new_balance)
    if new_balance
      check_type('balance', new_balance, 'Hash')
      write_attribute :balance, encrypt_add_pre_and_postfix(new_balance.to_yaml, 'balance', 11)
    else
      write_attribute :balance, nil
    end
  end

  # balance=
  alias_method :balance_before_type_cast, :balance

  def balance_was
    return balance unless balance_changed?
    return nil unless (temp_extended_balance = attribute_was(:balance))
    temp_balance = YAML::load encrypt_remove_pre_and_postfix(temp_extended_balance, 'balance', 11)
    temp_balance[BALANCE_KEY] = nil unless temp_balance.has_key?(BALANCE_KEY)
    temp_balance
  end

  # balance_was

  # 5) balance_at. Date. Not encrypted. Date for last balance calculation. Normally today.
  # validates_presence_of :balance_at # todo: only required for gofreerev users / not required for friends not using gofreerev

  # 6) permissions. Optional. Any Ruby type in model (hash with privs. for facebook users). Encrypted text in db
  # facebook: hash with grants privs {"installed"=>1, "basic_info"=>1, "bookmarked"=>1}
  # google+: empty - readonly api - any priv. error will be reported at login
  # linkedin: r_basicprofile,r_network (default/first login) or r_basicprofile,r_network,rw_nus (second login with rw_nus priv)
  # google+: todo
  # permissions is fetched at login and checked before operations (post to api wall)
  def permissions
    return nil unless (extended_permissions = read_attribute(:permissions))
    # todo: no type check for permissions!
    YAML::load(encrypt_remove_pre_and_postfix(extended_permissions, 'permissions', 12))
  end

  # permissions
  def permissions=(new_permissions)
    if new_permissions
      write_attribute :permissions, encrypt_add_pre_and_postfix(new_permissions.to_yaml, 'permissions', 12)
    else
      write_attribute :permissions, nil
    end
  end

  # permissions
  alias_method :permissions_before_type_cast, :permissions

  def permissions_was
    return permissions unless permissions_changed?
    return nil unless (extended_permissions = attribute_was(:permissions))
    YAML::load(encrypt_remove_pre_and_postfix(extended_permissions, 'permissions', 12))
  end

  # permissions_was

  # 7) no_api_friends. Fixnum in Model. Encrypted text in db.
  # for example number of facebook friends for a facebook user
  def no_api_friends
    return nil unless (temp_extended_no_api_friends = read_attribute(:no_api_friends))
    encrypt_remove_pre_and_postfix(temp_extended_no_api_friends, 'no_api_friends', 13).to_i
  end

  # balance
  def no_api_friends=(new_no_api_friends)
    if new_no_api_friends
      check_type('no_api_friends', new_no_api_friends, 'Fixnum')
      write_attribute :no_api_friends, encrypt_add_pre_and_postfix(new_no_api_friends.to_s, 'no_api_friends', 13)
    else
      write_attribute :no_api_friends, nil
    end
  end

  # balance=
  alias_method :no_api_friends_before_type_cast, :no_api_friends

  def no_api_friends_was
    return no_api_friends unless no_api_friends_changed?
    return nil unless (temp_extended_no_api_friends = attribute_was(:no_api_friends))
    encrypt_remove_pre_and_postfix(temp_extended_no_api_friends, 'no_api_friends', 13).to_i
  end

  # no_api_friends_was

  # 10) negative_interest. Required. Multi-currency Hash in model. Encrypted text in db
  # Keys is ISO code for currency USD, EUR, GBP etc.
  # Key BALANCE is sum of all currencies exchanged to users actual currency
  # validates_presence_of :negative_interest # todo: uncomment this
  def negative_interest
    return nil unless (temp_ext_neg_interest = read_attribute(:negative_interest))
    # logger.debug2  "temp_ext_neg_interest = #{temp_ext_neg_interest}"
    temp_negative_interest = YAML::load encrypt_remove_pre_and_postfix(temp_ext_neg_interest, 'negative_interest', 14)
    temp_negative_interest[BALANCE_KEY] = nil unless temp_negative_interest.has_key?(BALANCE_KEY)
    temp_negative_interest
  end

  # negative_interest
  def negative_interest=(new_neg_int)
    if new_neg_int
      check_type('negative_interest', new_neg_int, 'Hash')
      write_attribute :negative_interest, encrypt_add_pre_and_postfix(new_neg_int.to_yaml, 'negative_interest', 14)
    else
      write_attribute :negative_interest, nil
    end
  end

  # negative_interest=
  alias_method :negative_interest_before_type_cast, :negative_interest

  def negative_interest_was
    return negative_interest unless negative_interest_changed?
    return nil unless (temp_ext_neg_interest = attribute_was(:negative_interest))
    temp_negative_interest = YAML::load encrypt_remove_pre_and_postfix(temp_ext_neg_interest, 'negative_interest', 14)
    temp_negative_interest[BALANCE_KEY] = nil unless temp_negative_interest.has_key?(BALANCE_KEY)
    temp_negative_interest
  end

  # negative_interest_was

  # 11) share_account_id - unencrypted integer - connect user balance across login providers

  # 12) api_profile_url - user profile url - used for some API's with special url not derived from uid - for example linkedin
  # String in model - Encrypted text in db
  def api_profile_url
    return nil unless (temp_api_profile_url = read_attribute(:api_profile_url))
    # logger.debug2  "temp_api_profile_url = #{temp_api_profile_url}"
    encrypt_remove_pre_and_postfix(temp_api_profile_url, 'api_profile_url', 39)
  end

  # api_profile_url
  def api_profile_url=(new_api_profile_url)
    if new_api_profile_url
      check_type('api_profile_url', new_api_profile_url, 'String')
      write_attribute :api_profile_url, encrypt_add_pre_and_postfix(new_api_profile_url, 'api_profile_url', 39)
    else
      write_attribute :api_profile_url, nil
    end
  end

  # api_profile_url=
  alias_method :api_profile_url_before_type_cast, :api_profile_url

  def api_profile_url_was
    return api_profile_url unless api_profile_url_changed?
    return nil unless (temp_api_profile_url = attribute_was(:api_profile_url))
    encrypt_remove_pre_and_postfix(temp_api_profile_url, 'api_profile_url', 39)
  end

  # api_profile_url_was

  # 12) api_profile_picture_url - url to user profile picture
  # picture store for profile pictures is either :api or :local. See array constant API_PROFILE_PICTURE_STORE
  # String in model - Encrypted text in db
  def api_profile_picture_url
    return nil unless (temp_api_profile_picture_url = read_attribute(:api_profile_picture_url))
    # logger.debug2  "temp_api_profile_picture_url = #{temp_api_profile_picture_url}"
    encrypt_remove_pre_and_postfix(temp_api_profile_picture_url, 'api_profile_picture_url', 40)
  end

  # api_profile_picture_url
  def api_profile_picture_url=(new_api_profile_picture_url)
    if new_api_profile_picture_url
      check_type('api_profile_picture_url', new_api_profile_picture_url, 'String')
      write_attribute :api_profile_picture_url, encrypt_add_pre_and_postfix(new_api_profile_picture_url, 'api_profile_picture_url', 40)
    else
      write_attribute :api_profile_picture_url, nil
    end
  end

  # api_profile_picture_url=
  alias_method :api_profile_picture_url_before_type_cast, :api_profile_picture_url

  def api_profile_picture_url_was
    return api_profile_picture_url unless api_profile_picture_url_changed?
    return nil unless (temp_api_profile_picture_url = attribute_was(:api_profile_picture_url))
    encrypt_remove_pre_and_postfix(temp_api_profile_picture_url, 'api_profile_picture_url', 40)
  end

  # api_profile_picture_url_was

  # 13) post_on_wall_yn - allow post on api wall - default is Y unless readonly API (google+)
  # string in model and db
  validates_presence_of :post_on_wall_yn
  validates_inclusion_of :post_on_wall_yn, :allow_blank => true, :in => %w(Y N)


  # 14) deleted_at

  # 15) last_login_at

  # 16) deauthorized_at

  # 17) last_friends_find_at

  # 18) access_token - for ShareAccount.share_level's 3 and 4 (access token saved in db)
  # String in model - Encrypted text in db
  def access_token
    return nil unless (temp_access_token = read_attribute(:access_token))
    # logger.debug2  "temp_access_token = #{temp_access_token}"
    encrypt_remove_pre_and_postfix(temp_access_token, 'access_token', 43)
  end

  # access_token
  def access_token=(new_access_token)
    if new_access_token
      check_type('access_token', new_access_token, 'String')
      write_attribute :access_token, encrypt_add_pre_and_postfix(new_access_token, 'access_token', 43)
    else
      write_attribute :access_token, nil
    end
  end

  # access_token=
  alias_method :access_token_before_type_cast, :access_token

  def access_token_was
    return access_token unless access_token_changed?
    return nil unless (temp_access_token = attribute_was(:access_token))
    encrypt_remove_pre_and_postfix(temp_access_token, 'access_token', 43)
  end

  # access_token_was

  # 19) access_token_expires - for ShareAccount.share_level's 3 and 4 (access token saved in db)
  # Integer (unix timestamp) in model - Encrypted text in db
  def access_token_expires
    return nil unless (temp_access_token_expires = read_attribute(:access_token_expires))
    # logger.debug2  "temp_access_token_expires = #{temp_access_token_expires}"
    encrypt_remove_pre_and_postfix(temp_access_token_expires, 'access_token_expires', 44).to_i
  end

  # access_token_expires
  def access_token_expires=(new_access_token_expires)
    if new_access_token_expires
      check_type('access_token_expires', new_access_token_expires, 'Bignum')
      write_attribute :access_token_expires, encrypt_add_pre_and_postfix(new_access_token_expires.to_s, 'access_token_expires', 44)
    else
      write_attribute :access_token_expires, nil
    end
  end

  # access_token_expires=
  alias_method :access_token_expires_before_type_cast, :access_token_expires

  def access_token_expires_was
    return access_token_expires unless access_token_expires_changed?
    return nil unless (temp_access_token_expires = attribute_was(:access_token_expires))
    encrypt_remove_pre_and_postfix(temp_access_token_expires, 'access_token_expires', 44).to_i
  end

  # access_token_expires_was

  # 20) refresh_token - only google+ - google access token expires once every hour
  # for ShareAccount.share_level's 3 and 4 (access token saved in db)
  # String in model - Encrypted text in db
  def refresh_token
    return nil unless (temp_refresh_token = read_attribute(:refresh_token))
    # logger.debug2  "temp_refresh_token = #{temp_refresh_token}"
    encrypt_remove_pre_and_postfix(temp_refresh_token, 'refresh_token', 45)
  end

  # refresh_token
  def refresh_token=(new_refresh_token)
    if new_refresh_token
      check_type('refresh_token', new_refresh_token, 'String')
      write_attribute :refresh_token, encrypt_add_pre_and_postfix(new_refresh_token, 'refresh_token', 45)
    else
      write_attribute :refresh_token, nil
    end
  end

  # refresh_token=
  alias_method :refresh_token_before_type_cast, :refresh_token

  def refresh_token_was
    return refresh_token unless refresh_token_changed?
    return nil unless (temp_refresh_token = attribute_was(:refresh_token))
    encrypt_remove_pre_and_postfix(temp_refresh_token, 'refresh_token', 45)
  end

  # refresh_token_was

  # change currency in page header.
  attr_accessor :new_currency

  # cache inbox_new_notifications in @users.first - do not look up number of new notifications twice
  attr_accessor :cache_new_notifications

  # cache friends information (util.fetch_users)
  # friends categories:
  # 1) logged in user
  # 2) friends            - show detailed info
  # 3) friends of friends - show few info (including deselected api friends)
  attr_accessor :friends_hash

  # normally nil - true if user has been added to users array as a disconnected shared account (show friends for shared accounts)
  attr_accessor :disconnected_shared_account


  ##################
  # helper methods #
  ##################

  ## removed - used for migration from old to new user ids
  #def self.new_user_id (old_user_id)
  #  return nil unless old_user_id
  #  old_prefix = old_user_id.first(2)
  #  uid = old_user_id.from(3)
  #  provider = case old_prefix
  #                  when 'fb' then 'facebook'
  #                  when 'gp' then 'google'
  #                  when 'li' then 'linkedin'
  #                  when 'tw' then 'twitter'
  #                end # case
  #  "#{uid}/#{provider}"
  #end # self.new_user_i
  #def self.old_user_id (new_user_id)
  #  return nil unless new_user_id
  #  provider = new_user_id.split("/").last
  #  uid = new_user_id.first(new_user_id.size-provider.size-1)
  #  prefix = case provider
  #             when 'facebook' then 'fb-'
  #             when 'google' then 'gp-'
  #             when 'linkedin' then 'li-'
  #             when 'twitter' then 'tw-'
  #           end
  #  "#{prefix}#{uid}"
  #end # self.new_user_i

  # for ajax show-more-rows functionality
  public
  def last_row_id
    id
  end


  public
  def self.open4 (command, dir = nil)
    pid, stdin, stdout, stderr = Open4::popen4 "sh"
    stdin.puts "cd #{dir}" if dir
    stdin.puts command
    stdin.close
    ignored, status = Process::waitpid2 pid
    return [stdout.read, stderr.read, status.exitstatus]
  end

  # open4


  # list of valid providers from /config/initializers/omniauth.rb
  def self.valid_omniauth_provider? (provider)
    OmniAuth::Builder.providers.index(provider.to_s)
  end


  def self.find_or_create_dummy_user (provider)
    user_id = "gofreerev/#{provider}"
    user = User.find_by_user_id(user_id)
    return user if user
    user = User.new
    user.user_id = user_id
    if provider =~ /^google/
      user.user_name = "#{APP_NAME} Google"
    else
      user.user_name = "#{APP_NAME} #{provider.camelize}"
    end
    user.currency = BASE_CURRENCY
    # user.profile_picture_name = "#{provider}.png"
    user.api_profile_picture_url = "#{SITE_URL}/images/#{provider}.png".gsub('//images', '/images')
    user.balance = {BALANCE_KEY => 0.0}
    user.post_on_wall_yn = 'N'
    user.save!
    user
  end

  # self.find_or_create_dummy_user


  # find and create or update user from hash
  # options: :provider, :token, :uid, :name, :image, :country, :language
  # called from login methods (authController.create, FbController.index, etc)
  # returns user if ok
  # returns key or key + options if not ok (for translate)
  def self.find_or_create_user (options)
    # missing provider, unknown provider, missing token, uid or user_name are fatal errors.
    provider = options[:provider].to_s
    return '.provider_missing' if provider == ""
    return ['.unknown_provider', {:provider => provider}] unless User.valid_omniauth_provider?(provider)
    token = options[:token].to_s
    return ['.access_token_missing', {:provider => provider}] if token == ""
    expires_at = options[:expires_at].to_s
    return ['.expires_at_missing', {:provider => provider}] if expires_at == ""
    return ['.expires_at_invalid', {:provider => provider}] unless expires_at =~/^\d+$/
    return ['.expires_at_invalid', {:provider => provider}] if expires_at.to_i < Time.now.to_i
    uid = options[:uid].to_s
    return ['.uid_missing', {:provider => provider}] if uid == ""
    return ['.reserved_uid', {:provider => provider}] if uid == 'gofreerev' # reserved uid used for dummy users
    user_name = options[:name].to_s
    # todo: should escape username - ERB::Util.html_escape(user_name) does not work from activemodel
    return '.user_name_missing_google' if user_name == "" and provider.first(6) == 'google'
    return ['.user_name_missing', {:provider => provider}] if user_name == ""
    # missing profile image is a minor problem - only check here - profile image information is normally updated in a post login task
    # facebook: profile image from omniauth login is not used (wrong dimensions) -
    #           profile image from koala request in post_login_facebook is used
    image = options[:image].to_s
    logger.debug2 "no profile picture received from login provider #{provider}" if image == "" and provider != 'facebook'
    logger.debug2 "profile image url #{image}" unless image == ""
    # missing or invalid profile url is a minor problem
    profile_url = options[:profile_url].to_s
    if profile_url == ""
      logger.debug2 "no profile url was received from login provider #{provider}"
      profile_url = nil
    elsif profile_url !~ /^https?/
      logger.debug2 "invalid profile url '#{profile_url}' was received from login provider #{provider}"
      profile_url = nil
    end
    permissions = options[:permissions]
    # create/update user
    user_id = "#{uid}/#{provider}"
    user = User.find_by_user_id(user_id)
    if MAX_USERS > 0 and (!user or !user.last_login_at or user.last_login_at < 2.day.ago)
      # check max number of active Gofreerev accounts
      no_active_users = User.where('last_login_at > ?', 2.day.ago).count
      if no_active_users > 100
        logger.error2 "Login rejected - max number of active user limit #{MAX_USERS}"
        return ['.too_many_users', {:appname => APP_NAME, :max_users => 100}]
      end
    end
    user = User.new unless user
    user.user_id = user_id
    user.user_name = user_name
    user.permissions = permissions
    user.api_profile_url = profile_url if profile_url
    active_currencies = ExchangeRate.active_currencies
    if !user.currency or !active_currencies.index(user.currency)
      # initialize currency from country - for example google and twitter
      country_code = options[:country].to_s
      if country_code == ''
        # provider dod not return country code (google and twitter).
        # Try to get country code from language code
        language_code = options[:language].to_s
        countries = []
        Country.countries.each do |a|
          country_code2 = a[1]
          country2 = Country[country_code2]
          countries << country_code2 if country2.languages.index(language_code)
        end unless language_code == ""
        if countries.size == 1
          country_code = countries.first
        else
          country_code = BASE_COUNTRY
        end
      end # inner if
      c = Country[country_code]
      if !c
        currency = BASE_CURRENCY
      else
        currency = c.currency.code
      end
      currency = BASE_CURRENCY if active_currencies.size > 0 and !active_currencies.index(currency)
      user.currency = currency
    end # outer if
    user.balance = {BALANCE_KEY => 0.0} unless user.balance
    user.balance_at = Date.parse(Sequence.get_last_exchange_rate_date) unless user.balance_at
    user.post_on_wall_yn = API_POST_PERMITTED[provider] == API_POST_NOT_ALLOWED ? 'N' : 'Y' unless user.post_on_wall_yn
    # facebook profile image is set in post login task / post_login_update_friends
    # ( unless new facebook user without profile picture )
    user.api_profile_picture_url = image unless provider == 'facebook' and user.api_profile_picture_url.to_s != ''
    user.last_friends_find_at = user.last_login_at || Time.new unless user.last_friends_find_at
    user.last_login_at = Time.new
    user.deauthorized_at = nil
    user.save!
    # check/add dummy friend row for user (user_id_giver == user_id_receiver)
    friend = Friend.where('user_id_giver = ? and user_id_receiver = user_id_giver', user.user_id).first
    if !friend
      friend = Friend.new
      friend.user_id_giver = user.user_id
      friend.user_id_receiver = user.user_id
    end
    friend.api_friend = 'Y'
    friend.app_friend = nil
    friend.save!
    # cleanup any old flash message - there should never be any
    Flash.where("created_at < ?", 1.minute.ago).delete_all
    # user find/create ok - continue with login
    user
  end

  # find_or_create_user


  # task from task queue - download and save profile picture from provider after login
  # called from util.do_tasks after login process has completed
  # return nil if ok
  # return array with translate key and options if warning or error
  def self.update_profile_image (user_id, url)
    begin
      user = User.find_by_user_id(user_id)
      if !user
        logger.error2 "error: invalid user id"
        return ['.profile_image_invalid_user', {:user_id => user_id}]
      end
      return nil if user.deleted_at # ignore deleted marked users
      if url.to_s == ""
        logger.warn2 "error: no image received from provider / post_login ajax request"
        return ['.profile_image_blank', {:provider => user.provider}]
      end
      if url !~ /https?\:\/\//
        logger.warn2 "error: invalid image #{url} received from provider / post_login ajax request"
        return ['.profile_image_invalid_url', {:provider => user.provider, :image => url}]
      end
      # check image type
      begin
        image_type = FastImage.type(url, :raise_on_failure => true).to_s
      rescue FastImage::ImageFetchFailure => e
        logger.warn2 "Could not get image type for new profile image #{url}. "
        logger.warn2 "Ignoring error. Must be a temporary problem"
        logger.warn2 "Error message was #{e.message}"
        return nil
      end
      if image_type.to_s == ''
        logger.error2 "profile picture url #{url} with blank image type. provider #{user.provider}"
        # todo: FastImage.type returns blank if internet connection is temporary unavailable
        return ['.profile_image_invalid_type', {:provider => user.provider, :image => url, :image_type => image_type}]
      end
      if !%w(gif jpeg png jpg bmp).index(image_type)
        logger.error2 "profile picture url #{url} with unsupported image type #{image_type}. provider #{user.provider}"
        return ['.profile_image_invalid_type', {:provider => user.provider, :image => url, :image_type => image_type}]
      end
      # check image store for profile pictures (:api or :local)
      picture_store = API_PROFILE_PICTURE_STORE[user.provider] || :api
      if picture_store == :api
        # preferred choice - profile pictures not downloaded - use profile picture url from provider as it is
        Picture.delete_if_app_url(user.api_profile_picture_url)
        logger.debug2 "update profile picture: url = #{url}"
        user.api_profile_picture_url = url
        user.update_attribute('api_profile_picture_url', user.api_profile_picture_url) if user.api_profile_picture_url_changed?
        return nil
      end
      if picture_store != :local
        logger.fatal2 "unknown profile picture store #{picture_store} for login provider #{user.provider}"
        logger.fatal2 "please check array constant API_PROFILE_PICTURE_STORE (/config/initializers/omniauth.rb"
        return ['.profile_image_unsupported_store', {:provider => user.provider}]
      end

      # download profile pictures from server to local picture store

      if user.api_profile_picture_url
        # ignore old api profile picture url - will be replaced with an app profile picture url after download
        user.api_profile_picture_url = nil unless Picture.app_url?(user.api_profile_picture_url)
      end
      old_image_type = Picture.find_picture_type(user.api_profile_picture_url) if user.api_profile_picture_url
      # 3 cases:
      #  1) first profile picture download (new path)
      #  2) profile picture with unchanged image type (unchanged path - overwrite old picture)
      #  3) profile picture with new image type (changed path - delete old picture and download new picture)
      if !user.api_profile_picture_url or old_image_type != image_type
        # case 1) and 3) get new picture location
        case_no = user.api_profile_picture_url ? 3 : 1
        old_api_profile_picture_url = user.api_profile_picture_url
        rel_path = Picture.new_perm_rel_path image_type
      else
        # case 2) reuse old picture location
        rel_path = Picture.rel_path(user.api_profile_picture_url)
        case_no = 2
      end
      # create temp dir for picture download
      tmp_dir_full_os_path = Picture.create_tmp_dir :rel_path => rel_path
      # download image to temp dir
      stdout, stderr, status = User.open4("wget \"#{url}\" --no-check-certificate", tmp_dir_full_os_path)
      if status != 0
        # download failed
        logger.warn2 "image download failed: wget: stdout = #{stdout}, stderr = #{stderr}, status = #{status} (#{status.class})"
        Picture.delete_tmp_dir :full_os_path => tmp_dir_full_os_path
        return ['.profile_image_wget_failed', {:provider => user.provider, :image => url, :error => error}]
      end
      # check download
      files = Dir.entries(tmp_dir_full_os_path).delete_if { |x| ['.', '..'].index(x) }
      if files.size != 1
        logger.error2 "image download failed. expected 1 image. found #{files.size} images"
        Picture.delete_tmp_dir :full_os_path => tmp_dir_full_os_path
        return ['.profile_image_count_failed', {:provider => user.provider, :image => url, :count => files.size}]
      end
      new_image_file_full_os_path = "#{tmp_dir_full_os_path}/#{files.first}"
      if case_no == 2
        # 2) overwrite old profile picture - backup before overwrite
        from = Picture.full_os_path :url => old_api_profile_picture_url
        to = "#{new_image_file_full_os_path}.old"
        cmd = "cp #{from} #{to}"
        if status != 0
          logger.debug2 "case #{case_no}"
          logger.debug2 "cp1: cmd = #{cmd}"
          logger.error2 "cp1: stdout = #{stdout}, stderr = #{stderr}, status = #{status} (#{status.class})"
          error = stderr.to_s.split("\n").last
          Picture.delete_tmp_dir :full_os_path => tmp_dir_full_os_path
          return ['.profile_image_cp1_failed', {:provider => user.provider, :image => url, :error => error}]
        end
        # backup ok
      end
      # copy
      from = new_image_file_full_os_path
      to = Picture.full_os_path :rel_path => rel_path
      cmd = "cp #{from} #{to}"
      stdout, stderr, status = User.open4(cmd)
      if status != 0
        # copy failed
        logger.debug2 "case #{case_no}"
        logger.debug2 "cp2: cmd = #{cmd}"
        logger.error2 "cp2: stdout = #{stdout}, stderr = #{stderr}, status = #{status} (#{status.class})"
        error1 = stderr.to_s.split("\n").last
        if case_no == 2
          # restore backup
          from = "#{new_image_file_full_os_path}.old"
          to = Picture.full_os_path :url => old_api_profile_picture_url
          cmd = "cp #{from} #{to}"
          stdout, stderr, status = User.open4(cmd)
          if status != 0
            logger.debug2 "case #{case_no}"
            logger.debug2 "cp3: cmd = #{cmd}"
            logger.error2 "cp3: stdout = #{stdout}, stderr = #{stderr}, status = #{status} (#{status.class})"
            error2 = stderr.to_s.split("\n").last
            error = "#{error1} - #{error2}"
            Picture.delete_tmp_dir :full_os_path => tmp_dir_full_os_path
            return ['.profile_image_cp3_failed', {:provider => user.provider, :image => url, :error => error}]
          end
          # backup restored
        end
        # copy failed
        Picture.delete_tmp_dir :full_os_path => tmp_dir_full_os_path
        return ['.profile_image_cp2_failed', {:provider => user.provider, :image => url, :error => error1}]
      end
      # copied
      # download and copy ok
      user.reload
      user.api_profile_picture_url = Picture.url :rel_path => rel_path
      user.update_attribute('api_profile_picture_url', user.api_profile_picture_url) if user.api_profile_picture_url_changed?
      # cleanup
      Picture.delete_tmp_dir :full_os_path => tmp_dir_full_os_path
      Picture.delete :url => old_api_profile_picture_url if case_no == 3
      nil
    rescue => e
      logger.error2 "Exception: #{e.message.to_s}"
      logger.error2 "Backtrace: " + e.backtrace.join("\n")
      # picture cleanup - any problems are only written to log
      begin
        if tmp_dir_full_os_path and File.exists?(tmp_dir_full_os_path)
          begin
            # always remove tmp dir if tmp dir exists
            Picture.delete_tmp_dir :full_os_path => tmp_dir_full_os_path
          rescue => e
            logger.error2 "Error in tmp dir cleanup after exception. Error = #{e.message}"
          end
        end
        if case_no and [1, 3].index(case_no) and rel_path
          begin
            # new picture location - remove picture if picture exists
            to = Picture.full_os_path :rel_path => rel_path
            FileUtils.rm(to) if File.exists(to)
          rescue => e
            logger.error2 "Error in tmp dir cleanup after exception. Error = #{e.message}"
          end
        end
      rescue => e2
        logger.error2 "Error in picture cleanup after exception. Error = #{e2.message}"
      end
      return ['.profile_image_exception', :error => e.message, :provider => (user ? user.provider : 'API')]
    end
    nil
  end

  # self.download_profile_image

  # called from generic_post_login / post_login_update_friends if api_client instance method gofreerev_get_user exists
  def update_api_user_from_hash (user_hash)
    logger.debug2 "user_hash = #{user_hash}"
    allowed_fields = [:permissions, :api_profile_picture_url]
    invalid_fields = user_hash.keys - allowed_fields
    if invalid_fields.size > 0
      return ['.post_login_user_invalid_field',
              {:provider => provider, :apiname => (API_DOWNCASE_NAME[:provider] || provider),
               :userid => user_id, :field => invalid_fields.first}]

    end
    # permissions
    update_attribute(:permissions, user_hash[:permissions]) if user_hash.has_key? :permissions
    # profile picture
    if user_hash.has_key?(:api_profile_picture_url)
      logger.debug2 "update profile picture: api_profile_picture_url = #{user_hash[:api_profile_picture_url]}"
      key, options = User.update_profile_image(user_id, user_hash[:api_profile_picture_url])
      return [key, options] if key # error when updating profile picture information
    end
    # ok
    nil
  end

  # update_api_user_from_hash

  #def usertype
  #  return nil unless user_id
  #  user_id.first(2)
  #end

  # return uid part of user_id
  def uid
    return nil unless user_id
    user_id.split('/').first
  end

  # return provider part of user_id - facebook, google_oauth2, linkedin or twitter - see OmniAuth::Builder.providers
  def provider
    return nil unless user_id
    user_id.split('/').last
  end

  # true if dummy user
  # gofreerev/gofreerev or gofreerev/<provider>
  # dummy user is used for dummy page header, deep links and unmatched providers when closing deal between two users
  def dummy_user?
    (user_id.split('/').first == 'gofreerev')
  end

  def self.dummy_users? (login_users)
    # logger.debug2 "login_users.class = #{login_users.class}"
    raise "invalid call" unless [Array, ActiveRecord::Relation::ActiveRecord_Relation_User].index(login_users.class)
    raise "invalid call" unless login_users.size > 0
    login_users.each do |login_user|
      return false unless login_user.dummy_user?
    end
    true
  end

  def self.logged_in? (login_users = [])
    return false if login_users.size == 0
    return false if User.dummy_users?(login_users)
    true
  end

  def app_user?
    (last_login_at and !deleted_at and !deauthorized_at)
  end

  def camelized_user_name
    user_name.split(' ').collect { |x| x.camelize}.join(' ')
  end

  def short_user_name
    a = user_name.split(' ')
    "#{a.first} #{a.last.first(1)}"
  end

  def short_or_full_user_name (login_users)
    friend?(login_users) <= 2 ? short_user_name : user_name
  end

  # short_or_full_user_name
  def debug_info
    "#{user_id} #{short_user_name}"
  end

  def self.debug_info (users)
    users.collect { |u| u.debug_info }.join(', ')
  end


  def apiname
    API_DOWNCASE_NAME[provider] || provider
  end

  def apiname_with_brackets
    "(#{apiname})"
  end


  # add login api to user name
  def user_name_with_api
    "#{user_name} #{apiname_with_brackets}"
  end

  # user_name_with_api

  # used in many translates
  def app_and_apiname_hash
    {:appname => APP_NAME,
     :apiname => apiname}
  end

  # refactored from user controller helper. Also used in user mailer
  def api_profile_url_helper
    return api_profile_url if api_profile_url.to_s =~ /^https?/
    # API SETUP
    return case provider
             when 'facebook' then
               "#{API_URL[provider]}/#{uid}"
             when 'flickr' then
               "#{API_URL[:flickr]}people/#{uid}"
             when 'foursquare' then
               "#{API_URL[provider]}/user/#{uid}"
             when 'google_oauth2' then
               "#{API_URL[provider]}#{uid}/posts"
             else
               nil
           end
  end # api_profile_url_helper


  def currency_with_text
    return nil unless currency
    m = Money::Currency.table.find { |a| a[0] == currency.downcase.to_sym }
    return nil unless m
    "#{m[1][:iso_code]} #{m[1][:name]}".first(CURRENCY_LOV_LENGTH)
  end

  # currency_with_text

  # has user granted app privs wall postings?
  # information is copied to session after login
  def post_on_wall_authorized?
    permissions = self.permissions
    return false if API_GIFT_PICTURE_STORE[provider] == nil # readonly api: google+ and instagram
    return true if permissions.to_s == 'write' # flickr and twitter
    # API SETUP - keep comment for source code search when adding new provider
    case provider
      when "facebook"
        if !permissions
          logger.debug2 "Found #{provider} user without permissions. post_login_#{provider} method must have failed"
          return false
        end
        if permissions.class == Array
          # new oauth 2.2 permission array
          return true if permissions.find { |p| p['permission'] == 'publish_actions' and p['status'] == 'granted' }
        else
          # unknown permissions
          logger.debug2 "unknown facebook permissions object #{permissions}"
          false
        end
      when "linkedin"
        permissions.to_s.split(',').index('rw_nus') != nil
      else
        logger.error2 "post_on_wall? not implemented for #{provider}"
        logger.error2 "API_GIFT_PICTURE_STORE[provider] = #{API_GIFT_PICTURE_STORE[provider]}, permissions = #{permissions}"
        false
    end # case
  end

  # post_on_wall_authorized?


  # post_on_wall privs. have been moved to session.
  # User.post_on_wall_authorized? has been moved to app controller - see get_post_on_wall_authorized(nil)
  # def self.post_on_wall_authorized? (users)
  #   return false unless [Array, ActiveRecord::Relation::ActiveRecord_Relation_User].index(users.class) and users.length > 0
  #   users.each do |user|
  #     next unless API_POST_PERMITTED[user.provider]
  #     return true if user.post_on_wall_authorized?
  #   end
  #   false
  # end # self.post_on_wall_authorized?


  # has user authorized and enabled post on wall?
  # used in Picture.self.find_picture_store
  # todo: post_on_wall privs. have been moved to session. Move post_on_wall_allowed? to applicationController
  # def post_on_wall_allowed?
  #   post_on_wall_yn == 'Y' and post_on_wall_authorized?
  # end
  # def self.post_on_wall_allowed? (login_users)
  #   return false if login_users.size == 0 or login_users.size == 1 and login_users.first.dummy_user?
  #   login_users.each do |login_user|
  #     return true if login_user.post_on_wall_allowed?
  #   end
  #   return false
  # end

  # post_on_wall privs. have been moved to session.
  # class method Picture.find_picture_store should be moved to application controller
  # move class method User.post_image_allowed? to application controller
  # def self.post_image_allowed? (login_users)
  #   (Picture.find_picture_store(login_users) != nil)
  # end # post_image_allowed?

  # "permissions"=>{"data"=>[{"installed"=>1, "basic_info"=>1, "read_stream"=>1, "publish_actions"=>1, "photo_upload"=>1, "video_upload"=>1, "create_note"=>1 ...
  def read_gifts_allowed?
    permissions = self.permissions
    case provider
      when 'facebook'
        return true if permissions.find { |p| p['permission'] == 'read_stream' and p['status'] == 'granted'}
        false
      else
        logger.error2 "read_wall_allowed? not implemented for #{provider} users"
        false
    end
  end

  # read_gifts_allowed?

  # post_on_wall privs. have been moved to session. WRITE_ON_WALL_* ruby constants and get_write_on_wall_action have been moved to application controller

  # write on api wall helpers
  # WRITE_ON_WALL_YES = 1
  # WRITE_ON_WALL_NO = 2
  # WRITE_ON_WALL_MISSING_PRIVS = 3

  # def get_write_on_wall_action
  #   # check user privs before post in provider wall
  #   # that is user.permissions and user.post_on_wall_yn settings
  #   if post_on_wall_authorized?
  #     # user has authorized post on provider wall
  #     if post_on_wall_yn != 'Y'
  #       logger.debug2 "User has authorized post on #{provider} but has selected not to post on #{provider} wall"
  #       return User::WRITE_ON_WALL_NO
  #     end
  #     # write priv ok - continue with post on provider wall
  #     return User::WRITE_ON_WALL_YES
  #   else
  #     # user has not authorized post on provider wall
  #     if post_on_wall_yn == 'Y'
  #       # inject link to authorize post on provider wall
  #       return User::WRITE_ON_WALL_MISSING_PRIVS
  #     else
  #       logger.debug2 "Ignore post_on_#{provider}. User has not authorzed post on #{provider} wall and has also selected not to post on #{provider} wall"
  #       return User::WRITE_ON_WALL_NO
  #     end
  #   end
  # end # check_write_on_wall_privs


  # relation helpers
  def offers
    ApiGift.where('user_id_giver = ? and provider = ?', user_id, provider).includes(:gift)
  end

  def wishes
    ApiGift.where('user_id_receiver = ? and provider = ?', user_id, provider).includes(:gift)
  end

  def gifts_given
    offers.find_all { |ag| (ag.user_id_receiver and ag.gift.price and ag.gift.price != 0.00 and !ag.gift.deleted_at) }
  end

  # gifts_given
  def gifts_received
    wishes.find_all { |ag| (ag.user_id_giver and ag.gift.price and ag.gift.price != 0.00 and !ag.gift.deleted_at) }
  end

  #def gifts_received_with_sign
  #  gifts_received.collect do |g|
  #    g.new_price = -g.new_price
  #    g
  #  end # collect
  #end # gifts_received_with_sig
  def gifts_given_and_received
    gifts_given + gifts_received
  end

  # find app friends. instance method for actual user and class method for logged in users
  def app_friends
    Friend.where("user_id_giver = ?", user_id).includes(:friend).find_all do |f|
      # logger.debug2  "user_id_receiver = #{f.user_id_receiver}, api_friend = #{f.api_friend}, app_friend = #{f.app_friend}"
      if f.app_friend == 'Y'
        true
      elsif f.app_friend == nil and f.api_friend == 'Y'
        true
      else
        false
      end
    end # find all
  end

  # app_friends

  # return all friends for login_users - no filters on
  def self.friends (login_users, user_categories = [1, 2])
    return [] if login_users.size == 0
    return [] if login_users.size == 1 and login_users.first.dummy_user?
    login_user_ids = login_users.collect { |login_user| login_user.user_id }
    logger.debug2 "find friends1"
    if user_categories.uniq == [6]
      friends1 = []
    else
      friends1 = User.where(:user_id => Friend.select('user_id_receiver').where(:user_id_giver => login_user_ids))
    end
    logger.debug2 "find friends2"
    if user_categories.index(6)
      friends2 = friends2 = User.where(:user_id => Friend.select('user_id_receiver').where(:user_id_giver => Friend.select('user_id_receiver').where(:user_id_giver => login_user_ids)))
    else
      friends2 = []
    end
    logger.debug2 "merge friends1 and friends2"
    friends = (friends1+friends2).uniq
    friends = User.define_sort_by_user_name(friends)
    logger.debug2 "done"
    friends
  end

  # self.friends

  # friends categories:
  # 1) logged in user
  # 2) mutual friends         - show detailed info
  # 3) follows (F)            - show few info
  # 4) stalked by (S)         - show few info
  # 5) deselected api friends - show few info
  # 6) friends of friends     - show few info
  # 7) friend proposals       - show few info
  def self.app_friends (login_users, user_categories = [1, 2]) # 1: logged in users + 2: mutual friends
    # login_users_text = login_users.collect { |u| "#{u.user_id} #{u.short_user_name}"}.join(', ')
    logger.debug2 "User.app_friends - start. user_categories = #{user_categories}"
    friends = User.friends(login_users, user_categories).find_all do |u|
      friend = user_categories.index(u.friend?(login_users))
      # logger.debug2 "#{f.friend.user_id} #{f.friend.short_user_name} is " + (friend ? '' : 'not ') + "friend with login users " + login_users_text
      friend
    end
    logger.debug2 "User.app_friends - end"
    User.define_sort_by_user_name(friends)
  end

  # self.app_friends

  # find number of app friends. instance method for actual user and class method for logged in users
  # show special messages to user if no app friends was found
  #def no_app_friends
  #  return @no_app_friends if @no_app_friends
  #  @no_app_friends = app_friends.size
  #end
  def self.no_app_friends (login_users)
    no_app_friends = 0
    login_users.each do |login_user|
      no_app_friends += login_user.friends_hash.find_all { |key, value| value <= 2 }.size
    end
    no_app_friends
  end

  # cross api friends search - compare friend lists across multiple api providers
  # used in users/index?friends=find and in batch notifications
  # compare friends categories 2 and 3 with friends categories 4, 6 and 7
  # match non friends on user_name or on share_account_id
  # note that any shared accounts is added to login_users array
  def self.find_friends (login_users, options = {})
    # add shared accounts before friends find
    logger.debug2 "login_users.size = #{login_users.size}"
    login_users = User.add_shared_accounts(login_users, [2,3,4])
    logger.debug2 "login_users.size = #{login_users.size}"
    # check friend cache (user.friends_hash)
    users_without_cache = login_users.find_all { |u| !u.friends_hash }
    if users_without_cache.size > 0
      # cache friends info
      User.cache_friend_info(users_without_cache)
      login_users.each do |u1|
        next if u1.friends_hash
        u2 = users_without_cache.find { |u3| u3.user_id == u1.user_id }
        u1.friends_hash = u2.friends_hash
      end
    end
    # find friends
    friends = users3 = User.app_friends(login_users, [2, 3])
    friend_names = friends.collect { |u| u.user_name }.uniq
    friend_user_comb = friends.collect { |u| u.share_account_id }.delete_if { |uc| !uc }.uniq
    # compare with non friends
    users = User.app_friends(login_users, [4, 6, 7]).find_all do |u|
      (friend_names.index(u.user_name) or
          (u.share_account_id and friend_user_comb.index(u.share_account_id)))
    end
    # add any old friends proposal from previous find_friends searches (friends? == 7) done by login users friends
    # ( friends proposals have been inserted in friends table with api_friend = 'P' )
    old_user_ids = users.collect { |u| u.user_id }
    new_user_ids = []
    login_users.each do |login_user|
      next unless login_user.friends_hash
      login_user.friends_hash.each do |friend_user_id, friend|
        next unless friend == 7
        new_user_ids << friend_user_id unless old_user_ids.index(friend_user_id)
      end
    end
    logger.debug2 "new_user_ids = #{new_user_ids}"
    users += User.where(:user_id => new_user_ids) if new_user_ids.size > 0
    # update timestamp for last friends find - only notification once a week
    login_users.each do |user|
      user.last_friends_find_at = Time.now
      user.save!
    end
    # insert reverse search result in friends table as api_friend = 'P' (proposal)
    # allows find_friends for other users even if login users does not shared account
    users.each do |receiver|
      giver = login_users.find { |u| u.provider == receiver.provider }
      f1 = Friend.where('user_id_giver = ? and user_id_receiver = ?', giver.user_id, receiver.user_id).first
      if !f1
        f1 = Friend.new
        f1.user_id_giver = giver.user_id
        f1.user_id_receiver = receiver.user_id
      end
      f1.api_friend = 'P' unless f1.api_friend == 'Y'
      f2 = Friend.where('user_id_giver = ? and user_id_receiver = ?', receiver.user_id, giver.user_id).first
      if !f2
        f2 = Friend.new
        f2.user_id_giver = receiver.user_id
        f2.user_id_receiver = giver.user_id
      end
      f2.api_friend = 'P' unless f2.api_friend == 'Y'
      transaction do
        f1.save!
        f2.save!
      end if f1.new_record? or f2.new_record? or f1.api_friend_changed? or f2.api_friend_changed?
    end
    users
  end

  # self.find_friends

  # batch task for friends find - only relevant for multi user login or shared accounts find friends batch task for friends find notifications
  # without users param - started as post login task after single user login - batch notification in gofreerev and to facebook/email
  # with user param - called from util.new_messages_count for multi user login - auto friends search for login users - online notification in Gofreerev only
  # rules:
  # 1) only friends find for active users. last_login_at >= 3.month.ago
  # 2) use last_login_at as start offset starting with first friends find search two weeks after last login
  # called from util.new_messages_count
  def self.find_friends_batch (login_users = [])
    begin
      if login_users.size == 0
        batch_notification = true
        # started as post login task after single user login
        # api notifications for facebook. email notification otherwise
        # send internal Gofreerev and facebook/email notification to one user
        # find one random user and check for friends proposals
        # find with user combination
        login_user = User.where('share_account_id is not null ' +
                              'and last_login_at > ? ' +
                              'and last_friends_find_at < ?',
                          FIND_FRIENDS_LAST_LOGIN.ago, FIND_FRIENDS_LAST_NOTI.ago).shuffle.first
        if login_user
          # user with share accounts - dynamic friends proposal check - compare friends lists across APIs
          login_users = User.where('share_account_id = ?', login_user.share_account_id)
          friends_proposals = User.find_friends(login_users)
        else
          # find without user combination - pending friends proposals are already stored on friends table with api_friend == 'P'
          login_users = User.where('share_account_id is null and last_login_at is not null ' +
                                 'and last_login_at > ? ' +
                                 'and last_friends_find_at < ?',
                             FIND_FRIENDS_LAST_LOGIN.ago, FIND_FRIENDS_LAST_NOTI.ago).includes(:friends)
          # check for "unread" friends proposals
          login_users.delete_if do |login_user|
            if login_user.friends.find { |f| f.api_friend == 'P' }
              # friends proposal was found - keep user in array
              false
            else
              # friends proposal was not found - next check in two weeks - remove user from array
              login_user.update_attribute :last_friends_find_at, Time.now
              true
            end
          end # delete_if
          login_user = login_users.shuffle.first
          return unless login_user # no users with pending friends proposals was found
          friends_proposals = login_user.friends.find_all { |f| f.api_friend == 'P' }.collect { |f| f.friend }
        end
      else
        # from called from util.new_messages_count for multi user login - online notifications in Gofreerev only
        batch_notification = false
        friends_proposals = User.find_friends(login_users)
      end
      return unless friends_proposals.size > 0

      # "send" internal gofreerev notifications (internal = Y)
      noti_key_prefix = 'friends_find_'
      # delete any old unread gofreerev notifications
      to_user_ids = login_users.collect { |u| u.user_id }
      Notification.where(:to_user_id => to_user_ids, :noti_read => 'N', :internal => 'Y').each do |n|
        n.destroy if n.noti_key.first(noti_key_prefix.length) == noti_key_prefix
      end
      noti_key = "#{noti_key_prefix}#{friends_proposals.size <= 3 ? friends_proposals.size : 'n'}_v1"
      noti_options = {:no_users => friends_proposals.size,
                      :no_other_users => (friends_proposals.size-2),
                      :username1 => friends_proposals[0].user_name,
                      :username2 => (friends_proposals.size >= 2 ? friends_proposals[1].user_name : nil),
                      :username3 => (friends_proposals.size >= 3 ? friends_proposals[2].user_name : nil)}
      notification_user = nil
      login_users.each do |login_user|
        n = Notification.new
        n.to_user_id = login_user.user_id
        n.from_user_id = nil
        n.internal = 'Y'
        n.noti_key = noti_key
        n.noti_options = noti_options
        n.noti_read = 'N'
        n.save!
        login_user.update_attribute :last_friends_find_at, Time.now # next friends find in two weeks
        notification_user = login_user if login_user.provider == 'facebook'
      end
      return unless batch_notification
      notification_user = login_users.shuffle.first unless notification_user

      # external notification.
      # - FB notification if one of the "login" users is a FB user.
      # - Email notification if no FB "login" user or FB notifications has not been set up.
      # - sent external mail is saved in Notification with internal = 'N'

      # do not send friends suggestions to inactive Gofreerev users
      return if notification_user.last_login_at < FIND_FRIENDS_LAST_LOGIN.ago #

      # development environment - special filter - notifications is only send to selected users
      if !FORCE_SSL and !FIND_FRIENDS_DEV_USERIDS.index(notification_user.user_id)
        # raise "cannot send friends suggestion to #{notification_user.debug_info} in development environment. check ENV['GOFREEREV_DEV_EN_USERIDS'])"
        return ['.not_dev_user', {:user => notification_user.debug_info}]
      end

      if notification_user.provider == 'facebook'
        # FB notifications
        if API_TOKEN[:facebook]
          language = notification_user.language || BASE_LANGUAGE
          href = '/'
          template = I18n.t "inbox.index.#{noti_key}_to_msg", noti_options.merge(:locale => language)
          # RestClient is using SSLv3 as default and facebook has disabled SSLv3 (SSLv3 POODLE vulnerability)
          # res = RestClient.post "https://graph.facebook.com/#{fb_user.uid}/notifications",
          #                       :href => href, :template => template, :access_token => API_TOKEN[:facebook], :ref => "friends_find"
          res = RestClient::Request.execute :method => :post,
                                            :url => "https://graph.facebook.com/#{notification_user.uid}/notifications",
                                            :payload => {:href => href, :template => template, :access_token => API_TOKEN[:facebook], :ref => "friends_find"},
                                            :ssl_version => 'SSLv23'
          res = YAML::load(res)
          if res.class == Hash and res.has_key?("success") and res["success"] == true
            # success. fb notification sent
            # signature from FB notification:
            # Started POST "/?fb_source=notification&fb_ref=friends_find&ref=notif&notif_t=app_notification" for 127.0.0.1 at 2014-04-02 07:48:09 +0200
            # User Load (5.5ms)  SELECT "users".* FROM "users" WHERE (user_id in ('1705481075/facebook'))
            # CACHE (0.1ms)  SELECT "users".* FROM "users" WHERE (user_id in ('1705481075/facebook'))
            # Processing by FacebookController#create as HTML
            # Parameters: {"signed_request"=>"6xbhSI-JNpGOf7Ye54gft7kF4Tmxdr0AQVA0Iy0hw34.eyJhbGdvcml0aG0iOiJITUFDLVNIQTI1NiIsImV4cGlyZXMiOjEzOTY0MjIwMDAsImlzc3VlZF9hdCI6MTM5NjQxNzY4Mywib2F1dGhfdG9rZW4iOiJDQUFGalpCR3p6T2tjQkFQUGoyakJtVTc2UkxkODFjcG0xSTVqMDlZcWNZNjFSOFRwYnRoa3l0QlNkb0JoalNrQWh0UFBhaTN3VmlCekZRM2dsb1pCVUtxTVhXV0tlTkVqeVk3U2pOTXJRZXUzWkI4MVRoVEhwTEtBZzMyRzlLaVpCaFpCR1pBbEdROFpBQThnN3R5aDZVREpRS0pqY3dnek52djZqaE9lR00yUlUyTEk1MkZDWkFIZUJaQWdSWVVWZXVTRHNzamdrYjVKcTNBWkRaRCIsInVzZXIiOnsiY291bnRyeSI6ImRrIiwibG9jYWxlIjoiZW5fR0IiLCJhZ2UiOnsibWluIjoyMX19LCJ1c2VyX2lkIjoiMTcwNTQ4MTA3NSJ9", "fb_locale"=>"en_GB", "fb_source"=>"notification", "fb_ref"=>"friends_find", "ref"=>"notif", "notif_t"=>"app_notification"}
            return
          elsif res.class == Hash and res.has_key?("error") and options = res["error"] and options.class == Hash
            # error fb notification not sent
            options["code"] = nil unless options["code"]
            options["type"] = nil unless options["type"]
            options["message"] = nil unless options["message"]
            return ['.fb_error', options]
          else
            # unexcepted (error) response from facebook
            logger.warn2 "res = #{res}"
            return ['fb_other', {:response => res.to_s}]
          end
        else
          logger.warn2 "facebook app token was not found"
          logger.debug2 "Use api_server = Koala::Facebook::RealtimeUpdates.new :app_id => API_ID[:facebook], :secret => API_SECRET[:facebook] request to get a facebook application token"
          logger.debug2 "application token must be stored in environment variable. See /config/initializers/omniauth.rb"
          # continue with email notification
        end
      end # if facebook user

      # email notification.
      email = notification_user.share_account.email if notification_user.share_account
      if !email
        logger.debug2 "no email address for #{notification_user.debug_info}. Friends suggestions not send"
        return nil
      end
      # check Unsubscribe before sending email
      us = Unsubscribe.where('email = ? and user_id is null', email).first
      if us
        logger.debug2 "email #{email} has been unsubscribed. Friends suggestions not send"
        return nil
      end
      login_users.each do |login_user|
        us = Unsubscribe.where('email = ? and user_id = ?', email, login_user.user_id).first
        if us
          logger.debug2 "email to #{email} from user id #{login_user.user_id} has been unsubscribed. Friends suggestions not send"
          return nil
        end
      end

      # save email  meta information on a special friends_find external notification
      # extra information in this speciel notification: email, password + list of "login" users
      # email: checked in unsubscribe and inserted in unsubscribe table
      # password: check in unsubscribe. Only allow unsubscribe if email has been send to user
      # login users: inserted into unsubscribe table
      # friends proposals: links inserted into email
      noti_options[:email] = notification_user.share_account.email
      noti_options[:password] = String.generate_random_string(20)
      noti_options[:login_users] = login_users.collect { |login_user| login_user.user_id }.join(',')
      noti_options[:friends_proposals] = friends_proposals.collect { |login_user| login_user.user_id }.join(',')
      n = Notification.new
      n.to_user_id = notification_user.user_id
      n.from_user_id = nil
      n.internal = 'N' # hide in inbox
      n.noti_key = noti_key
      n.noti_options = noti_options
      n.noti_read = 'Y' # no new message count
      n.save!
      logger.debug2 "n.id = #{n.id}"

      # send email - language in mail is selected from noti_options[:login_users] - user.language
      locale = I18n.locale
      UserMailer.friends_suggestions(n).deliver
      I18n.locale = locale

      nil
    rescue => e
      logger.debug2 "Exception: #{e.message.to_s} (#{e.class})"
      logger.debug2 "Backtrace: " + e.backtrace.join("\n")
      raise
    end
  end  # self.find_friends_batch

  # friends information is used many different places
  # cache friends information once and for all in @users array (user.friends_hash)
  # friends categories:
  # 1) logged in user
  # 2) mutual friends         - show detailed info
  # 3) follows (F)            - show few info
  # 4) stalked by (S)         - show few info
  # 5) deselected api friends - show few info
  # 6) friends of friends     - show few info
  # 7) friend proposals       - show few info
  # 8) others                 - not clickable user div - for example comments from other login providers
  def self.cache_friend_info (login_users)
    return if login_users.size == 0
    user_ids = login_users.collect { |u| u.user_id }
    # get friends. split in 4 categories. Y: mutual friends, F: follows, S: Stalked by, N: not app friend
    # P: friends proposal is treated as others/non friends
    # logger.debug2 "get friends. user_ids = #{user_ids.join(', ')}"
    users_app_friends = {'Y' => [], 'F' => [], 'S' => [], 'N' => [], 'P' => []}
    friends = Friend.where("user_id_giver in (?)", user_ids)
    friends.each do |f|
      friend_status_code = f.friend_status_code
      users_app_friends[friend_status_code] = [] unless users_app_friends.has_key?(friend_status_code)
      users_app_friends[friend_status_code] << f.user_id_receiver # save userids in Y, F, S and N arrays
    end
    # logger.debug2 "get friends of mutual friends"
    friends_of_friends_ids = Friend.
        where('user_id_giver in (?)', users_app_friends['Y']).
        find_all { |f| (f.app_friend || f.api_friend) == 'Y' }.
        collect { |f| f.user_id_receiver }
    # 7) friends proposal is a special category of 6) friends og friends
    users_app_friends['P'].delete_if { |user_id| !friends_of_friends_ids.index(user_id) }
    # logger.debug2 "friends proposals = #{users_app_friends['P']}"
    friends_of_friends_ids = friends_of_friends_ids - users_app_friends['P']
    friends_hash = {}
    login_users.each do |user|
      friends_hash[user.provider] = {}
    end
    # loop for each friend category
    # Y: mutual friends, F: follows, S: Stalked by, N: not app friend, P: friends proposal
    [[1, user_ids], [2, users_app_friends['Y']], [3, users_app_friends['F']], [4, users_app_friends['S']],
     [5, users_app_friends['N']], [6, friends_of_friends_ids], [7, users_app_friends['P']]].each do |x|
      friends_category, friends_user_ids = x
      friends_user_ids.each do |user_id|
        provider = user_id.split('/').last
        friends_hash[provider][user_id] = friends_category unless friends_hash[provider].has_key?(user_id)
      end # friends_user_ids
    end
    # copy friends_hash to users array
    login_users.each do |user|
      user.friends_hash = friends_hash[user.provider]
    end
    login_users
  end

  # cache_friend_info


  # recalculate user balance
  # currency and balance is not updated if one or more exchange rates are missing
  # missing exchange rates is put in queue for bank and looked up batch
  # batch job started at after returning actual page to user
  def recalculate_balance
    if !last_login_at
      # never calculate balance for non app users
      logger.warn2 "recalculate_balance method should not be called for non app user #{debug_info}"
      return true
    end
    # find user(s)
    if share_account_id
      # find all closed deals for this user combination
      user_ids = User.where('share_account_id = ?', share_account_id).collect { |user| user.user_id }
    else
      # find all closed deals for this user
      user_ids = [user_id]
    end
    # find closed deals
    api_gifts = ApiGift.where('user_id_giver in (?) and user_id_receiver is not null or ' +
                                  'user_id_receiver in (?) and user_id_giver is not null',
                              user_ids, user_ids).includes(:gift)
    # remove closed deals without a price and remove delete marked deals
    api_gifts = api_gifts.find_all do |api_gift|
      (api_gift.user_id_giver and api_gift.gift.price and api_gift.gift.price != 0.00 and !api_gift.gift.deleted_at)
    end
    # remove closed deals with user(s) as giver AND receiver
    api_gifts = api_gifts.delete_if do |api_gift|
      (user_ids.index(api_gift.user_id_giver) and user_ids.index(api_gift.user_id_receiver))
    end
    # sort: 1 received_at, 2 id
    api_gifts = api_gifts.sort_by { |ag| [ag.gift.received_at, ag.gift.id] }
    # delete gift doublets
    old_gift_id = -1
    api_gifts = api_gifts.delete_if do |api_gift|
      if api_gift.gift.id == old_gift_id
        true
      else
        old_gift_id = api_gift.gift.id
        false
      end
    end # delete_if

    user_balance_hash = {BALANCE_KEY => 0.0} # BASE_CURRENCY
    user_negative_interest_hash = {BALANCE_KEY => 0.0} # BASE_CURRENCY (USD)
    missing_exchange_rates = false
    logger.debug2 "user #{self.short_user_name}. #{api_gifts.size} gifts"
    previous_date = nil
    date = nil
    exchange_rates_hash = {} # used as help variables for exchange rate gains/losses calculation in view
    api_gifts.each do |api_gift|
      # update user.balance hash and save balance in gift.balance for documentation
      # previous balance >= 0 - use FACTOR_POS_BALANCE_PER_DAY to calculate new price
      # previous balance < 0 - use FACTOR_NEG_BALANCE_PER_DAY to calculate new price
      # note a small problem as balance in BASE_CURRENCY is a sum of different currencies and sum changes when currency rates changes
      # balance in BASE_CURRENCY can change between >= 0 and < 0 in period between two deals
      # but only previous balance is used when selection negative interest rate
      balance_doc_hash = {}
      previous_date = api_gift.gift.received_at.to_date unless previous_date
      previous_balance_hash = user_balance_hash.clone
      balance_doc_hash[:previous_balance] = previous_balance_hash
      if previous_date != api_gift.gift.received_at.to_date
        # save old exchange rates for exchange rate difference calculation
        user_balance_hash.keys.each do |balance_hash_currency|
          next if balance_hash_currency == BALANCE_KEY
          exchange_rates_hash[balance_hash_currency] = ExchangeRate.exchange(1.0, BASE_CURRENCY, balance_hash_currency, previous_date)
        end
      end
      previous_exchange_rates_hash = exchange_rates_hash.clone
      balance_doc_hash[:previous_exchange_rates] = previous_exchange_rates_hash
      # logger.debug2  "balance_doc_hash[:previous_balance] = #{balance_doc_hash[:previous_balance]}"
      balance_doc_hash[:previous_date] = previous_date.to_yyyymmdd
      # balance_doc_hash[:number_of_days] = (g.received_at.to_date - previous_date).to_i

      # step 1 - calculate negative interest from previous gift to this gift
      # use FACTOR_POS_BALANCE_PER_DAY for positive balance - 0.9998594803001535 per day <=>  5 % per year
      # use FACTOR_NEG_BALANCE_PER_DAY for negative balance - 0.9997113827109777 per day <=> 10 % per year
      balance_sum = user_balance_hash[BALANCE_KEY] # current user balance in BASE_CURRENCY (USD)
      date = previous_date
      while (date < api_gift.gift.received_at.to_date) do
        date = 1.day.since(date)
        factor = (balance_sum >= 0 ? FACTOR_POS_BALANCE_PER_DAY : FACTOR_NEG_BALANCE_PER_DAY) # 5 OR 10 % in negative interest
        balance_sum = 0.0
        user_balance_hash.keys.each do |balance_hash_currency|
          next if balance_hash_currency == BALANCE_KEY
          user_balance_hash[balance_hash_currency] *= factor
          exchange_rate = ExchangeRate.exchange(1.0, balance_hash_currency, BASE_CURRENCY, date)
          balance_sum += user_balance_hash[balance_hash_currency] * exchange_rate
          exchange_rates_hash[balance_hash_currency] = 1.0 / exchange_rate if date == api_gift.gift.received_at.to_date
        end # each
      end # while
      user_balance_hash[BALANCE_KEY] = balance_sum
      # initialize negative interest hash
      logger.debug2 "gift id #{api_gift.id}: initialize and save negative interest hash"
      gift_negative_interest_hash = {}
      user_balance_hash.keys.each do |balance_hash_currency|
        next if balance_hash_currency == BALANCE_KEY
        gift_negative_interest = (previous_balance_hash[balance_hash_currency] - user_balance_hash[balance_hash_currency]).abs
        logger.debug2 "gift id #{api_gift.id}, currency = #{balance_hash_currency}, old = #{previous_balance_hash[balance_hash_currency]}, new = #{user_balance_hash[balance_hash_currency]}, neg.int. = #{gift_negative_interest}"
        gift_negative_interest_hash[balance_hash_currency] = gift_negative_interest
        user_negative_interest_hash[balance_hash_currency] = 0.0 unless user_negative_interest_hash.has_key?(balance_hash_currency)
        user_negative_interest_hash[balance_hash_currency] += gift_negative_interest
      end
      balance_sum = 0.0
      gift_negative_interest_hash.keys.each do |balance_hash_currency|
        balance_sum += ExchangeRate.exchange(gift_negative_interest_hash[balance_hash_currency], balance_hash_currency, BASE_CURRENCY, previous_date)
      end
      gift_negative_interest_hash[BALANCE_KEY] = balance_sum
      balance_doc_hash[:exchange_rates] = exchange_rates_hash
      balance_doc_hash[:negative_interest] = gift_negative_interest_hash
      previous_date = date

      # step 2: calculate previous_balance + negative_interest hash
      # used for exchange rate gains/losses calculation in view
      #previous_balance_neg_int_hash = {}
      #previous_balance_hash.keys.each do |balance_hash_currency|
      #  next if balance_hash_currency == BALANCE_KEY
      #  previous_balance_neg_int_hash[balance_hash_currency] = previous_balance_hash[balance_hash_currency] + gift_negative_interest_hash[balance_hash_currency]
      #end
      #balance_doc_hash[:previous_balance_and_negative_interest] = previous_balance_neg_int_hash

      # step 3 - new balance with this gift
      sign = user_ids.index(api_gift.user_id_giver) ? 1 : -1
      user_balance_hash[api_gift.gift.currency] = 0.0 unless user_balance_hash.has_key?(api_gift.gift.currency)
      user_balance_hash[api_gift.gift.currency] += api_gift.gift.price * sign
      user_balance_hash[BALANCE_KEY] += ExchangeRate.exchange((api_gift.gift.price*sign), api_gift.gift.currency, BASE_CURRENCY, date)
      balance_doc_hash[:sign] = sign > 0 ? '+' : '-'
      balance_doc_hash[:balance] = user_balance_hash

      # save balance and balance documentation
      api_gift.gift.set_balance(user_ids, user_balance_hash[BALANCE_KEY], balance_doc_hash)
      # g.save
      logger.debug2 "recalculate_balance. gift.id = #{api_gift.gift.id}, gift.received_at = #{api_gift.gift.received_at}, balance_hash = #{user_balance_hash.to_s}, balance_doc_hash = #{balance_doc_hash}"
    end # each
    return false if missing_exchange_rates # error - one or more missing currency rates
    today = Date.parse(Sequence.get_last_exchange_rate_date)
    if date
      # calculate negative interest from last gift and up to "today"
      # "today" as last date with known exchange rates from default money bank
      previous_balance_hash = user_balance_hash.clone
      while (date < today) do
        date = 1.day.since(date)
        factor = (user_balance_hash[BALANCE_KEY] >= 0 ? FACTOR_POS_BALANCE_PER_DAY : FACTOR_NEG_BALANCE_PER_DAY)
        balance_sum = 0.0
        user_balance_hash.keys.each do |balance_hash_currency|
          next if balance_hash_currency == BALANCE_KEY
          user_balance_hash[balance_hash_currency] *= factor
          balance_sum += ExchangeRate.exchange(user_balance_hash[balance_hash_currency], balance_hash_currency, BASE_CURRENCY, date)
        end # each
        user_balance_hash[BALANCE_KEY] = balance_sum
      end
      user_balance_hash.keys.each do |balance_hash_currency|
        user_negative_interest_hash[balance_hash_currency] = 0.0 unless user_negative_interest_hash.has_key?(balance_hash_currency)
        user_negative_interest_hash[balance_hash_currency] += (previous_balance_hash[balance_hash_currency] - user_balance_hash[balance_hash_currency])
      end
    end
    logger.debug2 "user balance = #{user_balance_hash}"
    logger.debug2 "user negative_interest #{user_negative_interest_hash}"
    # calculation ok - all needed exchange rates was found
    self.balance = user_balance_hash
    self.balance_at = today
    self.negative_interest = user_negative_interest_hash
    # todo: catch any exception and return false if transaction fails
    Gift.check_gift_and_api_gift_rel
    transaction do
      api_gifts.each do |api_gift|
        logger.debug2 "api gift id = #{api_gift.id}"
        api_gift.gift.save!
      end
      if user_ids.size > 1
        # user with shared accounts -
        User.where(:user_id => (user_ids - [self.user_id])).each do |other_user|
          other_user.balance = user_balance_hash
          other_user.balance_at = today
          other_user.negative_interest = user_negative_interest_hash
          other_user.save!
        end # each other_user
      end # if
      self.save!
    end
    true
  end

  # recalculate_balance

  def self.recalculate_balance (login_users)
    users = login_users.sort_by { |u| u.share_account_id || 0 }
    # user.share_account_id is used to combine accounts across multiple login providers
    # keep one login_user for each share_account_id for balance calculation
    # keep all users without share_account_id
    old_share_account_id = -1
    users = users.find_all do |user|
      if user.share_account_id
        if user.share_account_id == old_share_account_id
          false # skip user with doublet share_account_id
        else
          old_share_account_id = user.share_account_id
          true # keep first user for share_account_id
        end
      else
        true # keep all users without share_account_id
      end
    end
    # recalculate
    users.each { |user| user.recalculate_balance }
  end

  # self.recalculate_balance

  # ajax task - used when recalculation balance for friends with old balance
  # added to task queue in /shared/user_div partial
  def self.recalculate_balance_task (id)
    begin
      u = User.find(id)
      return unless u # error
      return unless u.last_login_at # ignore non app users
      return if u.balance_at == Date.parse(Sequence.get_last_exchange_rate_date) # has already been calculated
      u.recalculate_balance
      nil # ignore problem with currency rates
    rescue => e
      logger.debug2 "Exception: #{e.message.to_s} (#{e.class})"
      logger.debug2 "Backtrace: " + e.backtrace.join("\n")
      raise
    end
  end

  # self.recalculate_balance_task

  def balance_with_2_decimals
    '%0.2f' % (balance[BALANCE_KEY] || 0)
  end

  # sort_by_user_name
  def self.define_sort_by_user_name (users)
    users.define_singleton_method :sort_by_user_name do
      self.sort_by { |u| [u.camelized_user_name, u.id] }
    end # sort_by_user_name
    users
  end

  # get friend record from login users cached list of friends
  def get_friend (login_user)
    return nil unless login_user
    login_user.friends.find_all { |f| f.user_id_receiver == self.user_id }.first
  end

  # get_friend

  # reverse friend record is identical with friend record except for app_friend = R, P and B
  def get_reverse_friend (login_user)
    return @reverse_friend if defined?(@reverse_friend)
    @reverse_friend = Friend.where("user_id_giver = ? and user_id_receiver = ?", self.user_id, login_user.user_id).first
  end

  # simple friend check from friends_hash cache. Initialized in fetch_user / cache_friend_info in app. controller
  # 1) logged in user
  # 2) mutual friends         - show detailed info
  # 3) follows (F)            - show few info
  # 4) stalked by (S)         - show few info
  # 5) deselected api friends - show few info
  # 6) friends of friends     - show few info
  # 7) friends proposals      - not clickable user div 
  # 8) others                 - not clickable user div - for example comments from other login providers
  def friend? (login_users)
    # logger.debug2  "login_users.class = #{login_users.class}"
    return 8 unless [Array, ActiveRecord::Relation::ActiveRecord_Relation_User].index(login_users.class) # not logged in
    # logger.debug2  "login_users.size = #{login_users.size}"
    return 8 if login_users.size == 0 # not logged in
    return 8 if login_users.first.dummy_user?
    login_user = login_users.find { |user| user.provider == self.provider }
    return 8 unless login_user
    if !login_user.friends_hash
      logger.warn2 "no friends cache was found for login user #{login_user.debug_info}"
      return 8
    end
    return login_user.friends_hash[user_id] || 8
  end

  # friend?

  # friend status code. "this" is friend. login_user is login user.
  #   Y - friends
  #   F - follows
  #   S - is stalked by
  #   N - not friends
  #   A - login api friends and not app friends
  #   G - gofreerev app friends and not login api friends (api friend = N)
  #   H - gofreerev app friends and not login api friends (api friend = F)
  #   I - gofreerev app friends and not login api friends (api friend = S)
  #   R - app friendship request from login user to friend
  #   P - pending app friendship request to login user from friend (todo)
  #   M - my account == friends
  #   D - my account == friends & delete account in progress
  # code is used for friend_status_text_<code> translate key
  def friend_status_code (login_user)
    return 'N' unless login_user # not logged in user
    if login_user.user_id == self.user_id
      if login_user.deleted_at
        return 'D' # my account - delete in progress
      else
        return 'M' # my account
      end
    end
    f = get_friend(login_user)
    return 'N' unless f
    return f.app_friend if %w(R P B).index(f.app_friend) # app friendship request or blocked user
    if f.api_friend == 'Y'
      # api friend
      case f.app_friend
        when nil then
          return 'Y' # api and app friends
        when 'Y' then
          return 'Y' # api and app friends
        when 'N' then
          return 'A' # user has been deselected as app friend by login user
      end # case
    elsif f.api_friend == 'F'
      # login user follows friend
      case f.app_friend
        when nil then
          return 'F' # login user follows friend
        when 'Y' then
          return 'H' # app friends + follower
        when 'N' then
          return 'F' # user has been deselected as app friend by login user
      end # case
    elsif f.api_friend == 'S'
      # login user is stalked by friend
      case f.app_friend
        when nil then
          return 'S' # login user is stalked by friend
        when 'Y' then
          return 'I' # app friend + stalker
        when 'N' then
          return 'S' # user has been deselected as app friend by login user
      end # case
    else
      # non api friend
      case f.app_friend
        when nil then
          return 'N' # not api and not app friend
        when 'Y' then
          return 'G' # not login api friends - only friends within gofreerev app
        when 'N' then
          return 'N' # user has been deselected as app friend by login user
      end # case
    end
  end

  def friend_status_translate_code (login_users)
    login_user = login_users.find { |u| u.provider == self.provider }
    if !login_user
      logger.error2 'Invalid friend_status_translate_code call. Cross provider friends are not allowed. ' +
                        "Login users = #{User.debug_info(login_users)}. user = #{debug_info}}"
      return '.friend_status_text_n'
    end
    code = friend_status_code(login_user).downcase
    logger.debug2 "code = #{code}"
    ".friend_status_text_#{code}"
  end

  # friend_status_translate_code

  def find_friend_request_noti (login_user)
    ns = Notification.where("from_user_id = ? and to_user_id = ? and noti_read = 'N'", login_user.user_id, self.user_id)
    return nil unless ns.size > 0
    n = ns.find { |n| n.noti_key == FRIEND_REQUEST_NOTI_KEY }
  end

  # find_friend_request_noti

  # returns list with allowed friendship actions: add_api_friend, remove_api_friend, send_app_friend_request, cancel_app_friend_request, accept_app_friend_request, ignore_app_friend_request, remove_app_friend, block_app_user, unblock_app_user
  # used in users/show page / users/friend_action_buttons partial
  # The action names is also used as keys in translate. See <language>.users.friend_action_buttons.<method>
  # first letter uppercase - confirm box before submit
  # second letter uppercase - new window (target=_blank)
  def friend_status_actions (login_user_or_login_users)
    if login_user_or_login_users.class == User
      login_user = login_user_or_login_users
    elsif [Array, ActiveRecord::Relation::ActiveRecord_Relation_User].index(login_user_or_login_users.class)
      login_user = login_user_or_login_users.find { |u| u.provider == self.provider }
    end
    if login_user.class != User
      logger.error2 "Invalid call. expected user or array of users. login_user_or_login_users = #{login_user_or_login_users} (#{login_user_or_login_users.class})"
      raise "debug - stackdump"
      return []
    end
    return [] if login_user.deleted_at
    return [] if login_user.disconnected_shared_account
    return [] unless last_login_at # never logged in - do not show any friend action
    case friend_status_code(login_user)
      # dropped add/remove api friend bottoms
      #when 'Y' then return %w(rEmove_api_friend Remove_app_friend)
      #when 'N' then return %w(aDd_api_friend send_app_friend_request)
      #when 'A' then return %w(rEmove_api_friend send_app_friend_request)
      #when 'G' then return %w(aDd_api_friend Remove_app_friend)
      #when 'R' then return %w(aDd_api_friend send_app_friend_request cancel_app_friend_request)
      #when 'P' then return %w(aDd_api_friend accept_app_friend_request ignore_app_friend_request block_app_user)
      #when 'B' then return %w(unblock_app_user)
      when 'Y' then
        return %w(Remove_app_friend)
      when 'N' then
        return %w(send_app_friend_request)
      when 'F' then
        return %w(send_app_friend_request)
      when 'S' then
        return %w(send_app_friend_request)
      when 'A' then
        return %w(send_app_friend_request)
      when 'G' then
        return %w(Remove_app_friend)
      when 'H' then
        return %w(Remove_app_friend)
      when 'I' then
        return %w(Remove_app_friend)
      when 'R' then
        return %w(send_app_friend_request cancel_app_friend_request)
      when 'P' then
        return %w(accept_app_friend_request ignore_app_friend_request block_app_user)
      when 'B' then
        return %w(unblock_app_user)
      else
        logger.error2 "Unknown friend_status_code #{friend_status_code(login_user)}"
        return []
    end
  end

  # friend_status_actions
  def allowed_friend_status_action (login_user, action)
    allowed_friend_actions = friend_status_actions(login_user).collect { |fa| fa.downcase }
    allowed = allowed_friend_actions.index(action.to_s)
    logger.debug2 "action #{action} was not allowed. Friend status code = #{friend_status_code(login_user)}, allowed actions = #{allowed_friend_actions.join(', ')}" if  !allowed
    allowed
  end

  def add_api_friend (login_user)
    return unless allowed_friend_status_action(login_user, __method__)
    raise "not used. no facebook api dialog to add friend"
  end

  def remove_api_friend (login_user)
    return unless allowed_friend_status_action(login_user, __method__)
    raise "not used. no facebook api dialog to remove friend"
  end

  def send_app_friend_request (login_user)
    # set api_friend = R for login user, set api_friend = P for friend
    return false unless allowed_friend_status_action(login_user, __method__)
    f = get_friend (login_user)
    if !f
      f = Friend.new
      f.user_id_giver = login_user.user_id
      f.user_id_receiver = self.user_id
      f.api_friend = 'N'
    end
    r = get_reverse_friend(login_user)
    if !r
      r = Friend.new
      r.user_id_giver = f.user_id_receiver
      r.user_id_receiver = f.user_id_giver
      r.api_friend = f.api_friend
    end
    f.app_friend = 'R'
    if r.app_friend != 'B' # friend request from blocked users is ignored silently
      r.app_friend = 'P'
      # don't add new notification if previously request_for_app_friendship has not been read
      n = find_friend_request_noti(login_user)
      if !n
        n = Notification.new
        n.to_user_id = self.user_id
        n.from_user_id = login_user.user_id
        n.internal = 'Y'
        # Be careful when renaming or deleting altering keys in noti_options hash.
        # you may run into problems displaying old and new notification format
        # Consider creating a new version of request_for_app_friendship key if you renames or deletes noti_options hash keys
        n.noti_key = FRIEND_REQUEST_NOTI_KEY
        n.noti_options = {:from_user => login_user.user_name, :from_id => login_user.id,
                          :to_user => self.user_name, :to_id => self.id,
                          :appname => APP_NAME}
        n.noti_read = 'N'
      end
    end
    f.save!
    r.save!
    n.save! if n
    true
  end

  # send_app_friend_request
  def cancel_app_friend_request (login_user)
    return false unless allowed_friend_status_action(login_user, __method__)
    f = get_friend (login_user)
    r = get_reverse_friend(login_user)
    if f.api_friend == 'Y'
      f.app_friend = 'N'
    else
      f.app_friend = nil
    end
    if !r
      # error - r should exists - create missing record
      r = Friend.new
      r.user_id_giver = f.user_id_receiver
      r.user_id_receiver = f.user_id_giver
      r.api_friend = f.api_friend
    end
    if r.app_friend == 'P'
      if r.api_friend == 'Y'
        r.app_friend = 'N'
      else
        r.app_friend = nil
      end
    end
    n = find_friend_request_noti(login_user)
    f.save!
    r.save!
    n.destroy if n
    true
  end

  # cancel_app_friend_request
  def accept_app_friend_request (login_user)
    # set api_friend = Y for login user and friend
    return false unless allowed_friend_status_action(login_user, __method__)
    f = get_friend (login_user)
    r = get_reverse_friend(login_user)
    raise "invalid request" if !f or !r or f.app_friend != 'P' or r.app_friend != 'R'
    f.app_friend = 'Y'
    r.app_friend = 'Y'
    n = Notification.new
    n.to_user_id = self.user_id
    n.from_user_id = login_user.user_id
    n.internal = 'Y'
    # Be careful when renaming or deleting altering keys in noti_options hash.
    # you may run into problems displaying old and new notification format
    # Consider creating a new version of app_friendship_accepted key if you renames or deletes noti_options hash keys
    n.noti_key = 'app_friendship_accepted_v1'
    n.noti_options = {:from_user => login_user.short_user_name, :from_id => login_user.id,
                      :to_user => self.short_user_name, :to_id => self.id,
                      :appname => APP_NAME}
    n.noti_read = 'N'
    f.save!
    r.save!
    n.save!
    true
  end

  # accept_app_friend_request
  def ignore_app_friend_request (login_user)
    return false unless allowed_friend_status_action(login_user, __method__)
    f = get_friend (login_user)
    if f.api_friend == 'Y'
      f.app_friend = 'N'
    else
      f.app_friend = nil
    end
    f.save!
    true
  end

  def remove_app_friend (login_user)
    return false unless allowed_friend_status_action(login_user, __method__)
    f = get_friend (login_user)
    if !f
      f = Friend.new
      f.user_id_giver = login_user.user_id
      f.user_id_receiver = self.user_id
      f.api_friend = 'N'
    end
    r = get_reverse_friend(login_user)
    if !r
      r = Friend.new
      r.user_id_giver = f.user_id_receiver
      r.user_id_receiver = f.user_id_giver
      r.api_friend = f.api_friend
    end
    f.app_friend = 'N'
    r.app_friend = 'N' unless r.app_friend == 'B'
    f.save!
    r.save!
    true
  end

  # remove_app_friend
  def block_app_user (login_user)
    return false unless allowed_friend_status_action(login_user, __method__)
    f = get_friend (login_user)
    f.app_friend = 'B'
    f.save!
    true
  end

  def unblock_app_user (login_user)
    return unless allowed_friend_status_action(login_user, __method__)
    f = get_friend (login_user)
    if f.api_friend == 'Y'
      f.app_friend = 'N'
    else
      f.app_friend = nil
    end
    f.save!
  end


  #def inbox_new_notifications
  #  raise "debug - maybe no longer used"
  #  return @new_notifications if defined?(@new_notifications)
  #  return @new_notifications = nil if User.dummy_users?(@users)
  #  notifications = Notification.where("to_user_id = ? and noti_read = 'N'", self.user_id)
  #  # don't count notifications for deleted or delete marked gifts
  #  notifications = notifications.find_all do |noti|
  #    giftid = noti.noti_options[:giftid]
  #    if giftid
  #      # gift/comment notification. Check if gift has been deleted or delete marked.
  #      gift = Gift.find_by_id(giftid)
  #      gift and !gift.deleted_at
  #    else
  #      # other notifications
  #      true
  #    end
  #  end
  #  if notifications.length > 0
  #    @new_notifications = notifications.length
  #  else
  #    @new_notifications = nil
  #  end
  #end # inbox_new_notifications

  # return nil if no notification - return number of notifications
  def self.inbox_new_notifications (login_users)
    # check cache (first user in user array)
    n = login_users.first.cache_new_notifications
    return (n == 0 ? nil : n) if n
    return nil if login_users.length == 0 # error
    return nil if login_users.first.dummy_user? # not logged in
    # lookup number of new notifications
    login_user_ids = login_users.collect { |user| user.user_id }
    notifications = Notification.where("to_user_id in (?) and noti_read = 'N'", login_user_ids)
    # don't count notifications for deleted or delete marked gifts
    notifications = notifications.find_all do |noti|
      giftid = noti.noti_options[:giftid]
      if giftid
        # gift/comment notification. Check if gift has been deleted or delete marked.
        gift = Gift.find_by_id(giftid)
        gift and !gift.deleted_at
      else
        # other notifications
        true
      end
    end
    n = login_users.first.cache_new_notifications = notifications.length
    (n == 0 ? nil : n)
  end

  # self.inbox_new_notifications

  # refresh user permisssions
  # called in error handling after picture upload with ApiPostNotFoundException error
  # see api_gifts/create
  def get_permissions_facebook(api_client)
    api_request = 'me?fields=permissions'
    logger.debug2 "api_request = #{api_request}"
    begin
      api_response = api_client.get_object(api_request)
    rescue Koala::Facebook::ClientError => e
      e.logger = logger
      e.puts_exception("#{__method__}: ")
      raise
    end # rescue
    logger.debug2 "api_response = #{api_response}"
    self.permissions = api_response['permissions']['data']
    save!
    self
  end

  # get_api_permissions

  # as instance method gifts, but extended to be used for multiple provider logins
  # last_status_update_at & limit are used from gifts/index to return first row (http request) or next 10 rows (ajax request)
  # newest_gift_id, newest_status_update_at & include_delete_marked_gifts are used from util/new_messages_count to
  # return new gifts, changed gifts, delete marked gifts to gifts/index page in ajax request
  def self.api_gifts (login_users, options = {})
    # get param
    last_status_update_at = options[:last_status_update_at] || 2147483647 # status_update_at for last gift in gifts/index page
    limit = options[:limit] # number of rows to return to gifts/index page (1 for http and 10 for ajax)
    newest_gift_id = options[:newest_gift_id] || 0 # newest gift id when gifts/index page was last updated
    newest_status_update_at = options[:newest_status_update_at] || 0 # newest status_update_at when gifts/index page was last updated
    include_delete_marked_gifts = options[:include_delete_marked_gifts] || false # used in util/new_message_count to remove deleted gifts from gifts/index page
    # dump params
    logger.debug2 "login_users.size            = #{login_users.size}"
    logger.debug2 "last_status_update_at       = #{last_status_update_at}"
    logger.debug2 "limit                       = #{limit}"
    logger.debug2 "newest_gift_id              = #{newest_gift_id}"
    logger.debug2 "newest_status_update_at     = #{newest_status_update_at}"
    logger.debug2 "include_delete_marked_gifts = #{include_delete_marked_gifts}"
    # validate params
    unless [Array, ActiveRecord::Relation::ActiveRecord_Relation_User].index(login_users.class) and
        login_users.length > 0 and
        !login_users.first.dummy_user?
      logger.error2 "Invalid call. expected array of login users"
      return [[], nil]
    end
    if limit and (newest_gift_id > 0 or newest_status_update_at > 0)
      logger.warn2 ":newest_gift_id and :newest_status_update_at are used in util.new_messages_count to get new, changed and deleted gifts"
      logger.warn2 ":limit should not be used in combination with :newest_gift_id and :newest_status_update_at"
      limit = nil
    end

    # initialize list of gifts
    # list of gifts with @users as giver or receiver + list of gifts med @users.friends as giver or receiver
    # where clause is used for non encrypted fields. find_all is used for encrypted fields

    # find friends from friends_hash (was cached in application_controller.fetch_users / User.cache_friend_info)
    friends_ids = []
    login_users.each do |login_user|
      # logger.debug "friends_ids = #{friends_ids}"
      # logger.debug "friends_hash = #{login_user.friends_hash}"
      friends_ids += login_user.friends_hash.find_all { |key, value| value <= 2 }.collect { |a| a[0] }
    end

    # find api gifts
    if include_delete_marked_gifts
      # called from util.new_messages_count - include delete marked gifts in response
      # delete marked gifts will be ajax replaced with invisible rows
      deleted = ""
    else
      # called from users or gifts controller - to not return delete mark gifts in response
      deleted = ' and gifts.deleted_at is null and api_gifts.deleted_at is null'
    end
    # Use a larger limit in sql statement. correct limit for multi provider login and for hidden gifts
    sql_limit = limit
    if sql_limit
      # correct for multi provider posts
      if sql_limit == 1
        sql_limit = login_users.size
      else
        # 1.50 <=> half of gift post is multi provider posts
        sql_limit = sql_limit * login_users.size * 1.50
      end
      # correct for hidden posts. 1.10 <=> 10 % hidden posts
      sql_limit = sql_limit * 1.10
      sql_limit = sql_limit.ceil
    end

    if newest_gift_id == 0 and newest_status_update_at == 0
      # called from gifts/index page - newest_gift_id and newest_status_update_at are not relevant
      ags = ApiGift.
          where('(user_id_giver in (?) or user_id_receiver in (?)) and status_update_at < ?' + deleted,
                friends_ids, friends_ids, last_status_update_at).
          limit(sql_limit).
          references(:gifts, :api_gifts).
          includes(:gift, :giver, :receiver).
          order('gifts.status_update_at desc')
    else
      # called from util/new_messages_count - limit and last_status_update_at are not relevant
      ags = ApiGift.
          where('(gifts.id > ? or status_update_at > ?) and (user_id_giver in (?) or user_id_receiver in (?))' + deleted,
                newest_gift_id, newest_status_update_at, friends_ids, friends_ids).
          references(:gifts, :api_gifts).
          includes(:gift, :giver, :receiver).
          order('gifts.status_update_at desc')
    end
    # execute query now
    ags = ags.to_a
    # check for eod - end of data
    if newest_gift_id == 0 and newest_status_update_at == 0
      eod = (!sql_limit or sql_limit and ags.size < sql_limit)
    else
      eod = true
    end
    logger.debug2 "sql_limit = #{sql_limit}, ags.size = #{ags.size}, eod = #{eod}"

    return [ags, nil] if ags.size == 0 # no (more) rows
    if eod
      new_last_status_update_at = nil
    else
      new_last_status_update_at = ags.last.gift.status_update_at
    end

    if login_users.size > 1
      # remove any multi provider gift doublets

      # multiple logins - find and remove any doublet gifts
      # priority:
      # 1) sort by status_update_at desc (also order by condition in select statement)
      # 2) closed gift before open gift
      # 3) sort not delete marked api gifts before deleted marked api gifts
      # 4) api gift with picture
      # 5) api picture url with error and creator of gift in login_users - recheck picture with login user privs.
      # 6) api gift without picture
      ags = ags.sort_by { |ag| [-ag.gift.status_update_at, ag.status_sort, ag.deleted_at_sort, ag.picture_sort(login_users)] }

      # delete doublets if creator of gift was using multi provider login
      old_size = ags.size
      old_gift_id = -1
      ags.delete_if do |ag|
        if ag.gift.id == old_gift_id
          # remove doublet api gift
          true
        else
          # keep first priority api gift
          # delete mark gift (not saved to db) if api gift has been delete marked
          # ( delete marked api gifts is used for "partial" deleted gift when deleting user account )
          ag.gift.deleted_at = ag.deleted_at if !ag.gift.deleted_at and ag.deleted_at
          old_gift_id = ag.gift.id
          false
        end
      end # delete_if
      new_size = ags.size
      logger.debug2 "removed #{old_size-new_size} doublet api gifts. old size #{old_size}. new size #{new_size}"
      # end - remove any multi provider gift doublets
    end

    # remove any hidden gifts (show=N) from api gifts list
    userids = login_users.collect { |u| u.user_id }
    giftids = ags.collect { |ag| ag.gift_id }
    hide_giftids = GiftLike.
        where("user_id in (?) and gift_id in (?)", userids, giftids).
        find_all { |gl| gl.show == 'N' }.
        collect { |gl| gl.gift_id }.
        uniq
    if hide_giftids.size > 0
      # remove hidden gifts
      logger.debug2 "remove hidden gifts: #{hide_giftids.join(', ')}"
      old_size = ags.size
      ags = ags.find_all { |ag| !hide_giftids.index(ag.gift_id) }
      new_size = ags.size
      logger.debug2 "#{old_size-new_size} hidden gifts was removed. old size = #{old_size}, new_size = #{new_size}"
    end

    return [ags, nil] if eod # no more rows from db

    while ags.size < limit and new_last_status_update_at do
      # too few rows - get more rows - stop when limit is reached or when no more rows in database
      new_limit = limit - ags.size
      logger.debug2 "too few rows. limit = #{limit}, ags.size = #{ags.size}, new limit = #{new_limit}"
      ags2, new_last_status_update_at = User.api_gifts login_users,
                                                       :last_status_update_at => new_last_status_update_at,
                                                       :limit => new_limit,
                                                       :newest_gift_id => newest_gift_id,
                                                       :newest_status_update_at => newest_status_update_at,
                                                       :include_delete_marked_gifts => include_delete_marked_gifts
      ags = ags + ags2
    end

    if ags.size > limit
      # too many rows - return first limit rows
      logger.debug2 "too many rows. limit = #{limit}, ags.size = #{ags.size}, ignore last #{ags.size-limit} rows"
      ags = ags.first(limit)
      return [ags, ags.last.gift.status_update_at]
    end

    # correct number of rows
    logger.debug2 "correct number of rows. limit = #{limit}, last_status_update_at = #{new_last_status_update_at}"
    return [ags, new_last_status_update_at]

    # done
    ags
  end

  # self.gifts


  ## cache mutual friends lookup in @mutual_friends hash index by login_user.id
  ## dropped - not working optimal and too slow
  #def mutual_friends (login_users)
  #  # raise "debug"
  #  raise "invalid call" unless [Array, ActiveRecord::Relation::ActiveRecord_Relation_User].index(login_users.class)
  #  login_user = login_users.find { |user| self.provider == user.provider }
  #  return {} unless login_user
  #  return @mutual_friends[login_user.id] if @mutual_friends and @mutual_friends.has_key?(login_user.id)
  #  @mutual_friends = {} unless @mutual_friends
  #  friends1 = app_friends.collect { |f| f.friend }
  #  friends2 = login_user.app_friends.collect { |f| f.friend }
  #  friends3 = friends1 & friends2
  #  logger.debug2 "user1 = #{short_user_name}, friends1 = " + friends1.collect { |u| u.short_user_name }.join(', ')
  #  logger.debug2 "user2 = #{login_user.short_user_name}, friends2 = " + friends2.collect { |u| u.short_user_name }.join(', ')
  #  logger.debug2 "friends3 = " + friends3.collect { |u| u.short_user_name }.join(', ')
  #  @mutual_friends[login_user.id] = friends3.collect { |u| u.short_user_name }
  #end


  # ajax task. return nil or [key, options] array
  # called twice.
  # First in users/edit page when user account has been marked as deleted - delete mark gifts and comments so that gifts and comments can be ajax removed from gifts/index pages
  # Second after 6 minutes in util/new_messages_count to delete other data and user account
  def self.delete_user(id)
    begin
      user = User.find_by_id(id)
      return ['.delete_user_id_not_found', {}] unless user
      return ['.delete_user_invalid_id', {}] unless user.deleted_at

      # start logical delete
      affected_users = {}
      if user.share_account_id
        old_share_account_id = user.share_account_id
        user.share_account_clear
        ShareAccount.where(:id => old_share_account_id, :no_users => 1).each do |sa|
          user2 = sa.users.first
          sa.destroy
          user2.share_account_clear
        end
      end
      # delete mark gifts
      ApiGift.where('? in (user_id_giver, user_id_receiver)', user.user_id).each do |ag|
        # delete gift or delete api gift
        # check gift has api_gifts from other login providers - ignore dummy users
        g = ag.gift
        api_gifts = g.api_gifts.find_all do |ag2|
          if ag2.id == ag.id
            false
          elsif ag2.giver and ag2.giver.dummy_user?
            false
          elsif ag2.receiver and ag2.receiver.dummy_user?
            false
          else
            true
          end
        end # find_all
        if api_gifts.size == 0
          # no other providers was found for this gift
          # marked as deleted. Will be ajax deleted in gifts/index pages within 5 minutes
          g.deleted_at = Time.new
          g.save!
        else
          # found other providers for this gift.
          # mark api gift as deleted. Gift be ajax removed from gifts/index page if api gift is last api gift for gift in other session.
          ag.deleted_at = Time.new
          ag.save!
        end
        if g.received_at and g.price and g.price != 0.0
          # save gift for notification to affected users (number of gifts, currencies and prices)
          if user.user_id == ag.user_id_giver
            other_user_id = ag.user_id_receiver
            sign = +1
          else
            other_user_id = ag.user_id_giver
            sign = -1
          end
          other_user_id = user.user_id == ag.user_id_giver ? ag.user_id_receiver : ag.user_id_giver
          affected_users[other_user_id] = {:no_gifts => 0} unless affected_users.has_key?(other_user_id)
          affected_users[other_user_id][:no_gifts] += 1
          affected_users[other_user_id][g.currency] = 0 unless affected_users[other_user_id].has_key?(g.currency)
          affected_users[other_user_id][g.currency] += sign * g.price
          #
          # other_user = User.find_by_user_id(other_user_id)
          # if !other_user.dummy_user? and !affected_users.index(other_user_id)
          #   #create_table "notifications", force: true do |t|
          #   #  t.string   "noti_id",      limit: 20, null: false
          #   #  t.string   "to_user_id",   limit: 40, null: false
          #   #  t.string   "from_user_id", limit: 40
          #   #  t.string   "internal",     limit: 1,  null: false
          #   #  t.text     "noti_key",                null: false
          #   #  t.text     "noti_options"
          #   #  t.string   "noti_read",    limit: 1,  null: false
          #   #  t.datetime "created_at"
          #   #  t.datetime "updated_at"
          #   #end
          #   # todo: save information in an notification hash
          #   n = Notification.new
          #   n.to_user_id = other_user_id
          #   n.from_user_id = nil
          #   n.internal = 'Y'
          #   n.noti_key = 'deleted_account_v1'
          #   n.noti_options = user.app_and_apiname_hash.merge(:userid => other_user.id, :username => user.user_name)
          #   n.noti_read = 'N'
          #   n.save!
          #   affected_users << other_user_id
          # end
        end

      end # each ag

      # send notifications to affected users (name of deleted user, number of deleted gifts and change in amount)
      logger.debug2 "send notifications to affected users (name of deleted user, number of deleted gifts and change in amount)"
      logger.debug2 "affected_users = #{affected_users}"
      affected_users.each do |other_user_id, hash|
        other_user = User.find_by_user_id(other_user_id)
        next if other_user.dummy_user?
        #
        other_user.recalculate_balance
        no_gifts = hash.delete(:no_gifts)
        amount = hash.collect { |name, value| "#{name} #{value}" }.sort.join(', ')
        n = Notification.new
        n.to_user_id = other_user_id
        n.from_user_id = nil
        n.internal = 'Y'
        n.noti_key = 'deleted_account_v2'
        n.noti_options = user.app_and_apiname_hash.merge(:userid => other_user.id,
                                                         :username => user.user_name,
                                                         :no_gifts => no_gifts,
                                                         :amount => amount)
        n.noti_read = 'N'
        n.save!
      end # each affected_user

      # delete mark comments
      ApiComment.where('user_id = ? and gifts.deleted_at is not null',
                       user.user_id).includes(:gift, :comment).references(:gift).each do |ac|
        c = ac.comment
        # check if comment has api_comments from other login providers
        api_comments = c.api_comments.find_all { |ac2| ac2.id != ac.id }
        if api_comments.size == 0
          # no other login provider involved for this comment
          # mark comment as deleted - will be ajax removed from gifts/index pages within 5 minutes
          c.deleted_at = Time.new
          c.updated_by = user.user_id
          c.save!
        else
          # other login providers found for this login provider
          # todo: cancel deal proposal if deal proposal and it was made from this and only this provider
          # todo. no deleted_at timestamp for api_comment. Can not ajax remove api comment from gifts/index page
          # mark api comment as deleted. Gift be ajax removed from gifts/index page if api comment is last api comment for comment in other session.
          ac.deleted_at = Time.new
          ac.save!
        end
      end
      # end logical delete

      # check for physical delete
      delete = (Time.new - user.deleted_at > 6.minutes)
      if (delete)
        # start physical delete
        # user account has been deleted marked more than 6 minutes ago
        # physical delete all data for user account
        # repeat twice just in case that new data is created doing delete operation
        # should not happen as update operations are disabled for delete marked users
        1.upto(2) do
          AjaxComment.where('user_id = ?', user.user_id).delete_all
          GiftLike.where('user_id = ?', user.user_id).delete_all
          Notification.where('to_user_id = ? or from_user_id = ?', user.user_id, user.user_id).each do |n|
            n.api_comments.delete # delete rows in comments_notifications table - not comments
            n.delete
          end
          ApiComment.where('user_id = ?', user.user_id).each do |ac|
            ac.delete
            c = Comment.where('comment_id = ?', ac.comment_id).includes(:api_comments).first
            c.delete if c.api_comments.size == 0
          end
          ApiGift.where('user_id_giver = ? or user_id_receiver = ?', user.user_id, user.user_id).each do |ag|
            ag.delete
            g = Gift.where('gift_id = ?', ag.gift_id).includes(:api_gifts).first
            g.delete if g.api_gifts.size == 0
          end
          # delete friends information. keep information about blocked and deselected app friends
          Friend.where('user_id_giver = ?', user.user_id).delete_all
          Friend.where('user_id_receiver = ?', user.user_id).each do |f|
            f.delete unless %w(N B).index(f.app_friend)
          end
          user.delete
          # remove inactive users that is no longer used
          # that is friends of deleted user not used by any other users
          inactive_user_ids = User.all.where('last_login_at is null').find_all { |u| !u.dummy_user? }.collect { |u| u.user_id }
          friend_user_ids = Friend.where('user_id_giver <> user_id_receiver').collect { |u| u.user_id_giver }.uniq
          delete_user_ids = inactive_user_ids - friend_user_ids
          User.where('user_id in (?)', delete_user_ids).each do |u|
            begin
              u.destroy!
            rescue => e
              # write exception and continue cleanup
              logger.debug2 "Could not delete inactive user #{u.debug_info}."
              logger.debug2 "Exception: #{e.message.to_s} (#{e.class})"
              logger.debug2 "Backtrace: " + e.backtrace.join("\n")
            end
          end
        end # 2 loops
        # end physical delete
      end

      # raise "debug issue 37"

      # logical and/or physical delete ok
      nil

    rescue => e
      logger.debug2 "Exception: #{e.message.to_s} (#{e.class})"
      logger.debug2 "Backtrace: " + e.backtrace.join("\n")
      raise
    end
  end

  # self.delete_user


  def share_account_clear
    self.share_account_id = nil
    self.access_token = nil
    self.access_token_expires = nil
    self.save!
  end



  # todo: remove - competition running until 31-dec-2014 - see about/ad1

  # calculate number of points
  def ad1_points (login_users = [])
    if login_users == []
      # called from User.ad1_points with empty login_users array - just return points for current user
      points = 0
      points += 3 if last_login_at # 2 : Log in (3 point)
      points += 2 if ApiGift.where('user_id_giver = ? or user_id_receiver = ?', self.user_id, self.user_id).first # Create post (2 point)
      # check user comments. 5 points if user has commented other posts
      acs = ApiComment.where(:user_id => self.user_id).includes(:gift)
      return points if acs.size == 0
      acs.each do |ac|
        g = ac.gift
        if !g
          logger.warn2 "api comment #{ac.id} without a gift"
          next
        end
        return (points+5) if g.direction == 'both' # ok - 5 point - comment to accepted deal
        ag = g.api_gifts.find { |ag| ag.provider == self.provider }
        if ag
          return (points+5) if ag.user_id_giver    and ag.user_id_giver !=    self.user_id
          return (points+5) if ag.user_id_receiver and ag.user_id_receiver != self.user_id
        end
      end
      # no comments to other users posts was found
      return points
    end
    return nil unless User.logged_in?(login_users)
    friend = self.friend?(login_users)
    return nil if friend > 2 # hide points - not a Gofreerev friend
    return User.ad1_points(login_users) if friend == 1 # user is a login user
    # user is a friend
    User.ad1_points([self])
  end

  # return ad1 points for an array of users
  # for example current login users or a friend
  def self.ad1_points (login_users = [])
    return 0 unless User.logged_in?(login_users)
    # add shared accounts before calculation points
    login_users = User.add_shared_accounts(login_users, [1,2,3,4])
    login_users.collect { |u| u.ad1_points }.sum
  end # self.ad1_points


  # return user array including disconnected shared accounts
  # auth/index page - show information about share levels and accounts
  # find friends - also show friends from not connected API's
  # params:
  #   login_users: @users - array with current login users
  #   filter_share_levels: array with selected share levels 1..4
  #   cache_friends: true/false - cache friend info for added users?
  def self.add_shared_accounts (login_users, filter_share_levels = [2,3,4], cache_friends=false)
    # only relevant for logged in users
    return login_users if !User.logged_in?(login_users)
    # check share accounts and share levels filter
    filter_share_levels = filter_share_levels & [1,2,3,4]
    return login_users if filter_share_levels.size == 0
    share_account_ids = login_users.collect { |u| u.share_account_id }.uniq.find_all { |x| x }
    return login_users if share_account_ids.size == 0 # none shared accounts
    share_accounts = ShareAccount.where(:share_account_id => share_account_ids)
    share_accounts = share_accounts.find_all { |sa| filter_share_levels.index(sa.share_level) }
    return login_users if share_accounts.size == 0 # no shared accounts with selected filter
    share_account_ids = share_accounts.collect { |sa| sa.share_account_id }
    # get shared but disconnected user accounts
    login_user_ids = login_users.collect { |u| u.user_id }
    login_providers = login_users.collect { |u| u.provider }
    other_users = User.where('share_account_id in (?) and user_id not in (?)', share_account_ids, login_user_ids)
    return login_users if other_users.size == 0 # already connected with all relevant share accounts
    other_users = other_users.find_all { |u| !login_providers.index(u.provider) }
    return login_users if other_users.size == 0 # already logged in for all relevant login providers
    # add other disconnected accounts to login_users array
    # logger.debug2 "before clone: users without friends hash: " + login_users.find_all { |u| !u.friends_hash}.collect { |u| u.user_id }.join(', ')
    # # clone login_users array including custom accessor variables
    # login_users_clone = login_users.clone
    # 0.upto(login_users.size-1).each do |i|
    #   login_users_clone[i].new_currency = login_users[i].new_currency
    #   login_users_clone[i].cache_new_notifications = login_users[i].cache_new_notifications
    #   login_users_clone[i].friends_hash = login_users[i].friends_hash
    # end
    # login_users = login_users_clone
    # logger.debug2 "after clone: users without friends hash: " + login_users.find_all { |u| !u.friends_hash}.collect { |u| u.user_id }.join(', ')
    users_without_cache = []
    other_users.each do |u|
      if !login_providers.index(u.provider)
        u.disconnected_shared_account = true
        login_providers << u.provider
        login_users << u
        users_without_cache << u if cache_friends
      end
    end
    if cache_friends
      # cache friends info for added disconnected shared accounts
      User.cache_friend_info(users_without_cache)
      login_users.each do |u1|
        next if u1.friends_hash
        u2 = users_without_cache.find { |u3| u3.user_id == u1.user_id }
        u1.friends_hash = u2.friends_hash
      end
    end
    login_users
  end # self.add_shared_accounts


  ##############
  # encryption #
  ##############

  # https://github.com/jmazzi/crypt_keeper gem encrypts all attributes and all rows in db with the same key
  # this extension to use different encryption for each attribute and each row
  # overwrites non model specific methods defined in /config/initializers/active_record_extensions.rb
  protected
  def encrypt_pk
    self.user_id
  end

  def encrypt_pk=(new_encrypt_pk_value)
    self.user_id = new_encrypt_pk_value
  end

  def new_encrypt_pk
    self.user_id
  end

end # User
