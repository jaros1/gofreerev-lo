class ApiGift < ActiveRecord::Base

  #create_table "api_gifts", force: true do |t|
  #  t.string   "gid",                     limit: 20
  #  t.string   "provider",                    limit: 20
  #  t.string   "user_id_giver",               limit: 40
  #  t.string   "user_id_receiver",            limit: 40
  #  t.string   "picture",                     limit: 1
  #  t.text     "api_gift_id"
  #  t.text     "api_picture_url"
  #  t.text     "api_picture_url_updated_at"
  #  t.text     "api_picture_url_on_error_at"
  #  t.string   "deleted_at_api",              limit: 1
  #  t.datetime "created_at"
  #  t.datetime "updated_at"
  #  t.string   "deep_link_id",                limit: 20
  #  t.text     "deep_link_pw"
  #  t.integer  "deep_link_errors"
  #  t.text     "api_gift_url"
  #end

  belongs_to :gift, :class_name => 'Gift', :primary_key => :gid, :foreign_key => :gid
  belongs_to :giver, :class_name => 'User', :primary_key => :user_id, :foreign_key => :user_id_giver
  belongs_to :receiver, :class_name => 'User', :primary_key => :user_id, :foreign_key => :user_id_receiver

  before_update :before_update


  # https://github.com/jmazzi/crypt_keeper - text columns are encrypted in database
  # encrypt_add_pre_and_postfix/encrypt_remove_pre_and_postfix added in setters/getters for better encryption
  # this is different encrypt for each attribute and each db row
  # _before_type_cast methods are used by form helpers and are redefined
  crypt_keeper :api_gift_id, :api_picture_url, :api_picture_url_updated_at, :api_picture_url_on_error_at, :deep_link_pw,
               :api_gift_url, :encryptor => :aes, :key => ENCRYPT_KEYS[1]


  ##############
  # attributes #
  ##############

  # 1) gid - required - not encrypted - readonly
  validates_presence_of :gid
  validates_uniqueness_of :gid, :scope => :provider
  attr_readonly :gid
  before_validation(on: :create) do
    self.gid = self.new_encrypt_pk unless self.gid
  end
  def gid=(new_gid)
    return self['gid'] if self['gid']
    self['gid'] = new_gid
  end

  # 2) provider - login provider - required - not encrypted - readonly
  validates_presence_of :provider
  validates_inclusion_of :provider, :in => OmniAuth::Builder.providers, :allow_blank => true

  # 3) user_id_giver - FK - not encrypted.
  # validates_presence_of :user_id_giver, :if => Proc.new {|g| (g.received_at or !g.user_id_receiver) }
  validates_each :user_id_giver do |record, attr, value|
    if record.new_record?
      record.errors.add :base, :giver_or_receiver_must_be_blank if value and record.user_id_receiver
      record.errors.add :base, :giver_or_receiver_is_required if !value and !record.user_id_receiver
    elsif record.user_id_giver_was and record.user_id_giver_was != value
      record.errors.add attr, :readonly
    end
  end

  # 4) user_id_receiver - FK - not encrypted. Gift must have a giver or an receiver when created. Must have giver and receiver when closed
  # validates_presence_of :user_id_receiver, :if => Proc.new {|g| (g.received_at or !g.user_id_giver) }
  validates_each :user_id_receiver do |record, attr, value|
    if record.new_record?
      nil if value and record.user_id_giver # error already reported for user_id_giver
      nil if !value and !record.user_id_giver # # error already reported for user_id_giver
    elsif record.user_id_receiver_was and record.user_id_receiver_was != value
      record.errors.add attr, :readonly
    end
  end

  # 5) picture Y/N - String - not encrypted
  validates_presence_of :picture
  validates_inclusion_of :picture, :allow_blank => true, :in => %w(Y N) ;
  validates_each :picture, :allow_blank => true do |record, attr, value|
    record.errors.add attr, :invalid if value == 'Y' and record.api_picture_url.to_s == ""
    record.errors.add attr, :invalid if value == 'N' and record.api_picture_url.to_s != ""
  end

  # 6) api_gift_id - String in model - encrypted text in db - api id for the gift / status update on the wall
  def api_gift_id
    return nil unless (extended_api_gift_id = read_attribute(:api_gift_id))
    encrypt_remove_pre_and_postfix(extended_api_gift_id, 'api_gift_id', 24)
  end
  def api_gift_id=(new_api_gift_id)
    return api_gift_id if self.api_gift_id
    if new_api_gift_id
      check_type('api_gift_id', new_api_gift_id, 'String')
      write_attribute :api_gift_id, encrypt_add_pre_and_postfix(new_api_gift_id, 'api_gift_id', 24)
    else
      write_attribute :api_gift_id, nil
    end
  end # api_gift_id=
  alias_method :api_gift_id_before_type_cast, :api_gift_id
  def api_gift_id_was
    return api_gift_id unless api_gift_id_changed?
    return nil unless (extended_api_gift_id = attribute_was(:api_gift_id))
    encrypt_remove_pre_and_postfix(extended_api_gift_id, 'api_gift_id', 24)
  end # api_gift_id_was

  # 7) api_picture_url - String in Model - encrypted text in db
  validates_presence_of :api_picture_url, :if => Proc.new { |rec| rec.picture? }
  validates_each :api_picture_url, :allow_blank => true do |rec, attr, value|
    rec.errors.add attr, :invalid unless Picture.app_url?(value) or Picture.api_url?(value)
  end
  def api_picture_url
    # logger.debug2  "api_picture_url = #{read_attribute(:api_picture_url)} (#{read_attribute(:api_picture_url).class.name})"
    return nil unless (extended_api_picture_url = read_attribute(:api_picture_url))
    encrypt_remove_pre_and_postfix(extended_api_picture_url, 'api_picture_url', 23)
  end # api_picture_url
  def api_picture_url=(new_api_picture_url)
    # logger.debug2  "api_picture_url = #{new_api_picture_url} (#{new_api_picture_url.class.name})"
    if new_api_picture_url
      check_type('api_picture_url', new_api_picture_url, 'String')
      write_attribute :api_picture_url, encrypt_add_pre_and_postfix(new_api_picture_url, 'api_picture_url', 23)
    else
      write_attribute :api_picture_url, nil
    end
  end # api_picture_url=
  alias_method :api_picture_url_before_type_cast, :api_picture_url
  def api_picture_url_was
    return api_picture_url unless api_picture_url_changed?
    return nil unless (extended_api_picture_url = attribute_was(:api_picture_url))
    encrypt_remove_pre_and_postfix(extended_api_picture_url, 'api_picture_url', 23)
  end # api_picture_url_was

  # 8) api_picture_url_updated_at - timestamp in model - encrypted text
  def api_picture_url_updated_at
    return nil unless (temp_extended_api_picture_url_updated_at = read_attribute(:api_picture_url_updated_at))
    temp_api_picture_url_updated_at = encrypt_remove_pre_and_postfix(temp_extended_api_picture_url_updated_at, 'api_picture_url_updated_at', 21)
    YAML::load(temp_api_picture_url_updated_at)
  end # api_picture_url_updated_at
  def api_picture_url_updated_at=(new_api_picture_url_updated_at)
    if new_api_picture_url_updated_at
      check_type('api_picture_url_updated_at', new_api_picture_url_updated_at, 'Time')
      write_attribute :api_picture_url_updated_at, encrypt_add_pre_and_postfix(new_api_picture_url_updated_at.to_yaml, 'api_picture_url_updated_at', 21)
    else
      write_attribute :api_picture_url_updated_at, nil
    end
  end # api_picture_url_updated_at=
  alias_method :api_picture_url_updated_at_before_type_cast, :api_picture_url_updated_at
  def api_picture_url_updated_at_was
    return api_picture_url_updated_at unless api_picture_url_updated_at_changed?
    return nil unless (temp_extended_api_picture_url_updated_at = attribute_was(:api_picture_url_updated_at))
    temp_api_picture_url_updated_at = encrypt_remove_pre_and_postfix(temp_extended_api_picture_url_updated_at, 'api_picture_url_updated_at', 21)
    YAML::load(temp_api_picture_url_updated_at)
  end # api_picture_url_updated_at_was

  # 9) api_picture_url_on_error_at - timestamp in model - encrypted text (todo) in db
  def api_picture_url_on_error_at
    return nil unless (temp_extended_api_picture_url_on_error_at = read_attribute(:api_picture_url_on_error_at))
    temp_api_picture_url_on_error_at = encrypt_remove_pre_and_postfix(temp_extended_api_picture_url_on_error_at, 'api_picture_url_on_error_at', 22)
    YAML::load(temp_api_picture_url_on_error_at)
  end # api_picture_url_on_error_at
  def api_picture_url_on_error_at=(new_api_picture_url_on_error_at)
    if new_api_picture_url_on_error_at
      check_type('api_picture_url_on_error_at', new_api_picture_url_on_error_at, 'Time')
      write_attribute :api_picture_url_on_error_at, encrypt_add_pre_and_postfix(new_api_picture_url_on_error_at.to_yaml, 'api_picture_url_on_error_at', 22)
    else
      write_attribute :api_picture_url_on_error_at, nil
    end
  end # api_picture_url_on_error_at=
  alias_method :api_picture_url_on_error_at_before_type_cast, :api_picture_url_on_error_at
  def api_picture_url_on_error_at_was
    return api_picture_url_on_error_at unless api_picture_url_on_error_at_changed?
    return nil unless (temp_extended_api_picture_url_on_error_at = attribute_was(:api_picture_url_on_error_at))
    temp_api_picture_url_on_error_at = encrypt_remove_pre_and_postfix(temp_extended_api_picture_url_on_error_at, 'api_picture_url_on_error_at', 22)
    YAML::load(temp_api_picture_url_on_error_at)
  end # api_picture_url_on_error_at_was

  # 10) deleted_at_api. String Y/N.
  validates_inclusion_of :deleted_at_api, :allow_blank => true, :in => %w(Y N)

  # 11) created_at - timestamp - not encrypted

  # 12) updated_at - timestamp - not encrypted
  
  # 13) deep_link_id - String - not encrypted
  
  # 14) deep_link_errors - integer - not encrypted
  
  # 15) deep_link_pw - String in model - Encrypred text in db
  def deep_link_pw
    return nil unless (extended_deep_link_pw = read_attribute(:deep_link_pw))
    encrypt_remove_pre_and_postfix(extended_deep_link_pw, 'deep_link_pw', 38)
  end
  def deep_link_pw=(new_deep_link_pw)
    if new_deep_link_pw
      check_type('deep_link_pw', new_deep_link_pw, 'String')
      write_attribute :deep_link_pw, encrypt_add_pre_and_postfix(new_deep_link_pw, 'deep_link_pw', 38)
    else
      write_attribute :deep_link_pw, nil
    end
  end
  alias_method :deep_link_pw_before_type_cast, :deep_link_pw
  def deep_link_pw_was
    return deep_link_pw unless deep_link_pw_changed?
    return nil unless (extended_deep_link_pw = attribute_was(:deep_link_pw))
    encrypt_remove_pre_and_postfix(extended_deep_link_pw, 'deep_link_pw', 38)
  end # deep_link_pw_was
  
  # 16) deep_link_errors - integer 
  
  # 17) api_gift_url - url to post on api wall - String in model - encrypted text in db
  def api_gift_url
    return nil unless (extended_api_gift_url = read_attribute(:api_gift_url))
    encrypt_remove_pre_and_postfix(extended_api_gift_url, 'api_gift_url', 42)
  end
  def api_gift_url=(new_api_gift_url)
    if new_api_gift_url
      check_type('api_gift_url', new_api_gift_url, 'String')
      write_attribute :api_gift_url, encrypt_add_pre_and_postfix(new_api_gift_url, 'api_gift_url', 42)
    else
      write_attribute :api_gift_url, nil
    end
  end
  alias_method :api_gift_url_before_type_cast, :api_gift_url
  def api_gift_url_was
    return api_gift_url unless api_gift_url_changed?
    return nil unless (extended_api_gift_url = attribute_was(:api_gift_url))
    encrypt_remove_pre_and_postfix(extended_api_gift_url, 'api_gift_url', 42)
  end # api_gift_url_was


  # helper methods
  def gift_with_placeholders
    g = gift
    g.giver = self.giver
    g.receiver = self.receiver
    g.picture = self.picture
    g
  end # gift_with_placeholders

  # 1 for closed api gift - 2 for open api gift - used in sort before removing api gift doubles. Used in User.api_gifts sort
  def status_sort
    user_id_giver and user_id_receiver ? 1 : 2
  end # status_sort

  # 1 for picture with error url and creator in login_users
  # 2 for picture
  # 3 for without picture
  # used in sort before removing api gift doubles. Used in User.api_gifts sort
  def picture_sort (login_users)
    return 3 unless picture?
    return 2 unless api_picture_url_on_error_at
    # find picture with error marked url - could be missing privs or maybe picture has been deleted on wall
    # sort picture created by login user before other pictures
    if user_id_giver and user_id_receiver
      comment = gift.api_comments.find { |c| c.accepted_yn == 'Y' }
      creator = comment.user_id == user_id_giver ? user_id_receiver : user_id_giver
    else
      creator = user_id_giver || user_id_receiver
    end
    return 1 if login_users.find { |user| user.user_id == creator } # picture created by login user(s)
    2
  end # picture_sort

  # sort not delete marked api gifts before delete marked api gifts
  # used in User.api_gifts
  # ( api gift is used to partial delete gift when user account is logical deleted. See User.delete_user)
  def deleted_at_sort
    deleted_at ? 2 : 1
  end

  # for ajax show-more-rows functionality
  # api_gift can be a little random for users with multi provider login (see User.api_gift)
  # use api_gift.gift.id for last_row_id in ajax expanding pages (gifts/index and users/show balance tab)
  def last_row_id
    gift.id
  end

  def picture?
    (picture == 'Y')
  end

  public
  def self.http_get (url, timeout=30, max_redirects=3, return_url=false)
    xstarttime = Time.new
    while max_redirects > 0
      # get header
      response = nil
      begin

        # support for https - see http://stufftohelpyouout.blogspot.com/2010/05/how-to-fix-nethttpbadresponse-wrong.html
        url_obj = URI.parse(url)
        http = Net::HTTP.new(url_obj.host, url_obj.port)
        http.use_ssl = true if url =~ /^https/
        http.read_timeout=timeout
        lpath = url_obj.path
        lpath = "/" if lpath.to_s == ""
        lpath = "#{lpath}?#{url_obj.query}" unless url_obj.query.to_s == ""
        request = Net::HTTP::Get.new(lpath, {"User-Agent" => "Mozilla/5.0 (X11; U; Linux i686; en-US; rv:1.9.2.23) Gecko/20110921 Ubuntu/10.04 (lucid) Firefox/3.6.23"})
        response = http.start {|http| http.request(request) }

      rescue => e
        xmessage = e.message.to_s
        raise HttpRequestTimeOut("Timeout after #{timeout} seconds") if xmessage == "execution expired"
        logger.error2 "Exception = #{xmessage} (#{e.class})"
        raise
      end # begin

      # check response
      case response
        when Net::HTTPOK
          return (return_url ? url : response)
        when Net::HTTPRedirection
          # redirection - continue loop
          url = response['location']
          max_redirects = max_redirects - 1
        else
          # unexpected response
          logger.warn2 "response.class = #{response.class}, response.code = #{response.code}"
          return (return_url ? url : response)
      end # case

    end # while
    raise HttpRedirection.new("More than #{max_redirects} redirections")

  end # http_get



  # helpers for deep link - that is deep link from api wall to gift on gofreerev without login
  def self.new_deep_link_id (provider)
    deep_link_id = nil
    loop do
      deep_link_id = String.generate_random_string(20)
      deep_link_id.downcase! if provider == 'facebook'
      break unless ApiGift.find_by_deep_link_id(deep_link_id)
    end
    deep_link_id
  end
  def init_deep_link ()
    self.deep_link_id = ApiGift.new_deep_link_id(provider)
    self.deep_link_pw = String.generate_random_string(10)
    self.deep_link_pw.downcase! if provider == 'facebook'
    self.deep_link_errors = 0
    self.save!
    "#{SITE_URL}#{I18n.locale}/gifts/#{self.deep_link_id}#{self.deep_link_pw}"
  end
  def deep_link_invalid?
    # deep link check not working in WEBrick / development (single threaded server)
    return nil unless Rails.application.config.cache_classes
    link = deep_link()
    return 'No deep link' unless link
    begin
      response = ApiGift.http_get(link)
    rescue HttpRequestTimeOut => e
      return e.message
    rescue Net::ReadTimeout => e
      return e.message
    end
    return nil if response.class == Net::HTTPOK
    # error in deep link page
    logger.error2 "error in deep link page #{link}"
    logger.error2 "link_res.class = #{response.class}"
    error = $1 if response.body.to_s =~ /<h2>(.*?)<\/h2>/
    if error
      logger.error2 "error = #{error}"
    else
      logger.error2 "link_res.body = #{response.body}"
      error = response.class.to_s
    end
    error
  end
  def deep_link
    return nil unless deep_link_id and deep_link_pw
    "#{SITE_URL}#{I18n.locale}/gifts/#{self.deep_link_id}#{self.deep_link_pw}"
  end
  def clear_deep_link
    self.deep_link_id = self.deep_link_pw = self.deep_link_errors = nil
    self.save!
  end


  def apiname
    API_DOWNCASE_NAME[provider] || provider
  end

  # used in many translates
  def app_and_apiname_hash
    { :appname => APP_NAME,
      :apiname => apiname }
  end


  def before_update
    if !deleted_at_was and deleted_at
      # api gift has been delete marked in User.delete_user (partial delete gift when deleting user account)
      # update gift.status_update_at so that gift will be ajax updated or deleted in other browser sessions
      gift.status_update_at = Sequence.next_status_update_at
      gift.save!
    end # if
  end # before_update


  # https://github.com/jmazzi/crypt_keeper gem encrypts all attributes and all rows in db with the same key
  # this extension to use different encryption for each attribute and each row
  # overwrite non model specific methods defined in /config/initializers/active_record_extensions.rb
  protected
  def encrypt_pk
    self.gid
  end
  def encrypt_pk=(new_encrypt_pk_value)
    self.gid = new_encrypt_pk_value
  end
  def new_encrypt_pk
    raise "gid must always be initialized as first attribute"
  end


end
