class Message < ActiveRecord::Base

  # create_table "messages", force: true do |t|
  #   t.string   "from_did",    limit: 20,       null: false
  #   t.string   "from_sha256", limit: 45,       null: false
  #   t.string   "to_did",      limit: 20,       null: false
  #   t.string   "to_sha256",   limit: 45,       null: false
  #   t.text     "message",     limit: 16777215, null: false
  #   t.datetime "created_at"
  #   t.datetime "updated_at"
  # end

  def self.messages (sender_did, sender_sha256, input_messages)

    # todo: sender_sha256 is null in server to server messages

    logger.debug2 "sender_did = #{sender_did}"
    logger.debug2 "sender_sha256 = #{sender_sha256}"
    logger.debug2 "messages = #{input_messages}"

    if !sender_did
      return { :error => 'System error in message service. Did for actual client is unknown on server.'}
    end
    if !sender_sha256
      return { :error => 'System error in message service. Sha256 for actual client is unknown on server.'}
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

    # return any messages to client from other devices
    ms = Message.where(:to_did => sender_did, :to_sha256 => sender_sha256).order(:created_at)
    output_messages = ms.collect do |m|
      { :sender_did => m.from_did,
        :sender_sha256 => m.from_sha256,
        :encryption => m.encryption,
        :created_at_server => m.created_at.to_i,
        :message => m.message }
    end
    ms.delete_all

    output_messages.size == 0 ? nil : { :messages => output_messages }
  end

end
