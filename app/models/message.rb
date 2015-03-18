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

  def receive_message_password
    # setup password for symmetric communication
    # gofreerev.js: see GiftService.receive_message_password (client to client)
    key = OpenSSL::PKey::RSA.new SystemParameter.private_key
    message_json_rsa_enc = Base64.decode64(self.message)
    message_json = key.private_decrypt(message_json_rsa_enc, OpenSSL::PKey::RSA::PKCS1_OAEP_PADDING)
    logger.secret2 "message_json = #{message_json}"
    message = JSON.parse(message_json)

    server = Server.find_by_new_did self.from_did
    if !server
      # todo: how to handle rsa message from unknown did. Should ask gofreerev network for information
      logger.error2 "Received rsa message from unknown server #{self.from_did}"
      return
    end
    if !server.new_pubkey
      # todo: how to handle missing public key for server. Should ask other gofreerev server for public key
      logger.error2 "Received rsa message from #{server.site_url} but public key is missing"
      return
    end
    # save symmetric password part 2 received from other Gofreerev server
    server.set_new_password1 unless server.new_password1
    server.new_password2 = message[0]
    server.new_password2_at = message[1]
    server.save!
    if message.size == 3 and message[2] == server.new_password_md5
      logger.debug2 "symmetric password setup completed."
    else
      logger.debug2 "symmetric password setup in progress."
    end
    self.destroy!

    if message.size == 2 or message[2] != server.new_password_md5
      # todo: send/resend password part 1 to other server
      hash = server.create_password_message
      m = Message.new
      m.from_did = hash[:sender_did]
      m.to_did = hash[:receiver_did]
      m.server = hash[:server]
      m.encryption = hash[:encryption]
      m.message = hash[:message]
      m.save!
    end

  end # receive_message_password


  # read message for this server
  def receive_message
    logger.debug "new mail: #{self.to_json}"

    if self.encryption == 'rsa'
      # setup password for symmetric communication
      # javascript: see GiftService.receive_message_password in gofreerev.js (client to client)
      receive_message_password
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
    if input_messages.class == Array
      input_messages.each do |message|
        # todo: validate record format
        # 1) sender_sha256 and receiver_sha256 is blank in server to server messages (server=true)
        # 2) sender_sha256 and receiver_sha256 is required in client to client messages (server=false)
        # 3) allowed values for encryption is rsa, sym or mix
        # 4) key is only allowed for encryption = mix
        if server and message['receiver_did'] != SystemParameter.did
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
