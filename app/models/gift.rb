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
    # logger.debug2 "new_gifts = #{new_gifts}"
    # logger.debug2 "login_user_ids = #{login_user_ids}"
    msg = "Could not create gift signature on server. "
    # check params
    return if !new_gifts or new_gifts.size == 0 # ignore empty new gifts request
    if login_user_ids.class != Array or login_user_ids.size == 0
      # system error - util/ping + Gift.new_gifts should only be called with logged in users.
      return { :error => "#{msg}System error. Expected array with one or more login user ids."}
    end
    # verify user ids. should never fail. user ids are from sessions table and should be valid
    # order by user id - order is used in sha256 server signature
    login_users = User.where(:user_id => login_user_ids).order('user_id')
    if login_users.size < login_user_ids.size
      return { :error => "#{msg}System error. Invalid login. Expected #{login_user_ids.size} users. Found #{login_users.size} users."}
    end
    # logger.debug2 "login user ids = " + login_users.collect { |u| u.id }.join(', ')
    login_providers = login_users.collect { |u| u.provider }
    # logger.debug2 "login users internal ids = " + login_users.collect { |u| u.id }.join(', ')
    # check and create sha256 digest signature for the new gift(s)
    new_gifts.shuffle!
    data = []
    no_errors = 0
    # new gifts array has already been json schema validated to some extend
    new_gifts.each do |new_gift|
      # check new_gift hash: gid, sha256 and either a giver_user_ids array or a receiver_user_ids array
      gid = new_gift['gid'].to_s
      sha256_client = new_gift['sha256'].to_s
      # check giver/receiver user ids. Must have either giver or receiver but not both
      if new_gift.has_key?('giver_user_ids') and new_gift['giver_user_ids'].class == Array and new_gift['giver_user_ids'].size > 0
        giver_user_ids = new_gift['giver_user_ids']
      else
        giver_user_ids = nil
      end
      if new_gift.has_key?('receiver_user_ids') and new_gift['receiver_user_ids'].class == Array and new_gift['receiver_user_ids'].size > 0
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
        data << { :gid => gid, :error => "#{msg}both giver_user_ids and receiver_user_ids properties are not allowed for a new gift." }
        no_errors += 1
        next
      end
      # check authorization. login user ids from rails session and gift user ids from client must match.
      # can fail if social network logins has changed between time when gift was created at client and gifts upload to server (offline client)
      direction = giver_user_ids ? 'giver' : 'receiver'
      gift_user_ids = (giver_user_ids || receiver_user_ids).uniq
      # logger.debug2 "gid = #{gid}, direction = #{direction}, gift_user_ids = #{gift_user_ids}"

      # Could not create gift signature on server. Invalid authorization. Expected 2 users. Found 1 users
      signature_users = login_users.find_all { |u| gift_user_ids.index(u.id)}
      if signature_users.size == gift_user_ids.size
        # authorization ok. create server side sha256 digest signature
        #       field should be readonly and gift signature check can verify that field is not updated by client
        # todo: include created_at_server in server side sha256 signature? no, but return created_at_server timestamp in signature check
        sha256_server_text = ([gid, sha256_client, direction] + signature_users.collect { |u| u.user_id }).join(',')
        sha256_server = Base64.encode64(Digest::SHA256.digest(sha256_server_text))
        logger.debug2 "sha256_server = #{sha256_server}"
        g = Gift.find_by_gid(gid)
        if g
          # gift already exists - check signature
          if g.sha256 == sha256_server
            data << { :gid => gid, :created_at_server => g.created_at.to_i }
          else
            data << { :gid => gid, :error => "#{msg}Gift already exists but sha256 signature was invalid." }
            no_errors += 1
          end
          next
        end
        g = Gift.new
        g.gid = gid
        g.sha256 = sha256_server
        g.save!
        data << { :gid => gid, :created_at_server => g.created_at.to_i }
        next
      end

      # authorization error. maybe api log out on client before new gift signature was created on server.
      missing_login_user_ids = gift_user_ids - login_users.collect { |u| u.id }
      missing_login_users = User.where(:id => missing_login_user_ids)
      missing_login_providers = missing_login_users.collect { |u| u.provider }
      # logger.debug2 "missing_login_user_ids = #{missing_login_user_ids.join(', ')}"
      # logger.debug2 "missing login users = " + missing_login_users.collect { |u| u.debug_info }.join(', ')
      # split missing login users in missing login and changed login
      changed_login_providers = login_providers & missing_login_providers
      missing_login_providers = missing_login_providers - changed_login_providers
      # logger.debug2 "changed_login_providers = #{changed_login_providers.join('. ')}"
      # logger.debug2 "missing_login_providers = #{missing_login_providers.join('. ')}"
      # nice informative error message
      if (changed_login_providers.size > 0)
        data << { :gid => gid, :error => "#{msg}Log in has changed for #{changed_login_providers.join('. ')} since gift was created. Please log in with old #{changed_login_providers.join('. ')} user."}
      else
        data << { :gid => gid, :error => "#{msg}Log out for #{missing_login_providers.join('. ')} since gift was created. Please log in for #{missing_login_providers.join('. ')}."}
      end
      no_errors += 1

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
