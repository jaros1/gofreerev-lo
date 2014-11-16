class ShareAccount < ActiveRecord::Base

  has_many :users, :class_name => 'User', :primary_key => :share_account_id, :foreign_key => :share_account_id, :dependent => :nullify

  # https://github.com/jmazzi/crypt_keeper - text columns are encrypted in database
  # encrypt_add_pre_and_postfix/encrypt_remove_pre_and_postfix added in setters/getters for better encryption
  # this is different encrypt for each attribute and each db row
  crypt_keeper :email, :encryptor => :aes, :key => ENCRYPT_KEYS[48]


  # 2) email. String in model. Encrypted text in db. Optional
  def email
    # logger.debug2  "email = #{read_attribute(:email)} (#{read_attribute(:email).class.name})"
    share_account_id = new_encrypt_pk unless share_account_id
    return nil unless (extended_email = read_attribute(:email))
    encrypt_remove_pre_and_postfix(extended_email, 'email', 49)
  end # email
  def email=(new_email)
    # logger.debug2  "email = #{new_email} (#{new_email.class.name})"
    if new_email
      check_type('email', new_email, 'String')
      write_attribute :email, encrypt_add_pre_and_postfix(new_email, 'email', 49)
    else
      self.share_account_id = new_encrypt_pk unless share_account_id
      write_attribute :email, nil
    end
  end # email=
  alias_method :email_before_type_cast, :email
  def email_was
    return email unless email_changed?
    return nil unless (extended_email = attribute_was(:email))
    encrypt_remove_pre_and_postfix(extended_email, 'email', 49)
  end # email_was  
  

  # to combine users from different providers to a "single" account
  # user have to login for each provider to see friends and gifts from each provider
  # but balance total can be shared across providers
  def self.get_share_account_id (share_level, email)
    sa = ShareAccount.new
    sa.share_level = share_level
    sa.email = email
    sa.save!
    sa.share_account_id
  end # self.next_user_combination

  ##############
  # encryption #
  ##############

  # https://github.com/jmazzi/crypt_keeper gem encrypts all attributes and all rows in db with the same key
  # this extension to use different encryption for each attribute and each row
  # overwrites non model specific methods defined in /config/initializers/active_record_extensions.rb
  protected
  def encrypt_pk
    self.share_account_id
  end
  def encrypt_pk=(new_encrypt_pk_value)
    self.share_account_id = new_encrypt_pk_value
  end
  def new_encrypt_pk
    loop do
      temp_share_account_id = String.generate_random_string(20)
      return temp_share_account_id unless ShareAccount.find_by_share_account_id(temp_share_account_id)
    end
  end

end
