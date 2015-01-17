class Session < ActiveRecord::Base

  # create_table "sessions", force: true do |t|
  #   t.string   "session_id",     limit: 32
  #   t.integer  "client_userid",             default: 0
  #   t.text     "created"
  #   t.text     "expires_at"
  #   t.text     "flash_id"
  #   t.text     "language"
  #   t.text     "last_row_at"
  #   t.text     "last_row_id"
  #   t.text     "refresh_tokens"
  #   t.text     "state"
  #   t.text     "tokens"
  #   t.text     "user_ids"
  #   t.datetime "created_at"
  #   t.datetime "updated_at"
  # end

  # timestamps are updated manual in ActionControllerExtensions
  self.record_timestamps = false

  crypt_keeper :created, :expires_at, :encryptor => :aes, :key => ENCRYPT_KEYS[0]

  # 1) session_id - string 32 characters = request.session_options[:id

  # 2) client_userid - integer (0, 1, 2 etc) - from client local storage login. 0 = not logged in, > 0 = logged in

  # 3) created - Time in model - encrypted text in db - start time for showing cookie note in page header (fuck EU)
  def created
    return nil unless (extended_created = read_attribute(:created))
    encrypt_remove_pre_and_postfix(extended_created, 'created', 1).to_time
  end # created
  def created=(new_created)
    if new_created
      # logger.debug2  "new_created = #{new_created} (#{new_created.class.name})"
      check_type('created', new_created, 'Time')
      write_attribute :created, encrypt_add_pre_and_postfix(new_created.to_s, 'created', 1)
    else
      write_attribute :created, nil
    end
  end # created=
  alias_method :created_before_type_cast, :created
  def created_was
    return created unless created_changed?
    return nil unless (extended_created = attribute_was(:created))
    encrypt_remove_pre_and_postfix(extended_created, 'created', 1)
  end # created_was
  
  # 4) expires_at - Hash in model - encrypted text in db - unix timestamp for oauth tokens
  def expires_at
    return nil unless (temp_extended_expires_at = read_attribute(:expires_at))
    # logger.debug2  "temp_extended_expires_at = #{temp_extended_expires_at}"
    YAML::load encrypt_remove_pre_and_postfix(temp_extended_expires_at, 'expires_at', 2)
  end # expires_at
  def expires_at=(new_expires_at)
    if new_expires_at
      check_type('expires_at', new_expires_at, 'Hash')
      write_attribute :expires_at, encrypt_add_pre_and_postfix(new_expires_at.to_yaml, 'expires_at', 2)
    else
      write_attribute :expires_at, nil
    end
  end # expires_at=
  alias_method :expires_at_before_type_cast, :expires_at
  def expires_at_was
    return expires_at unless expires_at_changed?
    return nil unless (temp_extended_expires_at = attribute_was(:expires_at))
    YAML::load encrypt_remove_pre_and_postfix(temp_extended_expires_at, 'expires_at', 2)
  end # expires_at_was

  # 5) flash_id - Fixnum/Bignum in model - encrypted text in db
  def flash_id
    return nil unless (temp_flash_id = read_attribute(:flash_id))
    # logger.debug2  "temp_flash_id = #{temp_flash_id}"
    encrypt_remove_pre_and_postfix(temp_flash_id, 'flash_id', 3).to_i
  end # flash_id
  def flash_id=(new_flash_id)
    if new_flash_id
      check_type('flash_id', new_flash_id, 'Bignum')
      write_attribute :flash_id, encrypt_add_pre_and_postfix(new_flash_id.to_s, 'flash_id', 3)
    else
      write_attribute :flash_id, nil
    end
  end # flash_id=
  alias_method :flash_id_before_type_cast, :flash_id
  def flash_id_was
    return flash_id unless flash_id_changed?
    return nil unless (temp_flash_id = attribute_was(:flash_id))
    encrypt_remove_pre_and_postfix(temp_flash_id, 'flash_id', 3).to_i
  end # flash_id_was

  # 6) language - String in model - encrypted text in db - 2 characters - en, da etc
  def language
    return nil unless (extended_language = read_attribute(:language))
    encrypt_remove_pre_and_postfix(extended_language, 'language', 4)
  end # language
  def language=(new_language)
    if new_language
      # logger.debug2  "new_language = #{new_language} (#{new_language.class.name})"
      check_type('language', new_language, 'String')
      write_attribute :language, encrypt_add_pre_and_postfix(new_language, 'language', 4)
    else
      write_attribute :language, nil
    end
  end # language=
  alias_method :language_before_type_cast, :language
  def language_was
    return language unless language_changed?
    return nil unless (extended_language = attribute_was(:language))
    encrypt_remove_pre_and_postfix(extended_language, 'language', 4)
  end # language_was

  # 7) last_row_at - Float in model (seconds since midnight) - encrypted text in db (old show more rows functionality)
  def last_row_at
    return nil unless (temp_extended_last_row_at = read_attribute(:last_row_at))
    str_to_float_or_nil encrypt_remove_pre_and_postfix(temp_extended_last_row_at, 'last_row_at', 5)
  end # last_row_at
  def last_row_at=(new_last_row_at)
    if new_last_row_at.to_s != ''
      check_type('last_row_at', new_last_row_at, 'Float')
      write_attribute :last_row_at, encrypt_add_pre_and_postfix(new_last_row_at.to_s, 'last_row_at', 5)
    else
      write_attribute :last_row_at, nil
    end
  end # last_row_at=
  alias_method :last_row_at_before_type_cast, :last_row_at
  def last_row_at_was
    return last_row_at unless last_row_at_changed?
    return nil unless (temp_extended_last_row_at = attribute_was(:last_row_at))
    str_to_float_or_nil encrypt_remove_pre_and_postfix(temp_extended_last_row_at, 'last_row_at', 5)
  end # last_row_at_was

  # 8) last_row_id - Integer in model (status_update_at_seq sequence) - encrypted text in db
  def last_row_id
    return nil unless (temp_last_row_id = read_attribute(:last_row_id))
    # logger.debug2  "temp_last_row_id = #{temp_last_row_id}"
    encrypt_remove_pre_and_postfix(temp_last_row_id, 'last_row_id', 6).to_i
  end # last_row_id
  def last_row_id=(new_last_row_id)
    if new_last_row_id
      check_type('last_row_id', new_last_row_id, 'Bignum')
      write_attribute :last_row_id, encrypt_add_pre_and_postfix(new_last_row_id.to_s, 'last_row_id', 6)
    else
      write_attribute :last_row_id, nil
    end
  end # last_row_id=
  alias_method :last_row_id_before_type_cast, :last_row_id
  def last_row_id_was
    return last_row_id unless last_row_id_changed?
    return nil unless (temp_last_row_id = attribute_was(:last_row_id))
    encrypt_remove_pre_and_postfix(temp_last_row_id, 'last_row_id', 6).to_i
  end # last_row_id_was

  # 9) refresh_tokens - Hash in model - encrypted text in db - only used for google+
  def refresh_tokens
    return nil unless (temp_extended_refresh_tokens = read_attribute(:refresh_tokens))
    # logger.debug2  "temp_extended_refresh_tokens = #{temp_extended_refresh_tokens}"
    YAML::load encrypt_remove_pre_and_postfix(temp_extended_refresh_tokens, 'refresh_tokens', 7)
  end # refresh_tokens
  def refresh_tokens=(new_refresh_tokens)
    if new_refresh_tokens
      check_type('refresh_tokens', new_refresh_tokens, 'Hash')
      write_attribute :refresh_tokens, encrypt_add_pre_and_postfix(new_refresh_tokens.to_yaml, 'refresh_tokens', 7)
    else
      write_attribute :refresh_tokens, nil
    end
  end # refresh_tokens=
  alias_method :refresh_tokens_before_type_cast, :refresh_tokens
  def refresh_tokens_was
    return refresh_tokens unless refresh_tokens_changed?
    return nil unless (temp_extended_refresh_tokens = attribute_was(:refresh_tokens))
    YAML::load encrypt_remove_pre_and_postfix(temp_extended_refresh_tokens, 'refresh_tokens', 7)
  end # refresh_tokens_was

  # 10) state - String in model - encrypted text in db - used in oauth cross-site Request Forgery protection
  def state
    return nil unless (extended_state = read_attribute(:state))
    encrypt_remove_pre_and_postfix(extended_state, 'state', 8)
  end # state
  def state=(new_state)
    if new_state
      # logger.debug2  "new_state = #{new_state} (#{new_state.class.name})"
      check_type('state', new_state, 'String')
      write_attribute :state, encrypt_add_pre_and_postfix(new_state, 'state', 8)
    else
      write_attribute :state, nil
    end
  end # state=
  alias_method :state_before_type_cast, :state
  def state_was
    return state unless state_changed?
    return nil unless (extended_state = attribute_was(:state))
    encrypt_remove_pre_and_postfix(extended_state, 'state', 8)
  end # state_was

  # 11) tokens - Hash in model - encrypted text in db - api oath tokens for each login provider
  def tokens
    return nil unless (temp_extended_tokens = read_attribute(:tokens))
    # logger.debug2  "temp_extended_tokens = #{temp_extended_tokens}"
    YAML::load encrypt_remove_pre_and_postfix(temp_extended_tokens, 'tokens', 9)
  end # tokens
  def tokens=(new_tokens)
    if new_tokens
      check_type('tokens', new_tokens, 'Hash')
      write_attribute :tokens, encrypt_add_pre_and_postfix(new_tokens.to_yaml, 'tokens', 9)
    else
      write_attribute :tokens, nil
    end
  end # tokens=
  alias_method :tokens_before_type_cast, :tokens
  def tokens_was
    return tokens unless tokens_changed?
    return nil unless (temp_extended_tokens = attribute_was(:tokens))
    YAML::load encrypt_remove_pre_and_postfix(temp_extended_tokens, 'tokens', 9)
  end # tokens_was

  # 12) user_ids - Array in model - encrypted text in db - array with currency logged in oauth users
  def user_ids
    return nil unless (temp_extended_user_ids = read_attribute(:user_ids))
    # logger.debug2  "temp_extended_user_ids = #{temp_extended_user_ids}"
    YAML::load encrypt_remove_pre_and_postfix(temp_extended_user_ids, 'user_ids', 10)
  end # user_ids
  def user_ids=(new_user_ids)
    if new_user_ids
      check_type('user_ids', new_user_ids, 'Array')
      write_attribute :user_ids, encrypt_add_pre_and_postfix(new_user_ids.to_yaml, 'user_ids', 10)
    else
      write_attribute :user_ids, nil
    end
  end # user_ids=
  alias_method :user_ids_before_type_cast, :user_ids
  def user_ids_was
    return user_ids unless user_ids_changed?
    return nil unless (temp_extended_user_ids = attribute_was(:user_ids))
    YAML::load encrypt_remove_pre_and_postfix(temp_extended_user_ids, 'user_ids', 10)
  end # user_ids_was

  # 13) created_at

  # 14) updated_at

  # set secret from session cookie
  attr_accessor :secret

  public
  def set_column_value (key, value)
    key = key.to_sym
    case key
      when :created then self.created = value
      when :expires_at then self.expires_at = value
      when :flash_id then self.flash_id = value
      when :language then self.language = value
      when :last_row_at then self.last_row_at = value
      when :last_row_id then self.last_row_id = value
      when :refresh_tokens then self.refresh_tokens = value
      when :state then self.state = value
      when :tokens then self.tokens = value
      when :user_ids then self.user_ids = value
      else raise "unknown key #{key}"
    end # case
  end


  ##############
  # encryption #
  ##############

  # https://github.com/jmazzi/crypt_keeper gem encrypts all attributes and all rows in db with the same key
  # this extension to use different encryption for each attribute and each row
  # overwrites non model specific methods defined in /config/initializers/active_record_extensions.rb
  protected
  def encrypt_pk
    secret
  end
  def encrypt_pk=(new_encrypt_pk_value)
    secret = new_encrypt_pk_value
  end
  def new_encrypt_pk
    secret
  end

end
