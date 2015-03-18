class Message < ActiveRecord::Base

  # create_table "messages", force: true do |t|
  #   t.string   "from_did",    limit: 20,       null: false
  #   t.string   "from_sha256", limit: 45
  #   t.string   "to_did",      limit: 20,       null: false
  #   t.string   "to_sha256",   limit: 45
  #   t.string   "encryption",  limit: 3,        null: false
  #   t.boolean  "server",                       null: false
  #   t.text     "key"
  #   t.text     "message",     limit: 16777215, null: false
  #   t.datetime "created_at"
  #   t.datetime "updated_at"
  # end
  # add_index "messages", ["from_did", "created_at"], name: "index_messages_from_did", using: :btree
  # add_index "messages", ["to_did", "created_at"], name: "index_messages_to_did", using: :btree

  # 1) from_did - from unique device id - client or server
  validates_presence_of :from_did
  validates_format_of :from_did, :with => /\A[0-9]{20}\z/, :allow_blank => true

  # 2) from_sha256 - from sha256 signature - only client - generated from client secret + user ids for logged in users
  validates_presence_of :from_sha256, :if => Proc.new { |rec| rec.server == false }
  validates_absence_of :from_sha256, :if => Proc.new { |rec| rec.server == true }

  # 3) to_did - to unique device id - client or server
  validates_presence_of :to_did
  validates_format_of :to_did, :with => /\A[0-9]{20}\z/, :allow_blank => true
  validates_each :to_did, :allow_blank => true do |record, attr, value|
    if record.from_did and record.from_did =~ /\A[0-9]{20}\z/ and value =~ /\A[0-9]{20}\z/
      record.errors.add attr, 'from_did must be different than to_did' if value == record.from_did
    end
  end
  # 4) to_sha256 - to sha256 signature - only client - generated from client secret + user ids for logged in users
  validates_presence_of :to_sha256, :if => Proc.new { |rec| rec.server == false }
  validates_absence_of :to_sha256, :if => Proc.new { |rec| rec.server == true }

  # 5) encryption - rsa, sym or mix
  #    rsa - public private key encryption. key length should be minimum 2048 bits
  #    sym - symmetric encryption - the 2 parts in communication must previous exchanged password for symmetric communication
  #    mix - key is rsa encrypted and message is symmetric encrypted with key
  validates_presence_of :encryption
  validates_inclusion_of :encryption, :in => %w(rsa sym mix), :allow_blank => true

  # 6) server - true: server to server communication - false: client to client communication
  validates_inclusion_of :server, :in => [true, false]

  # 7) key - only mix - rsa encrypted key used for symmetric encrypted message
  validates_presence_of :key, :if => Proc.new { |rec| rec.encryption == 'mix' }
  validates_absence_of :key, :if => Proc.new { |rec| %w(rsa sym).index(rec.encryption) }

  # 8) message - rsa or sym encrypted message
  validates_presence_of :message

  # 9) timestamps

  def receive_message_sym_password
    # setup password for symmetric communication
    # gofreerev.js: see GiftService.receive_message_password (client to client)
    key = OpenSSL::PKey::RSA.new SystemParameter.private_key
    message_str_rsa_enc = Base64.decode64(self.message)
    message_str = key.private_decrypt(message_str_rsa_enc, OpenSSL::PKey::RSA::PKCS1_OAEP_PADDING)
    logger.secret2 "message_json = #{message_str}"
    message = message_str.split(',')
    # todo: allow rsa symmetric password setup to be routed through other gofreerev servers?
    #       must include did, site url and public key information - to big for rsa - must use sym or mix encryption
    server = Server.find_by_new_did self.from_did
    if !server
      # Unknown server! Cannot handle rsa message. Can be an old message from a server with new did
      logger.error2 "Ignoring rsa message from unknown server #{self.from_did}"
      self.destroy!
      return
    end
    if !server.new_pubkey
      # Public keys are send and received in login request/response
      logger.error2 "Ignoring rsa message from #{server.site_url} without a public key"
      self.destroy!
      return
    end
    # save symmetric password part 2 received from other Gofreerev server
    server.set_new_password1 unless server.new_password1
    done = message[0]
    server.new_password2 = message[1]
    server.new_password2_at = message[2].to_i
    server.save!
    client_md5 = Base64.decode64(message[3]) if message.size == 4
    md5_ok = (client_md5 == server.new_password_md5)
    if md5_ok
      logger.debug2 "symmetric password setup completed."
    else
      logger.debug2 "symmetric password setup in progress. md5_ok = #{md5_ok}, message.size = #{message.size}"
      logger.debug2 "client_md5 = #{client_md5}"
      logger.debug2 "server_md5 = #{server.new_password_md5}"
    end
    self.destroy!

    return if done and md5_ok # password setup completed on both Gofreerev servers

    # send/resend password part 1 to other server
    hash = server.send_message_sym_password(md5_ok)
    m = Message.new
    m.from_did = hash[:sender_did]
    m.to_did = hash[:receiver_did]
    m.server = hash[:server]
    m.encryption = hash[:encryption]
    m.message = hash[:message]
    m.save!

  end # receive_message_password


  # read message for this server
  def receive_message
    logger.debug "new mail: #{self.to_json}"

    if self.encryption == 'rsa'
      # setup password for symmetric communication
      # javascript: see GiftService.receive_message_password in gofreerev.js (client to client)
      receive_message_sym_password
      return
    end

    logger.error2 "not implemented"

  end # receive_message


  def self.receive_messages (sender_did, sender_sha256, input_messages)

    # todo: sender_sha256 is null in server to server messages

    logger.debug2 "sender_did    = #{sender_did}"
    logger.debug2 "sender_sha256 = #{sender_sha256}"
    logger.debug2 "messages      = #{input_messages}"

    server = (sender_sha256.to_s == '')

    if !sender_did
      return { :error => 'System error in message service. Did for actual client is unknown on server.'}
    end

    # save any new messages received from client to other clients
    # todo: how to handle message from client on one server to client on an other client?
    #       pings table should include online clients on other gofreerev servers
    #       now ping.did is client did on this gofreerev server
    #       add ping.server_did? rename ping.did to ping.client_did
    did = SystemParameter.did
    old_dids = SystemParameter.old_dids
    if input_messages.class == Array
      input_messages.each do |message|
        if old_dids.index(message['receiver_did'])
          # todo: receiving rsa message with old did. Should a) return new did, b) return error, c) ask client to reconnect
          logger.debug2 "ignoring incoming message to old did #{message['receiver_did']}. message = #{message.to_json}"
          # send changed did rsa message to calling server
          next
        end
        if server and message['receiver_did'] != did
          logger.warn2 "received message for other gofreerev server #{message['receiver_did']}. message = #{message.to_json}"
        end
        m = Message.new
        m.from_did = sender_did
        m.from_sha256 = sender_sha256
        m.to_did = message['receiver_did']
        m.to_sha256 = message['receiver_sha256']
        m.server = message['server']
        m.encryption = message['encryption']
        m.key = message['key']
        m.message = message['message']
        m.save!
      end # each message
    end

    # check for any server messages to this server
    Message.where(:to_did => SystemParameter.did, :server => true).order(:created_at).each { |m| m.receive_message }

    nil
  end # self.receive_messages


  def self.send_messages (sender_did, sender_sha256)

    logger.debug2 "sender_did    = #{sender_did}"
    logger.debug2 "sender_sha256 = #{sender_sha256}"

    server = (sender_sha256.to_s == '')

    if !sender_did
      return { :error => 'System error in message service. Did for actual client is unknown on server.'}
    end

    # return any messages to client from other devices
    if server
      # todo: allow server to server allow messages to be routed through one or more gofreerev servers. receiver_did added to messages
      # todo: take into account other server pings (ingoing or outgoing) within the next server ping cycle
      # todo: select route to other gofreerev server with best encryption and shortest response time
      # todo: forwarded messages returned in an response to a gofreerev server can be deleted now (here)
      # todo: forwarded messages send in an request to an other gofreerev server can be deleted after ok response
      ms = Message.where(:to_did => sender_did, :server => true).order(:created_at)
    else
      ms = Message.where(:to_did => sender_did, :to_sha256 => sender_sha256, :server => false).order(:created_at)
    end
    output_messages = ms.collect do |m|
      hash = {:sender_did => m.from_did,
              :server => m.server,
              :encryption => m.encryption,
              :message => m.message}
      hash[:receiver_did] = m.to_did if m.to_did
      hash[:sender_sha256] = m.from_sha256 if m.from_sha256
      hash[:key] = m.key if m.key
      hash
    end
    ms.delete_all

    output_messages.size == 0 ? nil : { :messages => output_messages }
  end # self.send_messages


  # receive messages from client (or server) and messages to client (or server)
  def self.messages (sender_did, sender_sha256, input_messages)

    # todo: sender_sha256 is null in server to server messages

    logger.debug2 "sender_did    = #{sender_did}"
    logger.debug2 "sender_sha256 = #{sender_sha256}"
    logger.debug2 "messages      = #{input_messages}"

    error = Message.receive_messages(sender_did, sender_sha256, input_messages)
    return error if error
    Message.send_messages(sender_did, sender_sha256)

  end # self.messages


end
