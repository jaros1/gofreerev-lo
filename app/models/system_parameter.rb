class SystemParameter < ActiveRecord::Base


  # 1 - name - String in model and database
  
  # 2 - value - String in model - base64 encoded in database
  def value
    return nil unless (extended_value = read_attribute(:value))
    Base64.decode64(extended_value)
  end # value
  def value=(new_value)
    if new_value
      # logger.debug2  "new_value = #{new_value} (#{new_value.class.name})"
      write_attribute :value, Base64.encode64(new_value)
    else
      write_attribute :value, nil
    end
  end # value=
  alias_method :value_before_type_cast, :value
  def value_was
    return value unless value_changed?
    return nil unless (extended_value = attribute_was(:value))
    Base64.decode64(extended_value)
  end # value_was

  # setup distributed server network
  # this server can connect to other gofreerev servers as client
  # other gofreerev servers can connect to this gofreerev as clients
  def self.generate_key_pair
    # generate and save public/private key pair
    SystemParameter.where(:name => %w(public_key private_key)).delete_all
    k = SSHKey.generate
    # save public key - not encrypted
    s = SystemParameter.new
    s.name = 'public_key'
    s.value = k.public_key
    s.save!
    # save private key - encrypted with 1-5 passwords - see config/initializers/constants.rb
    x = k.private_key
    [PK_PASS_1_ENV, PK_PASS_2_RAILS, PK_PASS_3_DB, PK_PASS_4_FILE, PK_PASS_5_MEM].each do |password|
      x = x.encrypt(:symmetric, :password => password) if password
    end
    s = SystemParameter.new
    s.name = 'private_key'
    s.value = x
    s.save!

    # todo: change did, secret and/or sid when key pair changes?
    # create/update did (unique device id) - new key pair = new did
    SystemParameter.new_did
    # create/update client secret. used as secret part of device.sha256
    # did+sha256 is mailbox address in client to client communication
    SystemParameter.new_secret
    # create/update sid (unique session id). used in ping request
    SystemParameter.new_sid
  end # self.generate_key_pair

  def self.public_key
    s = SystemParameter.find_by_name('public_key')
    return nil unless s
    s.value
  end

  def self.private_key
    s = SystemParameter.find_by_name('private_key')
    return nil unless s
    # decrypt private key
    x = s.value
    passwords = [PK_PASS_1_ENV, PK_PASS_2_RAILS, PK_PASS_3_DB, PK_PASS_4_FILE, PK_PASS_5_MEM]
    (passwords.length-1).downto(0) do |i|
      password = passwords[i]
      next unless password
      # write debug information to identify where decrypt failed
      begin
        x = x.decrypt(:symmetric, :password => password)
      rescue OpenSSL::Cipher::CipherError => e
        # write debug information to identify where decrypt failed
        logger.error2 "private key decrypt failed at step #{i} with error message #{e.message}"
        raise
      end
    end
    x
  end

  def self.did
    s = SystemParameter.find_by_name('did')
    s ? s.value : nil
  end

  # create new did or update old did.
  # all gofreerev servers must reconnect (login) after changed did
  # calling gofreerev servers are automatic disconnected when changing did (Session.close_server_sessions)
  # called gofreerev servers will return error message "signature http://... was not valid" until new reconnect
  def self.new_did
    s = SystemParameter.find_by_name('did')
    old_did = s.value if s
    if !s
      s = SystemParameter.new
      s.name = 'did'
    end
    s.value = (Time.now.to_f.to_s + rand().to_s.last(7)).gsub('.','').first(20)
    s.save!
    return unless old_did

    # changed did - new login is required for all server to server sessions
    # todo: there must be a table with timestamp for next ping to other Gofreerev servers. use this table to force reconnect
    # todo: fields last_ping_at and next_ping_at are already in servers table (outgoing pings)
    # todo: fields last_ping_at and next_ping_at are already in pings table (ingoing pings)
    logger.warn2 "Did was changed. Please reconnect (login) for all Gofreerev server sessions"
    Session.close_server_sessions

    # keep a list of old dids. Ignore messages to/from old dids
    old_dids = SystemParameter.old_dids
    old_dids << old_did
    SystemParameter.old_dids = old_dids

    # cleanup messages
    messages = Message.where("server = ? and (from_did = ? or to_did = ?)", true, old_did, old_did)
    return if messages.size == 0
    logger.warn2 "deleting #{messages.size} messages to/from old did #{old_did}"
    messages.delete_all
    nil
  end # self.new_did

  # keep a list of old dids. Ignore messages to/from old dids
  def self.old_dids
    s = SystemParameter.find_by_name('old_dids')
    s ? JSON.parse(s.value) : []
  end
  def self.old_dids=(old_dids)
    s = SystemParameter.find_by_name('old_dids')
    if !s
      s = SystemParameter.new
      s.name = 'old_dids'
    end
    s.value = old_dids.to_json
    s.save!
  end

  def self.sid
    s = SystemParameter.find_by_name('sid')
    s ? s.value : nil
  end

  def self.new_sid
    s = SystemParameter.find_by_name('sid')
    if !s
      s = SystemParameter.new
      s.name = 'sid'
    end
    s.value = (Time.now.to_f.to_s + rand().to_s.last(7)).gsub('.','').first(20)
    s.save!
    nil
  end # self.new_sid
  
  def self.secret
    s = SystemParameter.find_by_name('secret')
    s ? s.value : nil
  end

  def self.secret_at
    s = SystemParameter.find_by_name('secret')
    s ? s.updated_at : nil
  end

  # create/update secret.
  # client: used as secret part of device.sha256. did+sha256 is mailbox address in client to client communication
  # server: used as secret part of user sha256 signature when comparing user lists with other Gofreerev servers
  def self.new_secret
    s = SystemParameter.find_by_name('secret')
    if !s
      s = SystemParameter.new
      s.name = 'secret'
    end
    # no sha256 signature for gofreerev dummy users
    users = User.where("user_id not like 'gofreerev/%'")
    # prevent overlap between old sha256 signatures and new sha256 signatures
    # ( old sha256 signature is used as fallback option when receiving messages with unknown sha256 signatures )
    old_signatures = {}
    users.each do |u|
      old_signatures[u.sha256] = true if u.sha256 ;
    end
    # generate new secret. loop until user.sha256 values are unique
    secret = nil
    loop do
      secret = String.generate_random_string(10)
      signatures = {}
      users.each do |u|
        sha256 = u.calc_sha256(secret)
        if old_signatures[sha256]
          logger.debug2 "old sha256 signature was found for #{u.debug_info}"
          break
        end
        if signatures[sha256]
          logger.debug2 "doublet sha256 signature was found for #{u.debug_info}"
          break
        end
        signatures[sha256] = true
      end # each user
      logger.debug2 "users.size = #{users.size}, signatures.size = #{signatures.size}"
      break if users.size == signatures.size
    end
    # found new system secret
    # update sha256 for all users - fast lookup when comparing users across Gofreerev servers
    # sha256 signature is also used is user id when receiving messages from clients on other gofreerev servers
    # old_sha256 signature is used as fallback option when receiving messages with old sha256 signature from other Gofreerev servers
    # timestamp for secret change is in updated_at for secret
    # allow messages with old sha256 signatures to arrive 1-2 minutes after secret change
    update_batch_size = 50 # todo: move to rails constant
    if update_batch_size > 1
      # update users in bundles with update_batch_size in each update statement (mysql)
      update_batch = []
      0.upto(users.length-1) do |i|
        user = users[i]
        update_batch << {:id => user.id,
                         :sha256 => user.calc_sha256(secret),
                         :old_sha256 => user.sha256
        }
        if update_batch.size == update_batch_size or i == users.length-1
          update_sql = 'sha256 = case id ' ;
          update_batch.each do |hash|
            update_sql += "when #{hash[:id]} then '#{hash[:sha256]}' "
          end
          update_sql += 'end, old_sha256 = case id ' ;
          update_batch.each do |hash|
            update_sql += "when #{hash[:id]} then '#{hash[:old_sha256]}' "
          end
          update_sql += 'end where id in (' + update_batch.collect { |hash| hash[:id] }.join(',') + ')' ;
          # logger.debug2 "update = #{update_sql}"
          User.update_all(update_sql)
          update_batch = []
        end
      end
    else
      # rails update loop. can take some time in a database with many users
      users.each do |u|
        u.update_attribute :old_sha256, u.sha256
        u.update_attribute :sha256, u.calc_sha256(secret)
      end
    end
    # update secret.
    s.value = secret
    s.save!
    # force server reconnect - servers must exchange secrets in new login - used when comparing users
    logger.warn2 "Secret was changed. Please reconnect (login) for all Gofreerev server sessions"
    Session.close_server_sessions
    # todo: there is a copy of secret.updated_at in all sessions browser sessions
    # todo: next ping will download a list with new sha256 signatures for friend lists
    #
    # sha256 signatures are used as user_id in client to client messages on other Gofreerev servers
    # sha256 signatures used in outgoing messages can be found in ping/online response and is stored in JS mailboxes array (GiftService)
    # sha256 signatures used in incoming messages can be found in JS friends array (UserService)
    # todo: see warnings
    logger.warn2 "todo: how to handle receiving messages with old sha256 user signature (secret on other gofreerev server was changed after message has been sent)"
    logger.warn2 "todo: how to handle receiving messages with new sha256 user signature (secret on this gofreerev server has changed but sha256 signatures in friends JS array are old)"
    nil
  end

end
