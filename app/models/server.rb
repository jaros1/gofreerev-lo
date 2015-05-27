class Server < ActiveRecord::Base

  # create_table "servers", force: true do |t|
  #  1  t.string   "site_url"
  #  2  t.boolean  "secure"
  #  3  t.string   "new_did",              limit: 20
  #  4  t.text     "new_pubkey"
  #  5  t.string   "old_did",              limit: 20
  #  6  t.text     "old_pubkey"
  #  7  t.decimal  "last_ping_at",                    precision: 13, scale: 3
  #  8  t.decimal  "next_ping_at",                    precision: 13, scale: 3
  #  9  t.text     "key"
  # 10  t.string   "secret"
  # 11  t.integer  "last_checked_user_id"
  #     t.datetime "created_at"
  #     t.datetime "updated_at"
  # end
  # add_index "servers", ["site_url"], name: "index_servers_url", unique: true, using: :btree

  has_many :server_users
  has_many :pubkeys

  # 1: site_url - other others SITE_URL but always http://...
  # secure is true if site supports ssl. secure is false if site doesn't support ssl
  validates_presence_of :site_url
  validates_uniqueness_of :site_url
  validates_format_of :site_url, :with => /\Ahttp:/

  # 2: secure. true if server supports https. false if server doesn't support ssl.
  # always to use ssl. self-signed ssl certificate is better than no certificate.
  validates_inclusion_of :secure, :in => [true, false]

  # 3: new_did - new unvalidated did - unique device id - unix timestamp (10) with milliseconds (3) and random numbers (7) - total 20 decimals
  validates_format_of :new_did, :with => /\A[0-9]{20}\z/, :allow_blank => true

  # 4: new_pubkey - new unvalidated public key

  # 5: old_did - old validated did - unique device id - unix timestamp (10) with milliseconds (3) and random numbers (7) - total 20 decimals

  # 6: old_pubkey - old validated public key

  # 7: last_ping_at - last ping request to server - last outgoing ping
  # datetime with milliseconds in model - decimal(13,3) in database
  def last_ping_at
    return nil unless (temp_last_ping_at = read_attribute(:last_ping_at))
    # logger.debug2  "temp_last_ping_at = #{temp_last_ping_at}"
    Time.at temp_last_ping_at
  end

  def last_ping_at=(new_last_ping_at)
    if new_last_ping_at
      check_type('last_ping_at', new_last_ping_at, 'Time')
      write_attribute :last_ping_at, new_last_ping_at.to_f
    else
      write_attribute :last_ping_at, nil
    end
  end

  # last_ping_at=
  alias_method :last_ping_at_before_type_cast, :last_ping_at

  def last_ping_at_was
    return last_ping_at unless last_ping_at_changed?
    return nil unless (temp_last_ping_at = attribute_was(:last_ping_at))
    Time.at temp_last_ping_at
  end

  # last_ping_at_was

  # 8: next_ping_at - next ping request to server - next outgoing ping
  # datetime with milliseconds in model - decimal(13,3) in database
  def next_ping_at
    return nil unless (temp_next_ping_at = read_attribute(:next_ping_at))
    # logger.debug2  "temp_next_ping_at = #{temp_next_ping_at}"
    Time.at temp_next_ping_at
  end

  def next_ping_at=(new_next_ping_at)
    if new_next_ping_at
      check_type('next_ping_at', new_next_ping_at, 'Time')
      write_attribute :next_ping_at, new_next_ping_at.to_f
    else
      write_attribute :next_ping_at, nil
    end
  end

  # next_ping_at=
  alias_method :next_ping_at_before_type_cast, :next_ping_at

  def next_ping_at_was
    return next_ping_at unless next_ping_at_changed?
    return nil unless (temp_next_ping_at = attribute_was(:next_ping_at))
    Time.at temp_next_ping_at
  end

  # next_ping_at_was

  # 9: key - encrypt symmetric password information in memory storage
  # symmetric passwords will be generated after server restart

  # 10: secret - secret from server used in user.sha256 signature. used in server to server users message

  # 11: last_checked_user_id. last user id compared in users message. Compare starts with lowest user id


  # password helpers. symmetric password stored in memory encrypted with key stored in database
  # symmetric passwords used in server to server communication expires after one hour

  # key - symmetric password for password stored in shared memory
  def set_key
    self.key = String.generate_random_string(80)
    logger.secret2 "old key = #{self.key_was}"
    logger.secret2 "new key = #{self.key}"
  end

  # password1 - this servers part of symmetric password
  def new_password1=(password)
    if password
      self.set_key unless key
      Rails.cache.write "#{self.site_url}new_password1", password.encrypt(:symmetric, :password => self.key)
    else
      Rails.cache.write "#{self.site_url}new_password1", nil
    end
  end

  def new_password1
    password = Rails.cache.fetch "#{self.site_url}new_password1"
    password ? password.decrypt(:symmetric, :password => self.key) : nil
  end

  def new_password1_at=(timestamp)
    Rails.cache.write "#{self.site_url}new_password1_at", timestamp
  end

  def new_password1_at
    Rails.cache.fetch "#{self.site_url}new_password1_at"
  end

  # symmetric password setup
  # protected
  public # todo: change to protected
  def set_new_password1
    self.set_key unless key
    self.new_password1 = String.generate_random_string(80)
    self.new_password1_at = (Time.now.to_f*1000).floor
    self.new_password2 = nil
    self.new_password2_at = nil
    self.save!
    logger.secret2 "key = #{self.key}, new_password1 = #{self.new_password1}, new_password1_at = #{self.new_password1_at}"
  end

  # password 2 - other servers part of symmetric password
  def new_password2=(password)
    if password
      self.set_key unless key
      Rails.cache.write "#{self.site_url}new_password2", password.encrypt(:symmetric, :password => self.key)
    else
      Rails.cache.write "#{self.site_url}new_password2", nil
    end
  end

  def new_password2
    password = Rails.cache.fetch "#{self.site_url}new_password2"
    password ? password.decrypt(:symmetric, :password => self.key) : nil
  end

  def new_password2_at=(timestamp)
    Rails.cache.write "#{self.site_url}new_password2_at", timestamp
  end

  def new_password2_at
    Rails.cache.fetch "#{self.site_url}new_password2_at"
  end

  # new password (password1 from this server and password2 from other server)
  def new_password
    return nil unless self.new_password1 and self.new_password2
    if self.new_password1_at <= self.new_password2_at
      self.new_password1 + self.new_password2
    else
      self.new_password2 + self.new_password1
    end
  end

  def new_password_md5
    new_password = self.new_password
    new_password ? Digest::MD5.digest(new_password) : nil
  end


  # receive did and public key from other gofreerev server
  # saved in new_did and new_public if changed - must be validated before moved to old_did and old_pubkey
  # called from server.login (model) and util.login (controller)
  public
  def save_new_did_and_public_key (did, pubkey)
    if ![self.old_did, self.new_did].index(did)
      # new did received. ok to change to a new did - not ok to change to a existing did
      return "#{site_url}: Cannot change did to #{did}. did #{did} already exists" if Pubkey.find_by_did(did)
      logger.warn2 "#{site_url}: changing did to #{did}"
      self.new_did = did
      self.new_pubkey = pubkey
      self.set_new_password1
      self.save!
      return nil
    end
    # check/save received public key
    return if did == self.old_did and pubkey == self.old_pubkey # unchange old public key
    return if did == self.new_did and pubkey == self.new_pubkey # unchange new public key
    if did == self.old_did and pubkey != self.old_pubkey
      # changed old public key
      logger.warn2 "#{site_url}: received new public key for old did #{did}"
      self.new_did = did # changed old public key
      self.new_pubkey = pubkey
      self.set_new_password1
    end
    if did == self.new_did and pubkey != self.new_pubkey
      # changed new public key
      logger.debug2 "#{site_url}: received new public key for new did #{did}"
      self.new_pubkey = pubkey
      self.set_new_password1
    end
    self.save! if self.changed?
    nil
  end

  # save_new_did_and_public_key!

  # path to cookie file, signature file etc
  # md5 chosen for shorter filename/path
  # md5 may not be the best hash but cookie files are private and signature files also include a client timestamp
  protected
  def site_url_md5_path
    Digest::MD5.hexdigest(self.site_url).scan(/.{2}/)
  end

  # get filename for cookie store used in httpclient - one file per gofreerev server
  protected
  def cookie_filename
    site_url_md5_path = self.site_url_md5_path()
    parent_dir = Rails.root.join('tmp/cookies/'+site_url_md5_path[0..-2].join('/')).to_s
    FileUtils.mkdir_p parent_dir
    parent_dir + '/' + site_url_md5_path.last + '.cookie'
  end

  # get signature filename - some requests are signed so that called server can verify the request
  protected
  def signature_filename (client_timestamp)
    site_url_md5_path = self.site_url_md5_path()
    parent_dir = Rails.root.join('public/signatures/'+site_url_md5_path.join('/')).to_s
    FileUtils.mkdir_p parent_dir
    parent_dir + '/' + client_timestamp.to_s + '.txt'
  end

  public
  def signature_url (client_timestamp)
    "#{self.site_url}signatures/#{SITE_SIGNATURE_PATH}/#{client_timestamp}.txt"
  end

  # signature used in server to server login request
  # created in Server.login and validated in UtilController.login
  public
  def self.login_signature (hash)
    Digest::SHA256.hexdigest([hash[:client_secret], hash[:did], hash[:pubkey]].join(','))
  end

  # signature used in server to server ping request
  # created in Server.ping and validated in UtilController.ping
  # ping_request = {
  #     client_userid: 1,
  #     sid: sid,
  #     client_timestamp: new_client_timestamp,
  #     # new_gifts: giftService.new_gifts_request(),
  #     # verify_gifts: giftService.verify_gifts_request(),
  #     # delete_gifts: giftService.delete_gifts_request(),
  #     # new_comments: giftService.new_comments_request(),
  #     # verify_comments: giftService.verify_comments_request(),
  #     # pubkeys: giftService.pubkeys_request(),
  #     # refresh_tokens: result.refresh_tokens_request,
  #     messages: self.send_messages
  # }
  public
  def self.ping_signature (did, secret, hash)
    if hash[:messages]
      messages = hash[:messages].collect do |m|
        [m[:sender_did], m[:receiver_did], m[:receiver_sha256], m[:server], m[:encryption], m[:key], m[:message]].join(',')
      end.join(',')
    else
      messages = ''
    end
    sha256_input = [did, secret, hash[:sid], messages].join(',')
    sha256 = Digest::SHA256.hexdigest(sha256_input)
    # logger.secret2 "hash         = #{hash.to_json}"
    logger.secret2 "sha256_input = #{sha256_input}"
    logger.secret2 "sha256       = #{sha256}"
    sha256
  end

  # self.ping_signature


  # verify that sha256 signature generated from incoming request matches signature file on sending server
  # signature file must exists and sha256 signature must match
  # used for login and ping request from other Gofreerev servers
  public
  def invalid_signature(client_timestamp, signature)
    # url to signature file on other gofreerev server
    signature_url = self.signature_url(client_timestamp)
    secure = self.secure
    signature_url = 'https' + signature_url.from(4) if secure

    # create http client
    client = HTTPClient.new
    client.set_cookie_store(self.cookie_filename()) # one cookie file per gofreerev server

    # loop. fallback to http if https fails
    res = nil
    loop do
      url = URI.parse("#{signature_url}")
      begin
        logger.warn2 "unsecure get #{url}" unless secure
        res = client.get("#{url}")
      rescue Errno::ECONNREFUSED, OpenSSL::SSL::SSLError => e
        if secure
          # https failed. retry with http
          logger.debug "secure get #{url} failed with #{e.message}. Trying without ssl"
          secure = false
          signature_url = 'http' + signature_url.from(5)
          next
        end
        return "signature verification failed with: \"#{e.message}\""
      end
      break
    end
    if !res
      error = "signature #{signature_url} was not found"
      logger.debug2 error
      return error
    end
    return nil if signature == res.body

    error = "signature #{signature_url} was not valid"
    logger.debug2 error
    logger.debug2 "signature = #{signature}"
    logger.debug2 "res.body  = #{res.body}"
    return error

  end

  # invalid_signature


  # login as client to on other gofreerev server (SITE_URL, did, public key, secret)
  # server validation and login process is completed with server to server messages:
  # - validate site_url
  # - generate password for symmetric communication
  # - compare meta information for users
  # - exchange information about online friends
  # - sync gifts information
  public
  def login
    # always try with secure login if possible
    site_url = 'https' + self.site_url.from(4)
    secure = true

    # create http client
    client = HTTPClient.new
    client.set_cookie_store(self.cookie_filename()) # one cookie file per gofreerev server

    # get session cookie and authenticity token (XSRF-TOKEN) from gofreerev server
    # loop. first loop with secure = true. second loop with secure = false
    res = nil
    url = nil
    loop do
      url = URI.parse("#{site_url}en/main")
      begin
        logger.warn2 "unsecure get #{url}" unless secure
        res = client.get("#{url}")
      rescue Errno::ECONNREFUSED => e
        return "get #{url.to_s} failed with: \"#{e.message}\""
      rescue OpenSSL::SSL::SSLError => e
        if secure
          # https failed. retry with http
          logger.debug "secure get #{url} failed with #{e.message}. Trying without ssl"
          secure = false
          site_url = self.site_url
          next
        end
        return "get #{url.to_s} failed with: \"#{e.message}\""
      end
      break
    end
    return "get #{url.to_s} failed with status #{res.status}" unless res.status == 200
    if self.secure != secure
      self.secure = secure
      self.save!
      logger.warn2 "secure changed to #{secure} for #{self.site_url}"
    end
    xsrf_token = nil
    client.cookie_manager.cookies.each do |cookie|
      # logger.debug2 "cookie = #{cookie.to_json}"
      xsrf_token = cookie.value if cookie.name == 'XSRF-TOKEN'
    end
    return "No XSRF-TOKEN was received from #{url.to_s}" unless xsrf_token
    # client.save_cookie_store # not working. discard=true for all cookies
    client.cookie_manager.save_all_cookies(true, true, true)

    # post login request to other gofreerev server
    # todo: more encryption in login request?
    #       could use site_url + mix encrypted message
    #       { :encryption => 'mix', key => xxx, :message => xxx }
    #       add /util/login_mix action, decrypt message and redirect to /util/login
    #       or decrypt filter before login
    SystemParameter.generate_key_pair unless SystemParameter.public_key
    url = URI.parse("#{site_url}util/login.json")
    login_request = {:client_userid => 1,
                     :client_timestamp => (Time.now.to_f*1000).floor,
                     :client_secret => SystemParameter.secret,
                     :did => SystemParameter.did,
                     :pubkey => SystemParameter.public_key,
                     :site_url => SITE_URL}
    # X_XSRF_TOKEN - escaped in cookie - unescaped in request header
    header = {'X_XSRF_TOKEN' => CGI::unescape(xsrf_token), 'Content-Type' => 'application/json'}

    # json validate login request before send
    json_schema = :login_request
    if !JSON_SCHEMA.has_key? json_schema
      return "Could not validate login request. JSON schema definition #{json_schema.to_s} was not found."
    end
    json_errors = JSON::Validator.fully_validate(JSON_SCHEMA[json_schema], login_request)
    return "Invalid login json request: #{json_errors.join(', ')}" unless json_errors.size == 0

    # sign login request - called gofreerev server must validate signature for incoming login request
    signature_filename = self.signature_filename(login_request[:client_timestamp])
    signature = Server.login_signature(login_request)
    logger.debug2 "signature_filename = #{signature_filename}"
    logger.debug2 "signature = #{signature}"
    File.write(signature_filename, signature)

    # send login request
    logger.warn2 "unsecure post #{url}" unless secure
    res = client.post(url, :body => login_request.to_json, :header => header)
    logger.debug2 "res = #{res}"
    FileUtils.rm signature_filename
    if res.status != 200
      puts "post #{url.to_s} failed with status #{res.status}"
      return nil
    end
    client.cookie_manager.save_all_cookies(true, true, true)

    # json validate login response
    login_response = JSON.parse(res.body)
    logger.debug2 "login_response = #{login_response}"
    json_schema = :login_response
    if !JSON_SCHEMA.has_key? json_schema
      return "Could not validate login response. JSON schema definition #{json_schema.to_s} was not found."
    end
    json_errors = JSON::Validator.fully_validate(JSON_SCHEMA[json_schema], login_response)
    return "Invalid login json response: #{json_errors.join(', ')}" unless json_errors.size == 0
    return login_response['error'] if login_response['error']

    # check/save received did as new_did (new unvalidated unique device id)
    error = save_new_did_and_public_key(login_response['did'], login_response['pubkey'])
    return error if error
    # save secret from other gofreerev server. used when comparing users between two Gofreerev servers
    self.secret = login_response['client_secret']
    self.save!

    nil

  end

  # login


  # create rsa message - symmetric password setup - send/resend until md5 check ok
  # done: false: password setup in progress, true: password setup completed
  public
  def sym_password_message (done)
    # rsa symmetric password setup message. array with 3-4 elements. 4 elements if md5 and ready for md5 check
    # [0, new_password1, new_password1_at, new_password_md5]
    if !self.new_password1 or !self.new_password1_at
      logger.error2 "Error. new_password1 was not found"
      self.set_new_password1
      self.save!
    end
    message = [(done ? 1 : 0), self.new_password1, self.new_password1_at] # 0 = symmetric password setup, 1 = symmetric password setup completed
    if new_password_md5 = self.new_password_md5
      new_password_md5 = Base64.encode64(new_password_md5)
      message << new_password_md5
      logger.debug2 "md5 = #{new_password_md5}"
    end
    # server.new_password_md5
    message_str = message.join(',')
    logger.secret2 "message_json = #{message_str}"
    key = OpenSSL::PKey::RSA.new self.new_pubkey
    logger.debug2 "message_str.size = #{message_str.size}"
    message_str_rsa_enc = Base64.encode64(key.public_encrypt(message_str, OpenSSL::PKey::RSA::PKCS1_OAEP_PADDING))
    logger.debug2 "message_str_rsa_enc = #{message_str_rsa_enc}"
    # add envelope for encrypted rsa message
    # receiver_sha256 is only used in client to client communication = sha256 (client_secret + login_user ids)
    # client_secret is received in login request and saved in sessions table
    # sha256 values changes when client changes api provider login
    # ensures that messages are delivered to "correct" mailbox (did + authorization)
    # messages and api provider authorization must match in client to client messages
    # for now no usage in server to server messages
    message_with_envelope = {
        sender_did: SystemParameter.did,
        receiver_did: self.new_did,
        server: true,
        encryption: 'rsa',
        message: message_str_rsa_enc
    }
    logger.debug2 "message_with_envelope = #{message_with_envelope}"
    message_with_envelope
  end

  # sym_password_message


  # check for user doublets in compare users message before send / after receive
  private
  def validate_compare_users_message (users)
    logger.debug2 "users = #{users}"
    # doublet check 1 - no doublet user ids are allowed in response array
    user_id_doublets = users.group_by { |u| u['user_id'] }.select { |k, v| v.size > 1 }.keys
    return "compare users message with doublet user_ids #{user_id_doublets.join(', ')}" if user_id_doublets.size > 0
    # doublet check 2 - error if sha256 values doublets - todo: see todo # 395
    # separate doublet check for positive user ids and negative user ids
    # (positive user id from client and negative user id from server - server to server communication)
    sha256_values = users.find_all do |usr|
      usr['sha256'].to_s != ''
    end.collect do |usr|
      sender = usr['user_id'] >= 0 ? 'client' : 'server'
      {'sha256' => "#{usr['sha256']} (#{sender})"}
    end
    sha256_doublets = sha256_values.group_by { |u| u['sha256'] }.select { |k, v| v.size > 1 }.keys
    return "compare users message with doublet sha256 values #{sha256_doublets.join(', ')}" if sha256_doublets.size > 0
    # no doublets in message
    nil
  end

  # validate_compare_users_message


  # create symmetric encrypted users message. return message or nil if no new users to check
  # match user information with other Gofreerev server
  # matching is done with user.sha256
  # send user_id + server user.sha256 to other Gofreerev server
  # receive user_id + client user.sha256 from other Gofreerev server
  # comparing is done with sha256 signatures - no user information is exchanged
  # user_id > 0 - user from Gofreerev server - complete verified in one request/response cycle
  # user_id < 0 - user from other Gofreerev server - received in response - response in next request
  # params:
  # - pseudo_user_ids: hash with user_ids in users message (if any). user_ids are checked in Server.ping
  #                    when receiving response to users message
  protected
  def create_compare_users_message (pseudo_user_ids)
    request = []
    # 1) reverse request/response cycle (request received in response and response returned in request).
    # that is users with negative user_id and sha256 received from server in last ping response
    buffer = ServerUserRequest.where('server_id = ? and pseudo_user_id < 0', self.id)
    buffer.each do |usr|
      u = User.find_by_sha256(usr.sha256)
      if !u
        request << {'user_id' => usr.pseudo_user_id, 'sha256' => nil}
        next
      end
      # sha256 match
      request << {'user_id' => usr.pseudo_user_id, 'sha256' => u.calc_sha256(self.secret)}
      # insert user match as NOT verified in server_users table
      su = ServerUser.find_by_server_id_and_user_id(self.id, u.id)
      if su
        logger.debug2 "old su #{su.to_json} already exists"
        if su.remote_pseudo_user_id and su.remote_pseudo_user_id != -usr.pseudo_user_id
          # error. already in ServerUser table but with an other pseudo user id!
          logger.error2 "old remote_pseudo_user_id = #{su.remote_pseudo_user_id}. new remote_pseudo_user_id = #{-usr.pseudo_user_id}"
        end
      else
        su = ServerUser.new
        su.server_id = self.id
        su.user_id = u.id
      end
      su.remote_pseudo_user_id = -usr.pseudo_user_id
      su.save!
      logger.debug2 "new su #{su.to_json}"
    end
    logger.debug2 "request (1) = #{request.to_json}"
    buffer.delete_all

    # 2) normal request/response cycle. user_id > 0. send next 10 users for verification
    logger.debug2 "last_checked_user_id = #{last_checked_user_id}"
    new_users = []
    User.where("id > ? and user_id not like 'gofreerev/%'", (last_checked_user_id || 0)).order(:id).limit(10).each do |u|
      new_users << u.id
      pseudo_user_id = Sequence.next_pseudo_user_id
      request << {'user_id' => pseudo_user_id, 'sha256' => u.calc_sha256(self.secret)}
      # remember user ids from users request
      pseudo_user_ids[pseudo_user_id] = u.id
    end
    logger.debug2 "request (2) = #{request.to_json}"
    if new_users.size < 10
      # 3) normal request/response cycle. less than 10 new users. check for changed sha256 signatures for old users
      limit = 10 - new_users.size
      new_users << 0 if new_users.size == 0
      from_timestamp = last_changed_user_sha256_at
      from_timestamp = 1.year.ago unless from_timestamp
      user = User.where("sha256_updated_at is not null and sha256_updated_at > ? and id not in (?) and user_id not like 'gofreerev/%'",
                        from_timestamp, new_users).order(:sha256_updated_at).limit(limit).last
      if user
        # found users with changed sha256 signature since last compare users check
        to_timestamp = user.sha256_updated_at
        User.where("sha256_updated_at is not null and sha256_updated_at > ? and sha256_updated_at <= ? and id not in (?) and user_id not like 'gofreerev/%'",
                   from_timestamp, to_timestamp, new_users).each do |u|
          su = ServerUser.find_by_server_id_and_user_id(self.id, u.id)
          if su and su.pseudo_user_id
            logger.warn2 "reusing pseudo_user_id from old match #{su.to_json}"
            pseudo_user_id = su.pseudo_user_id
          else
            pseudo_user_id = Sequence.next_pseudo_user_id
          end
          request << {'user_id' => pseudo_user_id, 'sha256' => u.calc_sha256(self.secret)}
          # remember user ids from users request
          pseudo_user_ids[pseudo_user_id] = u.id
        end
        logger.debug2 "request (2) = #{request.to_json}"
        self.last_changed_user_sha256_at = to_timestamp
        self.save!
      end # if
    end # if

    return nil if request.size == 0

    # doublet check 1 - no doublet user ids are allowed in users array
    # doublet check 2 - no doublets sha256 are allowed in users array - todo: see todo # 395
    error = validate_compare_users_message(request)
    if error
      logger.error2 "#{error} was not sent"
      return nil
    end

    message = {
        :msgtype => 'users',
        :users => request
    }
    logger.debug2 "message = #{message.to_json}"
    sym_enc_message = message.to_json.encrypt(:symmetric, :password => self.new_password)
    logger.debug2 "sym_enc_message = #{sym_enc_message}"
    sym_enc_message = Base64.encode64(sym_enc_message)
    logger.debug2 "sym_enc_message = #{sym_enc_message}"

    # add envelope with symmetric encrypted users message
    envelope = {
        :sender_did => SystemParameter.did,
        :receiver_did => self.new_did,
        :server => true,
        :encryption => 'sym',
        :message => sym_enc_message
    }
    logger.debug2 "envelope = #{envelope.to_json}"
    envelope

  end

  # create_compare_users_message


  # receive symmetric encrypted compare users message on "client" or on "server"
  # response:
  # - array with user_id and sha256. rules for user_id and client
  #   user_id>0 and client - My user in response to outgoing users message
  #   user_id>0 and server - User from other gofreerev server in response to outgoing users message. save for next outgoing users message
  #   user_id<0 and client - User from other gofreerev server in incoming users message
  #   user_id<0 and server - My user from response to a previously incoming users message
  # client:
  # - true - server side of communication - called from Server.ping
  # - false - server side of communication - called from util_controller.ping via Message.receive_messages
  # pseudo_user_ids:
  # - only relevant for client==true. called from Server.ping
  #   hash with user ids in outgoing users message
  #   user ids must be in response to outgoing users message
  #   only relevant for direct server to server user compare
  #   not relevant in forwarded users messages
  public
  def receive_compare_users_message (response, client, pseudo_user_ids, received_msgtype)
    logger.debug2 "users = #{response}"
    if client
      logger.debug2 "client = #{client} - called from Server.ping. received incoming compare users message. response to outgoing compare users message (create_compare_users_message)"
    else
      logger.debug2 "client = #{client} - called from called from util_controller.ping via Message.receive_messages"
    end

    # doublet check 1 - no doublet user ids are allowed in users array
    # doublet check 2 - no doublets sha256 are allowed in users array - todo: see todo # 395
    error = validate_compare_users_message(response)
    return "#{error} was rejected" if error

    max_checked_user_id = last_checked_user_id || 0

    request = [] unless client

    response.each do |usr|
      logger.debug2 "usr = #{usr}"
      if client
        # client: called from Server.ping. received incoming users message. response to outgoing users message (create_users_message)
        if usr["user_id"] > 0
          # user_id > 0. My user in response to outgoing users message.
          logger.debug2 "#{usr["user_id"]} > 0. My user in response to outgoing users message"
          if !pseudo_user_ids.has_key?(usr["user_id"])
            # todo: could be a buffered / old users message returned from server!
            logger.error2 "Ignoring pseudo user id #{usr["user_id"]} that was not in outgoing users message"
            next
          end
          user_id = pseudo_user_ids[usr["user_id"]]
          u = User.find_by_id(user_id)
          if !u
            # very unlikely error
            logger.error2 "user id #{user_id} (pseudo user id #{usr["user_id"]}) does not exists. Only ok if user was deleted between ping request and ping response"
            next
          end
          max_checked_user_id = u.id if u.id > max_checked_user_id
          if !usr['sha256']
            logger.debug2 "user id #{u.id} does not exists on other Gofreerev server"
            next
          elsif u.sha256 == usr['sha256']
            logger.debug2 "confirmed match. user_id #{u.id} exists on other Gofreerev servers"
            # insert user match as verified in server_users table
            su = ServerUser.find_by_server_id_and_user_id(self.id, u.id)
            if !su
              su = ServerUser.new
              su.server_id = self.id
              su.user_id = u.id
            end
            old_match = (su.verified_at and su.pseudo_user_id == usr["user_id"])
            if old_match
              logger.debug "ignoring old unchanged match #{su.to_json}"
            else
              su.verified_at = Time.zone.now
              su.pseudo_user_id = usr["user_id"]
              su.save!
              logger.debug2 "su = #{su.to_json}"
              # mark sha256 as updated for user. friends and friend of friends. user must be included in next ping :friends response
              u.update_sha256(true)
              u.save!
            end
          else
            logger.warn2 "ignore user match. invalid sha256 signature was returned for user_id #{u.id}. Expected #{u.sha256}. Received #{usr['sha256']}"
          end
        else
          # user_id < 0. User from other gofreerev server in response to outgoing users message. save for next outgoing users message
          logger.debug2 "#{usr["user_id"]} < 0. User from other gofreerev server in response to outgoing users message. save for next outgoing users message"
          sur = ServerUserRequest.find_by_server_id_and_pseudo_user_id(self.id, usr['user_id'])
          if sur
            if sur.sha256 == usr['sha256']
              logger.warn2 "ignoring pseudo user id #{usr['user_id']} from server already in buffer for next outgoing users message."
              next
            else
              logger.error2 "pseudo user id #{usr['user_id']} is already in buffer with an other sha256 value. previous sha256 was #{sur.sha256}. new sha256 value is #{usr['sha256']}"
              sur.destroy!
              next
            end
          end
          sur = ServerUserRequest.new
          sur.server_id = self.id
          sur.pseudo_user_id = usr['user_id']
          sur.sha256 = usr['sha256']
          sur.save!
        end
      else
        # server: called from called from util_controller.ping via Message.receive_messages
        if usr["user_id"] > 0
          # user_id > 0. User from other gofreerev server in incoming users message
          logger.debug2 "#{usr["user_id"]} > 0. User from other gofreerev server in incoming users message"
          # receive_users_message: client = false - called from called from util_controller.ping via Message.receive_messages
          # block in receive_users_message: usr = {"user_id"=>706, "sha256"=>"5v6FeCmN9PO0m0SLraD7aZlvvLIHFTeHvJkbQoS70jY=\n"}
          # block in receive_users_message: 706 > 0. User from other gofreerev server in incoming users message
          # todo: this is almost like reverse request/response cycle part of create_users_message
          u = User.find_by_sha256(usr["sha256"])
          if u
            # todo: respond with client user.sha256
            logger.debug2 "user exists. return client user.sha256 signature"
            request << {'user_id' => usr["user_id"], 'sha256' => u.calc_sha256(self.secret)}
            # save match as not verified in server_users table
            su = ServerUser.find_by_server_id_and_user_id(self.id, u.id)
            if !su
              su = ServerUser.new
              su.server_id = self.id
              su.user_id = u.id
            end
            su.remote_pseudo_user_id = usr['user_id']
            su.save!
            logger.debug2 "su = #{su.to_json}"
          else
            # todo: respond with sha2546 = nil
            logger.debug2 "user does not exists. return null user.sha256 signature"
            request << {'user_id' => usr["user_id"]}
          end
        else
          # user_id < 0. My user from response to a previously incoming users message.
          logger.debug2 "#{usr["user_id"]} < 0. My user from response to a previously incoming users message"
          # check that received user id is from previous response
          sur = ServerUserRequest.find_by_server_id_and_pseudo_user_id(self.id, -usr["user_id"])
          if !sur
            logger.error2 "ignoring pseudo user id #{-usr["user_id"]} not found in ServerUserRequest buffer"
            next
          end
          sur.destroy!
          # recheck user - could have been deleted between two ping requests
          u = User.find_by_id(sur.user_id)
          if !u
            logger.error2 "user id #{sur.user_id} does not exists. Only ok if user was deleted between two pings"
            next
          end
          max_checked_user_id = u.id if u.id > max_checked_user_id
          if !usr['sha256']
            logger.debug2 "no match - user_id #{u.id} does not exist on other Gofreerev server"
          elsif u.sha256 == usr['sha256']
            logger.debug2 "confirmed match. user_id #{u.id} exists on other Gofreerev servers"
            # insert user match as verified in server_users table
            su = ServerUser.find_by_server_id_and_user_id(self.id, u.id)
            if !su
              su = ServerUser.new
              su.server_id = self.id
              su.user_id = u.id
            end
            old_match = (su.verified_at and su.pseudo_user_id == sur.pseudo_user_id)
            if old_match
              logger.debug "ignoring old unchanged match #{su.to_json}"
            else
              su.verified_at = Time.zone.now
              su.pseudo_user_id = sur.pseudo_user_id
              su.save!
              logger.debug2 "su = #{su.to_json}"
              # mark sha256 as updated for user. friends and friend of friends. user must be included in next ping :friends response
              u.update_sha256(true)
              u.save!
            end
          else
            logger.warn2 "ignore user match. invalid sha256 signature was returned for user_id #{u.id}"
          end
        end
      end
    end

    if max_checked_user_id > 0
      logger.debug2 "max_checked_user_id = #{max_checked_user_id}"
      self.last_checked_user_id = max_checked_user_id
      self.save!
      self.reload
      logger.debug2 "max_checked_user_id = #{max_checked_user_id}, self.last_checked_user_id = #{self.last_checked_user_id}"
    end

    return nil if client # client - called from Server.ping

    # server - called from UtilController.ping
    # add sha256 signatures for reverse request/response cycle (request in response and response in request). user_id < 0

    return nil if received_msgtype[:users] # more than one ingoing compare users message (response already in messages table)
    received_msgtype[:users] = true

    logger.debug2 "add users to response users message. response will be sent in next ping request"
    # exclude gofreerev dummy users (provider=gofreerev)
    ServerUserRequest.where(:server_id => self.id).delete_all

    new_users = []
    User.where("id > ? and user_id not like 'gofreerev/%'", (self.last_checked_user_id || 0)).order(:id).limit(10).each do |u|
      new_users << u.id
      # use negative pseudo user id in response and positive pseudo user id in db
      pseudo_user_id = Sequence.next_pseudo_user_id
      request << {'user_id' => -pseudo_user_id, 'sha256' => u.calc_sha256(self.secret)}
      # insert into ServerUserRequest. Pseudo user ids must be in next ping request from "client".
      sur = ServerUserRequest.new
      sur.server_id = self.id
      sur.pseudo_user_id = pseudo_user_id
      sur.user_id = u.id
      sur.save!
    end # each u
    logger.debug2 "users (2) = #{request}"

    if new_users.size < 10
      # less than 10 new users. check for any changed sha256 signatures.
      limit = 10 - new_users.size
      new_users << 0 if new_users.size == 0
      from_timestamp = last_changed_user_sha256_at
      from_timestamp = 1.year.ago unless from_timestamp
      user = User.where("sha256_updated_at is not null and sha256_updated_at > ? and id not in (?) and user_id not like 'gofreerev/%'",
                        from_timestamp, new_users).order(:sha256_updated_at).limit(limit).last
      if user
        # found users with changed sha256 signature since last compare users check
        to_timestamp = user.sha256_updated_at
        User.where("sha256_updated_at is not null and sha256_updated_at > ? and sha256_updated_at <= ? and id not in (?) and user_id not like 'gofreerev/%'",
                   from_timestamp, to_timestamp, new_users).each do |u|
          # use negative pseudo user id in response and positive pseudo user id in db
          su = ServerUser.find_by_server_id_and_user_id(self.id, u.id)
          if su and su.pseudo_user_id
            logger.warn2 "reusing old pseudo_user_id"
            pseudo_user_id = su.pseudo_user_id
          else
            pseudo_user_id = Sequence.next_pseudo_user_id
          end
          logger.debug2 "su = #{su.to_json}" if su
          request << {'user_id' => -pseudo_user_id, 'sha256' => u.calc_sha256(self.secret)}
          # insert into ServerUserRequest. Pseudo user ids must be in next ping request from "client".
          sur = ServerUserRequest.new
          sur.server_id = self.id
          sur.pseudo_user_id = pseudo_user_id
          sur.user_id = u.id
          sur.save!
        end
        logger.debug2 "users (3) = #{request}"
        self.last_changed_user_sha256_at = to_timestamp
        self.save!
      end # if
    end # if

    # doublet check 1 - no doublet user ids are allowed in users array
    # doublet check 2 - no doublets sha256 are allowed in users array - todo: see todo # 395
    error = validate_compare_users_message(request)
    return "#{error} was not sent" if error

    message = {
        :msgtype => 'users',
        :users => request
    }
    logger.debug2 "message = #{message.to_json}"
    sym_enc_message = message.to_json.encrypt(:symmetric, :password => self.new_password)
    logger.debug2 "sym_enc_message = #{sym_enc_message}"
    sym_enc_message = Base64.encode64(sym_enc_message)
    logger.debug2 "sym_enc_message = #{sym_enc_message}"

    # insert message in messages table. will be returned in a moment in ping response
    m = Message.new
    m.from_did = SystemParameter.did
    m.to_did = self.new_did
    m.server = true
    m.encryption = 'sym'
    m.message = sym_enc_message
    m.save!

    nil

  end

  # receive_compare_users_message


  # send information about online mutual users to other gofreerev server
  # merge information in pings table with verified matches in server_users table
  # using user remote sha256 signatures. No user information is exchanged
  protected
  def create_online_users_message

    # get server ping cycle. each client should ping server once every server ping cycle (*2 = allow delayed pings)
    s = Sequence.get_server_ping_cycle
    return nil unless s
    server_ping_cycle = s.value

    # find online users in pings table.
    pings = Ping.where('last_ping_at <= ? and last_ping_at > ? and server_id is null',
                       Time.zone.now.to_f, (server_ping_cycle*2/1000).seconds.ago.to_f).
        order('session_id, client_userid, last_ping_at desc')

    # remove server pings and remove "old" pings. only last ping for each did is relevant
    old_key = 'x'
    pings.delete_if do |p|
      server = (p.user_ids and p.user_ids.size == 1 and p.user_ids.first =~ /^http:\/\//)
      new_key = "#{p.session_id},#{p.client_userid}"
      if server or (new_key == old_key)
        true
      elsif !p.did
        logger.warn2 "ignoring ping without did: #{p.to_json}"
        true
      elsif !p.user_ids
        logger.warn2 "ignoring ping without user_ids: #{p.to_json}"
        true
      else
        old_key = new_key
        false
      end
    end

    # find online users
    online_user_ids = []
    pings.each do |p|
      online_user_ids += p.user_ids
    end
    online_user_ids = online_user_ids.uniq
    logger.debug2 "ping_user_ids = #{online_user_ids.join(', ')}"
    if online_user_ids.size == 0
      logger.debug2 "no online users was found in pings table"
      return nil
    end

    # initialize a hash with sha256 signature and pseudo user ids for verified users (identical users on both Gofreerev servers)
    # sha256 signature is used when :user ids array in message to internal user ids
    # pseudo user id is used as user id in message after invalid or changed user sha256 (see receive_online_users_message)
    verified_users = {}
    ServerUser.where('server_id = ? and verified_at is not null', self.id).includes(:user).where('users.user_id' => online_user_ids).each do |su|
      verified_users[su.user.user_id] = {
          :sha256 => su.user.calc_sha256(self.secret),
          :sha256_updated_at => su.user.sha256_updated_at,
          :pseudo_user_id => su.remote_pseudo_user_id
      }
    end
    logger.debug2 "verified_users = #{verified_users}"
    if verified_users.size == 0
      logger.debug2 "no verified users was found for this server id #{self.id}"
      return nil
    end

    # filter pings information using verified_users hash. Only pings from verified users are send to other Gofreerev server
    request = []
    pings.each do |p|
      next if p.user_ids.size == 1 and p.user_ids.first =~ /^http:\/\// # ignore server pings
      if !p.did
        logger.error2 "ignoring ping without did: #{p.to_json}"
        next
      end
      user_ids = []
      p.user_ids.each do |user_id|
        user_ids << verified_users[user_id] if verified_users.has_key? user_id
      end
      next if user_ids.size == 0
      # use pseudo session id when sending ping information to other Gofreerev servers
      rs = RemoteSession.find_by_session_id(p.session_id)
      if !rs
        rs = RemoteSession.new
        rs.session_id = p.session_id
        rs.pseudo_session_id = Sequence.next_pseudo_session_id
        rs.save!
      end
      request << {:session_id => rs.pseudo_session_id,
                  :client_userid => p.client_userid,
                  # :client_sid => p.client_sid,
                  :last_ping_at => p.last_ping_at.to_f,
                  # :next_ping_at => p.next_ping_at, # remove - not relevant
                  :did => p.did,
                  :user_ids => user_ids, # user sha256 signatures
                  :sha256 => p.sha256}
    end
    logger.debug2 "request = #{request}"
    # request = [{:session_id=>1, :last_ping_at=>1427037843.2940001, :did=>"14252356907464191530",
    #             :user_ids=>["QoTMDQkHpw7Gyjl9NBcuIHk6JwdK7THv2RKXVoTNWM0=\n"],
    #             :sha256=>"0SumAAlBe/4vEMdftHU5puueYlccj0F50zDaUGkV4/Y=\n"}]
    if request.size == 0
      logger.debug2 "no online users was found for server id #{self.id}"
      return nil
    end

    message = {
        :msgtype => 'online',
        :users => request
    }
    logger.debug2 "message = #{message.to_json}"
    sym_enc_message = message.to_json.encrypt(:symmetric, :password => self.new_password)
    sym_enc_message = Base64.encode64(sym_enc_message)
    logger.debug2 "sym_enc_message = #{sym_enc_message}"

    # add envelope with symmetric encrypted users message
    envelope = {
        :sender_did => SystemParameter.did,
        :receiver_did => self.new_did,
        :server => true,
        :encryption => 'sym',
        :message => sym_enc_message
    }
    logger.debug2 "envelope = #{envelope.to_json}"
    envelope

  end

  # create_online_users_message


  # ingoing message (online_users and verify_gifts - convert sha256 signatures to user_ids
  # send changed sha256 message in case of changed sha256 signatures
  # params:
  # - user_signatures: from ingoing message - array with sha256, pseudo_user_id and sha256_updated_at (verified users)or negative user id (unknown users)
  # - options (hash):
  #   - :seq:
  #       1: invalid user sha256 signature in receive_online_users_message
  #     ( 2: user sha256 signature changed (User.update_sha256) ) -
  #       3: invalid user sha256 signature in receive_verify_gifts_message
  #       4: generic. Message.receive_messages
  #       5: sha256 user signature changed message
  #   - :msg: log info. online users, verify gifts etc
  #   - :negative_user_ids:
  #       false: not allowed - for example in receive_online_users_message
  #       true: allowed but don't translate (login_users array in verify gifts request)
  #       :translate: allowed + translate (giver and receiver user ids in verify gifts request)
  #   - :sha256_msg: true if incoming sha256 (:msgtype) message. warning if NOT changed sha256 signature
  #   - :allow_changed_sha256: integer. 0: not allowed, >0: max number of seconds to wait for valid sha256 signature
  #   - :field: :id or :user_id - return user_ids for logged in users. return ids for givers/receivers
  # returns error and user_ids
  # todo: login users - return user_id (uid/provider). givers/receivers - return id
  private
  def from_sha256s_to_user_ids (user_signatures, options = {})
    # logger.debug2 "user_signatures = #{user_signatures}"
    # logger.debug2 "options         = #{options}"

    # get/check options
    seq = options.delete(:seq) || 0 # id - where was method called from - not used
    msg = options.delete(:msg) # message: online users, verify gifts, changed sha256 etc - used in debug information
    negative_user_ids = options.delete(:negative_user_ids) || false
    sha256_msg = options.delete(:sha256_msg) || false # true if incoming changed sha256 user signature
    allow_changed_sha256 = options.delete(:allow_changed_sha256) || 0
    field = options.delete(:field) || :user_id

    # sha256 = false if sha256 == nil
    raise "invalid :seq param. Must be an integer. Was #{seq} (#{seq.class})" unless seq.class == Fixnum
    raise "invalid :msg param. Must be a string. Was #{msg} (#{msg.class})" unless msg.class == String
    raise "invalid :negative_user_ids parm. Allowed values are false, true and :translate. Was #{negative_user_ids} (#{negative_user_ids.class})" unless [false, true, :translate].index(negative_user_ids)
    raise "invalid :sha256_msg param. Must be true (incoming changed sha256 signature message) or false. Was #{sha256_msg} (#{sha256_msg.class})" unless [true, false].index(sha256_msg)
    raise "invalid :allow_changed_sha256 param. Must be a integer > 0. Was #{allow_changed_sha256} (#{allow_changed_sha256.class})" unless [Fixnum, Bignum].index(allow_changed_sha256.class) and allow_changed_sha256 >= 0
    raise "invalid :field parm. Allowed values are :id and :user_id. Was #{field} (#{field.class})" unless [:id, :user_id, 'id', 'user_id'].index(field)
    raise "unknown #{options.keys.join(', ')} param" unless options == {}

    sha_signatures = []
    negative_user_ids = []
    user_signatures.each do |user_signature|
      if user_signature.class == Hash
        sha_signatures << user_signature
      else
        negative_user_ids << user_signature
      end
    end

    # check sha256 signatures. hash with sha256, pseudo_user_id and sha256_updated_at
    # must exist as verified server user in server_users table
    # pseudo_user_id is used as fallback information in case of changed sha256 signature
    now = Time.zone.now
    valid_sha_signatures = []
    changed_sha_signatures = []
    invalid_sha_signatures = []
    local_changed_sha_signatures = 0
    remote_changed_sha_signatures = 0
    errors = []
    if sha_signatures.size > 0
      sha256s = sha_signatures.collect { |hash| hash["sha256"] }
      pseudo_user_ids = sha_signatures.collect { |hash| hash["pseudo_user_id"] }
      server_users = ServerUser.includes(:user).where(
          '(users.sha256 in (?) or pseudo_user_id in (?)) and server_id = ? and verified_at is not null',
          sha256s, pseudo_user_ids, self.id).references(:users)
      sha_signatures.each do |sha_signature|
        su = server_users.find { |su2| su2.user.sha256 == sha_signature['sha256'] }
        su = server_users.find { |su2| su2.pseudo_user_id == sha_signature['pseudo_user_id'] } unless su
        user = su.user if su
        if !su
          invalid_sha_signatures << sha_signature
          logger.error2 "unknown signature #{sha_signature} in incoming changed sha256 message" if sha256_msg
        elsif su.user.sha256 == sha_signature['sha256']
          # received valid signature from other gofreerev server
          valid_sha_signatures << su.user[field]
          logger.warn2 "warning. valid signature #{sha_signature} in incoming changed sha256 message" if sha256_msg
          # blank any old changed signature information
          su.remote_sha256_updated_at = nil if su.remote_sha256_updated_at
          su.sha256_signature_received_at = nil if su.sha256_signature_received_at
          su.sha256_message_sent_at = nil if su.sha256_message_sent_at
          user.update_attribute :remote_sha256_updated_at, nil if user.remote_sha256_updated_at
          # todo: blank user.remote_sha256_update_info?
          logger.debug2 "user = #{user.to_json}"
        elsif !sha_signature['sha256_updated_at']
          invalid_sha_signatures << sha_signature
          logger.error2 "invalid signature #{sha_signature} without sha256_updated_at timestamp in incoming changed sha256 message" if sha256_msg
        elsif sha_signature['sha256_updated_at'] > now.to_i
          # identical pseudo user id - changed sha256 signature but with invalid sha256_updated_at timestamp
          logger.error2 "#{msg} message. rejected changed sha256 signature #{sha_signature} with sha256_updated_at in the future. now = #{now.to_i}"
          invalid_sha_signatures << sha_signature
        else
          # identical pseudo user id - changed sha256 signature - changed user information on this or on other gofreerev server
          user = su.user
          if !su.remote_sha256_updated_at or su.remote_sha256_updated_at.to_i < sha_signature['sha256_updated_at']
            su.remote_sha256_updated_at = Time.at sha_signature['sha256_updated_at']
            su.sha256_signature_received_at = now
            if !user.sha256_updated_at or user.sha256_updated_at < su.remote_sha256_updated_at
              # todo:
              # update user info and calc new user.sha256 on this gofreerev server
              # a client of this gofreerev server must download fresh user info from login provider
              # user sha256 signature on this server must change and sha256 message will be sent to other gofreerev server
              # push verify gifts request back in messages and wait for updated user info
              user.set_changed_remote_sha256(sha_signature)
            elsif sha256_msg
              errors << "Incoming sha256 changed message with old signature #{sha_signature}. user.sha256_updated_at = #{user.sha256_updated_at.to_i}, sha256_signature['sha256_updated_at'] = #{sha_signature['sha256_updated_at']}"
              invalid_sha_signatures << sha_signature
              next
            else
              # todo:
              # update user info and calc new user.sha256 on other gofreerev server
              # sent changed user sha256 message to other gofreerev server
              # other server must receive sha256 signature changed message with changed signature
              # other server must ask a client to download and update user info
              # user sha256 signature on other gofreerev server must change and sha256 changed signature message will be sent to this gofreerev server
              # other server must resend verify gifts request with new correct sha256 signatures
              su.sha256_message_sent_at = nil
            end
            su.save!
          end
          # debug info with status for changed sha256 signature:
          #  1) old user info on this server - waited x seconds
          #  2) old user info on other server - waited x seconds for sha256 message to be sent
          #  3) old user info on other server - waited x seconds for updated sha256 signature
          waited = (now-su.sha256_signature_received_at).round
          if user.remote_sha256_updated_at
            logger.debug2 "#{msg} message. changed sha256 signature #{sha_signature}. waited #{waited} seconds for user info update on this server"
          elsif su.sha256_message_sent_at
            logger.debug2 "#{msg} message. changed sha256 signature #{sha_signature}. waited #{waited} seconds for user info update on other server"
          else
            logger.debug2 "#{msg} message. changed sha256 signature #{sha_signature}. waited #{waited} for sha256 changed signature message to be sent to other server"
          end
          # todo: should only wait for user info update on this server. other server must resend verify gifts request with correct sha256 signatures after user info has been updated
          if waited < allow_changed_sha256
            # waiting for valid sha256 signature
            if user.sha256_updated_at < su.remote_sha256_updated_at
              # waiting for this gofreerev server. keep verify gift request and return response later
              local_changed_sha_signatures += 1
            else
              # waiting for other gofreerev server. return verify gift request with "changed sha signature" error code
              remote_changed_sha_signatures += 1
            end
            valid_sha_signatures << user[field]
          else
            # reject message. timeout or changed sha256 signatures not allowed in message
            changed_sha_signatures << su
          end
        end # if else ..
      end # each sha256_signature
      if changed_sha_signatures.size > 0
        error = "Changed sha256 user signatures #{changed_sha_signatures}. allow_changed_sha256 = #{allow_changed_sha256}"
        errors << error
        logger.debug2 "#{msg} message. #{error}"
      end
    end # if

    # check negative user ids - allow for login users in verify gifts message - not allowed for giver and receiver in verify gifts message
    valid_negative_user_ids = []
    invalid_negative_user_ids = []
    if negative_user_ids.size > 0
      if negative_user_ids == nil
        # not allowed in online users message
        errors << "Invalid negative user ids #{negative_user_ids.join(', ')}"
        invalid_negative_user_ids += negative_user_ids
      elsif negative_user_ids
        # giver and receiver in verify gifts message
        # todo: how to handle gift creator on one gofreerev server and accepted deal proposal from an other gofreerev server? one or more user ids can be unknown
        positive_user_ids = negative_user_ids.collect { |user_id| -user_id }
        users = User.where(:id => positive_user_ids)
        valid_negative_user_ids += users.collect { |user| user[field] }
        unknown_positive_user_ids = positive_user_ids - users.collect { |user| user.id }
        unknown_negative_user_ids = unknown_positive_user_ids.collect { |user_id| -user_id }
        errors << "Invalid negative user ids #{unknown_negative_user_ids.join(', ')}" if unknown_negative_user_ids.size > 0
      else
        # login users in verify gifts request
      end
    end # if

    # debug info
    if changed_sha_signatures.size > 0 or invalid_sha_signatures.size > 0 or invalid_negative_user_ids.size > 0 or local_changed_sha_signatures > 0 or remote_changed_sha_signatures > 0
      logger.debug2 "#{msg} message. #{user_signatures.size} user ids. #{sha_signatures.size} signatures and #{negative_user_ids.size} negative user ids"
    end
    logger.debug2 "#{msg} message. #{changed_sha_signatures.size} changed signatures" if changed_sha_signatures.size > 0
    logger.debug2 "#{msg} message. #{invalid_sha_signatures.size} invalid signatures" if invalid_sha_signatures.size > 0
    logger.debug2 "#{msg} message. #{invalid_negative_user_ids.size} invalid negative user ids" if invalid_negative_user_ids.size > 0
    logger.debug2 "#{msg} message. #{local_changed_sha_signatures} changed signatures waiting for this server" if local_changed_sha_signatures > 0
    logger.debug2 "#{msg} message. #{remote_changed_sha_signatures} changed signatures waiting for other server" if remote_changed_sha_signatures > 0

    # return array with error, user_ids array and number of changed sha256 signatures
    error = errors.size > 0 ? errors.join(', ') : nil
    user_ids = valid_sha_signatures + valid_negative_user_ids
    [error, user_ids, local_changed_sha_signatures, remote_changed_sha_signatures]
  end # from_sha256s_to_user_ids


  public
  def receive_online_users_message (response, client, received_msgtype)

    logger.debug2 "users = #{response}"
    # users = [{"session_id"=>"9c653cde5b1cd771756cf2dc49a1376d", "last_ping_at"=>1427021803.289,
    #           "did"=>"14252356907464191530", "user_ids"=>["QoTMDQkHpw7Gyjl9NBcuIHk6JwdK7THv2RKXVoTNWM0=\n"],
    #           "sha256"=>"0SumAAlBe/4vEMdftHU5puueYlccj0F50zDaUGkV4/Y=\n"}]

    if client
      logger.debug2 "client = #{client} - called from Server.ping. received incoming online users message. response to outgoing online users message (create_online_users_message)"
    else
      logger.debug2 "client = #{client} - called from called from util_controller.ping via Message.receive_messages"
    end

    # delete old remote pings
    # note - timestamps in pings table are decimal(13,3) - always use number timestamps in compare
    Ping.where('server_id = ? and last_ping_at < ?', self.id, 2.minute.ago.to_f).delete_all

    errors = []

    response.each do |ping|

      # check and convert user_ids. sha256 signature must match and user must be in server_users table as verified user
      # changed sha256 signature message is sent in case of changed sha256 signature for known verified users (using pseudo user id)
      error, user_ids, no_local_changed_signatures, no_remote_changed_signatures =
          from_sha256s_to_user_ids(ping["user_ids"],
                                   :seq => 1, :msg => 'online users', :negative_user_ids => false,
                                   :allow_changed_sha256 => 0, :field => :user_id)
      if error
        errors << error
        next
      end
      next unless user_ids.size > 0

      # check did
      pubkey = Pubkey.find_by_did(ping['did'])
      if pubkey
        if !pubkey.server_id
          errors << "Invalid did #{ping['did']} in online users message. Did is already in use for a local user account"
          next
        elsif pubkey.server_id != self.id
          errors << "Invalid did #{ping['did']} in online user message. Did is already used by an other Gofreerev server"
          next
        end
      end

      # translate pseudo session id received from other gofreerev server to pseudo session id used on this gofreerev server
      ss = ServerSession.find_by_server_id_and_remote_session_id(self.id, ping["session_id"])
      if !ss
        ss = ServerSession.new
        ss.server_id = self.id
        ss.remote_session_id = ping["session_id"]
        ss.session_id = Sequence.next_pseudo_session_id
        ss.save!
      end
      if !pubkey
        # create empty public key. client(s) will request public key if needed in client to client communication
        pubkey = Pubkey.new
        pubkey.did = ping["did"]
        pubkey.server_id = self.id
        pubkey.save!
      end

      # find/create/update ping for remote session
      # note! - using String session id in pings table! integer in remote_sessions, server_sessions and online users message but string in pings table
      p = Ping.find_by_session_id_and_client_userid(ss.session_id.to_s, ping["client_userid"])
      if !p
        p = Ping.new
        p.session_id = ss.session_id.to_s
        p.client_userid = ping["client_userid"]
        p.client_sid = ss.session_id.to_s
        p.did = ping["did"]
      elsif p.server_id != self.id
        errors << "System error when receiving online users message. Invalid server id in pings table. received #{ping}. ping in db #{p.to_json}"
        next
      end
      p.last_ping_at = Time.at ping["last_ping_at"]
      p.next_ping_at = 1.year.from_now.round(3)
      p.user_ids = user_ids
      p.sha256 = ping["sha256"]
      p.server_id = self.id
      p.save!
    end

    if client
      return errors.size == 0 ? nil : errors.join(', ')
    end

    return nil if received_msgtype[:online] # more than one ingoing online users message (response already in messages table)
    received_msgtype[:online] = true

    # return online users message to calling gofreerev server
    message = create_online_users_message()
    return nil unless message # no shared online users

    # add online users message to messages table. response to calling gofreerev server in a moment
    m = Message.new
    m.from_did = message[:sender_did]
    m.to_did = message[:receiver_did]
    m.server = message[:server]
    m.encryption = message[:encryption]
    m.message = message[:message]
    m.save!

    return errors.size == 0 ? nil : errors.join(', ')

  end # receive_online_users_message


  # create and save user sha256 signature changed message
  # after (seq):
  # - 1: invalid user sha256 signature in receive_online_users_message (not used)
  # - 2: user sha256 signature changed (User.update_sha256)
  # - 3: invalid user sha256 signature in receive_verify_gifts_request (not used)
  # - 4: generic. Message.receive_messages (1 and/or 3)
  public
  def self.save_sha256_changed_message (seq, server_users)

    now = Time.zone.now
    server_users = server_users.sort_by { |su| su.server_id }

    users = []
    0.upto(server_users.size-1) do |i|
      su = server_users[i]
      if su.server.new_password
        users.push({:sha256 => su.user.calc_sha256(su.server.secret),
                    :pseudo_user_id => su.remote_pseudo_user_id,
                    :sha256_updated_at => su.user.sha256_updated_at.to_i
                   })
        # mark sha256 message as sent
        su.sha256_message_sent_at = now
      else
        # symmetric password setup not yet completed. symmetric passwords are stored in memory and are null after reboot.
        # or maybe no server to server connection to other gofreerev server
        # mark sha256 message as not sent. Will be sent later after completed password setup in Message.receive_messages
        logger.warn2 "symmetric password setup not completed for server #{su.server_id}. sha256 message for #{su.user.debug_info} will be sent later"
        su.sha256_message_sent_at = nil
        su.remote_sha256_updated_at = Time.zone.now unless su.remote_sha256_updated_at
      end
      su.save!
      if (i == server_users.size-1 or su.server_id != server_users[i+1].server_id) and  users.size > 0
          # save message
          message = {
              :msgtype => 'sha256',
              :seq => seq,
              :users => users
          }
          logger.debug2 "send sha256 message #{message}"
          sym_enc_message = message.to_json.encrypt(:symmetric, :password => su.server.new_password)
          sym_enc_message = Base64.encode64(sym_enc_message)
          m = Message.new
          m.from_did = SystemParameter.did
          m.to_did = su.server.new_did
          m.server = true
          m.encryption = 'sym'
          m.message = sym_enc_message
          m.save!

        users = []
      end # if
    end # do  i

  end # save_sha256_changed_message


  public
  def receive_sha256_changed_message (seq, users)
    logger.error2 "seq = #{seq}"
    logger.error2 "users = #{users}"
    # translate sha256 signatures (sha256, pseudo_user_id and sha256_updated_at) to user_ids
    # from_sha256s_to_user_ids checks for changed sha256 signatures and marks server_user or user as changed  (remote_sha256_updated_at)
    # returns a sha256 signature changed message if user information on this server is newest
    # ask a client on this gofreerev server to download fresh user information from login provider if user information on this server is oldest
    error, user_ids, no_local_changed_signatures, no_remote_changed_signatures =
        from_sha256s_to_user_ids(users,
                                 :seq => 5, :msg => 'sha256_changed', :negative_user_ids => false, :sha256_msg => true,
                                 :allow_changed_sha256 => 5.minutes.to_i, :field => :id)
    logger.debug2 "error = #{error}" if error
    logger.debug2 "user_ids = #{user_ids.join(', ')}"

    User.where(:id => user_ids).includes(:server_users).each do |u|
      su = u.server_users.find { |su2| su2.server_id == self.id }
      logger.debug2 "su = #{su.to_json}"
      sha_signature = users.find { |user| user["pseudo_user_id"] == su.pseudo_user_id }
      logger.debug2 "sha_signature = #{sha_signature}"
      u.set_changed_remote_sha256(sha_signature)
    end if user_ids.size > 0
    return "receive_sha256_changed_message not implemented: user_ids = #{user_ids}, error = #{error}"
  end # receive_sha256_changed_message


  # send and receive client public keys to and from other gofreerev servers
  # note difference between missing pubkey in request and null pubkey in error response
  protected
  def create_public_keys_message

    request = []

    # 1) reverse request/response. Send public keys required in last response from other gofreerev server
    ServerPubkeyRequest.where(:server_id => self.id).each do |spr|
      p = Pubkey.find_by_did(spr.did)
      if !p or p.server_id
        # invalid request. did does not exists or is not a local device
        request << {:did => spr.did, :pubkey => nil} # error response
      else
        request << {:did => p.did, :pubkey => p.pubkey} # ok response
      end
    end

    # 2) normal request. Request missing public keys from other gofreerev server
    Pubkey.where('server_id = ? and pubkey is null and client_request_at is not null', self.id).each do |p|
      request << {:did => p.did} # request. no pubkey
    end

    return nil if request.size == 0
    logger.debug2 "request = #{request}"

    message = {
        :msgtype => 'pubkeys',
        :users => request
    }
    logger.debug2 "message = #{message.to_json}"
    sym_enc_message = message.to_json.encrypt(:symmetric, :password => self.new_password)
    sym_enc_message = Base64.encode64(sym_enc_message)
    logger.debug2 "sym_enc_message = #{sym_enc_message}"

    # add envelope with symmetric encrypted users message
    envelope = {
        :sender_did => SystemParameter.did,
        :receiver_did => self.new_did,
        :server => true,
        :encryption => 'sym',
        :message => sym_enc_message
    }
    logger.debug2 "envelope = #{envelope.to_json}"
    envelope

  end

  # create_public_keys_message


  public
  def receive_public_keys_message (response, client, received_msgtype)

    logger.debug2 "pubkeys = #{response}"

    if client
      logger.debug2 "client = #{client} - called from Server.ping. received incoming public keys message. response to outgoing public keys message (create_public_keys_message)"
    else
      logger.debug2 "client = #{client} - called from called from util_controller.ping via Message.receive_messages"
    end

    errors = []
    request = []

    response.each do |p|
      if p.has_key? 'pubkey'
        # response with public key or null (error)
        # client, called from Server.ping, ingoing public keys response to outgoing public keys request
        # server: called from util_controller via receive_message. ingoing public keys request with response to last outgoing public keys request in previous ping response
        pubkey = Pubkey.find_by_did(p['did'])
        if !pubkey
          errors << "Unknown did #{p['did']} in public keys response from Gofreerev server id #{self.id}"
        elsif !pubkey.server_id
          errors << "Invalid local did #{p['did']} in public keys response from Gofreerev server id #{self.id}"
        elsif pubkey.server_id != self.id
          errors << "Invalid did #{p['did']} received in public keys response from Gofreerev server id #{self.id}. Did #{p['did']} belongs to Gofreeerv server #{pubkey.server_id}"
        elsif !pubkey.client_request_at
          errors << "Not requested did #{p['did']} received in response public keys from Gofreerev server id #{self.id}"
        elsif !p['pubkey']
          errors << "Public key request for did #{p['did']} was rejected by Gofreerev server #{self.id}"
          pubkey.pubkey = nil
          pubkey.server_response_at = Time.zone.now
          pubkey.save!
        elsif !pubkey.pubkey
          # ok
          pubkey.pubkey = p['pubkey']
          pubkey.server_response_at = Time.zone.now
          pubkey.save!
        elsif pubkey.pubkey == p['pubkey']
          logger.warn2 "public key for did #{p['did']} has been receive earlier"
        else
          errors << "Receive changed public key for did #{p['did']} in public keys response from Gofreerev server id #{self.id}"
        end
      elsif client
        # client, called from Server.ping, request with did in ping response. save for next outgoing ping request
        spr = ServerPubkeyRequest.find_by_server_id_and_did(self.id, p['did'])
        if spr
          logger.warn2 "request for public key for device #{p['did']} was already in ServerPubkeyRequest buffer"
        else
          spr = ServerPubkeyRequest.new
          spr.server_id = self.id
          spr.did = p['did']
          spr.save!
        end
      else
        # server, called from util_controller via receive messages. add to request array. message will be returned to calling client in ping response
        p = Pubkey.find_by_did(p['did'])
        if !p or p.server_id
          # invalid request. did does not exists or is not a local device
          request << {:did => spr.did, :pubkey => nil} # error response
        else
          request << {:did => p.did, :pubkey => p.pubkey} # ok response
        end
      end
    end # each

    if !client

      if received_msgtype[:pubkeys]
        # more than one ingoing public keys (response already in messages table)
      else
        # any public key requests from server to client. response in next ping request
        Pubkey.where('server_id = ? and pubkey is null and client_request_at is not null', self.id).each do |p|
          request << {:did => p.did} # request. no pubkey
        end
        received_msgtype[:pubkeys] = true
      end

    end

    if request.size > 0

      # add public keys message to messages table with
      # - response to ingoing public key requests
      # - public keys request to client. response in next ping
      message = {
          :msgtype => 'pubkeys',
          :users => request
      }
      logger.debug2 "message = #{message.to_json}"
      sym_enc_message = message.to_json.encrypt(:symmetric, :password => self.new_password)
      sym_enc_message = Base64.encode64(sym_enc_message)
      logger.debug2 "sym_enc_message = #{sym_enc_message}"

      m = Message.new
      m.from_did = SystemParameter.did
      m.to_did = self.new_did
      m.server = true
      m.encryption = 'sym'
      m.message = sym_enc_message
      m.save!

    end

    errors.size == 0 ? nil : errors.join(', ')

  end

  # receive_public_keys_message


  # send and receive across Gofreerev server client to client messages
  # client messages are already encrypted but are put in a encrypted server to server message
  protected
  def create_client_messages

    messages = []

    # get client to client messages from local clients to clients on Gofreerev server <self.id>
    Message.includes(:from_pubkey, :to_pubkey).
        where('server = ? and pubkeys.server_id is null and to_pubkeys_messages.server_id = ?', false, self.id).
        references(:from_pubkey, :to_pubkey).order(:id).each do |m|
      messages << {:from_did => m.from_did,
                   :from_sha256 => m.from_sha256,
                   :to_did => m.to_did,
                   :to_sha256 => m.to_sha256,
                   :server => m.server,
                   :encryption => m.encryption,
                   :key => m.key,
                   :message => m.message
      }
      # todo: should first destroy client messages after ok response from other gofreerev server
      m.destroy!
    end
    if messages.size == 0
      logger.debug2 "No client messages was found for server id #{self.id}"
      return nil
    end

    logger.debug2 "messages = #{messages}"

    message = {
        :msgtype => 'client',
        :messages => messages
    }
    logger.debug2 "message = #{message.to_json}"
    sym_enc_message = message.to_json.encrypt(:symmetric, :password => self.new_password)
    sym_enc_message = Base64.encode64(sym_enc_message)
    logger.debug2 "sym_enc_message = #{sym_enc_message}"

    # add envelope with symmetric encrypted users message
    envelope = {
        :sender_did => SystemParameter.did,
        :receiver_did => self.new_did,
        :server => true,
        :encryption => 'sym',
        :message => sym_enc_message
    }
    logger.debug2 "envelope = #{envelope.to_json}"
    envelope

  end

  # create_client_messages


  public
  def receive_client_messages (response, client, received_msgtype)

    logger.debug2 "client messages = #{response}"
    # client messages = [{"from_did"=>"14252356907464191530", "from_sha256"=>"14252356907464191530",
    #                     "to_did"=>"14259151245218705856", "to_sha256"=>"RFknrRnG4TL+zhBkoTc2dgNkdFoIRMLxrOYduv3CKvQ=\n",
    #                     "server"=>false, "encryption"=>"rsa", "key"=>nil,
    #                     "message"=>"WUp3RGeenbmmP7rELXrc/iAF9O82urRflJYnQhyjeR65XcLRMBBQp142OyO9SEL0D9q6YGUfCTnu863ElaxaVb8tgfJi3VZa+awN8M6VllWG3x1w+vWAejAMTlqDar8uh2H6YLu9BErLrt7lpiLJ4LNGcHoVqUfuHe1mn+k/XerzeOwpg/dgHz9k8OYblXfj/xKsW7+eiFUzDCy3uSvi/6nW7OCSF6x0oIn9fLsyJwD7+nzWQ1YdRcI9acJrOeYKOeVIpaTBeFbJOZmIMbStuNvJUvd7fgYx5VtMhLYUDuTMU54gU2nQNSB19ZfuPd3sBiibC9U0X0xsXi7OCUsb6g=="},
    #                    {"from_did"=>"14252356907464191530", "from_sha256"=>"14252356907464191530",
    #                     "to_did"=>"14259151245218705856", "to_sha256"=>"RFknrRnG4TL+zhBkoTc2dgNkdFoIRMLxrOYduv3CKvQ=\n",
    #                     "server"=>false, "encryption"=>"rsa", "key"=>nil,
    #                     "message"=>"GjqACV7ie1vnnabZ/6yP5XOfu2A6d+z0VhVXWlbzKGuSK0d2OsIgnrL+/QLFIgY2ltdlhLdd0/f96FPbKnvPA3+WLf5XDkoxRCjwqsc+1qMGPzI9+Cw54Hwk5Qj8XS44iSgWHIZFcd6PqjdF1zxV/IxsPMXZrJ655PjC2eiv+jCv7EWIHPPGVJxsjfSSEzpFHCDwEHBLUU7bkOananuHsH0CbUsIk4h5oTgYOslZzqxzOpNDC717Xo87L9TnrP83/fG+2m5SnIqyc6X8ESro+z8iUbvkTtkwVCu/UvIS5Vtp6movOQk8g4SrsbnQTHBfcusWqEdInRMumRhT5Vnq6A=="}
    #                   ]

    if client
      logger.debug2 "client = #{client} - called from Server.ping. received incoming client messages. response to outgoing client messages (create_public_keys_message)"
    else
      logger.debug2 "client = #{client} - called from called from util_controller.ping via Message.receive_messages"
    end

    errors = []

    response.each do |m|

      # must be a client message from other Gofreerev server
      if m["server"] != false
        errors << "Client message with invalid server flag #{m['server']} was ignored"
        next
      end

      # check sender. must be a remote did on other Gofreerev server
      if m['from_did'].to_s == ''
        errors << "Client message without from_did was ignored"
        next
      end
      if m['from_did'].class != String or m['from_did'].to_s !~ /^[0-9]{20}$/
        errors << "Client message with invalid from_did #{m['from_did']} was ignored. Must be a unique device id (20 digits) string"
        next
      end
      from = Pubkey.find_by_did(m['from_did'])
      if !from
        errors << "Client message with unknown from_did #{m['from_did']} was ignored. Did is not in pubkeys table."
        next
      end
      if !from.server_id
        errors << "Client message with invalid from_did #{from.did} was ignored. Did is not a remote client."
        next
      end
      if from.server_id != self.id
        errors << "Client message with invalid from_did #{from.did} was ignored. Did belongs to an other Gofreerev server."
      end
      if m['from_sha256'].to_s == ''
        errors << "Client message from did #{from.did} without from_sha256 was ignored"
        next
      end
      from_sha256_decoded = Base64.decode64(m['from_sha256'])
      if from_sha256_decoded.size != 32
        logger.warn2 "invalid from_sha256 #{m['from_sha256']}"
        errors << "Client message with invalid from_sha256 was ignored. Must be a base64 encoded sha256 signature. Expected length 32. Found length #{from_sha256_decoded.size}"
        next
      end
      # check if sender is "online"
      ping = Ping.where(:did => from.did, :sha256 => m['from_sha256']).order('last_ping_at desc').first
      if !ping
        logger.warn2 "remove session did #{from.did} and sha256 #{m['from_sha256']} was not found in pings"
      elsif ping.server_id != self.id
        errors << "Client message from did #{from.did} with inconsistent online users information ignored. Expected server id #{self.id}. Found server id #{ping.server_id}"
        next
      end
      logger.debug "from did #{from.did} was last online #{ping.last_ping_at}" if ping

      # check receiver. must be a local did on this Gofreerev server
      if m['to_did'].to_s == ''
        errors << "Client message without to_did was ignored"
        next
      end
      if m['to_did'].class != String or m['to_did'].to_s !~ /^[0-9]{20}$/
        errors << "Client message with invalid to_did #{m['to_did']} was ignored. Must be a unique device id (20 digits) string"
        next
      end
      to = Pubkey.find_by_did(m['to_did'])
      if !to
        errors << "Client message with unknown to_did #{m['to_did']} was ignored"
        next
      end
      if to.server_id
        errors << "Client message with invalid to_did #{to.did} was ignored. Did is a remote device"
        next
      end
      if m['to_sha256'].to_s == ''
        errors << "Client message to did #{to.did} without to_sha256 was ignored"
        next
      end
      to_sha256_decoded = Base64.decode64(m['to_sha256'])
      if to_sha256_decoded.size != 32
        logger.warn2 "invalid to_sha256 #{m['to_sha256']}"
        errors << "Client message with invalid to_sha256 was ignored. Must be a base64 encoded sha256 signature. Expected length 32. Found length #{to_sha256_decoded.size}"
        next
      end
      # check if receiver is "online"
      ping = Ping.where(:did => to.did, :sha256 => m['to_sha256']).order('last_ping_at desc').first
      if !ping
        logger.warn2 "local session did #{to.did} and sha256 #{m['to_sha256']} was not found in pings"
      elsif ping.server_id
        errors << "Client message to did #{to.did} with inconsistent online users information ignored. Expected blank server id. Found server id #{ping.server_id}"
        next
      end
      logger.debug "to did #{to.did} was last online #{ping.last_ping_at}" if ping

      message = Message.new
      message.from_did = from.did
      message.from_sha256 = m['from_sha256']
      message.to_did = to.did
      message.to_sha256 = m['to_sha256']
      message.server = false
      message.encryption = m['encryption']
      message.key = m['key']
      message.message = m['message']
      message.save!

    end # each m

    logger.debug2 "errors = #{errors.join(', ')}"
    return errors.size == 0 ? nil : errors.join(', ') if client

    # server

    return nil if received_msgtype[:client] # more than one ingoing client message (response already in messages table)
    received_msgtype[:client] = true


    if !client
      # called from receive_message via util_controller.ping
      # any client messages to be returned to calling gofreerev server
      # will be returned in ping response in Server.ping
      client_message = create_client_messages()
      if client_message
        message = Message.new
        message.from_did = client_message[:sender_did]
        message.to_did = client_message[:receiver_did]
        message.server = true
        message.encryption = client_message[:encryption]
        message.message = client_message[:message]
        message.save!
      end
    end

    nil

  end

  # receive_client_messages

  # receive remote gift verification message (request and response)
  # request: with login_users array and without verified_at_server boolean in verify_gifts array
  #   {"msgtype" : "verify_gifts",
  #    "login_users" : [{"sha256" : "jAn3w9ZxeiadO57GC43eCBvmPx/+/HZmBzQNVnrShPw=", "pseudo_user_id" : 6542}],
  #    "verify_gifts" : [
  #       {"seq" : 4, "gid" : "14253148989837740200", "sha256" : "fsèÈAUñ\u003E6\u000F7|Í\u000BªÓ#$1ÈïÕ`8~\u000E0#", "sha256_deleted" : null, "sha256_accepted" : null, "giver_user_ids" : [1], "receiver_user_ids" : []},
  #       {"seq" : 5, "gid" : "14253152345973353338", "sha256" : "°\u000Fâ\u00154=l©Pe¤A¢w\u0019;ñ\u0004zª«ä\u001AóPõ´", "sha256_deleted" : null, "sha256_accepted" : null, "giver_user_ids" : [1], "receiver_user_ids" : []},
  #       {"seq" : 6, "gid" : "14253163835441202510", "sha256" : "ÞÕ¿£ámÎ=GmKÃÇ \u001Aiìw­µÀ]S]ôTjü\u0012Á", "sha256_deleted" : null, "sha256_accepted" : null, "giver_user_ids" : [1], "receiver_user_ids" : []},
  #       {"seq" : 7, "gid" : "14253166119353097472", "sha256" : "L[âLí³8\u000B\u0001ÍB\u0011\u001FÄÂz²½Ó|r²¼\u0015öÞ", "sha256_deleted" : null, "sha256_accepted" : null, "giver_user_ids" : [1], "receiver_user_ids" : []},
  #       {"seq" : 8, "gid" : "14253170024715544645", "sha256" : "GFÖfö{lT§ª\n\\_WOpi\u000BWpÈvÍÌºåzø", "sha256_deleted" : "Ó\u0004¼bë2ÖQúðÈïªw]ÇÉ)I\u001B{ÎìùJÞæw", "sha256_accepted" : null, "giver_user_ids" : [1], "receiver_user_ids" : []},
  #       {"seq" : 9, "gid" : "14254791174816684686", "sha256" : "z\u0004\u0026¨ðRt\\,N/\u0004]\u0015dÜlîjZ47,\u0007å\u0001Ó³", "sha256_deleted" : "\u0000wnSkKî«/zè¥u£Sv÷ªIdDOµ\b éÝú", "sha256_accepted" : null, "giver_user_ids" : [-790, 1], "receiver_user_ids" : []},
  #       {"seq" : 10, "gid" : "14255660363225768616", "sha256" : "X¢©·íÝ¸G\u0004ÌvËMÜ`,\u000FQ\u001BË-ÄÓÌÉì", "sha256_deleted" : "¯¨[\fX¦á\u0007Îþ«Ï)Y*ìH\u001Bë:°Ï$î¹ä", "sha256_accepted" : null, "giver_user_ids" : [-790, 1], "receiver_user_ids" : []},
  #       {"seq" : 11, "gid" : "14255663264284720316", "sha256" : "ÀTé+çjïÀm¶â)1%èºÒ^o\f0y", "sha256_deleted" : "smtPíÄ¾j53-Y\nÄXó\u0005ñ¨wQ\u0001ßÝÒ]i\u000B\u0012", "sha256_accepted" : null, "giver_user_ids" : [-790, 1], "receiver_user_ids" : []},
  #       {"seq" : 12, "gid" : "14255666249033078430", "sha256" : "óuAT'\u0002O\u0011xÀH²Ê9\u0001\n!j%ÊÄ÷ûþVB\u0010Oc", "sha256_deleted" : ",á»£è?L¯IÒå$\u0018µ5Î ¢¾ª0NÇ,v)ãÒè\u00134", "sha256_accepted" : null, "giver_user_ids" : [-790, 1], "receiver_user_ids" : []},
  #       {"seq" : 13, "gid" : "14255715337351272927", "sha256" : ")ÛuØ\u001D|´Cç·\u0026*Äñ±\u0010ßmX\u001DÇÕæùó0ä", "sha256_deleted" : "±µÝ#wqd©°Lê%iÉ\u000F\u0006ÛgÅ\u0000ÓsÉ÷óËÁ8", "sha256_accepted" : null, "giver_user_ids" : [-790, 1], "receiver_user_ids" : []},
  #       {"seq" : 14, "gid" : "14258782920140696549", "sha256" : "ïÏ\u0000\u000F·À0x*\"¿\\·ÚÓ8M\u001C¿J\u0012z¨Hq", "sha256_deleted" : null, "sha256_accepted" : null, "giver_user_ids" : [-1016, -790, 1], "receiver_user_ids" : []}]}
  # response: without login_users array and with verified_at_server boolean in verify_gifts array
  private
  def receive_verify_gifts_request (mid, login_users, verify_gifts)
    # check and convert login users
    # login users must be sha256 signature for a verified server user or a negative integer (unknown user)
    # there must be minimum one verified server login user with valid sha256 signature in message
    # user sha256 signature must match and user must be in server_users table as verified user
    # changes sha256 user signatures
    # - local changed signatures - wait for this server to refresh user info before processing verify gifts request (keep verify request)
    # - remote changed signatures - return verify gift request and wait for remote server to send a new verify gift request with correct user signatures
    keep_message = false
    error, login_user_ids, no_local_changed_signatures, no_remote_changed_signatures =
        from_sha256s_to_user_ids(login_users,
                                 :seq => 3, :msg => 'verify_gifts', :negative_user_ids => true,
                                 :allow_changed_sha256 => 5.minutes.to_i, :field => :user_id)
    return ["verify_gifts request message was rejected. #{error}", keep_message] if error
    return ["verify_gifts request message was rejected. Message must have minimum one verified server user. login users = #{login_users}", keep_message] if login_user_ids.size == 0
    logger.debug2 "login_user_ids = #{login_user_ids.join(', ')}"
    local_changed_login_users = (no_local_changed_signatures > 0)
    remote_changed_login_users = (no_remote_changed_signatures > 0)

    # check verify_gifts array
    # seq must be unique - used in response
    seqs = verify_gifts.collect { |hash| hash['seq'] }.uniq
    return ["verify_gifts request message was rejected. seq in verify_gifts array must be unique", keep_message] if seqs.size != verify_gifts.size

    # translate giver and receiver user ids from sha256 signatures and/or unknown user to user_ids
    logger.debug2 "verify_gifts (1) = #{verify_gifts}"
    no_errors = 0 # fatal errors - request not processed
    verify_gifts_response = [] # response to calling gofreerev server
    request_on_hold = [] # keep request for later - must update user info on this gofreerev server before processing verify gift request
    local_verify_gifts_request = [] # request ready for local verification
    verify_gifts.each do |verify_gift|
      seq = verify_gift['seq']
      gid = verify_gift['gid']
      giver_user_ids = verify_gift['giver_user_ids']
      local_changed_givers = remote_changed_givers = local_changed_receivers = remote_changed_receivers = false
      if giver_user_ids.class == Array and giver_user_ids.size > 0
        # check and translate giver user ids
        error, valid_giver_user_ids, no_local_changed_signatures, no_remote_changed_signatures =
            from_sha256s_to_user_ids(giver_user_ids,
                                     :seq => 3, :msg => 'verify_gifts', :negative_user_ids => :translate,
                                     :allow_changed_sha256 => 5.minutes.to_i, :field => :id)
        if error
          logger.debug2 "seq #{seq}: invalid givers in #{giver_user_ids}: #{error}"
          verify_gifts_response.push({:seq => seq,
                         :gid => gid,
                         :verified_at_server => false,
                         :error => "invalid givers in #{giver_user_ids}: #{error}" })
          no_errors += 1
          next
        end
        if giver_user_ids.size != valid_giver_user_ids.size
          logger.debug2 "seq #{seq}: invalid givers in #{giver_user_ids}"
          verify_gifts_response.push({:seq => seq,
                         :gid => gid,
                         :verified_at_server => false,
                         :error => "invalid givers in #{giver_user_ids}" })
          no_errors += 1
          next
        end
        local_changed_givers = true if no_local_changed_signatures > 0
        remote_changed_givers = true if no_remote_changed_signatures > 0
      else
        giver_user_ids = []
      end
      receiver_user_ids = verify_gift['receiver_user_ids']
      if receiver_user_ids.class == Array and receiver_user_ids.size > 0
        # check and translate receiver user ids
        error, valid_receiver_user_ids, no_local_changed_signatures, no_remote_changed_signatures =
            from_sha256s_to_user_ids(receiver_user_ids,
                                     :seq => 3, :msg => 'verify_gifts', :negative_user_ids => :translate,
                                     :allow_changed_sha256 => 5.minutes.to_i, :field => :id)
        if error
          logger.debug2 "seq #{seq}: invalid receivers in #{receiver_user_ids}: #{error}"
          verify_gifts_response.push({:seq => seq,
                         :gid => gid,
                         :verified_at_server => false,
                         :error => "invalid receivers in #{receiver_user_ids}: #{error}" })
          no_errors += 1
          next
        end
        if receiver_user_ids.size != valid_receiver_user_ids.size
          logger.debug2 "seq #{seq}: invalid receivers in #{receiver_user_ids}"
          verify_gifts_response.push({:seq => seq,
                         :gid => gid,
                         :verified_at_server => false,
                         :error => "invalid receivers in #{receiver_user_ids}" })
          no_errors += 1
          next
        end
        local_changed_receivers = true if no_local_changed_signatures > 0
        remote_changed_receivers = true if no_remote_changed_signatures > 0
      else
        receiver_user_ids = []
      end
      # move to relevant array
      if remote_changed_login_users or remote_changed_givers or remote_changed_receivers
        # sha256 changed user signature message will be sent to remote server
        # wait for remote server to update user info and resend verify gifts request with fresh user signatures
        verify_gifts_response.push({:seq => seq,
                       :gid => gid,
                       :sha256_changed => true})
      else
        # ready for local gift verification or waiting for local user info to be updated (changed sha256 signatures)
        hash = {"seq" => seq,
                "gid" => gid,
                "sha256" => verify_gift['sha256']}
        hash["sha256_deleted"] = verify_gift["sha256_deleted"] if verify_gift["sha256_deleted"]
        hash["sha256_accepted"] = verify_gift["sha256_accepted"] if verify_gift["sha256_accepted"]
        if local_changed_login_users or local_changed_givers or local_changed_receivers
          # wait for local server to update user info and process verify gifts request later
          hash["giver_user_ids"] = giver_user_ids if giver_user_ids.size > 0
          hash["receiver_user_ids"] = receiver_user_ids if receiver_user_ids.size > 0
          request_on_hold.push(hash)
        else
          # ready to process verify gifts request
          hash["giver_user_ids"] = valid_giver_user_ids
          hash["receiver_user_ids"] = valid_receiver_user_ids
          local_verify_gifts_request.push(hash)
        end
      end
    end # each verify_gift
    
    logger.debug2 "no_errors = #{no_errors}, response.size = #{verify_gifts_response.size}, request_on_hold.size = #{request_on_hold.size}, local_request.size = #{local_verify_gifts_request.size}"
    logger.debug2 "verify_gifts (2) = #{verify_gifts}"

    if verify_gifts.size == request_on_hold.size
      # waiting for local user info update - keep verify gift message for next ping
      keep_message = true
      return [nil, keep_message]
    end

    if request_on_hold.size > 0
      # some gifts in verify gifts requests are waiting for local user info update
      # save request for next ping. Receiver is this current gofreerev server
      message = {
          :msgtype => 'verify_gifts',
          :login_users => login_users,
          :verify_gifts => request_on_hold
      }
      # validate json message before "sending"
      json_schema = :verify_gifts_request
      if !JSON_SCHEMA.has_key? json_schema
        return ["Could not validate verify_gifts message with requests on hold. JSON schema definition #{json_schema.to_s} was not found.", false]
      end
      json_errors = JSON::Validator.fully_validate(JSON_SCHEMA[json_schema], message)
      if json_errors.size > 0
        logger.error2 "Failed to \"save\" verify_gifts message with requests on hold. Error in #{json_schema}"
        logger.error2 "message = #{message}"
        logger.error2 "json_schema = #{JSON_SCHEMA[json_schema]}"
        logger.error2 "errors = #{json_errors.join(', ')}"
        return "Failed to create verify_gifts message with requests on hold: #{json_errors.join(', ')}"
      end
      # save server to server message - will be procesed in next ping
      sym_enc_message = message.to_json.encrypt(:symmetric, :password => servers[server_id].new_password)
      sym_enc_message = Base64.encode64(sym_enc_message)
      m = Message.new
      m.from_did = servers[server_id].new_did
      m.to_did = SystemParameter.did
      m.server = true
      m.encryption = 'sym'
      m.message = sym_enc_message
      m.save!
    end

    if local_verify_gifts_request.size > 0
      # gift verify requests ready for local verification
      local_verify_gifts_response = Gift.verify_gifts(local_verify_gifts_request, login_user_ids, nil, nil) # client_sid = client_sha256 = nil (local verification)
      logger.debug2 "local_verify_gifts_request = #{local_verify_gifts_request}"
      logger.debug2 "local_verify_gifts_response = #{local_verify_gifts_response}"
      local_verify_gifts_error = local_verify_gifts_response[:error]
      verify_gifts_response += local_verify_gifts_response[:gifts] if local_verify_gifts_response[:gifts]
    end
    
    logger.debug2 "local_verify_gifts_error = #{local_verify_gifts_error}"
    logger.debug2 "verify_gifts_response = #{verify_gifts_response}"

    # format response - note - no login users array
    message = {
        :msgtype => 'verify_gifts',
        :verify_gifts => verify_gifts_response,
        :mid => Sequence.next_server_mid,
        :request_mid => mid
    }
    message[:error] = local_verify_gifts_error if local_verify_gifts_error

    # validate json message before "sending"
    json_schema = :verify_gifts_response
    if !JSON_SCHEMA.has_key? json_schema
      return ["Could not validate verify_gifts response. JSON schema definition #{json_schema.to_s} was not found.", false]
    end
    json_errors = JSON::Validator.fully_validate(JSON_SCHEMA[json_schema], message)
    if json_errors.size > 0
      logger.error2 "Failed to return remote verify gifts response. Error in #{json_schema}"
      logger.error2 "message = #{message}"
      logger.error2 "json_schema = #{JSON_SCHEMA[json_schema]}"
      logger.error2 "errors = #{json_errors.join(', ')}"
      return "Failed to return remote verify gifts response: #{json_errors.join(', ')}"
    end
    # save server to server message - will be procesed in next ping
    sym_enc_message = message.to_json.encrypt(:symmetric, :password => self.new_password)
    sym_enc_message = Base64.encode64(sym_enc_message)
    m = Message.new
    m.from_did = SystemParameter.did
    m.to_did = self.new_did
    m.server = true
    m.encryption = 'sym'
    m.message = sym_enc_message
    m.mid = message[:mid]
    m.save!

  end # receive_verify_gifts_request


  # receive verify gifts response from other Gofreerev server
  def receive_verify_gifts_response (mid, request_mid, verify_gifts, error)
    logger.debug2 "mid = #{mid}, request_mid = #{request_mid}"
    logger.debug2 "verify_gifts = #{verify_gifts}"
    logger.debug2 "error        = #{error} (#{error.class})"
    logger.debug2 "error.size = #{error.size}" if error.class == Array

    errors = []
    errors << "empty verify_gifts response message was rejected" unless verify_gifts or error
    errors << error if error

    # seq in verify_gifts must be unique
    if verify_gifts
      server_seqs = verify_gifts.collect { |hash| hash['seq'] }.uniq
      if server_seqs.size != verify_gifts.size
        errors << "verify_gifts response message was rejected. seq in verify_gifts array must be unique"
        verify_gifts = nil
      end
    end
    if !verify_gifts or verify_gifts.size == 0
      logger.debug2 "errors = #{errors.join(', ')}"
      return errors.size == 0 ? nil : errors.join(', ')
    end

    # seq must be in verify_gifts table (see Gift.verify_gifts)
    vgs = {}
    VerifyGift.where(:server_seq => server_seqs).each { |vg| vgs[vg.server_seq] = vg }
    unknown_seq = []
    invalid_server_id = []
    invalid_gid = []
    invalid_response = []
    identical_response = []
    ok_response = []
    verify_gifts.each do |verify_gift|
      seq = verify_gift['seq']
      gid = verify_gift['gid']
      verified_at_server = verify_gift['verified_at_server']
      error = verify_gift['error']
      vg = vgs[seq]
      if !vg
        unknown_seq << verify_gift
      elsif vg.server_id != self.id
        invalid_server_id << verify_gift
      elsif vg.gid != gid
        invalid_gid << verify_gift
      elsif vg.verified_at_server.class != NilClass
        if (verified_at_server != vg.verified_at_server or error != vg.error)
          # has already received a different response for this request
          invalid_response << verify_gift
        else
          identical_response << verify_gift
        end
      else
        # save response for remote gift verification. Response will be returned to client in next ping
        ok_response << verify_gift
        vg.verified_at_server = verified_at_server
        vg.error = error
        vg.save!
      end
    end # each verify_gift

    logger.debug2 "verify_gifts.size = #{verify_gifts.size}, unknown_seq.size = #{unknown_seq.size}, " +
                      "invalid_server_id.size = #{invalid_server_id.size}, invalid_gid.size = #{invalid_gid.size}, " +
                      "invalid_response.size = #{invalid_response.size}, identical_response.size = #{identical_response.size}, " +
                      "ok_response.size = #{ok_response.size}"

    # verify_gifts =
    #    [{:seq=>224, :gid=>"14253148989837740200", :verified_at_server=>true}, {:seq=>225, :gid=>"14253152345973353338", :verified_at_server=>true},
    #     {:seq=>226, :gid=>"14253163835441202510", :verified_at_server=>true}, {:seq=>227, :gid=>"14253166119353097472", :verified_at_server=>true},
    #     ...
    #     {:seq=>234, :gid=>"14258782920140696549", :verified_at_server=>true}]
    ok_response.each do |verify_gift|
      seq = verify_gift['seq']
      vg = vgs[seq]
      vg.verified_at_server = verify_gift['verified_at_server']
      vg.error = verify_gift['error'] if verify_gift['error']
      vg.response_mid = mid
      vg.save!
    end

    if unknown_seq.size + invalid_server_id.size + invalid_gid.size + invalid_response.size > 0
      # send server to server error message
      errors = [ "#{unknown_seq.size + invalid_server_id.size + invalid_gid.size + invalid_response.size} rows in verify gift response" ]
      errors << "Unknown or deleted seqs: " + unknown_seq.collect { |vg| vg['seq'] }.join(', ') if unknown_seq.size > 0
      errors << "Invalid seqs (other server): " + invalid_server_id.collect { |vg| vg['seq'] }.join(', ') if invalid_server_id.size > 0
      errors << "Invalid gids: " + invalid_gid.collect { |vg| vg['seq'] }.join(', ') if invalid_gid.size > 0
      errors << "Changed response: " + invalid_response.collect { |vg| vg['seq'] }.join(', ') if invalid_gid.size > 0
      message = {
          :msgtype => 'error',
          :mid => Sequence.next_server_mid,
          :request_mid => request_mid,
          :response_mid => mid,
          :error => errors.join(', ')
      }
      logger.debug2 "error message = #{message}"
      sym_enc_message = message.to_json.encrypt(:symmetric, :password => self.new_password)
      sym_enc_message = Base64.encode64(sym_enc_message)
      m = Message.new
      m.from_did = SystemParameter.did
      m.to_did = self.new_did
      m.server = true
      m.encryption = 'sym'
      m.message = sym_enc_message
      m.mid = message.mid
      m.save!
      return errors.join(', ')
    end

    return nil
  end # receive_verify_gifts_response


  public
  def receive_verify_gifts_message(message)
    # validate json (request with login user and gifts info or response with verified_at_server boolean for each gift)
    request = message.has_key?('login_users')
    json_schema = request ? :verify_gifts_request : :verify_gifts_response
    if !JSON_SCHEMA.has_key? json_schema
      error = "Could not validate verify_gifts message. JSON schema definition #{json_schema.to_s} was not found."
      logger.error2 error
      return error
    end
    json_errors = JSON::Validator.fully_validate(JSON_SCHEMA[json_schema], message)
    if json_errors.size > 0
      logger.error2 "Invalid #{json_schema} message"
      logger.error2 "message = #{message}"
      logger.error2 "schema  = #{JSON_SCHEMA[json_schema]}"
      logger.error2 "errors  = #{json_errors.join(', ')}"
      return "Invalid #{json_schema} message : #{json_errors.join(', ')}"
    end
    # json ok - process verify gifts request/response
    mid, request_mid, login_users, verify_gifts, error =
        message['mid'], message['request_mid'], message['login_users'], message['verify_gifts'], message['error']
    if request
      error, keep_message = receive_verify_gifts_request(mid, login_users, verify_gifts)
      return [error, keep_message]
    else
      return [receive_verify_gifts_response(mid, request_mid, verify_gifts, error), false]
    end
  end # receive_verify_gifts_message




  # receive remote comment verification message (request and response)
  # request: with login_users array and without verified_at_server boolean in verify_comments array
  # response: without login_users array and with verified_at_server boolean in verify_comments array
  private
  def receive_verify_comments_req (mid, login_users, verify_comments)
    # check and convert login users
    # login users must be sha256 signature for a verified server user or a negative integer (unknown user)
    # there must be minimum one verified server login user with valid sha256 signature in message
    # user sha256 signature must match and user must be in server_users table as verified user
    # changes sha256 user signatures
    # - local changed signatures - wait for this server to refresh user info before processing verify comments request (keep verify request)
    # - remote changed signatures - return verify comment request and wait for remote server to send a new verify comment request with correct user signatures
    keep_message = false
    error, login_user_ids, no_local_changed_signatures, no_remote_changed_signatures =
        from_sha256s_to_user_ids(login_users,
                                 :seq => 3, :msg => 'verify_comments', :negative_user_ids => true,
                                 :allow_changed_sha256 => 5.minutes.to_i, :field => :user_id)
    return ["verify_comments request message was rejected. #{error}", keep_message] if error
    return ["verify_comments request message was rejected. Message must have minimum one verified server user. login users = #{login_users}", keep_message] if login_user_ids.size == 0
    logger.debug2 "login_user_ids = #{login_user_ids.join(', ')}"
    local_changed_login_users = (no_local_changed_signatures > 0)
    remote_changed_login_users = (no_remote_changed_signatures > 0)

    # check verify_comments array
    # seq must be unique - used in response
    seqs = verify_comments.collect { |hash| hash['seq'] }.uniq
    return ["verify_comments request message was rejected. seq in verify_comments array must be unique", keep_message] if seqs.size != verify_comments.size

    # translate giver and receiver user ids from sha256 signatures and/or unknown user to user_ids
    logger.debug2 "verify_comments (1) = #{verify_comments}"
    no_errors = 0 # fatal errors - request not processed
    verify_comments_response = [] # response to calling gofreerev server
    request_on_hold = [] # keep request for later - must update user info on this gofreerev server before processing verify comment request
    local_verify_comments_request = [] # request ready for local verification
    verify_comments.each do |verify_comment|
      seq = verify_comment['seq']
      cid = verify_comment['cid']
      comment_user_ids = verify_comment['user_ids']
      local_changed_comment_users = remote_changed_comment_users = false
      if comment_user_ids.class == Array and comment_user_ids.size > 0
        # check and translate comment user ids
        error, valid_comment_user_ids, no_local_changed_signatures, no_remote_changed_signatures =
            from_sha256s_to_user_ids(comment_user_ids,
                                     :seq => 3, :msg => 'verify_comments', :negative_user_ids => :translate,
                                     :allow_changed_sha256 => 5.minutes.to_i, :field => :id)
        if error
          logger.debug2 "seq #{seq}: invalid users in #{comment_user_ids}: #{error}"
          verify_comments_response.push({:seq => seq,
                                      :gid => cid,
                                      :verified_at_server => false,
                                      :error => "invalid users in #{comment_user_ids}: #{error}" })
          no_errors += 1
          next
        end
        if comment_user_ids.size != valid_comment_user_ids.size
          logger.debug2 "seq #{seq}: invalid users in #{comment_user_ids}"
          verify_comments_response.push({:seq => seq,
                                      :gid => cid,
                                      :verified_at_server => false,
                                      :error => "invalid users in #{comment_user_ids}" })
          no_errors += 1
          next
        end
        local_changed_comment_users = true if no_local_changed_signatures > 0
        remote_changed_comment_users = true if no_remote_changed_signatures > 0
      else
        comment_user_ids = []
      end
      # move to relevant array
      if remote_changed_login_users or remote_changed_comment_users
        # sha256 changed user signature message will be sent to remote server
        # wait for remote server to update user info and resend verify comments request with fresh user signatures
        verify_comments_response.push({:seq => seq,
                                    :cid => cid,
                                    :sha256_changed => true})
      else
        # ready for local comment verification or waiting for local user info to be updated (changed sha256 signatures)
        hash = {"seq" => seq,
                "cid" => cid,
                "sha256" => verify_comment['sha256']}
        hash["sha256_action"] = verify_comment["sha256_action"] if verify_comment["sha256_action"]
        hash["sha256_deleted"] = verify_comment["sha256_deleted"] if verify_comment["sha256_deleted"]
        if local_changed_login_users or local_changed_comment_users
          # wait for local server to update user info and process verify comments request later
          hash["user_ids"] = comment_user_ids if user_ids.size > 0
          request_on_hold.push(hash)
        else
          # ready to process verify comments request
          hash["user_ids"] = valid_comment_user_ids
          local_verify_comments_request.push(hash)
        end
      end
    end # each verify_comment

    logger.debug2 "no_errors = #{no_errors}, response.size = #{verify_comments_response.size}, request_on_hold.size = #{request_on_hold.size}, local_request.size = #{local_verify_comments_request.size}"
    logger.debug2 "verify_comments (2) = #{verify_comments}"

    if verify_comments.size == request_on_hold.size
      # waiting for local user info update - keep verify comment message for next ping
      keep_message = true
      return [nil, keep_message]
    end

    if request_on_hold.size > 0
      # some comments in verify comments requests are waiting for local user info update
      # save request for next ping. Receiver is this current gofreerev server
      message = {
          :msgtype => 'verify_comments',
          :login_users => login_users,
          :verify_comments => request_on_hold
      }
      # validate json message before "sending"
      json_schema = :verify_comments_request
      if !JSON_SCHEMA.has_key? json_schema
        return ["Could not validate verify_comments message with requests on hold. JSON schema definition #{json_schema.to_s} was not found.", false]
      end
      json_errors = JSON::Validator.fully_validate(JSON_SCHEMA[json_schema], message)
      if json_errors.size > 0
        logger.error2 "Failed to \"save\" verify_comments message with requests on hold. Error in #{json_schema}"
        logger.error2 "message = #{message}"
        logger.error2 "json_schema = #{JSON_SCHEMA[json_schema]}"
        logger.error2 "errors = #{json_errors.join(', ')}"
        return "Failed to create verify_comments message with requests on hold: #{json_errors.join(', ')}"
      end
      # save server to server message - will be procesed in next ping
      sym_enc_message = message.to_json.encrypt(:symmetric, :password => servers[server_id].new_password)
      sym_enc_message = Base64.encode64(sym_enc_message)
      m = Message.new
      m.from_did = servers[server_id].new_did
      m.to_did = SystemParameter.did
      m.server = true
      m.encryption = 'sym'
      m.message = sym_enc_message
      m.save!
    end

    if local_verify_comments_request.size > 0
      # comment verify requests ready for local verification
      local_verify_comments_response = Comment.verify_comments(local_verify_comments_request, login_user_ids, nil, nil) # client_sid = client_sha256 = nil (local verification)
      logger.debug2 "local_verify_comments_request = #{local_verify_comments_request}"
      logger.debug2 "local_verify_comments_response = #{local_verify_comments_response}"
      local_verify_comments_error = local_verify_comments_response[:error]
      verify_comments_response += local_verify_comments_response[:comments] if local_verify_comments_response[:comments]
    end

    logger.debug2 "local_verify_comments_error = #{local_verify_comments_error}"
    logger.debug2 "verify_comments_response = #{verify_comments_response}"

    # format response - note - no login users array
    message = {
        :msgtype => 'verify_comments',
        :verify_comments => verify_comments_response,
        :mid => Sequence.next_server_mid,
        :request_mid => mid
    }
    message[:error] = local_verify_comments_error if local_verify_comments_error

    # validate json message before "sending"
    json_schema = :verify_comments_response
    if !JSON_SCHEMA.has_key? json_schema
      return ["Could not validate verify_comments response. JSON schema definition #{json_schema.to_s} was not found.", false]
    end
    json_errors = JSON::Validator.fully_validate(JSON_SCHEMA[json_schema], message)
    if json_errors.size > 0
      logger.error2 "Failed to return remote verify comments response. Error in #{json_schema}"
      logger.error2 "message = #{message}"
      logger.error2 "json_schema = #{JSON_SCHEMA[json_schema]}"
      logger.error2 "errors = #{json_errors.join(', ')}"
      return "Failed to return remote verify comments response: #{json_errors.join(', ')}"
    end
    # save server to server message - will be procesed in next ping
    sym_enc_message = message.to_json.encrypt(:symmetric, :password => self.new_password)
    sym_enc_message = Base64.encode64(sym_enc_message)
    m = Message.new
    m.from_did = SystemParameter.did
    m.to_did = self.new_did
    m.server = true
    m.encryption = 'sym'
    m.message = sym_enc_message
    m.mid = message[:mid]
    m.save!

  end # receive_verify_comments_req


  # receive verify comments response from other Gofreerev server
  def receive_verify_comments_res (mid, request_mid, verify_comments, error)
    logger.debug2 "mid = #{mid}, request_mid = #{request_mid}"
    logger.debug2 "verify_comments = #{verify_comments}"
    logger.debug2 "error        = #{error} (#{error.class})"
    logger.debug2 "error.size = #{error.size}" if error.class == Array

    errors = []
    errors << "empty verify_comments response message was rejected" unless verify_comments or error
    errors << error if error

    # seq in verify_comments must be unique
    if verify_comments
      server_seqs = verify_comments.collect { |hash| hash['seq'] }.uniq
      if server_seqs.size != verify_comments.size
        errors << "verify_comments response message was rejected. seq in verify_comments array must be unique"
        verify_comments = nil
      end
    end
    if !verify_comments or verify_comments.size == 0
      logger.debug2 "errors = #{errors.join(', ')}"
      return errors.size == 0 ? nil : errors.join(', ')
    end

    # seq must be in verify_comments table (see Comment.verify_comments)
    vcs = {}
    VerifyComment.where(:server_seq => server_seqs).each { |vc| vcs[vc.server_seq] = vc }
    unknown_seq = []
    invalid_server_id = []
    invalid_cid = []
    invalid_response = []
    identical_response = []
    ok_response = []
    verify_comments.each do |verify_comment|
      seq = verify_comment['seq']
      cid = verify_comment['cid']
      verified_at_server = verify_comment['verified_at_server']
      error = verify_comment['error']
      vc = vcs[seq]
      if !vc
        unknown_seq << verify_comment
      elsif vc.server_id != self.id
        invalid_server_id << verify_comment
      elsif vc.cid != cid
        invalid_cid << verify_comment
      elsif vc.verified_at_server.class != NilClass
        if (verified_at_server != vc.verified_at_server or error != vc.error)
          # has already received a different response for this request
          invalid_response << verify_comment
        else
          identical_response << verify_comment
        end
      else
        # save response for remote gift verification. Response will be returned to client in next ping
        ok_response << verify_comment
        vc.verified_at_server = verified_at_server
        vc.error = error
        vc.save!
      end
    end # each verify_gift

    logger.debug2 "verify_comments.size = #{verify_comments.size}, unknown_seq.size = #{unknown_seq.size}, " +
                      "invalid_server_id.size = #{invalid_server_id.size}, invalid_cid.size = #{invalid_cid.size}, " +
                      "invalid_response.size = #{invalid_response.size}, identical_response.size = #{identical_response.size}, " +
                      "ok_response.size = #{ok_response.size}"

    ok_response.each do |verify_comment|
      seq = verify_comment['seq']
      vc = vcs[seq]
      vc.verified_at_server = verify_comment['verified_at_server']
      vc.error = verify_comment['error'] if verify_comment['error']
      vc.response_mid = mid
      vc.save!
    end

    if unknown_seq.size + invalid_server_id.size + invalid_cid.size + invalid_response.size > 0
      # send server to server error message
      errors = [ "#{unknown_seq.size + invalid_server_id.size + invalid_cid.size + invalid_response.size} rows in verify gift response" ]
      errors << "Unknown or deleted seqs: " + unknown_seq.collect { |vg| vg['seq'] }.join(', ') if unknown_seq.size > 0
      errors << "Invalid seqs (other server): " + invalid_server_id.collect { |vg| vg['seq'] }.join(', ') if invalid_server_id.size > 0
      errors << "Invalid cids: " + invalid_cid.collect { |vg| vg['seq'] }.join(', ') if invalid_cid.size > 0
      errors << "Changed response: " + invalid_response.collect { |vg| vg['seq'] }.join(', ') if invalid_cid.size > 0
      message = {
          :msgtype => 'error',
          :mid => Sequence.next_server_mid,
          :request_mid => request_mid,
          :response_mid => mid,
          :error => errors.join(', ')
      }
      logger.debug2 "error message = #{message}"
      sym_enc_message = message.to_json.encrypt(:symmetric, :password => self.new_password)
      sym_enc_message = Base64.encode64(sym_enc_message)
      m = Message.new
      m.from_did = SystemParameter.did
      m.to_did = self.new_did
      m.server = true
      m.encryption = 'sym'
      m.message = sym_enc_message
      m.mid = message.mid
      m.save!
      return errors.join(', ')
    end

    return nil
  end # receive_verify_comments_res


  public
  def receive_verify_comments_msg(message)
    # validate json (request with login user and comments info or response with verified_at_server boolean for each comment)
    request = message.has_key?('login_users')
    json_schema = request ? :verify_comments_request : :verify_comments_response
    if !JSON_SCHEMA.has_key? json_schema
      error = "Could not validate verify_comments message. JSON schema definition #{json_schema.to_s} was not found."
      logger.error2 error
      return error
    end
    json_errors = JSON::Validator.fully_validate(JSON_SCHEMA[json_schema], message)
    if json_errors.size > 0
      logger.error2 "Invalid #{json_schema} message"
      logger.error2 "message = #{message}"
      logger.error2 "schema  = #{JSON_SCHEMA[json_schema]}"
      logger.error2 "errors  = #{json_errors.join(', ')}"
      return "Invalid #{json_schema} message : #{json_errors.join(', ')}"
    end
    # json ok - process verify comments request/response
    mid, request_mid, login_users, verify_comments, error =
        message['mid'], message['request_mid'], message['login_users'], message['verify_comments'], message['error']
    if request
      error, keep_message = receive_verify_comments_req(mid, login_users, verify_comments)
      return [error, keep_message]
    else
      return [receive_verify_comments_res(mid, request_mid, verify_comments, error), false]
    end
  end # receive_verify_comments_msg
  
  
  
  
  
  # return array with messages to server or nil
  # pseudo_user_ids: hash with user_ids in users message (if any). user_ids is checked when receiving response to users message
  # in memory hash only relevant in direct server to server user messages. cannot be used in forwarded user messages
  protected
  def send_messages (pseudo_user_ids)

    # 1) rsa password setup for gofreerev server. Array with new_password1, new_password1 and new_password_md5
    # password setup complete when my new_password_md5 matches with received new_password_md5
    if !self.new_password
      # send rsa password message. array with 2-3 elements. 3 elements if ready for md5 check
      return [sym_password_message(true)]
    end # if new_password

    # 2) add server to server messages from messages table
    messages_from_mailbox = Message.send_messages self.new_did, nil
    if messages_from_mailbox
      raise messages_from_mailbox[:error] if messages_from_mailbox.has_key? :error
      messages = messages_from_mailbox[:messages]
    end
    messages = [] unless messages

    # 3) add users message (compare user.sha256 signatures and insert matches in server_users table)
    compare_users_message = create_compare_users_message(pseudo_user_ids)
    messages << compare_users_message if compare_users_message

    # 4) add online device message - send and receive information about online users
    # information is inserted into pings table and is included in :online array to users (see /util/ping)
    # create empty public key for remote online devices. public keys are replicated in step 5
    online_users_message = create_online_users_message()
    messages << online_users_message if online_users_message

    # 5) add public keys message - send and receive public keys used in client to client communication
    public_keys_message = create_public_keys_message()
    messages << public_keys_message if public_keys_message

    # 6) add client messages - messages from clients on this Gofreerev server to clients on other Gofreerev server
    client_messages = create_client_messages()
    messages << client_messages if client_messages

    logger.debug2 "messages = #{messages}"
    messages.size == 0 ? nil : messages

  end # send_messages


  # server ping - server to server messages - like js ping /util/ping (client server messages)
  # 1) send "upstream" messages to other gofreerev server and receive "downstream" messages from other gofreerev server
  #    a) rsa encrypted password message
  public
  def ping

    # secret must exists. Used in users sync between servers
    return {:error => 'Cannot send ping request. No secret was found for server id #{self.id}. Please log in'} unless self.secret

    # all time calc in time with milliseconds
    now = Time.zone.now.round(3)
    if self.next_ping_at and now < self.next_ping_at
      seconds = (self.next_ping_at-now)
      return { :error => "Ping too early. Please wait #{seconds} seconds.", :interval => (seconds*1000).round }
    end
    default_interval = 60 # default 60 seconds is used as start and fallback value for interval between pings
    old_interval = self.next_ping_at - self.last_ping_at if self.last_ping_at and self.next_ping_at
    old_interval = default_interval unless old_interval
    logger.debug "old interval = #{old_interval}"

    site_url = self.site_url
    site_url = 'https' + site_url.from(4) if secure

    # create http client
    client = HTTPClient.new
    client.set_cookie_store(self.cookie_filename()) # one cookie file per gofreerev server

    # check session
    xsrf_token = nil
    client.cookie_manager.cookies.each do |cookie|
      # logger.debug2 "cookie = #{cookie.to_json}"
      xsrf_token = cookie.value if cookie.name == 'XSRF-TOKEN'
    end
    return { :error => "No XSRF-TOKEN was found in session cookie" } unless xsrf_token

    # pseudo_user_ids used in users message. from pseudo_user_id to user_id. initialised in request. checked in response
    pseudo_user_ids = {}

    # create ping request
    # todo: users request must be symmetric encrypted. Move to send_messages and receive_messages
    url = URI.parse("#{site_url}util/ping.json")
    new_client_timestamp = (Time.now.to_f*1000).floor
    sid = SystemParameter.sid
    ping_request = {
        client_userid: 1,
        sid: sid,
        client_timestamp: new_client_timestamp,
        # new_gifts: giftService.new_gifts_request(),
        # verify_gifts: giftService.verify_gifts_request(),
        # delete_gifts: giftService.delete_gifts_request(),
        # new_comments: giftService.new_comments_request(),
        # verify_comments: giftService.verify_comments_request(),
        # pubkeys: giftService.pubkeys_request(),
        messages: send_messages(pseudo_user_ids)
    }
    ping_request.delete(:messages) if ping_request.has_key?(:messages) and ping_request[:messages].class == NilClass
    ping_request.delete(:users) if ping_request.has_key?(:users) and ping_request[:users].class == NilClass
    logger.debug2 "ping_request = #{ping_request}"
    logger.debug2 "pseudo_user_ids = #{pseudo_user_ids.to_json}"
    # X_XSRF_TOKEN - escaped in cookie - unescaped in request header
    header = {'X_XSRF_TOKEN' => CGI::unescape(xsrf_token), 'Content-Type' => 'application/json'}

    # json validate ping request before send
    json_schema = :ping_request
    if !JSON_SCHEMA.has_key? json_schema
      return { :error => "Could not validate ping request. JSON schema definition #{json_schema.to_s} was not found." }
    end
    json_errors = JSON::Validator.fully_validate(JSON_SCHEMA[json_schema], ping_request)
    return { :error => "Invalid ping json request: #{json_errors.join(', ')}" } unless json_errors.size == 0

    # update timestamp before ping
    logger.debug2 "now = #{now} (#{now.class})"
    self.last_ping_at = now
    self.next_ping_at = now + default_interval
    self.save!

    # sign ping request - called gofreerev server must validate signature for incoming ping request
    # did is included in ping signature - error "signature ...  was not valid" is returned if did was changed without a new login
    # secret is included in ping signature - error "signature ...  was not valid" is returned if secret was changed without a new login
    signature_filename = self.signature_filename(ping_request[:client_timestamp])
    signature = Server.ping_signature(SystemParameter.did, SystemParameter.secret, ping_request)
    logger.debug2 "signature_filename = #{signature_filename}"
    logger.debug2 "signature = #{signature}"
    File.write(signature_filename, signature)

    # send ping request
    logger.warn2 "unsecure post #{url}" unless secure
    res = client.post(url, :body => ping_request.to_json, :header => header)
    logger.debug2 "res = #{res}"
    FileUtils.rm signature_filename
    return { :error => "post #{url.to_s} failed with status #{res.status}" } unless res.status == 200
    client.cookie_manager.save_all_cookies(true, true, true)
    logger.debug2 "res.body = #{res.body}"

    # json validate ping response
    ping_response = JSON.parse(res.body)
    logger.debug2 "ping_response = #{ping_response}"
    json_schema = :ping_response
    if !JSON_SCHEMA.has_key? json_schema
      return { :error => "Could not validate ping response. JSON schema definition #{json_schema.to_s} was not found." }
    end
    json_errors = JSON::Validator.fully_validate(JSON_SCHEMA[json_schema], ping_response)
    return { :error => "Invalid ping json response: #{json_errors.join(', ')}" } unless json_errors.size == 0
    return { :error => ping_response['error'] } if ping_response['error']

    # process ping response from other Gofreerev server
    # 1) interval in milliseconds between ping requests
    self.next_ping_at = now + ping_response["interval"]/1000
    self.save!
    # 2) receive and process any messages
    if ping_response["messages"]
      return { :error => ping_response["messages"]["error"], :interval => ping_response["interval"]} if ping_response["messages"].has_key? "error"
      # client=true: called from Server.ping. received messages are server messages
      error = Message.receive_messages true, self.new_did, nil, pseudo_user_ids, ping_response["messages"]["messages"]
      return { :error => error, :interval => ping_response["interval"] } if error
    end
    self.reload
    # 3) todo: etc
    { :interval => ping_response["interval"] }

  end # ping


  public
  def self.servers
    ([[0, SITE_URL.gsub(/^https/, "http")]] + Server.all.
        collect { |s| [s.id, s.site_url] }).
        collect { |array| {:server_id => array[0], :sha256 => Base64.encode64(Digest::SHA256.digest(array[1])).gsub(/\n$/, "")} }
  end

  def self.server_id_to_sha256_hash
    Server.servers.collect { |hash| {hash[:server_id] => hash[:sha256]} }.reduce({}, :merge)
  end

  def self.sha256_to_server_id_hash
    Server.servers.collect { |hash| {hash[:sha256] => hash[:server_id]} }.reduce({}, :merge)
  end


  # new servers request from util_controller.ping
  # servers hash Gofreerev.rails['SERVERS'] is downloaded to client at page load (/assets/ruby_to.js)
  # this request is only used when client receives new unknown server sha256 signatures (new_gifts message)
  public
  def self.new_servers (request)
    return if !request
    return if request.size == 0
    servers = Server.sha256_to_server_id_hash
    response = []
    request.each do |sha256|
      if servers[sha256]
        response << {:sha256 => sha256, :server_id => servers[sha256]}
      else
        # todo: check for new servers in extended server network
        logger.errors "server with sha256 signature #{sha256} was not found. todo: search extended gofreerev network for new gofreerev servers"
        response << {:sha256 => sha256}
      end
    end
    return response
  end # new_servers

  def ping_test_loop
    self.login
    loop do
      res = self.ping
      logger.debug2 "res = #{res}"
      self.reload
      interval = (res[:interval] || 6000) / 1000.0
      logger.debug2 "sleep = #{interval}"
      sleep interval
    end
  end

end
