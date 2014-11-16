class ApiGift < ActiveRecord::Base

  #create_table "api_gifts", force: true do |t|
  #  t.string   "gift_id",                     limit: 20
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

  belongs_to :gift, :class_name => 'Gift', :primary_key => :gift_id, :foreign_key => :gift_id
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

  # 1) gift_id - required - not encrypted - readonly
  validates_presence_of :gift_id
  validates_uniqueness_of :gift_id, :scope => :provider
  attr_readonly :gift_id
  before_validation(on: :create) do
    self.gift_id = self.new_encrypt_pk unless self.gift_id
  end
  def gift_id=(new_gift_id)
    return self['gift_id'] if self['gift_id']
    self['gift_id'] = new_gift_id
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


  # return array with 1-3 text fields to be used when posting on api walls
  # called from api_client.gofreerev_post_on_wall singleton methods in application controller (generic_post_on_wall)
  # ( used in generic_post_on_wall in util controller )
  # test:
  #   ag = ApiGift.where('deep_link_id is not null').shuffle.first
  #   no_fields = (rand*3).floor+1
  #   max_lng = [] ; 1.upto(no_fields) do |i| max_lng << (rand*150).floor+1 end ; texts = ag.get_wall_post_text_fields(max_lng) ; puts "description = #{ag.gift.description}\nmax_lng = #{max_lng}\ntexts = #{texts}"
  def get_wall_post_text_fields (is_open_graph, max_lng = [])
    # check param
    # check is_open_graph (true or false). false: return deep link, true: do not return deep link)
    raise InvalidCall.new('is_open_graph must be true or false') unless [TrueClass, FalseClass].index(is_open_graph.class)
    # check max_lng - array with 1-3 text field lengths
    # logger.debug2 "max_lng = #{max_lng}"
    invalid_call = InvalidCall.new('max_lng must be an array of 1-3 positive integers. nil elements are allowed')
    raise invalid_call unless max_lng.class == Array
    raise invalid_call unless max_lng.size >= 1 and max_lng.size <= 3
    max_lng.each do |l|
      next if l.class == NilClass
      raise invalid_call unless l.class == Fixnum
      raise invalid_call unless l == l.round
      raise invalid_call unless l > 0
    end
    # get relevant text fields: direction, description and deep_link
    direction = gift.human_value(:direction)
    direction_lng = direction.size
    description = gift.description
    description_lng = description.size
    deep_link = self.deep_link.clone
    if is_open_graph or !deep_link
      link_separator = ''
      deep_link = nil
      deep_link_lng = 0
    elsif provider == 'twitter' and FORCE_SSL
      link_separator = ' '
      deep_link_lng = 23 # twitter makes special short links
    else
      link_separator = ' - '
      deep_link_lng = deep_link.size
    end
    # logger.debug2 "deep_link_lng = #{deep_link_lng}"
    link_separator_lng = link_separator.size
    # prepare response - one return text field for each lng element (nil elements are allowed) + truncated flag
    res = [nil] * max_lng.size
    truncated_index = max_lng.size
    res[truncated_index] = false
    res_lng = []

    # case 1 - use only one text field when posting on api wall
    res[0] = "#{direction}#{description}#{link_separator}#{deep_link}"
    res_lng[0] = direction_lng + description_lng + link_separator_lng + deep_link_lng
    return res if (!max_lng[0] or res_lng[0] <= max_lng[0])
    if max_lng.size == 1
      if direction_lng + direction_lng + link_separator_lng + deep_link_lng <= max_lng[0]
        # return text with direction and deep link
        text_max_lng = max_lng[0] - direction_lng - link_separator_lng - deep_link_lng
        # logger.debug2 "text_max_lng (a) = #{text_max_lng}"
        description, res[truncated_index] =  Gift.truncate_text provider, description, text_max_lng
        res[0] = "#{direction}#{description}#{link_separator}#{deep_link}"
      elsif direction_lng + link_separator_lng + deep_link_lng <= max_lng[0]
        # return text with deep link
        text_max_lng = max_lng[0] - link_separator_lng - deep_link_lng
        # logger.debug2 "text_max_lng (b) = #{text_max_lng}"
        description, res[truncated_index] =  Gift.truncate_text provider, description, text_max_lng
        res[0] = "#{description}#{link_separator}#{deep_link}"
      elsif direction_lng + direction_lng <= max_lng[0]
        # return text with direction
        text_max_lng = max_lng[0] - direction_lng
        # logger.debug2 "text_max_lng (c) = #{text_max_lng}"
        description, res[truncated_index] = Gift.truncate_text provider, description, text_max_lng
        res[0] = "#{direction}#{description}"
      else
        # return text
        res[0], res[truncated_index] = Gift.truncate_text provider, description, max_lng[0]
      end
      return res
    end

    # case 2 - use field 1 and 2 when posting on api wall
    res[0] = "#{direction}#{description}"
    if res[0].size <= max_lng[0]
      # simple case. Split text between description and deep link
      res[1] = deep_link if (!max_lng[1] or deep_link_lng <= max_lng[1]) # no deep link if max_lng[1] is too smalll
      return res
    end
    # split text
    max_word_lng = 30
    pos = res[0].first(max_lng[0]).rindex(' ')
    if pos and max_lng[0]-pos < max_word_lng
      # slit text - skip space
      res[1] = res[0].from(pos+1)
      res[0] = res[0].first(pos)
    else
      # split word
      res[1] = res[0].from(max_lng[0])
      res[0] = res[0].first(max_lng[0])
    end
    if (!max_lng[1] or res[1].size + link_separator_lng + deep_link_lng <= max_lng[1])
      res[1] += "#{link_separator}#{deep_link}"
      return res
    end
    if max_lng.size == 2
      # truncate res[1] and add deep link
      text_max_lng = max_lng[1] - link_separator_lng - deep_link_lng
      if text_max_lng <= 0
        res[1], res[truncated_index] =  Gift.truncate_text provider, res[1], max_lng[1]
      else
        res[1], res[truncated_index] =  Gift.truncate_text provider, res[1], text_max_lng
        res[1] << "#{link_separator}#{deep_link}"
      end
      return res
    end

    # case 3 - use field 1, 2 and 3 when posting on api wall
    if res[1].size <= max_lng[1] or max_lng[2] and max_lng[2] >= deep_link_lng and max_lng[2] < link_separator_lng + deep_link_lng
      # simple case. Split text between description and deep link
      res[1], res[truncated_index] = res[1].first(max_lng[1]), true if res[1].size > max_lng[1]
      res[2] = deep_link if (!max_lng[2] or deep_link_lng <= max_lng[2]) # no deep link if max_lng[2] is too small
      return res
    end
    # split text
    puts "res[1] = #{res[1]}"
    pos = res[1].first(max_lng[1]).rindex(' ')
    if pos and max_lng[1]-pos < max_word_lng
      # split text - skip space
      res[2] = res[1].from(pos+1)
      res[1] = res[1].first(pos)
    else
      # split word
      res[2] = res[1].from(max_lng[1])
      res[1] = res[1].first(max_lng[1])
    end
    if !max_lng[2] or res[2].size + link_separator_lng + deep_link_lng <= max_lng[2]
      res[2] += "#{link_separator}#{deep_link}"
      return res
    end
    # truncate res[2] and add deep link
    text_max_lng = max_lng[2] - link_separator_lng - deep_link_lng
    puts "3: text_max_lng = #{text_max_lng}"
    if text_max_lng <= 0
      # very small max_lng[2] - skip deep link
      res[2], res[truncated_index] = Gift.truncate_text provider, res[2], max_lng[2]
    else
      res[2], res[truncated_index] = Gift.truncate_text provider, res[2], text_max_lng
      res[2] << "#{link_separator}#{deep_link}"
    end
    res
  end # get_wall_post_text_fields

  # run this test manual a number of times to verify result tests
  def self.test_get_wall_post_text_fields
    ag = ApiGift.where('deep_link_id is not null').shuffle.first
    no_fields = (rand*3).floor+1
    max_lng = []
    1.upto(no_fields) do |i| max_lng << (rand*150).floor+1 end
    texts = ag.get_wall_post_text_fields(max_lng)
    puts "ApiGift id = #{ag.id}\ndescription = #{ag.gift.description}\nmax_lng = #{max_lng}\ntexts = #{texts}"
    texts
  end # self.test_get_wall_post_text_fields


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
    self.gift_id
  end
  def encrypt_pk=(new_encrypt_pk_value)
    self.gift_id = new_encrypt_pk_value
  end
  def new_encrypt_pk
    raise "gift_id must always be initialized as first attribute"
  end


end
