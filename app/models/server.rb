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
  validates_presence_of :new_did
  validates_format_of :new_did, :with => /\A[0-9]{20}\z/

  # 4: new_pubkey - new unvalidated public key

  # 5: old_did - old validated did - unique device id - unix timestamp (10) with milliseconds (3) and random numbers (7) - total 20 decimals
  validates_presence_of :new_did
  validates_format_of :new_did, :with => /\A[0-9]{20}\z/

  # 6: old_pubkey - old validated public key

  # 7: last_ping_at - last ping request to server

  # 8: next_ping_at - next ping request to server


  # receive did and public key from other gofreerev server
  # saved in new_did and new_public if changed - must be validated before moved to old_did and old_pubkey
  # called from server.login (model) and util.login (controller)
  public
  def save_new_did_and_public_key! (did, pubkey)
    if ![self.old_did, self.new_did].index(did)
      # new did received. ok to change to a new did - not ok to change to a existing did
      return "#{site_url}: Cannot change did to #{did}. did #{did} already exists" if Pubkey.find_by_did(did)
      logger.warn2 "#{site_url}: changing did to #{did}"
      self.new_did = did
      self.new_pubkey = pubkey
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
    end
    if did == self.new_did and pubkey != self.new_pubkey
      # changed new public key
      logger.debug2 "#{site_url}: received new public key for new did #{did}"
      self.new_pubkey = pubkey
    end
    self.save! if self.changed?
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
      rescue Errno::ECONNREFUSED => e
        return "signature verification failed with: \"#{e.message}\""
      rescue OpenSSL::SSL::SSLError => e
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
    logger.debug2 "signature = #{signature}"
    logger.debug2 "res.body  = #{res.body}"
    signature == res.body ? nil : 'Invalid signature'

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
    s = SystemParameter.find_by_name('secret') ; secret = s.value
    s = SystemParameter.find_by_name('did') ; did = s.value
    url = URI.parse("#{site_url}util/login.json")
    login_request = {:client_userid => 1,
                     :client_timestamp => (Time.now.to_f*1000).floor,
                     :client_secret => secret,
                     :did => did,
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

    # sign login request - called gofreerev server should validate signature
    signature_filename = self.signature_filename(login_request[:client_timestamp])
    signature = Server.login_signature(login_request)
    logger.debug2 "signature_filename = #{signature_filename}"
    logger.debug2 "signature = #{signature}"
    File.write(signature_filename, signature) ;

    # send login request
    logger.warn2 "unsecure post #{url}" unless secure
    res = client.post(url, :body => login_request.to_json, :header => header)
    logger.debug2 "res = #{res}"
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
    save_new_did_and_public_key!(login_response['did'], login_response['pubkey'])

    nil

  end # login

end
