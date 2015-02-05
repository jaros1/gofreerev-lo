class Gift < ActiveRecord::Base

  has_many :comments, :class_name => 'Comment', :primary_key => :gid, :foreign_key => :gid, :dependent => :destroy
  has_many :api_comments, :class_name => 'ApiComment', :primary_key => :gid, :foreign_key => :gid, :dependent => :destroy
  # todo: :dependent => :destroy does not work for api_gifts. Has added a after_destroy callback to fix this problem
  has_many :api_gifts, :class_name => 'ApiGift', :primary_key => :gid, :foreign_key => :gid, :dependent => :destroy

  before_create :before_create
  before_update :before_update
  after_destroy :after_destroy

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

  # 28) direction - giver, receiver or both - starts with giver or receiver and is changed to both when the deal is accepted
  validates_presence_of :direction
  validates_inclusion_of :direction, :allow_blank => true, :in => %w(giver receiver both)
  validates_each :direction, :allow_blank => true do |record, attr, value|
    if record.new_record? and value == 'both'
      record.errors.add attr, :invalid
    elsif record.new_record? and record.created_by and value != record.created_by
      record.errors.add attr, :invalid
    elsif !record.new_record? and value != 'both' and value != record.created_by
      record.errors.add attr, :invalid
    elsif record.received_at and value != 'both'
      record.errors.add attr, :invalid
    end
  end

  # 29) created_by - giver or receiver - equal with direction when gift is created
  attr_readonly :created_by
  validates_presence_of :created_by
  validates_inclusion_of :created_by, :allow_blank => true, :in => %w(giver receiver)


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
    return false if direction == 'both' # closed deal
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


  def before_create
    self.status_update_at = Sequence.next_status_update_at
  end

  def before_update
    if !deleted_at_was and deleted_at
      # gift has been delete marked in util_controller.delete_gift
      # update status_update_at so that gift will be ajax deleted in other sessions
      self.status_update_at = Sequence.next_status_update_at
      # destroy all notifications for this gift
      api_comments.each do |api_comment|
        api_comment.remove_from_notifications
      end # each api_comment
    end # if
  end # before_update

  def after_destroy
    # :dependent => :destroy does not work for api_gifts relation
    logger.debug2 "before cleanup api gifts. gid = #{gid}"
    ApiGift.where('gid = ?', gid).delete_all
    logger.debug2 "after cleanup api gifts. gid = #{gid}"
  end

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

  # receive list with newly created gifts from client and return list with created_at_server timestamps to client
  def self.create_gifts (created_at_server_request, login_user_ids)
    logger.debug2 "created_at_server_request = #{created_at_server_request}"
    logger.debug2 "user_ids = #{login_user_ids}"
    login_users = User.where(:user_id => login_user_ids)
    logger.debug2 "not implemented"
    created_at_server_request
  end


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
