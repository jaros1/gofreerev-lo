class Server < ActiveRecord::Base

  # create_table "servers", force: true do |t|
  #   t.string   "site_url"
  #   t.boolean  "secure"
  #   t.string   "new_did",          limit: 20
  #   t.text     "new_pubkey"
  #   t.string   "old_did",          limit: 20
  #   t.text     "old_pubkey"
  #   t.datetime "last_ping_at"
  #   t.datetime "next_ping_at"
  #   t.datetime "created_at"
  #   t.datetime "updated_at"
  #   t.text     "key"
  #   t.text     "secret"
  # end
  # add_index "servers", ["site_url"], name: "index_servers_url", unique: true, using: :btree

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

  # 10: old_dids - json array with old not used dids. discard any incoming messages for old dids

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
  protected
  def create_users_message
    request = []
    # reverse request/response cycle (request in response and response in request). user_id < 0
    # that is users with negative user_id and client user.sha256 received from server in last ping
    surs = ServerUserRequest.where(:server_id => self.id)
    surs.all do |usr|
      u = User.find_by_sha256(usr.sha256)
      if !u
        request << { :user_id => usr.user_id, :sha256 => nil}
        next
      end
      # sha256 match
      request << { :user_id => usr.user_id, :sha256 => u.calc_sha256(self.secret) }
      # insert user match as not verified in server_users table
      su = ServerUser.find_by_server_id_and_user_id(self.id, u.id)
      next is su
      su = ServerUser.new
      su.server_id = self.id
      su.user_id = u.id
      su.save!
    end
    surs.delete_all
    # normal request/response cycle. user_id > 0. send next 10 users for verification
    User.order(:id).limit(10).each do |u|
      request << { :user_id => u.id, :sha256 => u.calc_sha256(self.secret) }
    end
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

  end # create_users_message


  # receice symmetric encrypted message on client or on server
  # client:
  # - true - server side of communication - called from Server.ping
  # - false - server side of communication - called from util_controller.ping via Message.receive_messages
  public
  def receive_users_message (response, client)
    logger.debug2 "users = #{response}"
    if client
      logger.debug2 "client = #{client} - called from Server.ping. received incoming users message. response to outgoing users message (create_users_message)"
    else
      logger.debug2 "client = #{client} - called from called from util_controller.ping via Message.receive_messages"
    end

    users = [] unless client

    response.each do |usr|
      logger.debug2 "usr = #{usr}"
      if client
        # called from Server.ping. received incoming users message. response to outgoing users message (create_users_message)
        if usr["user_id"] > 0
          # user_id > 0. My user in response to outgoing users message. todo: user_id must be in validate from to user_id range
          logger.debug2 "#{usr["user_id"]} > 0. My user in response to outgoing users message"
          u = User.find_by_id(usr["user_id"])
          if !u
            logger.error2 "user id #{usr["user_id"]} does not exists. Only ok if user was deleted between ping request and ping response"
            next
          end
          if usr['sha256']
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
            logger.warn2 "ignore user match. invalid sha256 signature was returned for user_id #{u.id}"
          end
        else
          # user_id < 0. User from other gofreerev server in response to outgoing users message. save for next outgoing users message
          logger.debug2 "#{usr["user_id"]} < 0. User from other gofreerev server in response to outgoing users message. save for next outgoing users message"
          sur = ServerUserRequest.new
          sur.server_id = self.id
          sur.user_id = usr['user_id']
          sur.sha256 = usr['sha256']
          sur.save!
        end
      else
        # called from called from util_controller.ping via Message.receive_messages
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
            users << { :user_id => usr["user_id"], :sha256 => u.calc_sha256(self.secret) }
          else
            # todo: respond with sha2546 = nil
            logger.debug2 "user does not exists. return null user.sha256 signature"
            users << { :user_id => usr["user_id"] }
          end
        else
          # user_id < 0. My user from response to a previously incoming users message. todo: user_id must be in validate from to user_id range
          logger.debug2 "#{usr["user_id"]} < 0. My user from response to a previously incoming users message"
          u = User.find_by_id(-usr["user_id"])
          if !u
            logger.error2 "user id #{-usr["user_id"]} does not exists. Only ok if user was deleted between two pings"
            next
          end
          if !usr['sha256']
            logger.debug2 "no match - user_id #{-usr["user_id"]} does not exist on other Gofreerev server"
          elsif u.sha256 == usr['sha256']
            logger.debug2 "confirmed match. user_id #{-usr["user_id"]} exists on other Gofreerev servers"
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
            logger.warn2 "ignore user match. invalid sha256 signature was returned for user_id #{-usr["user_id"]}"
          end
        end
      end
    end

    return if client

    logger.debug2 "add users to response users message. response will be sent in next ping request"
    User.order(:id).limit(10).each do |u|
      users << { :user_id => -u.id, :sha256 => u.calc_sha256(self.secret) }
    end
    logger.debug2 "users = #{users}"

    message = {
        :msgtype => 'users',
        :users => users
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

  end # receive_users_message


  # return array with messages to server or nil
  protected
  def send_messages

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

    # 3) add users message
    users_message = create_users_message()
    messages << users_message if users_message

    messages.size == 0 ? nil : messages

  end # send_messages


  # match user information with other Gofreerev server
  # matching is done with user.sha256
  # send user_id + server user.sha256 to other Gofreerev server
  # receive user_id + client user.sha256 from other Gofreerev server
  # comparing is done with sha256 signatures - no user information is exchanged
  # user_id > 0 - user from Gofreerev server - complete verified in one request/response cycle
  # user_id < 0 - user from other Gofreerev server - received in response - response in next request
  protected
  def send_users
    request = []
    # reverse request/response cycle (request in response and response in request). user_id < 0
    # that is users with negative user_id and client user.sha256 received from server in last ping
    surs = ServerUserRequest.all
    surs.all do |usr|
      u = User.find_by_sha256(usr.sha256)
      if !u
        request << { :user_id => usr.user_id, :sha256 => nil}
        next
      end
      # sha256 match
      request << { :user_id => usr.user_id, :sha256 => u.calc_sha256(self.secret) }
      # insert user match as not verified in server_users table
      su = ServerUser.find_by_server_id_and_user_id(self.id, u.id)
      next is su
      su = ServerUser.new
      su.server_id = self.id
      su.user_id = u.id
      su.save!
    end
    surs.delete_all
    # normal request/response cycle. user_id > 0. send next 10 users for verification
    User.order(:id).limit(10).each do |u|
      request << { :user_id => u.id, :sha256 => u.calc_sha256(self.secret) }
    end
    request
  end
  def receive_users (users)
  end


  # server ping - server to server messages - like js ping /util/ping (client server messages)
  # 1) send "upstream" messages to other gofreerev server and receive "downstream" messages from other gofreerev server
  #    a) rsa encrypted password message
  public
  def ping

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
        messages: self.send_messages
    }
    ping_request.delete(:messages) if ping_request.has_key?(:messages) and ping_request[:messages].class == NilClass
    ping_request.delete(:users) if ping_request.has_key?(:users) and ping_request[:users].class == NilClass
    logger.debug2 "ping_request = #{ping_request}"
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
      Message.receive_messages true, self.new_did, nil, ping_response["messages"]["messages"] # true: called from Server.ping
    end
    # 3) todo: etc

  end # ping

end
