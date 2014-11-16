class Notification < ActiveRecord::Base

  #create_table "notifications", force: true do |t|
  #  t.string   "noti_id",      limit: 20, null: false
  #  t.string   "to_user_id",   limit: 40, null: false
  #  t.string   "from_user_id", limit: 40
  #  t.string   "internal",     limit: 1,  null: false
  #  t.text     "noti_key",                null: false
  #  t.text     "noti_options"
  #  t.string   "noti_read",    limit: 1,  null: false
  #  t.datetime "created_at"
  #  t.datetime "updated_at"
  #end

  # relations
  belongs_to :from_user, :class_name => 'User', :primary_key => :user_id, :foreign_key => :from_user_id
  belongs_to :to_user, :class_name => 'User', :primary_key => :user_id, :foreign_key => :to_user_id
  has_and_belongs_to_many :api_comments

  before_create :before_create



  # https://github.com/jmazzi/crypt_keeper - text columns are encrypted in database
  # encrypt_add_pre_and_postfix/encrypt_remove_pre_and_postfix added in setters/getters for better encryption
  # this is different encrypt for each attribute and each db row
  # _before_type_cast methods are used by form helpers and are redefined
  crypt_keeper :noti_key, :noti_options, :encryptor => :aes, :key => ENCRYPT_KEYS[18]

  
  ##############
  # attributes #
  ##############

  # 1) noti_id - required - not encrypted - readonly
  validates_presence_of :noti_id
  validates_uniqueness_of :noti_id
  attr_readonly :noti_id
  before_validation(on: :create) do
    self.noti_id = self.new_encrypt_pk unless self.noti_id
  end
  def noti_id=(new_noti_id)
    return self['noti_id'] if self['noti_id']
    self['noti_id'] = new_noti_id
  end


  # 2) to_user_id - required - FK - not encrypted - readonly
  validates_presence_of :to_user_id
  # attr_readonly :to_user_id # todo: uncomment

  
  # 3) from_user_id - optional - FK - not encrypted - readonly
  validates_each :from_user_id, :allow_blank => true do |record, attr, value|
    if record.to_user_id == value
      logger.error2 "from_user_id and to_user_id are identical. user #{value}"
      record.errors.add attr, :invalid
    end
  end

  # 4) internal - required - Y/N - not encrypted
  validates_presence_of :internal
  validates_inclusion_of :internal, :in => %w(Y N)
  attr_readonly


  # 5) noti_key - key for translate - required - String in model - encrypted text in db
  # there most be 4 keys in yml file for each noti_key with postfix _from_msg, _from_url, _to_msg and _to_url
  validates_presence_of :noti_key
  def noti_key
    return nil unless (extended_noti_key = read_attribute(:noti_key))
    encrypt_remove_pre_and_postfix(extended_noti_key, 'noti_key', 19)
  end # noti_key
  def noti_key=(new_noti_key)
    if new_noti_key
      check_type('noti_key', new_noti_key, 'String')
      write_attribute :noti_key, encrypt_add_pre_and_postfix(new_noti_key, 'noti_key', 19)
    else
      write_attribute :noti_key, nil
    end
  end # noti_key=
  alias_method :noti_key_before_type_cast, :noti_key
  def noti_key_was
    return noti_key unless noti_key_changed?
    return nil unless (extended_noti_key = attribute_was('noti_key'))
    encrypt_remove_pre_and_postfix(extended_noti_key, 'noti_key', 19)
  end # noti_key_was
  
  # 6) noti_options - required - Hash in Model - encrypted text in db
  # validates_presence_of :noti_options # does not work for some reason!
  def noti_options
    return nil unless (temp_extended_noti_options = read_attribute(:noti_options))
    # logger.debug2  "get temp_extended_noti_options = #{temp_extended_noti_options} (#{temp_extended_noti_options.class.name})"
    YAML::load encrypt_remove_pre_and_postfix(temp_extended_noti_options, 'noti_options', 20)
  end # noti_options
  def noti_options=(new_noti_options)
    if new_noti_options
      check_type('noti_options', new_noti_options, 'Hash')
      temp_extended_noti_options = encrypt_add_pre_and_postfix(new_noti_options.to_yaml , 'noti_options', 20)
      # logger.debug2  "set temp_extended_noti_options = #{temp_extended_noti_options} (#{temp_extended_noti_options.class.name})"
      write_attribute :noti_options, temp_extended_noti_options
    else
      # logger.debug2  "set temp_extended_noti_options = nil"
      write_attribute :noti_options, nil
    end
  end # noti_options=
  alias_method :noti_options_before_type_cast, :noti_options
  def noti_options_was
    return noti_options unless noti_options_changed?
    return nil unless (temp_extended_noti_options = attribute_was(:noti_options))
    YAML::load encrypt_remove_pre_and_postfix(temp_extended_noti_options, 'noti_options', 20)
  end # noti_options_was

  # 7) noti_read - required - Y/N String in model - not encrypted
  # N until message is shown in inbox/index page
  validates_presence_of :noti_read
  validates_inclusion_of :noti_read, :in => %w(Y N)




  # keep max 20 internal notifications for each user
  def before_create
    limit = 19
    # logger.debug2  "notification.before_create: to_user_id = #{to_user_id}"
    count = Notification.where("to_user_id = ? and internal = ?", to_user_id, 'Y').length
    return if count <= limit
    # keep newest 19 notifications (0..18).
    ns = Notification.where("to_user_id = ? and internal = ?", to_user_id, 'Y').order("updated_at desc")
    ns = ns[limit..-1]
    ns.each { |n| n.destroy }
    # one new notification will be created just in a moment
  end # before_create
  


  ##################
  # helper methods #
  ##################

  def other_user (login_user)
    return nil unless login_user
    if login_user.user_id == from_user_id
      to_user
    elsif login_user.user_id == to_user_id
      from_user
    else
      nil
    end
  end # other_user



  # https://github.com/jmazzi/crypt_keeper gem encrypts all attributes and all rows in db with the same key
  # this extension to use different encryption for each attribute and each row
  # overwrite non model specific methods defined in /config/initializers/active_record_extensions.rb
  protected
  def encrypt_pk
    self.noti_id
  end
  def encrypt_pk=(new_encrypt_pk_value)
    self.noti_id = new_encrypt_pk_value
  end
  def new_encrypt_pk
    loop do
      temp_noti_id = String.generate_random_string(20)
      return temp_noti_id unless Notification.find_by_noti_id(temp_noti_id)
    end
  end

end
