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
  end # last_ping_at=
  alias_method :last_ping_at_before_type_cast, :last_ping_at
  def last_ping_at_was
    return last_ping_at unless last_ping_at_changed?
    return nil unless (temp_last_ping_at = attribute_was(:last_ping_at))
    Time.at temp_last_ping_at
  end # last_ping_at_was

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
  end # next_ping_at=
  alias_method :next_ping_at_before_type_cast, :next_ping_at
  def next_ping_at_was
    return next_ping_at unless next_ping_at_changed?
    return nil unless (temp_next_ping_at = attribute_was(:next_ping_at))
    Time.at temp_next_ping_at
  end # next_ping_at_was

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
      self.new_did = did  # changed old public key
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
  end # save_new_did_and_public_key!

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
  end # self.ping_signature


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

  end # invalid_signature


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
    header = {'X_XSRF_TOKEN' => CGI::unescape(xsrf_token), 'Content-Type' =>'application/json' }

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

  end # login


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
    message = [(done ? 1 : 0),self.new_password1, self.new_password1_at] # 0 = symmetric password setup
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
  end # sym_password_message


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
    # 1) reverse request/response cycle (request in response and response in request). user_id < 0
    # that is users with negative user_id and client user.sha256 received from server in last ping
    buffer = ServerUserRequest.where('server_id = ? and pseudo_user_id < 0', self.id)
    buffer.all.each do |usr|
      u = User.find_by_sha256(usr.sha256)
      if !u
        request << { :user_id => usr.pseudo_user_id, :sha256 => nil}
        next
      end
      # sha256 match
      request << { :user_id => usr.pseudo_user_id, :sha256 => u.calc_sha256(self.secret) }
      # insert user match as not verified in server_users table
      su = ServerUser.find_by_server_id_and_user_id(self.id, u.id)
      next if su
      su = ServerUser.new
      su.server_id = self.id
      su.user_id = u.id
      su.save!
    end
    logger.debug2 "request (1) = #{request.to_json}"
    buffer.delete_all
    # 2) normal request/response cycle. user_id > 0. send next 10 users for verification
    # exclude gofreerev dummy users (provider=gofreerev)
    # using pseudo user ids in request
    User.where("id > ? and user_id not like 'gofreerev/%'", (self.last_checked_user_id || 0)).order(:id).limit(10).each do |u|
      pseudo_user_id = Sequence.next_pseudo_user_id
      request << { :user_id => pseudo_user_id, :sha256 => u.calc_sha256(self.secret) }
      # remember user ids from users request
      pseudo_user_ids[pseudo_user_id] = u.id
    end
    logger.debug2 "request (2) = #{request.to_json}"
    return nil if request.size == 0

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

  end # create_compare_users_message


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
  def receive_compare_users_message (response, client, pseudo_user_ids)
    logger.debug2 "users = #{response}"
    if client
      logger.debug2 "client = #{client} - called from Server.ping. received incoming compare users message. response to outgoing compare users message (create_compare_users_message)"
    else
      logger.debug2 "client = #{client} - called from called from util_controller.ping via Message.receive_messages"
    end

    # doublet check - no doublet user ids are allowed in response array
    if response.size != response.collect { |usr| usr['user_id'] }.uniq.size
      return 'users message with doublet user_ids was rejected'
    end

    max_checked_user_id = 0

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
            # not very likely error
            logger.error2 "user id #{user_id} (pseudo user id #{usr["user_id"]}) does not exists. Only ok if user was deleted between ping request and ping response"
            next
          end
          max_checked_user_id = u.id if u.id > max_checked_user_id
          if !usr['sha256']
            logger.debug2 "user id #{u.id} does not exists on other Gofreerev server"
            next
          elsif u.sha256 = usr['sha256']
            logger.debug2 "confirmed match. user_id #{u.id} exists on other Gofreerev servers"
            # insert user match as verified in server_users table
            su = ServerUser.find_by_server_id_and_user_id(self.id, u.id)
            if !su
              su = ServerUser.new
              su.server_id = self.id
              su.user_id = u.id
            end
            su.verified_at = Time.zone.now
            su.save!
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
            request << { :user_id => usr["user_id"], :sha256 => u.calc_sha256(self.secret) }
            # save match as not verified in server_users table
            su = ServerUser.find_by_server_id_and_user_id(self.id, u.id)
            if !su
              su = ServerUser.new
              su.server_id = self.id
              su.user_id = u.id
              su.save!
            end
          else
            # todo: respond with sha2546 = nil
            logger.debug2 "user does not exists. return null user.sha256 signature"
            request << { :user_id => usr["user_id"] }
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
            su.verified_at = Time.zone.now
            su.save!
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
    end

    return nil if client # client - called from Server.ping

    # server - called from util_controller.ping
    logger.debug2 "add users to response users message. response will be sent in next ping request"
    # exclude gofreerev dummy users (provider=gofreerev)
    ServerUserRequest.where(:server_id => self.id).delete_all
    User.where("id > ? and user_id not like 'gofreerev/%'", (self.last_checked_user_id || 0)).order(:id).limit(10).each do |u|
      # use negative pseudo user id in response and positive pseudo user id in db
      pseudo_user_id = Sequence.next_pseudo_user_id
      request << { :user_id => -pseudo_user_id, :sha256 => u.calc_sha256(self.secret) }
      # insert into ServerUserRequest. Pseudo user ids must be in next ping request from "client".
      sur = ServerUserRequest.new
      sur.server_id = self.id
      sur.pseudo_user_id = pseudo_user_id
      sur.user_id = u.id
      sur.save!
    end # each u

    logger.debug2 "users = #{request}"

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

  end # receive_compare_users_message


  # send information about online mutual users to other gofreerev server
  # merge information in pings table with verified matches in server_users table
  # using user sha256 signatures. No real user information is exchanged
  # todo: use pseudo session ids when communicating with other gofreerev servers
  # todo: only include mutual_friends that is in server_users table
  protected
  def create_online_users_message

    # find any online users in pings table
    pings = Ping.where('server_id is null').order('session_id, client_userid, last_ping_at desc')

    # remove server pings and remove old pings. only last ping for each did is relevant
    old_key = 'x'
    pings.delete_if do |p|
      server = (p.user_ids.size == 1 and p.user_ids.first =~ /^http:\/\//)
      new_key = "#{p.session_id},#{p.client_userid}"
      if server or (new_key == old_key)
        true
      elsif !p.did
        logger.warn2 "ignoring ping without did: #{p.to_json}"
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

    # initialize a hash with user_id and sha256 signature for verified users (identical users on both Gofreerev servers)
    # from external user id (uid/provider) to sha256 signature for user on other gofreerev server
    verified_users = {}
    ServerUser.where('server_id = ? and verified_at is not null', self.id).includes(:user).where('users.user_id' => online_user_ids).each do |su|
      verified_users[su.user.user_id] = su.user.calc_sha256(self.secret)
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
      request << { :session_id => rs.pseudo_session_id,
                   :client_userid => p.client_userid,
                   # :client_sid => p.client_sid,
                   :last_ping_at => p.last_ping_at.to_f,
                   # :next_ping_at => p.next_ping_at, # remove - not relevant
                   :did => p.did,
                   :user_ids => user_ids, # user sha256 signatures
                   :sha256 => p.sha256 }
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

  end # create_online_users_message


  public
  def receive_online_users_message (response, client)

    logger.debug2 "users = #{response}"
    # users = [{"session_id"=>"9c653cde5b1cd771756cf2dc49a1376d", "last_ping_at"=>1427021803.289,
    #           "did"=>"14252356907464191530", "user_ids"=>["QoTMDQkHpw7Gyjl9NBcuIHk6JwdK7THv2RKXVoTNWM0=\n"],
    #           "sha256"=>"0SumAAlBe/4vEMdftHU5puueYlccj0F50zDaUGkV4/Y=\n"}]

    if client
      logger.debug2 "client = #{client} - called from Server.ping. received incoming online users message. response to outgoing online users message (create_online_users_message)"
    else
      logger.debug2 "client = #{client} - called from called from util_controller.ping via Message.receive_messages"
    end

    errors = []

    response.each do |ping|

      # check user_ids. sha256 signature must match and user must be in server_users table as verified user
      users = ServerUser.includes(:user).
          where("users.sha256 in (?) and server_id = ? and verified_at is not null", ping["user_ids"], self.id).references(:users)
      user_ids = users.collect { |u| u.user.user_id }
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
      ss = ServerSession.find_by_server_id_and_server_session_id(self.id, ping["session_id"])
      if !ss
        ss = ServerSession.new
        ss.server_id = self.id
        ss.server_session_id = ping["session_id"]
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
      # find/create ping
      p = Ping.find_by_session_id_and_client_userid(ss.session_id, ping["client_userid"])
      if !p
        p = Ping.new
        p.session_id = ss.session_id.to_s
        p.client_userid = ping["client_userid"]
        p.client_sid = ss.session_id.to_s
        p.did = ping["did"]
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
        request << { :did => spr.did, :pubkey => nil } # error response
      else
        request << { :did => p.did, :pubkey => p.pubkey } # ok response
      end
    end

    # 2) normal request. Request missing public keys from other gofreerev server
    Pubkey.where('server_id = ? and pubkey is null and client_request_at is not null', self.id).each do |p|
      request << { :did => p.did } # request. no pubkey
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

  end # create_public_keys_message


  public
  def receive_public_keys_message (response, client)

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
          request << { :did => spr.did, :pubkey => nil } # error response
        else
          request << { :did => p.did, :pubkey => p.pubkey } # ok response
        end
      end
    end # each

    if !client
      # any public key requests from server to client. response in next ping request
      Pubkey.where('server_id = ? and pubkey is null and client_request_at is not null', self.id).each do |p|
        request << { :did => p.did } # request. no pubkey
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

  end # receive_public_keys_message


  # send and receive across Gofreerev server client to client messages
  # client message is already encrypted but is put in a encrypted server to server message
  protected
  def create_client_messages

    messages = []

    Message.includes(:from_pubkey, :to_pubkey).
        where('server = ? and pubkeys.server_id is null and to_pubkeys_messages.server_id = ?', false, 1).
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
    return nil if messages.size == 0

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

  end # create_client_messages


  public
  def receive_client_messages (response, client)

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
        errors << "Client message with unknown from_did #{m['from_did']} was ignored"
        next
      end
      if !from.server_id
        errors << "Client message with invalid from_did #{from.did} was ignored. Did is not a remote device."
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

    errors.size == 0 ? nil : errors.join(', ')

  end # receive_client_messages


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

    messages.size == 0 ? nil : messages

  end # send_messages


  # server ping - server to server messages - like js ping /util/ping (client server messages)
  # 1) send "upstream" messages to other gofreerev server and receive "downstream" messages from other gofreerev server
  #    a) rsa encrypted password message
  public
  def ping

    # secret must exists. Used in users sync between servers
    return 'Cannot send ping request. No secret was found for server id #{self.id}. Please log in' unless self.secret

    # all time calc in time with milliseconds
    now = Time.zone.now.round(3)
    if self.next_ping_at and now < self.next_ping_at
      seconds = (self.next_ping_at-now)
      return "Ping too early. Please wait #{seconds} seconds."
    end
    default_interval = 60 # default 60 seconds is used as start and fallback value for interval between pings
    old_interval = self.next_ping_at - self.last_ping_at if self.last_ping_at and self.next_ping_at
    old_interval = default_interval  unless old_interval
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
    return "No XSRF-TOKEN was found in session cookie" unless xsrf_token

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
        messages: self.send_messages(pseudo_user_ids)
    }
    ping_request.delete(:messages) if ping_request.has_key?(:messages) and ping_request[:messages].class == NilClass
    ping_request.delete(:users) if ping_request.has_key?(:users) and ping_request[:users].class == NilClass
    logger.debug2 "ping_request = #{ping_request}"
    logger.debug2 "pseudo_user_ids = #{pseudo_user_ids.to_json}"
    # X_XSRF_TOKEN - escaped in cookie - unescaped in request header
    header = {'X_XSRF_TOKEN' => CGI::unescape(xsrf_token), 'Content-Type' =>'application/json' }

    # json validate ping request before send
    json_schema = :ping_request
    if !JSON_SCHEMA.has_key? json_schema
      return "Could not validate ping request. JSON schema definition #{json_schema.to_s} was not found."
    end
    json_errors = JSON::Validator.fully_validate(JSON_SCHEMA[json_schema], ping_request)
    return "Invalid ping json request: #{json_errors.join(', ')}" unless json_errors.size == 0

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
    if res.status != 200
      puts "post #{url.to_s} failed with status #{res.status}"
      return nil
    end
    client.cookie_manager.save_all_cookies(true, true, true)
    logger.debug2 "res.body = #{res.body}"
    
    # json validate ping response
    ping_response = JSON.parse(res.body)
    logger.debug2 "ping_response = #{ping_response}"
    json_schema = :ping_response
    if !JSON_SCHEMA.has_key? json_schema
      return "Could not validate ping response. JSON schema definition #{json_schema.to_s} was not found."
    end
    json_errors = JSON::Validator.fully_validate(JSON_SCHEMA[json_schema], ping_response)
    return "Invalid ping json response: #{json_errors.join(', ')}" unless json_errors.size == 0
    return ping_response['error'] if ping_response['error']

    # process ping response from other Gofreerev server
    # 1) interval in milliseconds between ping requests
    self.next_ping_at = now + ping_response["interval"]/1000
    self.save!
    # 2) receive and process any messages
    if ping_response["messages"]
      return ping_response["messages"]["error"] if ping_response["messages"].has_key? "error"
      Message.receive_messages true, self.new_did, nil, pseudo_user_ids, ping_response["messages"]["messages"] # true: called from Server.ping
    end
    # 3) todo: etc

  end # ping

end
