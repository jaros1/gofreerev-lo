class GiftLike < ActiveRecord::Base


  belongs_to :user, :class_name => 'User', :primary_key => :user_id, :foreign_key => :user_id
  belongs_to :gift, :class_name => 'Gift', :primary_key => :gift_id, :foreign_key => :gift_id

  # https://github.com/jmazzi/crypt_keeper - text columns are encrypted in database
  # encrypt_add_pre_and_postfix/encrypt_remove_pre_and_postfix added in setters/getters for better encryption
  # this is different encrypt for each attribute and each db row
  # _before_type_cast methods are used by form helpers and are redefined
  crypt_keeper :like, :show, :follow, :encryptor => :aes, :key => ENCRYPT_KEYS[28]


  ##############
  # attributes #
  ##############

  # 1) gift_like_id - required - not encrypted - readonly
  validates_presence_of :gift_like_id
  validates_uniqueness_of :gift_like_id
  attr_readonly :gift_like_id
  before_validation(on: :create) do
    self.gift_like_id = self.new_encrypt_pk unless self.gift_like_id
  end
  def gift_like_id=(new_gift_like_id)
    return self['gift_like_id'] if self['gift_like_id']
    self['gift_like_id'] = new_gift_like_id
  end

  # 2) user_id - required - not encrypted - readonly
  validates_presence_of :user_id
  attr_readonly :user_id # todo: uncomment
  
  # 3) gift_id - required - not encrypted - readonly
  validates_presence_of :gift_id
  attr_readonly :gift_id

  # 4) like - Y/N - default N - like/unlike gift - String in model - encrypted text in db
  def like
    # logger.debug2  "Giftlike: like = #{read_attribute(:like)} (#{read_attribute(:like).class.name})"
    return nil unless (extended_like = read_attribute(:like))
    encrypt_remove_pre_and_postfix(extended_like, 'like', 29)
  end # like
  def like=(new_like)
    # logger.debug2  "gift.like=: like = #{new_like} (#{new_like.class.name})"
    if new_like
      check_type('like', new_like, 'String')
      write_attribute :like, encrypt_add_pre_and_postfix(new_like, 'like', 29)
    else
      write_attribute :like, nil
    end
  end # like=
  alias_method :like_before_type_cast, :like
  def like_was
    return like uless like_changed?
    return nil unless (extended_like = attribute_was(:like))
    encrypt_remove_pre_and_postfix(extended_like, 'like', 29)
  end # like_was

  # 5) show - Y/N - default Y - show/hide gift
  def show
    # logger.debug2  "Giftshow: show = #{read_attribute(:show)} (#{read_attribute(:show).class.name})"
    return nil unless (extended_show = read_attribute(:show))
    encrypt_remove_pre_and_postfix(extended_show, 'show', 30)
  end # show
  def show=(new_show)
    # logger.debug2  "gift.show=: show = #{new_show} (#{new_show.class.name})"
    if new_show
      check_type('show', new_show, 'String')
      write_attribute :show, encrypt_add_pre_and_postfix(new_show, 'show', 30)
    else
      write_attribute :show, nil
    end
  end # show=
  alias_method :show_before_type_cast, :show
  def show_was
    return show unless show_changed?
    return nil unless (extended_show = attribute_was(:show))
    encrypt_remove_pre_and_postfix(extended_show, 'show', 30)
  end # show_was
  
  # 6) follow - Y/N - default nil - Y/N to explicit follow or ignore gift comments
  def follow
    # logger.debug2  "Giftfollow: follow = #{read_attribute(:follow)} (#{read_attribute(:follow).class.name})"
    return nil unless (extended_follow = read_attribute(:follow))
    encrypt_remove_pre_and_postfix(extended_follow, 'follow', 31)
  end # follow
  def follow=(new_follow)
    # logger.debug2  "gift.follow=: follow = #{new_follow} (#{new_follow.class.name})"
    if new_follow
      check_type('follow', new_follow, 'String')
      write_attribute :follow, encrypt_add_pre_and_postfix(new_follow, 'follow', 31)
    else
      write_attribute :follow, nil
    end
  end # follow=
  alias_method :follow_before_type_cast, :follow
  def follow_was
    return follow unless follow_changed?
    return nil unless (extended_follow = attribute_was(:follow))
    encrypt_remove_pre_and_postfix(extended_follow, 'follow', 31)
  end # follow_was


  # https://github.com/jmazzi/crypt_keeper gem encrypts all attributes and all rows in db with the same key
  # this extension to use different encryption for each attribute and each row
  # overwrite non model specific methods defined in /config/initializers/active_record_extensions.rb
  protected
  def encrypt_pk
    self.gift_like_id
  end
  def encrypt_pk=(new_encrypt_pk_value)
    self.gift_like_id = new_encrypt_pk_value
  end
  def new_encrypt_pk
    loop do
      temp_gift_like_id = String.generate_random_string(20)
      return temp_gift_like_id unless GiftLike.find_by_gift_like_id(temp_gift_like_id)
    end
  end

end # GiftLike
