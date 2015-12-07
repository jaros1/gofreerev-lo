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


  belongs_to :from_pubkey, :class_name => 'Pubkey', :foreign_key => :from_did, :primary_key => :did
  belongs_to :to_pubkey, :class_name => 'Pubkey', :foreign_key => :to_did, :primary_key => :did


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

  # 5) server - true: server to server communication - false: client to client communication
  validates_inclusion_of :server, :in => [true, false]

  # 6) key - optional rsa encrypted password
  # 7) message - optional symmetric encrypted message
  # three encryption models:
  # 1) key only - exchange symmetric encrypted password between two Gofreerev servers - less secure - identical encryption for identical messages
  # 2) message only - symmetric encrypted message using symmetric password from 1 - less secure - identical encryption for identical messages
  # 3) key and message - rsa encrypted random password and message symmetric encrypted with this random password - more secure - different encryption for identical messages

  # 8) timestamps

  # keep_message boolean. Normally messages are deleted when read/received
  # used for verify_gifts message if verify gift request is waiting for local user info update (changed sha256 signature)
  attr_accessor :keep_message


  # read message for this server
  # is_client:
  # - true - client side of communication - called from Server.ping
  # - false - server side of communication - called from util_controller.ping via Message.receive_messages
  # pseudo_user_ids:
  # - only relevant for client==true. called from Server.ping
  #   hash with user ids in outgoing users message
  #   user ids must be in response to outgoing users message
  #   only relevant for direct server to server user compare
  #   not relevant in forwarded users messages
  # received_msgtype:
  # - only relevant for client=false. mark when server has made a respond for a msgtype
  def receive_message (is_client, pseudo_user_ids, received_msgtype)
    logger.debug "new mail: #{self.to_json}"

    # find password in mix encrypted message. mix encryption. rsa encrypted random password in key and message encrypted with this random password
    server = Server.find_by_new_did(self.from_did)
    logger.debug2 "received mix encrypted message"
    private_key = OpenSSL::PKey::RSA.new SystemParameter.private_key
    password_rsa_enc = Base64.decode64(self.key)
    password = private_key.private_decrypt(password_rsa_enc, OpenSSL::PKey::RSA::PKCS1_OAEP_PADDING)
    logger.secret2 "password = #{password}"

    # decrypt message
    message_json_enc_base64 = self.message
    message_json_enc = Base64.decode64(message_json_enc_base64)
    message_json = message_json_enc.decrypt(:symmetric, :password => password)

    logger.secret2 "message_json = #{message_json}"
    message = JSON.parse(message_json)

    if message['msgtype'] == 'users'
      return "Cannot receive users message. Server secret was not found. Server secret should have been received in login request" if !server.secret
      error = server.receive_compare_users_message(message['users'], is_client, pseudo_user_ids, received_msgtype) # false: server side of communication
      return error ? error : nil
    end

    if message['msgtype'] == 'online'
      error = server.receive_online_users_message(message['users'], is_client, received_msgtype) # false: server side of communication
      return error ? error : nil
    end

    if message['msgtype'] == 'sha256'
      error = server.receive_sha256_changed_message(message['seq'], message['users'])
      return error ? error : nil
    end

    if message['msgtype'] == 'pubkeys'
      error = server.receive_public_keys_message(message['users'], is_client, received_msgtype) # false: server side of communication
      return error ? error : nil
    end

    if message['msgtype'] == 'client'
      error = server.receive_client_messages(message['messages'], is_client, received_msgtype) # false: server side of communication
      return error ? error : nil
    end

    if message['msgtype'] == 'verify_gifts'
      error, self.keep_message = server.receive_verify_gifts_message(message)
      return error ? error : nil
    end

    if message['msgtype'] == 'verify_comments'
      error, self.keep_message = server.receive_verify_comments_msg(message)
      return error ? error : nil
    end

    logger.error2 "mstype #{message["msgtype"]} not implemented"

    return nil

  end # receive_message


  # receive messages from client ()
  # params:
  # - is_client:
  #   - true - client side of communication - called from Server.ping
  #   - false - server side of communication - called from util_controller.ping via Message.receive_messages
  # - sender_did      :
  # - sender_sha256   :
  # - pseudo_user_ids : hash with user ids from outgoing users message (only client==true).
  #                     users must be included in response to outgoing users message
  #                     only relevant for direct server to server user compare
  #                     not relevant in forwarded user messages
  # - input_messages: : client=false: input messages are client messages
  #                     client=true: input messages are server messages
  def self.receive_messages (is_client, sender_did, sender_sha256, pseudo_user_ids, input_messages)

    # todo: sender_sha256 is null in server to server messages

    logger.debug2 "sender_did    = #{sender_did}"
    logger.debug2 "sender_sha256 = #{sender_sha256}"
    logger.debug2 "messages      = #{input_messages}"
    is_server_msg = (sender_sha256.to_s == '')
    logger.debug2 "is_client     = #{is_client}"
    logger.debug2 "is_server_msg = #{is_server_msg}"

    return 'System error in message service. Did for actual client is unknown on server.' unless sender_did

    # save any new messages received from client to other clients
    # todo: how to handle message from client on one server to client on an other client?
    #       pings table should include online clients on other gofreerev servers
    #       now ping.did is client did on this gofreerev server
    #       add ping.server_did? rename ping.did to ping.client_did
    did = SystemParameter.did
    old_dids = SystemParameter.old_dids
    logger.debug2 "did = #{did}, old_dids = #{old_dids.join(', ')}"
    if input_messages.class == Array
      input_messages.each do |message|

        # sender_did is used in server and only in server to server messages
        if message['sender_did']
          # server to server message. check if incoming message has been forwarded from an other Gofreerev server
          if !is_server_msg
            return 'System error in new message request. :sender_did must be blank in client messages. :sender_did is only used in server to server messages.'
          end
          if message['sender_did'] != sender_did
            logger.warn2 "received message forwarded from an other Gofreerev server. Sent from #{message['sender_did']} and forwarded by #{sender_did}."
            logger.secret2 "message = #{message.to_json}"
            # todo: check that message['sender_did'] exists. Should not receive forwarded messages from unknown servers
            # todo: forwarding a message should being with message['sender_did'] == sender_did for first receiving Gofreerev server
            # todo: add signature and check signature when forwarding messages
            # todo: how to prevent fake message['sender_did'] from being used be a Gofreerev server. add signature and signature check for forwards
            raise "not implemented"
          end
        end
        if is_server_msg and !message['sender_did']
          return 'System error in new message request. :sender_did is required in server to server messages.'
        end

        if old_dids.index(message['receiver_did'])
          # todo: receiving message with old did. Should a) return new did, b) return error, c) ask client to reconnect
          # todo: add mid to message and return mid in changed did message. calling server should resend message with correct did
          logger.debug2 "ignoring incoming message to old did #{message['receiver_did']}. message = #{message.to_json}"
          # send did changed rsa message to calling server. format [2, old_did, new_did]
          s = Server.find_by_new_did(message['sender_did'] || sender_did)
          raise "Unknown server #{message['sender_did'] || sender_did}" unless s
          m = Message.new
          m.from_did = did
          m.to_did = s.new_did
          m.server = true
          # todo: receive rsa rename did message not implemented
          key_str = [2, message['receiver_did'], did].join(',')
          logger.debug2 "key_str.size = #{key_str.size}"
          public_key = OpenSSL::PKey::RSA.new s.new_pubkey
          key_str_rsa_enc = Base64.encode64(public_key.public_encrypt(key_str, OpenSSL::PKey::RSA::PKCS1_OAEP_PADDING))
          logger.debug2 "key_str_rsa_enc = #{key_str_rsa_enc}"
          m.key = key_str_rsa_enc
          m.save!
          next
        end

        if is_server_msg and message['receiver_did'] != did
          logger.warn2 "received message to be forwarded to gofreerev server #{message['receiver_did']}. message = #{message.to_json}"
        end

        if message['server'] != is_server_msg
          logger.debug2 "is_server_msg = #{is_server_msg}, message['server'] = #{message['server']}"
          if is_server_msg
            return 'System error in new message request. Expected server message. Received client message'
          else
            return 'System error in new message request. Expected client message. Received server message'
          end
        end

        m = Message.new
        m.from_did = message['sender_did'] || sender_did
        m.from_sha256 = sender_sha256
        m.to_did = message['receiver_did']
        m.to_sha256 = message['receiver_sha256']
        m.server = message['server']
        m.key = message['key'] if message['key']
        m.message = message['message'] if message['message']
        m.save!
      end # each message
    end
    return nil unless is_server_msg

    # check for any messages to this server

    # flags for received message types (:users, :online, :pubkeys, :client)
    # server must respond make one and only one response for each message type
    received_msgtype = {}

    # debug info
    logger.debug2 "find relevant messages"
    logger.debug2 "is_client           = #{is_client}"
    logger.debug2 "is_server_msg       = #{is_server_msg}"
    logger.debug2 "received_msgtype    = #{received_msgtype.to_json}"
    logger.debug2 "SystemParameter.did = #{SystemParameter.did}"
    logger.debug2 "sender_did          = #{sender_did}"

    errors = []
    Message.where(:to_did => SystemParameter.did, :server => true).order(:created_at).each do |m|
      error = m.receive_message(is_client, pseudo_user_ids, received_msgtype)
      m.destroy! unless m.keep_message
      errors << error if error
    end

    return (errors.size == 0 ? nil : errors.join(', ')) unless is_server_msg # exit if called from browser client

    # call from other gofreerev server

    # check for any ingoing server messages with changed user sha256 signature.
    # must sent either changed sha256 signature to other gofreerev server (here)
    # or update user information on this gofreerev server (client ping)
    server_users = ServerUser.where(
        'verified_at is not null and remote_pseudo_user_id is not null and remote_sha256_updated_at is not null ' +
            'and ( sha256_message_sent_at is null or sha256_message_sent_at < ? )', 2.minutes.ago)
    Server.save_sha256_changed_message(4, server_users) if server_users.size > 0

    # check response for each message types. server must check and return any response for each message type
    logger.debug2 "received_msgtype (1) = #{received_msgtype}"
    server = Server.find_by_new_did(sender_did)
    if !received_msgtype[:users]
      # no ingoing compare users message. check for outgoing users message
      if server.secret
        error = server.receive_compare_users_message([], is_client, pseudo_user_ids, received_msgtype) # false: server side of communication
      else
        error = "Cannot receive users message. Server secret was not found. Server secret should have been received in login request"
      end
      errors << error if error
    end
    if !received_msgtype[:online]
      # no ingoing online users message. check for outgoing online users message
      error = server.receive_online_users_message([], is_client, received_msgtype) # false: server side of communication
      errors << error if error
    end
    if !received_msgtype[:pubkeys]
      # no ingoing public keys message. check for outgoing public keys message
      error = server.receive_public_keys_message([], is_client, received_msgtype) # false: server side of communication
      errors << error if error
    end
    if !received_msgtype[:client]
      # no ingoing client messages. check for outgoing client messages
      error = server.receive_client_messages([], is_client, received_msgtype) # false: server side of communication
      errors << error if error
    end
    logger.debug2 "received_msgtype (2) = #{received_msgtype}"

    (errors.size == 0 ? nil : errors.join(', '))

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
      ms = Message.where(:to_did => sender_did, :to_sha256 => sender_sha256, :server => false).order('created_at')
      # sort. rsa encrypted message (symmetric password setup) before other encryptions
      ms = ms.sort do |a,b|
        if a.created_at != b.created_at
          a.created_at <=> b.created_at
        elsif !a.message and b.message
          -1
        elsif a.message and !b.message
          1
        else
          0
        end
      end # sort
    end
    output_messages = ms.collect do |m|
      hash = {:sender_did => m.from_did, :server => m.server}
      hash[:receiver_did] = m.to_did if m.to_did
      hash[:sender_sha256] = m.from_sha256 if m.from_sha256
      hash[:key] = m.key if m.key
      hash[:message] = m.message if m.message
      m.destroy
      hash
    end

    output_messages.size == 0 ? nil : { :messages => output_messages }
  end # self.send_messages


  # receive messages from client and return messages to client (or server)
  # used in /util/ping from browser clients. Not used in server to server communication
  # params:
  # - sender_did: did from calling client
  # - sender_sha256: sha256 signature for calling client (only user in client to client communication)
  # - input_messages: array with messages from calling client
  def self.messages (sender_did, sender_sha256, input_messages)

    # todo: sender_sha256 is null in server to server messages

    logger.debug2 "sender_did    = #{sender_did}"
    logger.debug2 "sender_sha256 = #{sender_sha256}"
    logger.debug2 "messages      = #{input_messages}"

    # todo: Move sending part from receive_compare_users_message, receive_online_users_message, receive_public_keys_message and receive_client_messages
    # must compare users even if no compare users request from calling server
    # must send online users message even if no online users request from calling server
    # must send public keys even if no public keys request from calling server
    # must send client messages even if no client messages from calling server

    # client==false - called from server (util_controller.ping)
    request_users = [] # dummy array. only relevant when receive_messages is called from Server.ping
    # client=false: called from util_controller.ping. received messages are client messages
    request_error = Message.receive_messages(false, sender_did, sender_sha256, request_users, input_messages)
    logger.error2 "request_error = #{request_error}" if request_error
    output_messages = Message.send_messages(sender_did, sender_sha256)
    logger.debug2 "output_messages = #{output_messages}"
    [request_error, output_messages]
  end # self.messages


end
