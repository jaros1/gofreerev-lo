class Gift < ActiveRecord::Base

  # https://github.com/jmazzi/crypt_keeper - text columns are encrypted in database
  # encrypt_add_pre_and_postfix/encrypt_remove_pre_and_postfix added in setters/getters for better encryption
  # this is different encrypt for each attribute and each db row
  # _before_type_cast methods are used by form helpers and are redefined
  crypt_keeper :received_at, :encryptor => :aes, :key => ENCRYPT_KEYS[1]

  ##############
  # attributes #
  ##############

  # 1) gid - required - not encrypted - readonly
  validates_presence_of :gid
  validates_uniqueness_of :gid
  attr_readonly :gid
  before_validation(on: :create) do
    self.gid = self.new_encrypt_pk unless self.gid
  end
  def gid=(new_gid)
    return self['gid'] if self['gid']
    self['gid'] = new_gid
  end

  # 7) received_at. Date in model - encrypted text in db - set once when the deal is closed together with user_id_receiver
  def received_at
    return nil unless (temp_extended_received_at = read_attribute(:received_at))
    temp_received_at1 = encrypt_remove_pre_and_postfix(temp_extended_received_at, 'received_at', 5)
    temp_received_at2 = YAML::load(temp_received_at1)
    temp_received_at2 = temp_received_at2.to_time if temp_received_at2.class.name == 'Date'
    temp_received_at2
  end # received_at
  def received_at=(new_received_at)
    if new_received_at
      check_type('received_at', new_received_at, 'Time')
      write_attribute :received_at, encrypt_add_pre_and_postfix(new_received_at.to_yaml, 'received_at', 5)
    else
      write_attribute :received_at, nil
    end
  end # received_at=
  alias_method :received_at_before_type_cast, :received_at
  def received_at_was
    return received_at unless received_at_changed?
    return nil unless (temp_extended_received_at = attribute_was('received_at'))
    temp_received_at1 = encrypt_remove_pre_and_postfix(temp_extended_received_at, 'received_at', 5)
    temp_received_at2 = YAML::load(temp_received_at1)
    temp_received_at2 = temp_received_at2.to_time if temp_received_at2.class.name == 'Date'
    temp_received_at2
  end # received_at_was

  # 8) new_price_at - date - not encrypted - almost always = today

  # 21) deleted_at_api. String Y/N.

  # 22) status_change_at - integer - not encrypted - keep track of gifts changed after user has loaded gifts/index page

  # 26) created_at - timestamp - not encrypted

  # 27) updated_at - timestamp - not encrypted



  #
  # helper methods
  #


  def visible_for? (users)
    if ![Array, ActiveRecord::Relation::ActiveRecord_Relation_User].index(users.class)
      return false
    elsif users.length == 0
      return false
    elsif deleted_at
      return false
    else
      # check if user is giver or receiver
      api_gifts.each do |api_gift|
        user = users.find { |user2| user2.provider == api_gift.provider }
        next unless user
        return true if [api_gift.user_id_receiver, api_gift.user_id_giver].index(user.user_id)
      end
      # check if giver or receiver is a friend
      api_gifts.each do |api_gift|
        user = users.find { |user2| user2.provider == api_gift.provider }
        next unless user
        return true if user.app_friends.find { |f| [api_gift.user_id_receiver, api_gift.user_id_giver].index(f.user_id_receiver) }
      end
    end
    false
  end # visible_for


  # return last 4 comments for gifts/index page if first_comment_id is nil
  # return next 10 old comments in ajax request ii first_comment_id is not null
  # used in gifts/index (html/first_comment_id == nil) and in comments/comments (ajax/first_comment_id != nil)
  def api_comments_with_filter (login_users, first_comment_id = nil)
    # keep one api comment for each comment (multi provider comments).
    # sort:
    # 1) comments from friends
    # 2) comments from friends of friends (clickable user div)
    # 3) random sort
    logger.debug2 "get comments for gift id #{id}. sort"
    acs = api_comments
    .includes(:user,:comment)
    .where('comments.deleted_at is null')
    .references(:comments)
    .sort_by { |ac| [ ac.user.friend?(login_users), ac.comment.id, rand ]}
    # keep one api comment for each comment
    logger.debug2 "get comments for gift id #{id}. remove doubles"
    old_comment_id = '#' * 20
    acs = acs.find_all do |ac|
      if ac.comment_id == old_comment_id
        false
      else
        old_comment_id = ac.comment_id
        true
      end
    end
    # sort by created at
    # acs = acs.sort { |a,b| a.created_at <=> b.created_at }
    acs = acs.sort_by { |ac| ac.created_at }
    # remember number of older comments. For show older comments link
    (0..(acs.length-1)).each { |i| acs[i].no_older_comments = i }
    # start be returning up to 4 comments for each gift
    return acs.last(4) if first_comment_id == nil
    # show older comments - return next 10 older comments
    index = acs.find_index { |ac| ac.comment.id.to_s == first_comment_id.to_s }
    # logger.debug2  "index = #{index}"
    return [] if index == nil or index == 0
    acs[0..(index-1)].last(10)
  end # comments_with_filter


  # display new deal check box?
  # only for open deals - and not for users deals (user is giver or receiver)
  def show_new_deal_checkbox? (users)
    logger.debug2 "users.class = #{users.class}"
    return false unless [Array, ActiveRecord::Relation::ActiveRecord_Relation_User].index(users.class) and users.size > 0
    return false if User.dummy_users?(users)
    count = 0
    api_gifts.each do |api_gift|
      user = users.find { |user2| user2.provider == api_gift.provider }
      next unless user
      count += 1
      return false if api_gift.user_id_giver == user.user_id
      return false if api_gift.user_id_receiver == user.user_id
    end # each
    raise "gift #{id} without api gifts for login user(s)" unless count > 0
    true
  end # show_new_deal_checkbox?

  def show_delete_gift_link? (users)
    api_gifts.each do |api_gift|
      user = users.find { |user2| user2.provider == api_gift.provider }
      next unless user
      return true if [api_gift.user_id_giver, api_gift.user_id_receiver].index(user.user_id)
    end
    return false
  end # show_delete_gift_link?

  def show_hide_gift_link? (users)
    !show_delete_gift_link?(users)
  end # show_hide_gift_link?


  # psydo attributea
  attr_accessor :file

  attr_accessor :datatype


  # todo: there is a problem with api gifts without gifts.
  def self.check_gift_and_api_gift_rel
    giftids = nil
    uncached do
      giftids = (ApiGift.all.collect { |ag| ag.gid } - Gift.all.collect { |g| g.gid }).uniq
    end
    return if giftids.size == 0
    logger.fatal2 "ApiGift without Gift. gift id's #{giftids.join(', ')}"
    raise "ApiGift without Gift. gift id's #{giftids.join(', ')}" # email from exception notifier
    # Process.kill('INT', Process.pid) # stop rails server
  end

  # receive list with newly gifts from client,
  # verify user ids, generate a sha256 digest, save gifts and return created_at_server timestamps to client
  # sha256 digest can be used as a a control when replicating gifts between clients
  # todo: use short internal user id (sequence) or use full user id (uid+provider) in client js gifts array?
  #       the app should support replication gift from device a on app server 1 to device b on app server 2
  #       but interval user ids can not be used across two different gofreerev-lo servers
  def self.new_gifts (new_gifts, login_user_ids)
    logger.debug2 "new_gifts = #{new_gifts}"
    logger.debug2 "user_ids = #{login_user_ids}"
    msg = "Could not save signature for new gift on server. "
    # check params
    if new_gifts.class != Array or new_gifts.size == 0
      return { :error => "#{msg}Invalid request. Expected array with one or more new gifts."}
    end
    if login_user_ids.class != Array or login_user_ids.size == 0
      return { :error => "#{msg}System error. Expected array with one or more login user ids."}
    end
    # verify user ids.
    login_users = User.where(:user_id => login_user_ids).order('user_id')
    if login_users.size < login_user_ids.size
      return { :error => "#{msg}System error. Invalid login. Expected #{login_user_ids.size} users. Found #{login_users.size} users."}
    end
    logger.debug2 "login users internal ids = " + login_users.collect { |u| u.id }.join(', ')
    # check and create sha256 digest for the new gift(s)
    new_gifts.shuffle!
    data = []
    no_errors = 0
    new_gifts.each do |new_gift|
      # verify new_gift hash. expects gid, created_at_client and either a giver_user_ids array or a receiver_user_ids array
      # check gid (unix timestamp (10 decimals) + milliseconds (3 decimals) + random number (7 decimals))
      if !new_gift.has_key?('gid')
        return { :data => data, :error => "#{msg}Invalid request. gid property is missing for one or more gifts"}
      end
      gid = new_gift['gid'].to_s
      # check client sha256 signature (from client side fields created_at_client and description)
      if new_gift['sha256'].to_s == ''
        return { :data => data, :error => "#{msg}Invalid request. sha256 property is missing for one or more gifts"}
      end
      sha256_client = new_gift['sha256'].to_s
      # check giver/receiver user ids. Must have either giver or receiver but not both
      if new_gift.has_key?('giver_user_ids') and new_gift['giver_user_ids'].class == Array and new_gift.size > 0
        giver_user_ids = new_gift['giver_user_ids']
      else
        giver_user_ids = nil
      end
      if new_gift.has_key?('receiver_user_ids') and new_gift['receiver_user_ids'].class == Array and new_gift.size > 0
        receiver_user_ids = new_gift['receiver_user_ids']
      else
        receiver_user_ids = nil
      end
      if !giver_user_ids and !receiver_user_ids
        data << { :gid => gid, :error => "#{msg}giver_user_ids or receiver_user_ids property was missing" }
        no_errors += 1
        next
      end
      if giver_user_ids and receiver_user_ids
        data << { :gid => gid, :error => "#{msg}giver_user_ids and receiver_user_ids properties are not allowed for a new gift." }
        no_errors += 1
        next
      end
      # check authorization. login user ids from rails session and gift user ids from client must match.
      # can fail if social network logins has changed between time when gift was created at client and gifts upload to server (offline client)
      direction = giver_user_ids ? 'giver' : 'receiver'
      gift_user_ids = giver_user_ids || receiver_user_ids
      gift_user_ids = gift_user_ids.collect { |id| id.to_s }
      logger.debug2 "gid = #{gid}, direction = #{direction}, gift_user_ids = #{gift_user_ids}"
      if login_users.size != gift_user_ids.size
        data << { :gid => gid, :error => "#{msg}Invalid authorization. Expected #{login_users.size} users. Found #{gift_user_ids.size} users."}
        no_errors += 1
        next
      end
      no_auth_users = login_users.find_all { |u| (gift_user_ids.index(u.id.to_s) or gift_user_ids.index(u.user_id)) }.size
      if login_users.size != no_auth_users
        data << { :gid => gid, :error => "#{msg}Invalid authorization. Expected #{login_users.size} users. Found #{no_auth_users} users."}
        no_errors += 1
        next
      end
      # server side sha256 digest
      sha256_server_text = ([gid, sha256_client, direction] + login_users.collect { |u| u.user_id }).join(',')
      sha256_server = Base64.encode64(Digest::SHA256.digest(sha256_server_text))
      logger.debug2 "sha256_server = #{sha256_server}"
      g = Gift.find_by_gid(gid)
      if g
        # gift already exists - check signature
        if g.sha256 == sha256_server
          data << { :gid => gid, :created_at_server => g.created_at.to_i }
        else
          data << { :gid => gid, :error => "#{msg}Gift already exists but signature was invalid." }
          no_errors += 1
        end
        next
      end
      g = Gift.new
      g.gid = gid
      g.sha256 = sha256_server
      g.save!
      data << { :gid => gid, :created_at_server => g.created_at.to_i }
    end
    return { :data => data, :no_errors => no_errors }
  end # self.new_gifts


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
      loop do
        temp_gid = String.generate_random_string(20)
        return temp_gid unless Gift.find_by_gid(temp_gid)
      end
    end

end # Gift
