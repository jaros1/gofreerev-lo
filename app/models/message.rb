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

  # read message for this server
  def read_message
    logger.debug "new mail: #{self.to_json}"
  end


  def self.messages (sender_did, sender_sha256, input_messages)

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
    Message.where(:to_did => SystemParameter.did).order(:created_at).each { |m| m.read_message }

    # return any messages to client from other devices
    if server
      # todo: allow server to server allow messages to be routed through one or more gofreerev servers
      # todo: select route to other gofreerev server with best encryption and best response time
      # todo: take into account other server pings (ingoing or outgoing) within the next server ping cycle
      # todo: forwarded messages returned in an response can be deleted - here - called be an other Gofreerev server
      # todo: forwarded messages send to an other gofreerev server can be deleted after do response from other Gofreerev server
      ms = Message.where(:to_did => sender_did).order(:created_at)
    else
      ms = Message.where(:to_did => sender_did, :to_sha256 => sender_sha256).order(:created_at)
    end
    output_messages = ms.collect do |m|
      { :sender_did => m.from_did,
        :sender_sha256 => m.from_sha256,
        :encryption => m.encryption,
        :created_at_server => m.created_at.to_i,
        :message => m.message }
    end
    ms.delete_all

    output_messages.size == 0 ? nil : { :messages => output_messages }
  end # self.messages


end
