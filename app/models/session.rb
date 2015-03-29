class Session < ActiveRecord::Base

  # create_table "sessions", force: true do |t|
  #  1  t.string   "session_id",       limit: 32
  #  2  t.integer  "client_userid",               default: 0
  #  3  t.text     "created"
  #  4  t.text     "expires_at"
  #  5  t.text     "flash_id"
  #  6  t.text     "language"
  #  7  t.text     "last_row_at"
  #  8  t.text     "last_row_id"
  #  9  t.text     "refresh_tokens"
  # 10  t.text     "state"
  # 11  t.text     "tokens"
  # 12  t.text     "user_ids"
  # 13  t.text     "did"
  # 14  t.text     "client_timestamp"
  # 15  t.text     "client_secret"
  # 16  t.text     "sha256"
  # 17  t.boolean  "server"
  # 18  t.datetime "created_at"
  # 19  t.datetime "updated_at"
  # end
  # add_index "sessions", ["session_id", "client_userid"], name: "index_session_session_id", unique: true, using: :btree

  # only information in session cookie are userid, timezone and secret. Other session information is in sessions table
  # each session is splitted in one section/row for each client_userid/client log in
  # data in sessions table are encrypted (crypt_keeper) with ENCRYPT_KEYS array and secret from session cookie

  # timestamps are updated manual in ActionControllerExtensions
  self.record_timestamps = false

  # https://github.com/jmazzi/crypt_keeper - text columns are encrypted in database
  # encrypt_add_pre_and_postfix/encrypt_remove_pre_and_postfix added in setters/getters for better encryption
  # this is different encrypt for each attribute and each db row
  crypt_keeper :created, :expires_at, :flash_id, :language, :last_row_at, :last_row_id, :refresh_tokens, :state, :tokens,
               :user_ids, :did, :client_timestamp, :client_secret, :sha256, :encryptor => :aes, :key => ENCRYPT_KEYS[0]

  # 1) session_id - string 32 characters = request.session_options[:id

  # 2) client_userid - integer (0, 1, 2 etc) - from client local storage login. 0 = not logged in, > 0 = logged in

  # 3) created - Time in model - encrypted text in db - start time for showing cookie note in page header (EU cookie law - stupid waste of time!)
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

  # 12) user_ids - Array in model - encrypted text in db - array with currently logged in oauth users
  # user_ids are stored encrypted in sessions table and are stored in clear in pings table
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

  # 13) did - unique device id - String in model - encrypted text in db - used when sync info between user devices
  def did
    return nil unless (extended_did = read_attribute(:did))
    encrypt_remove_pre_and_postfix(extended_did, 'did', 11)
  end # did
  def did=(new_did)
    if new_did
      # logger.debug2  "new_did = #{new_did} (#{new_did.class.name})"
      check_type('did', new_did, 'String')
      write_attribute :did, encrypt_add_pre_and_postfix(new_did, 'did', 11)
    else
      write_attribute :did, nil
    end
  end # did=
  alias_method :did_before_type_cast, :did
  def did_was
    return did unless did_changed?
    return nil unless (extended_did = attribute_was(:did))
    encrypt_remove_pre_and_postfix(extended_did, 'did', 11)
  end # did_was

  # 14) client_timestamp - JS unix timestamp with miliseconds - Fixnum/Bignum in model - encrypted text in db
  def client_timestamp
    return nil unless (temp_client_timestamp = read_attribute(:client_timestamp))
    # logger.debug2  "temp_client_timestamp = #{temp_client_timestamp}"
    encrypt_remove_pre_and_postfix(temp_client_timestamp, 'client_timestamp', 12).to_i
  end # client_timestamp
  def client_timestamp=(new_client_timestamp)
    if new_client_timestamp
      check_type('client_timestamp', new_client_timestamp, 'Bignum')
      write_attribute :client_timestamp, encrypt_add_pre_and_postfix(new_client_timestamp.to_s, 'client_timestamp', 12)
    else
      write_attribute :client_timestamp, nil
    end
  end # client_timestamp=
  alias_method :client_timestamp_before_type_cast, :client_timestamp
  def client_timestamp_was
    return client_timestamp unless client_timestamp_changed?
    return nil unless (temp_client_timestamp = attribute_was(:client_timestamp))
    encrypt_remove_pre_and_postfix(temp_client_timestamp, 'client_timestamp', 12).to_i
  end # client_timestamp_was

  # 15) client_secret - String in model - encrypted text in db - used as secret element in device.sha256 signature
  def client_secret
    return nil unless (extended_client_secret = read_attribute(:client_secret))
    encrypt_remove_pre_and_postfix(extended_client_secret, 'client_secret', 13)
  end # client_secret
  def client_secret=(new_client_secret)
    if new_client_secret
      # logger.debug2  "new_client_secret = #{new_client_secret} (#{new_client_secret.class.name})"
      check_type('client_secret', new_client_secret, 'String')
      write_attribute :client_secret, encrypt_add_pre_and_postfix(new_client_secret, 'client_secret', 13)
    else
      write_attribute :client_secret, nil
    end
  end # client_secret=
  alias_method :client_secret_before_type_cast, :client_secret
  def client_secret_was
    return client_secret unless client_secret_changed?
    return nil unless (extended_client_secret = attribute_was(:client_secret))
    encrypt_remove_pre_and_postfix(extended_client_secret, 'client_secret', 13)
  end # client_secret_was

  # 16) sha256 - String in model - encrypted text in db - used together with did as an unique mailbox address in client to client communication
  # sha256 changes for each client device login - sha256 changes for each client api provider login
  # that ensures that messages only are send to and received by intended client
  # see set_column_value method
  def sha256
    return nil unless (extended_sha256 = read_attribute(:sha256))
    encrypt_remove_pre_and_postfix(extended_sha256, 'sha256', 14)
  end # sha256
  def sha256=(new_sha256)
    if new_sha256
      # logger.debug2  "new_sha256 = #{new_sha256} (#{new_sha256.class.name})"
      check_type('sha256', new_sha256, 'String')
      write_attribute :sha256, encrypt_add_pre_and_postfix(new_sha256, 'sha256', 14)
    else
      write_attribute :sha256, nil
    end
  end # sha256=
  alias_method :sha256_before_type_cast, :sha256
  def sha256_was
    return sha256 unless sha256_changed?
    return nil unless (extended_sha256 = attribute_was(:sha256))
    encrypt_remove_pre_and_postfix(extended_sha256, 'sha256', 14)
  end # sha256_was

  # 17) server - boolean in model and db - not encrypted
  # false: user/browser, true: other gofreerev server
  # is blank in a new session until login process is completed
  validates_inclusion_of :server, :in => [true, false], :allow_blank => true
  
  # 18) system_secret_updated_at - copy of SystemParameter.updated_at timestamp for secret
  # all sessions must download updated sha256 signatures after change in system secret / user sha256 signatures
  # datetime in model and database

  # 19) last_short_friends_list_at - timestamp for last short friends list download in util_controller.ping
  # relevant client sessions must download updated sha256 signatures after change in user information for login users,
  # friends of login users and friend of friends of login users
  # datetime in model and database

  # 20) created_at

  # 21) updated_at

  # secret from session cookie. encrypt/decrypt data in sessions table with secret from cookie
  attr_accessor :secret

  public
  def set_column_value (key, value)
    key = key.to_sym
    case key
      when :client_secret then self.client_secret = value
      when :client_timestamp then self.client_timestamp = value
      when :created then self.created = value
      when :did then self.did = value
      when :expires_at then self.expires_at = value
      when :flash_id then self.flash_id = value
      when :language then self.language = value
      when :last_row_at then self.last_row_at = value
      when :last_row_id then self.last_row_id = value
      when :last_short_friends_list_at then self.last_short_friends_list_at = value
      when :refresh_tokens then self.refresh_tokens = value
      when :server then self.server = value
      when :state then self.state = value
      when :system_secret_updated_at then self.system_secret_updated_at = value
      when :tokens then self.tokens = value
      when :user_ids
        # logger.debug "#{key} = #{value}"
        self.user_ids = value
        # update sha256 signature (client_secret + user_ids) - used in ping - used in client to client communication
        if self.server
          # sha256 is not used in server to server communication
          self.sha256 = nil
        elsif value.class == Array
          sha256_input = ([self.client_secret]+value.sort).join(',')
          self.sha256 = Base64.encode64(Digest::SHA256.digest(sha256_input))
        else
          self.sha256 = nil
        end
        # logger.debug "self.user_ids = #{self.user_ids}"
      else raise "unknown key #{key}"
    end # case
    value
  end # set_column_value


  def self.close_server_sessions
    Session.where(:server => true).delete_all
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
