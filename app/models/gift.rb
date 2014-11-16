class Gift < ActiveRecord::Base

  include Twitter::Extractor

  has_many :comments, :class_name => 'Comment', :primary_key => :gift_id, :foreign_key => :gift_id, :dependent => :destroy
  has_many :api_comments, :class_name => 'ApiComment', :primary_key => :gift_id, :foreign_key => :gift_id, :dependent => :destroy
  # todo: :dependent => :destroy does not work for api_gifts. Has added a after_destroy callback to fix this problem
  has_many :api_gifts, :class_name => 'ApiGift', :primary_key => :gift_id, :foreign_key => :gift_id, :dependent => :destroy
  has_many :likes, :class_name => 'GiftLike', :primary_key => :gift_id, :foreign_key => :gift_id, :dependent => :destroy

  before_create :before_create
  before_update :before_update
  after_destroy :after_destroy

  # https://github.com/jmazzi/crypt_keeper - text columns are encrypted in database
  # encrypt_add_pre_and_postfix/encrypt_remove_pre_and_postfix added in setters/getters for better encryption
  # this is different encrypt for each attribute and each db row
  # _before_type_cast methods are used by form helpers and are redefined
  crypt_keeper :description, :currency, :price, :received_at, :balance_giver, :balance_receiver,
               :balance_doc_giver, :balance_doc_receiver, :app_picture_rel_path, :encryptor => :aes, :key => ENCRYPT_KEYS[1]


  ##############
  # attributes #
  ##############

  # 1) gift_id - required - not encrypted - readonly
  validates_presence_of :gift_id
  validates_uniqueness_of :gift_id
  attr_readonly :gift_id
  before_validation(on: :create) do
    self.gift_id = self.new_encrypt_pk unless self.gift_id
  end
  def gift_id=(new_gift_id)
    return self['gift_id'] if self['gift_id']
    self['gift_id'] = new_gift_id
  end

  # 2) description - required - String in model - encrypted text in db - update not allowed
  validates_presence_of :description
  attr_readonly :description
  def description
    # logger.debug2  "gift.description: description = #{read_attribute(:description)} (#{read_attribute(:description).class.name})"
    return nil unless (extended_description = read_attribute(:description))
    encrypt_remove_pre_and_postfix(extended_description, 'description', 2)
  end
  def description=(new_description)
    # logger.debug2  "gift.description=: description = #{new_description} (#{new_description.class.name})"
    if new_description
      check_type('description', new_description, 'String')
      write_attribute :description, encrypt_add_pre_and_postfix(new_description, 'description', 2)
    else
      write_attribute :description, nil
    end
  end
  alias_method :description_before_type_cast, :description
  def description_was
    return description unless description_changed?
    return nil unless (extended_description = attribute_was(:description))
    encrypt_remove_pre_and_postfix(extended_description, 'description', 2)
  end # description_was

  # 3) currency - required - String in model - encrypted text in db - update not allowed
  validates_presence_of :currency
  validates_inclusion_of :currency, :allow_blank => true, :in => Money::Currency.table.collect { |a| [  a[1][:iso_code] ][0] }
  validates_each :currency do |record, attr, value|
    if record.new_record? or !record.currency_changed?
      nil # new record or unchanged currency - always ok
    elsif !record.received_at_was and record.received_at
      nil # deal has just been approved - currency and price have just been copied from proposal
    else
      # logger.debug2  "Gift.validates_each currency: gift id #{record.id}, old value = #{record.currency_was}, new value = #{value}"
      record.errors.add attr, :readonly
    end
  end # validates_each :currency
  def currency
    return nil unless (extended_currency = read_attribute(:currency))
    encrypt_remove_pre_and_postfix(extended_currency, 'currency', 3)
  end
  def currency=(new_currency)
    if new_currency
      check_type('currency', new_currency, 'String')
      write_attribute :currency, encrypt_add_pre_and_postfix(new_currency, 'currency', 3)
    else
      write_attribute :currency, nil
    end
  end # currency
  alias_method :currency_before_type_cast, :currency
  def currency_was
    return currency unless currency_changed?
    return nil unless (extended_currency = attribute_was('currency'))
    encrypt_remove_pre_and_postfix(extended_currency, 'currency', 3)
  end # currency_was

  # 4) price - Float in model - encrypted text in db
  validates_each :price do |record, attr, value|
    if record.new_record? or value == record.price_was
      nil # new record or unchanged price - always ok
    elsif !record.received_at_was and record.received_at
      nil # deal has just been approved - copy currency and price from proposal
    else
      record.errors.add attr, :readonly
    end
  end
  def price
    return nil unless (temp_extended_price = read_attribute(:price))
    str_to_float_or_nil encrypt_remove_pre_and_postfix(temp_extended_price, 'price', 4)
  end # price
  def price=(new_price)
    if new_price.to_s != ''
      check_type('price', new_price, 'Float')
      write_attribute :price, encrypt_add_pre_and_postfix(new_price.to_s, 'price', 4)
    else
      write_attribute :price, nil
    end
  end # price=
  alias_method :price_before_type_cast, :price
  def price_was
    return price unless price_changed?
    return nil unless (temp_extended_price = attribute_was('price'))
    str_to_float_or_nil encrypt_remove_pre_and_postfix(temp_extended_price, 'price', 4)
  end # price_was

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

  # 15) balance giver - Float in Model. Encrypted text in db.
  def balance_giver
    return nil unless (extended_balance_giver = read_attribute(:balance_giver))
    str_to_float_or_nil encrypt_remove_pre_and_postfix(extended_balance_giver, 'balance_giver', 25)
  end # balance_giver
  def balance_giver=(new_balance_giver)
    if new_balance_giver.to_s != ''
      check_type('balance_giver', new_balance_giver, 'Float')
      write_attribute :balance_giver, encrypt_add_pre_and_postfix(new_balance_giver.to_s, 'balance_giver', 25)
    else
      write_attribute :balance_giver, nil
    end
  end # balance_giver=
  alias_method :balance_giver_before_type_cast, :balance_giver
  def balance_giver_was
    return balance_giver unless balance_giver_changed?
    return nil unless (extended_balance_giver = attribute_was(:balance_giver))
    str_to_float_or_nil encrypt_remove_pre_and_postfix(extended_balance_giver, 'balance_giver', 25)
  end # balance_giver_was

  # 16) balance receiver - Float in model - encrypted text in db
  def balance_receiver
    return nil unless (extended_balance_receiver = read_attribute(:balance_receiver))
    str_to_float_or_nil encrypt_remove_pre_and_postfix(extended_balance_receiver, 'balance_receiver', 26)
  end
  def balance_receiver=(new_balance_receiver)
    if new_balance_receiver.to_s != ''
      check_type('balance_receiver', new_balance_receiver, 'Float')
      write_attribute :balance_receiver, encrypt_add_pre_and_postfix(new_balance_receiver.to_s, 'balance_receiver', 26)
    else
      write_attribute :balance_receiver, nil
    end
  end
  alias_method :balance_receiver_before_type_cast, :balance_receiver
  def balance_receiver_was
    return balance_receiver unless balance_receiver_changed?
    return nil unless (extended_balance_receiver = attribute_was(:balance_receiver))
    str_to_float_or_nil encrypt_remove_pre_and_postfix(extended_balance_receiver, 'balance_receiver', 26)
  end # balance_receiver_was

  # 21) deleted_at_api. String Y/N.

  # 22) status_change_at - integer - not encrypted - keep track of gifts changed after user has loaded gifts/index page

  # 23) balance_doc_giver. documentation for balance_giver to be used in users/show page
  # Hash in model, encrypted text in db
  def balance_doc_giver
    return nil unless (temp_extended_balance_doc_giver = read_attribute(:balance_doc_giver))
    # logger.debug2  "temp_extended_balance_doc_giver = #{temp_extended_balance_doc_giver}"
    YAML::load encrypt_remove_pre_and_postfix(temp_extended_balance_doc_giver, 'balance_doc_giver', 34)
  end # balance_doc_giver
  def balance_doc_giver=(new_balance_doc_giver)
    if new_balance_doc_giver
      check_type('balance_doc_giver', new_balance_doc_giver, 'Hash')
      write_attribute :balance_doc_giver, encrypt_add_pre_and_postfix(new_balance_doc_giver.to_yaml, 'balance_doc_giver', 34)
    else
      write_attribute :balance_doc_giver, nil
    end
  end # balance_doc_giver=
  alias_method :balance_doc_giver_before_type_cast, :balance_doc_giver
  def balance_doc_giver_was
    return balance_doc_giver unless balance_doc_giver_changed?
    return nil unless (temp_extended_balance_doc_giver = attribute_was(:balance_doc_giver))
    YAML::load encrypt_remove_pre_and_postfix(temp_extended_balance_doc_giver, 'balance_doc_giver', 34)
  end # balance_doc_giver_was

  # 24) balance_doc_receiver. documentation for balance_receiver to be used in users/show page
  # Hash in model, encrypted text in db
  def balance_doc_receiver
    return nil unless (temp_extended_balance_doc_receiver = read_attribute(:balance_doc_receiver))
    # logger.debug2  "temp_extended_balance_doc_receiver = #{temp_extended_balance_doc_receiver}"
    YAML::load encrypt_remove_pre_and_postfix(temp_extended_balance_doc_receiver, 'balance_doc_receiver', 35)
  end # balance_doc_receiver
  def balance_doc_receiver=(new_balance_doc_receiver)
    if new_balance_doc_receiver
      check_type('balance_doc_receiver', new_balance_doc_receiver, 'Hash')
      write_attribute :balance_doc_receiver, encrypt_add_pre_and_postfix(new_balance_doc_receiver.to_yaml, 'balance_doc_receiver', 35)
    else
      write_attribute :balance_doc_receiver, nil
    end
  end # balance_doc_receiver=
  alias_method :balance_doc_receiver_before_type_cast, :balance_doc_receiver
  def balance_doc_receiver_was
    return balance_doc_receiver unless balance_doc_receiver_changed?
    return nil unless (temp_extended_balance_doc_receiver = attribute_was(:balance_doc_receiver))
    YAML::load encrypt_remove_pre_and_postfix(temp_extended_balance_doc_receiver, 'balance_doc_receiver', 35)
  end # balance_doc_receiver_was

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
  
  # 30) app_picture_rel_path - rel_path to picture store - temp or perm picture store
  # perm picture store is used for providers with API_GIFT_PICTURE_STORE = :local (for example linkedin)
  # term picture store is used for temporary picture store when uploading pictures to provider (for example facebook)
  # String en model - encrypted text in db
  def app_picture_rel_path
    # logger.debug41  "gift.app_picture_rel_path: app_picture_rel_path = #{read_attribute(:app_picture_rel_path)} (#{read_attribute(:app_picture_rel_path).class.name})"
    return nil unless (extended_app_picture_rel_path = read_attribute(:app_picture_rel_path))
    encrypt_remove_pre_and_postfix(extended_app_picture_rel_path, 'app_picture_rel_path', 41)
  end
  def app_picture_rel_path=(new_app_picture_rel_path)
    # logger.debug41  "gift.app_picture_rel_path=: app_picture_rel_path = #{new_app_picture_rel_path} (#{new_app_picture_rel_path.class.name})"
    if new_app_picture_rel_path
      check_type('app_picture_rel_path', new_app_picture_rel_path, 'String')
      write_attribute :app_picture_rel_path, encrypt_add_pre_and_postfix(new_app_picture_rel_path, 'app_picture_rel_path', 41)
    else
      write_attribute :app_picture_rel_path, nil
    end
  end
  alias_method :app_picture_rel_path_before_type_cast, :app_picture_rel_path
  def app_picture_rel_path_was
    return app_picture_rel_path unless app_picture_rel_path_changed?
    return nil unless (extended_app_picture_rel_path = attribute_was(:app_picture_rel_path))
    encrypt_remove_pre_and_postfix(extended_app_picture_rel_path, 'app_picture_rel_path', 41)
  end # app_picture_rel_path_was

  # 31-34 open description attributes. used as an alternative to picture attachment in gifts/index page

  # 31) open_graph_url - http link to page on other website - alternative to picture attachment
  # String en model - encrypted text in db
  def open_graph_url
    # logger.debug50  "gift.open_graph_url: open_graph_url = #{read_attribute(:open_graph_url)} (#{read_attribute(:open_graph_url).class.name})"
    return nil unless (extended_open_graph_url = read_attribute(:open_graph_url))
    encrypt_remove_pre_and_postfix(extended_open_graph_url, 'open_graph_url', 50)
  end
  def open_graph_url=(new_open_graph_url)
    # logger.debug50  "gift.open_graph_url=: open_graph_url = #{new_open_graph_url} (#{new_open_graph_url.class.name})"
    if new_open_graph_url
      check_type('open_graph_url', new_open_graph_url, 'String')
      write_attribute :open_graph_url, encrypt_add_pre_and_postfix(new_open_graph_url, 'open_graph_url', 50)
    else
      write_attribute :open_graph_url, nil
    end
  end
  alias_method :open_graph_url_before_type_cast, :open_graph_url
  def open_graph_url_was
    return open_graph_url unless open_graph_url_changed?
    return nil unless (extended_open_graph_url = attribute_was(:open_graph_url))
    encrypt_remove_pre_and_postfix(extended_open_graph_url, 'open_graph_url', 50)
  end # open_graph_url_was

  # 32) open_graph_title - http link to page on other website - alternative to picture attachment
  # String en model - encrypted text in db
  def open_graph_title
    # logger.debug51  "gift.open_graph_title: open_graph_title = #{read_attribute(:open_graph_title)} (#{read_attribute(:open_graph_title).class.name})"
    return nil unless (extended_open_graph_title = read_attribute(:open_graph_title))
    encrypt_remove_pre_and_postfix(extended_open_graph_title, 'open_graph_title', 51)
  end
  def open_graph_title=(new_open_graph_title)
    # logger.debug51  "gift.open_graph_title=: open_graph_title = #{new_open_graph_title} (#{new_open_graph_title.class.name})"
    if new_open_graph_title
      check_type('open_graph_title', new_open_graph_title, 'String')
      write_attribute :open_graph_title, encrypt_add_pre_and_postfix(new_open_graph_title, 'open_graph_title', 51)
    else
      write_attribute :open_graph_title, nil
    end
  end
  alias_method :open_graph_title_before_type_cast, :open_graph_title
  def open_graph_title_was
    return open_graph_title unless open_graph_title_changed?
    return nil unless (extended_open_graph_title = attribute_was(:open_graph_title))
    encrypt_remove_pre_and_postfix(extended_open_graph_title, 'open_graph_title', 51)
  end # open_graph_title_was

  # 33) open_graph_description - http link to page on other website - alternative to picture attachment
  # String en model - encrypted text in db
  def open_graph_description
    # logger.debug52  "gift.open_graph_description: open_graph_description = #{read_attribute(:open_graph_description)} (#{read_attribute(:open_graph_description).class.name})"
    return nil unless (extended_open_graph_description = read_attribute(:open_graph_description))
    encrypt_remove_pre_and_postfix(extended_open_graph_description, 'open_graph_description', 52)
  end
  def open_graph_description=(new_open_graph_description)
    # logger.debug52  "gift.open_graph_description=: open_graph_description = #{new_open_graph_description} (#{new_open_graph_description.class.name})"
    if new_open_graph_description
      check_type('open_graph_description', new_open_graph_description, 'String')
      write_attribute :open_graph_description, encrypt_add_pre_and_postfix(new_open_graph_description, 'open_graph_description', 52)
    else
      write_attribute :open_graph_description, nil
    end
  end
  alias_method :open_graph_description_before_type_cast, :open_graph_description
  def open_graph_description_was
    return open_graph_description unless open_graph_description_changed?
    return nil unless (extended_open_graph_description = attribute_was(:open_graph_description))
    encrypt_remove_pre_and_postfix(extended_open_graph_description, 'open_graph_description', 52)
  end # open_graph_description_was

  # 34) open_graph_image - http link to page on other website - alternative to picture attachment
  # String en model - encrypted text in db
  def open_graph_image
    # logger.debug53  "gift.open_graph_image: open_graph_image = #{read_attribute(:open_graph_image)} (#{read_attribute(:open_graph_image).class.name})"
    return nil unless (extended_open_graph_image = read_attribute(:open_graph_image))
    encrypt_remove_pre_and_postfix(extended_open_graph_image, 'open_graph_image', 53)
  end
  def open_graph_image=(new_open_graph_image)
    # logger.debug53  "gift.open_graph_image=: open_graph_image = #{new_open_graph_image} (#{new_open_graph_image.class.name})"
    if new_open_graph_image
      check_type('open_graph_image', new_open_graph_image, 'String')
      write_attribute :open_graph_image, encrypt_add_pre_and_postfix(new_open_graph_image, 'open_graph_image', 53)
    else
      write_attribute :open_graph_image, nil
    end
  end
  alias_method :open_graph_image_before_type_cast, :open_graph_image
  def open_graph_image_was
    return open_graph_image unless open_graph_image_changed?
    return nil unless (extended_open_graph_image = attribute_was(:open_graph_image))
    encrypt_remove_pre_and_postfix(extended_open_graph_image, 'open_graph_image', 53)
  end # open_graph_image_was


  #
  # helper methods
  #

  # get/set balance for actual user. Used in user.recalculate_balance and in /gifts/index page
  def balance (current_user, login_user)
    return nil unless direction == 'both'
    api_gift = api_gifts.find { |ag| [ag.user_id_giver, ag.user_id_receiver].index(current_user.user_id)}
    return nil unless api_gift # error
    return nil unless api_gift.user_id_receiver and api_gift.user_id_giver # error
    balance_current_user = case current_user.user_id
      when api_gift.user_id_giver then balance_giver
      when api_gift.user_id_receiver then balance_receiver
      else nil # error
    end
    return nil unless balance_current_user
    balance_login_user = ExchangeRate.exchange(balance_current_user, 'USD', login_user.currency, received_at)
    balance_login_user
  end # balance
  def balance_doc (current_user)
    return nil unless direction == 'both'
    api_gift = api_gifts.find { |ag| [ag.user_id_giver, ag.user_id_receiver].index(current_user.user_id)}
    return nil unless api_gift
    case current_user.user_id
      when api_gift.user_id_giver then balance_doc_giver
      when api_gift.user_id_receiver then balance_doc_receiver
      else nil
    end
  end # balance_doc
  def set_balance (user_ids, new_balance, new_balance_doc)
    # logger.debug2  "Gift.set_balance: id = #{id}, user_id = #{user_id}, new_balance = #{new_balance}, user_id_giver = #{user_id_giver}, user_id_receiver = #{user_id_receiver}"
    return new_balance unless received_at
    api_gift = api_gifts.find { |ag| (user_ids.index(ag.user_id_giver) or user_ids.index(ag.user_id_receiver)) }
    return new_balance unless api_gift
    if user_ids.index(api_gift.user_id_giver)
      self.balance_giver = new_balance
      self.balance_doc_giver = new_balance_doc
    else
      self.balance_receiver = new_balance
      self.balance_doc_receiver = new_balance_doc
    end
    new_balance
  end # set_balance


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

  def show_like_gift_link? (users)
    user_ids = users.collect { |u| u.user_id }
    GiftLike.where('gift_id = ? and user_id in (?)', gift_id, user_ids).each do |gl|
      return false if gl.like == 'Y'
    end # each gl
    true
  end # show_like_gift_link?

  def show_unlike_gift_link? (users)
    !show_like_gift_link?(users)
  end # show_unlike_link?

  def show_follow_gift_link? (users)
    userids = users.collect { |user| user.user_id }
    if GiftLike.where('gift_id = ? and user_id in (?)', gift_id, userids).find_all { |gl| gl.follow == 'Y' }.first
      # user has selected to follow this gift
      false
    elsif GiftLike.where('gift_id = ? and user_id in (?)', gift_id, userids).find_all { |gl| gl.follow == 'N' }.first
      # user has selected not to follow this gift
      true
    elsif api_gifts.find { |api_gift| userids.index(api_gift.user_id_giver) or userids.index(api_gift.user_id_receiver)}
      # user is giver or receiver of this gift
      false
    elsif api_comments.find { |comment| userids.index(comment.user_id )}
      # user has commented this gift
      false
    else
      # other users - do not follow
      true
    end
  end # show_follow_gift_link?

  def show_unfollow_gift_link? (users)
    !show_follow_gift_link?(users)
  end # show_unfollow_gift_link?

  def rel_path_picture_exists?
    return false unless app_picture_rel_path
    full_os_path = Picture.full_os_path :rel_path => app_picture_rel_path
    return false unless full_os_path
    File.exists?(full_os_path)
  end

  # find twitter tags in text. Use when "truncating" too long tweets & preserving tags
  # https://github.com/twitter/twitter-text-rb
  def self.find_twitter_tags (text)
    indices = []
    x = Gift.new
    x.extract_entities_with_indices(text).each do |hash|
      next unless hash[:indices]
      next unless hash[:indices].class == Array
      next unless hash[:indices].size == 2
      indices << hash[:indices]
    end
    # indices.sort { |a,b| a[0] <=> b[0] }
    indices.sort_by { |a| a[0] }
  end # self.find_twitter_tags

  # truncate long tweet. preserve tags if possible.
  # use to shorten tweet before post on twitter wall. See util.generec_post_on_wall and application_controller.init_api_client_twitter
  # returns array with truncated text and truncated flag (true/false)
  # testcase: text.size.downto(1).each do |i| puts i.to_s + ': ' + Gift.truncate_twitter_text(x,i) ; end ; nil
  def self.truncate_twitter_text (text, max_lng)
    return [text, false] if text.to_s.size <= max_lng
    truncated = true
    text = original_text = text.to_s # keep original text for recursive call if too many tags in text
    # find tags in text
    indices = Gift.find_twitter_tags(text)
    return [text.first(max_lng), truncated] if indices.size == 0
    # array with temporary removed tags
    removed_tags = []
    removed_tags.define_singleton_method :lng do
      self.size == 0 ? 0 : 1 + self.join.size
    end
    # loop for each. Start with last tag. Copy tags to removed tags and remove non tag text
    indices.reverse.each do |from, to|
      break if text.size + removed_tags.lng <= max_lng # text ok
      # check if text ends with a tag
      if to >= text.length
        # remove tag from end of text and continue
        removed_tags << text[from..to]
        if removed_tags.size == 1 and removed_tags[0].last == ' '
          removed_tags[0] = removed_tags[0][0..-2]
        end
        if from == 0
          text = ''
        else
          text = text.to(from-1)
        end
        next
      end
      # check if text after tag (postfix) could be removed
      postfix = text.from(to+1)
      postfix_lng = postfix.length
      if to + removed_tags.lng >= max_lng
        # remove text after tag. Text is still too long
        removed_tags << text[from..to]
        if removed_tags.size == 1 and removed_tags[0].last == ' '
          removed_tags[0] = removed_tags[0][0..-2]
        end
        if from == 0
          text = ''
        else
          text = text.to(from-1)
        end
        next
      end
      # truncate postfix and exit
      new_postfix_lng = max_lng - to - removed_tags.lng - 1
      raise "negative new_postfix_lng #{new_postfix_lng}" if new_postfix_lng < 0
      text = text.to(to+new_postfix_lng)
      break
    end # each indice
    # check if text before first tag should be shorter
    if removed_tags.lng > max_lng
      # many tags in tweet - blank non tag text
      text = ''
    elsif text.size + removed_tags.lng > max_lng and indices.size > 0
      # truncate text before first tag
      from, to = indices[0]
      prefix = text
      prefix_lng = prefix.length
      new_prefix_lng = max_lng - removed_tags.lng
      text = text.first(new_prefix_lng)
    end
    # merge non tag text and tags
    if text == ''
      text = removed_tags.reverse.join
      text = ' ' + text if text.length < max_lng
    elsif removed_tags.size > 0
      text = text + ' ' + removed_tags.reverse.join
    end
    # check if tags must be removed from text
    if text.size > max_lng
      # remove last tag from text and retry (recursive call)
      text = original_text
      from, to = indices.last
      if from == 0 and to == original_text.size
        # text = one tag - can not be shorter
        text = text.from(1)
        return [text.first(max_lng), truncated]
      elsif to == original_text.size
        text = original_text.to(from-1)
      else
        text = original_text.to(from-1) + original_text.from(to+1)
      end
      return [Gift.truncate_twitter_text(text, max_lng), truncated]
    end
    if text.length != max_lng
      puts "new text = #{text}"
      raise "invalid length. Expected #{max_lng} text. Found #{text.length} text."
    end
    [text, truncated]
  end # self.truncate_twitter_text

  # truncate text before post in api walls
  # special text truncation for tweets where tags are preserved and removed
  # returns array with truncated text and truncated flag (true/false)
  def self.truncate_text (provider, text, max_lng)
    return [nil, false] unless text
    if provider == 'twitter'
      Gift.truncate_twitter_text(text, max_lng)
    else
      truncated = (text.length > max_lng)
      [text.first(max_lng), truncated]
    end
  end # self.truncate_text



  # psydo attributea
  attr_accessor :file





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
    logger.debug2 "before cleanup api gifts. gift_id = #{gift_id}"
    ApiGift.where('gift_id = ?', gift_id).delete_all
    logger.debug2 "after cleanup api gifts. gift_id = #{gift_id}"
  end

  # todo: there is a problem with api gifts without gifts.
  def self.check_gift_and_api_gift_rel
    giftids = nil
    uncached do
      giftids = (ApiGift.all.collect { |ag| ag.gift_id } - Gift.all.collect { |g| g.gift_id }).uniq
    end
    return if giftids.size == 0
    logger.fatal2 "ApiGift without Gift. gift id's #{giftids.join(', ')}"
    raise "ApiGift without Gift. gift id's #{giftids.join(', ')}" # email from exception notifier
    # Process.kill('INT', Process.pid) # stop rails server
  end


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
      loop do
        temp_gift_id = String.generate_random_string(20)
        return temp_gift_id unless Gift.find_by_gift_id(temp_gift_id)
      end
    end

end # Gift
