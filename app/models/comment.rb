
class Comment < ActiveRecord::Base

  # create_table "comments", force: true do |t|
  #   t.string   "cid",                   null: false
  #   t.string   "sha256",     limit: 45, null: false
  #   t.datetime "created_at"
  #   t.datetime "updated_at"
  # end
  # add_index "comments", ["cid"], name: "index_comments_on_cid", unique: true, using: :btree

  # receive list with new comments from client,
  # verify user ids, generate a sha256 digests, save comments and return created_at_server boolean to client
  # sha256 digest is used as a control when replicating comments between clients
  # todo: use short internal user id (sequence) or use full user id (uid+provider) in client js comments array?
  # todo  the app should support replication comment from device a on app server 1 to device b on app server 2
  # todo  but interval user ids can not be used across two different gofreerev-lo servers
  def self.new_comments (new_comments, login_user_ids)
    # logger.debug2 "new_comments = #{new_comments}"
    # logger.debug2 "login_user_ids = #{login_user_ids}"
    msg = "Could not create comment signature on server. "
    # check params
    return if !new_comments or new_comments.size == 0 # ignore empty new comments request
    if login_user_ids.class != Array or login_user_ids.size == 0
      # system error - util/ping + Gift.new_comments should only be called with logged in users.
      return { :error => "#{msg}System error. Expected array with one or more login user ids."}
    end
    # verify user ids. should never fail. user ids are from sessions table and should be valid
    # order by user id - order is used in sha256 server signature
    login_users = User.where(:user_id => login_user_ids).order('user_id')
    if login_users.size < login_user_ids.size
      return { :error => "#{msg}System error. Invalid login. Expected #{login_user_ids.size} users. Found #{login_users.size} users."}
    end
    # logger.debug2 "login user ids = " + login_users.collect { |u| u.id }.join(', ')
    login_providers = login_users.collect { |u| u.provider }
    # logger.debug2 "login users internal ids = " + login_users.collect { |u| u.id }.join(', ')
    # check and create sha256 digest signature for the new comment(s)
    new_comments.shuffle!
    response = []
    no_errors = 0
    # new comments array has already been json schema validated to some extend
    new_comments.each do |new_comment|
      # check new_comment hash: gid, sha256 and user_ids array
      cid = new_comment['cid'].to_s
      sha256_client = new_comment['sha256'].to_s
      comment_user_ids = new_comment['user_ids'].uniq
      # logger.debug2 "cid = #{cid}, comment_user_ids = #{comment_user_ids}"

      # Could not create gift signature on server. Invalid authorization. Expected 2 users. Found 1 users
      signature_users = login_users.find_all { |u| comment_user_ids.index(u.id)}
      if signature_users.size == comment_user_ids.size
        # authorization ok. create server side sha256 digest signature
        # field are readonly and comment signature check can verify that field is not updated by client
        sha256_server_text = ([cid, sha256_client] + signature_users.collect { |u| u.user_id }).join(',')
        sha256_server = Base64.encode64(Digest::SHA256.digest(sha256_server_text))
        logger.debug2 "sha256_server = #{sha256_server}"
        c = Comment.find_by_cid(cid)
        if c
          # comment already exists - check signature
          if c.sha256 == sha256_server
            response << { :cid => cid, :created_at_server => true }
          else
            response << { :cid => cid, :created_at_server => false, :error => "#{msg}Comment exists but sha256 signature is invalid." }
            no_errors += 1
          end
          next
        end
        c = Comment.new
        c.cid = cid
        c.sha256 = sha256_server
        c.save!
        response << { :cid => cid, :created_at_server => true }
        next
      end

      # authorization error. maybe api log out on client before new comment signature was created on server.
      missing_login_user_ids = comment_user_ids - login_users.collect { |u| u.id }
      missing_login_users = User.where(:id => missing_login_user_ids)
      missing_login_providers = missing_login_users.collect { |u| u.provider }
      # logger.debug2 "missing_login_user_ids = #{missing_login_user_ids.join(', ')}"
      # logger.debug2 "missing login users = " + missing_login_users.collect { |u| u.debug_info }.join(', ')
      # split missing login users in missing login and changed login
      changed_login_providers = login_providers & missing_login_providers
      missing_login_providers = missing_login_providers - changed_login_providers
      # logger.debug2 "changed_login_providers = #{changed_login_providers.join('. ')}"
      # logger.debug2 "missing_login_providers = #{missing_login_providers.join('. ')}"
      # nice informative error message
      if (changed_login_providers.size > 0)
        response << { :cid => cid, :created_at_server => false,
                      :error => "#{msg}Log in has changed for #{changed_login_providers.join('. ')} since comment was created. Please log in with old #{changed_login_providers.join('. ')} user."}
      else
        response << { :cid => cid, :created_at_server => false,
                      :error => "#{msg}Log out for #{missing_login_providers.join('. ')} since comment was created. Please log in for #{missing_login_providers.join('. ')}."}
      end
      no_errors += 1

    end
    return { :comments => response, :no_errors => no_errors }
  end # self.new_comments



  # verify comments request from client - used when receiving new comments from other clients - check server side sha256 signature and return true or false
  # sha256 is required and must be valid
  # sha256_action and sha256_deleted are optional in request and are validated if supplied
  # client must supply sha256_action in request if comment has as new_deal_action (cancel, accept or reject) - only relevant for comments with new_deal = true
  # client must supply sha256_deleted in request if comment has been deleted
  # params:
  # - verify_comments: array - see verify_comments array in JSON_SCHEMA[:ping_request]
  # - login_user_ids: from session :user_ids array - logged in users
  # - client_sid: from ping - unique session id (one did can have multiple sids) = browser tab
  # - client_sha256: from ping - mailbox sha256 signature - changes when api provider login changes
  # ( client_sid + client_sha256 is used as unique session id when sending and receiving remote comment verifications )
  def self.verify_comments (verify_comments, login_user_ids, client_sid, client_sha256)
    logger.debug2 "verify_comments = #{verify_comments.to_json}"
    logger.debug2 "login_user_ids = #{login_user_ids.to_json}"
    if !verify_comments
      # any remote verify comment response ready for this client?
      vcs = VerifyComment.where("client_sid = ? and client_sha256 = ? and verified_at_server is not null", client_sid, client_sha256)
      return nil if vcs.size == 0
      logger.debug2 "vcs.size = #{vcs.size}"
      response = {
          :comments => vcs.collect do |vc|
            logger.debug2 "vc = #{vc.to_json}" if vc.error
            {
                :seq => vc.client_seq,
                :cid => vc.cid,
                :verified_at_server => vc.verified_at_server
            }
          end
      }
      vcs.delete_all
      return response
    end

    # cache friends for login users - giver and/or receiver for gifts must be friend of login user
    login_users = User.where(:user_id => login_user_ids).includes(:server_users)
    if login_users.size == 0 or login_users.size != login_user_ids.size
      return { :error => 'System error. Expected array with login user ids for current logged in users'}
    end
    User.cache_friend_info(login_users)
    friends = {}
    login_users.each do |u|
      friends.merge!(u.friends_hash)
    end

    # cache users (user_id's are used in server side sha256 signature)
    # cache comments (get previous server side sha256 signature and created_at timestamp)
    # cache servers (secrets for remote user sha256 signatures)
    users = {} # id => user
    comments = {} # cid => comment
    cids = []
    comments_user_ids = []
    seqs = {}
    server_ids = []
    servers = {}
    verify_comments.each do |new_comment|
      seq = new_comment["seq"]
      return { :error => 'Invalid verify comments request. Seq in comments array must be unique' } if seqs.has_key? seq
      seqs[seq] = true
      cids << new_comment["cid"]
      comments_user_ids += new_comment["user_ids"]
      server_id = new_comment['server_id']
      server_ids << server_id if server_id and !server_ids.index(server_id)
    end
    Comment.where(:cid => cids.uniq).each { |c| comments[c.cid] = c }
    User.where(:id => comments_user_ids.uniq).includes(:server_users).each { |u| users[u.id] = u }
    Server.where(:id => server_ids).each { |s| servers[s.id] = s } if server_ids.size > 0

    response = []
    server_requests = {} # server_id => array with remote commments verification request
    server_mid = {} # one mid (unique message id) for each remote server in verify comments request

    verify_comments.each do |verify_comment|
      seq = verify_comment['seq']
      server_id = verify_comment['server_id']
      cid = verify_comment['cid']

      if (server_id)
        # remote comment verification
        if seq >= 0
          logger.error2 "cid #{cid}. Invalid request. seq must be negative for remote comment verification"
          response << { :seq => seq, :cid => cid, :verified_at_server => false}
          next
        end
        if !servers.has_key? server_id
          logger.error2 "cid #{cid}. Invalid request. Unknown server id #{server_id}"
          response << { :seq => seq, :cid => cid, :verified_at_server => false}
          next
        end
      else
        # local gift verification
        if seq < 0
          logger.error2 "cid #{cid}. Invalid request. seq must be postive for local comment verification"
          response << { :seq => seq, :cid => cid, :verified_at_server => false}
          next
        end
      end

      # validate row in verify comment request
      if verify_comment["user_ids"] and verify_comment["user_ids"].size > 0
        comment_user_ids = verify_comment["user_ids"]
      else
        comment_user_ids = []
      end
      if comment_user_ids.size == 0
        logger.error2 "cid #{cid}. Invalid request. user_ids is missing."
        response << { :seq => seq, :cid => cid, :verified_at_server => false }
        next
      end
      if comment_user_ids.size != comment_user_ids.uniq.size
        logger.error2 "cid #{cid}. Invalid request. User ids in user_ids must be unique."
        response << { :seq => seq, :cid => cid, :verified_at_server => false }
        next
      end

      # check if comment exists
      if !server_id
        # local gifts verification - comment must exist
        comment = comments[cid]
        if !comment
          # comment not found -
          logger.warn2 "cid #{cid} was not found"
          response << { :seq => seq, :cid => cid, :verified_at_server => false }
          next
        end
      end

      # check mutual friends
      # todo: change to must be friend of friend to login user(s)? but that could be true on one gofreerev server and false on an other gofreerev server!
      mutual_friend = false
      user_ids = []
      user_error = false
      comment_user_ids.each do |user_id|
        if server_id and user_id < 0 # unknown remote user
          user_ids << user_id
          next
        end
        user = users[user_id]
        if user
          if server_id
            # remote comment verification
            su = user.server_users.find { |su| (su.server_id == server_id) and su.verified_at }
            if su
              # verified server user. use sha256 signature as user id and pseudo user id as fallback information (changed sha256 signature)
              user_ids.push({ :sha256 => user.calc_sha256(servers[server_id].secret),
                                    :pseudo_user_id => su.remote_pseudo_user_id,
                                    :sha256_updated_at => user.sha256_updated_at.to_i
                                  })
            else
              user_ids << -user.id # unknown remote user
            end
          else
            # local gift verification - use user id as it is
            user_ids << user.user_id
          end
          friend = friends[user.user_id]
          mutual_friend = true if friend and friend <= 2
        else
          logger.warn2 "Gid #{cid} : user with id #{user_id} was not found. Cannot check server sha256 signature for comment with unknown user ids."
          response << { :seq => seq, :cid => cid, :verified_at_server => false }
          user_error = true
          break
        end
      end
      next if user_error
      user_ids.uniq! # todo: should return an error if doublets in giver_user_ids array
      user_ids.sort! unless server_id

      if !mutual_friend
        logger.warn2 "cid #{cid} is not from a friend"
        # response << { :seq => seq, :gid => cid }
        # next
      end

      if server_id
        # remote comment verification (server to server verify comments message)
        # todo: sha256 signatures on this gofreerev server can be out of date
        #       must keep verify_comment row from client if verify comment request must be resent after updated sha256 signature (comment.user_ids)
        #       could also be used in a verify comment cache on this gofreerev server
        #       don't send identical verify comments request to other gofreerev server
        # 1) insert row in verify_comments table
        server_mid[server_id] = Sequence.next_server_mid unless server_mid.has_key?(server_id)
        vg = VerifyComment.new
        vg.client_sid = client_sid
        vg.client_sha256 = client_sha256
        vg.client_seq = seq
        vg.server_id = server_id
        vg.cid = cid
        vg.server_seq = Sequence.next_verify_comment_seq
        vg.request_mid = server_mid[server_id]
        vg.save!
        # 2) insert verify_comments request in server_requests hash
        hash = {:seq => vg.server_seq,
                :cid => cid,
                :sha256 => verify_comment["sha256"]}
        hash[:sha256_action] = verify_comment["sha256_action"] if verify_comment["sha256_action"]
        hash[:sha256_deleted] = verify_comment["sha256_deleted"] if verify_comment["sha256_deleted"]
        hash[:user_ids] = user_ids
        server_requests[server_id] = [] unless server_requests.has_key? server_id
        server_requests[server_id].push(hash)
        next
      end

      # calculate and check server side sha256 signature
      sha256_client = verify_comment["sha256"]
      sha256_input = ([cid, sha256_client] + user_ids).join(',')
      sha256_calc = Base64.encode64(Digest::SHA256.digest(sha256_input))
      logger.debug "sha256 check failed. sha256_input = #{sha256_input}, sha256_calc = #{sha256_calc}, comment.sha256 = #{comment.sha256}" unless comment.sha256 == sha256_calc

      # sha256_action: if supplied - calculate and check server side sha256_action signature
      # old server sha256_action signature was generated when new_deal propocal was cancelled, accepted or rejected
      # calculate and check sha256_action signature from information received in verify comments request
      sha256_action_client = verify_comment["sha256_action"]
      if sha256_action_client
        if !comment.sha256_action
          logger.warn2 "Comment #{cid}. Verify comment request failed. sha256_action in request but comment does not have a sha256_action signature on server."
          response << { :seq => seq, :cid => cid, :verified_at_server => false }
          next
        end
        sha256_input = ([cid, sha256_action_client] + user_ids).join(',')
        sha256_calc = Base64.encode64(Digest::SHA256.digest(sha256_input))
        if comment.sha256_action != sha256_calc
          logger.warn2 "Comment #{cid}. Verify comment request failed. new sha256_action calculation = #{sha256_calc}. old sha256_action on server = #{comment.sha256_action}."
          response << { :seq => seq, :cid => cid, :verified_at_server => false }
          next
        end
      end

      # sha256_deleted: if supplied - calculate and check server side sha256_deleted signature
      # old server sha256_deleted signature was generated when comment previously was deleted
      # calculate and check sha256_deleted signature from information received in verify comments request
      sha256_deleted_client = verify_comment["sha256_deleted"]
      if sha256_deleted_client
        if !comment.sha256_deleted
          logger.warn2 "Comment #{cid}. Verify comment request failed. sha256_deleted in request but comment dont have a sha256_deleted signature on server."
          response << { :seq => seq, :cid => cid, :verified_at_server => false }
          next
        end
        sha256_input = ([cid, sha256_deleted_client] + user_ids).join(',')
        sha256_calc = Base64.encode64(Digest::SHA256.digest(sha256_input))
        if comment.sha256_deleted != sha256_calc
          logger.warn2 "Comment #{cid}. Verify comment request failed. new sha256_deleted calculation = #{sha256_calc}. old sha256_deleted on server = #{comment.sha256_deleted}."
          response << { :seq => seq, :cid => cid, :verified_at_server => false }
        end
      end

      # no errors
      response << { :seq => seq, :cid => cid, :verified_at_server => true }

    end # each new_gift

    # any remote verify gift response ready for this client?
    vcs = VerifyComment.where("client_sid = ? and client_sha256 = ? and verified_at_server is not null", client_sid, client_sha256)
    if vcs.size > 0
      logger.debug2 "vcs.size = #{vcs.size}"
      vcs.each do |vc|
        logger.debug2 "vc = #{vc.to_json}" if vc.error
        response.push({
                          :seq => vc.client_seq,
                          :cid => vc.cid,
                          :verified_at_server => vc.verified_at_server
                      })

      end
      vcs.delete_all
    end

    logger.debug2 "response = #{response}"
    logger.debug2 "server_requests = #{server_requests}"

    # send any server to server verify comments messages
    server_requests.each do |server_id, server_request|
      # translate login user uds to sha256 signatures (verified server users) or negative user ids (unknown users)
      login_user_ids = []
      login_users.each do |login_user|
        su = login_user.server_users.find { |su2| ((su2.server_id == server_id) and su2.verified_at) }
        if su
          # verified server user - use sha256 signature as user id and pseudo user id as fallback information (changed sha256 signature)
          login_user_ids.push({ :sha256 => login_user.calc_sha256(servers[server_id].secret),
                                :pseudo_user_id => su.remote_pseudo_user_id,
                                :sha256_updated_at => login_user.sha256_updated_at.to_i
                              })
        else
          # unknown login user - use negative user id
          login_user_ids.push(-login_user.id)
        end
      end
      message = {
          :msgtype => 'verify_comments',
          :mid => server_mid[server_id],
          :login_users => login_user_ids,
          :verify_comments => server_request }
      logger.debug2 "verify_comments message = #{message}"
      # validate json message before sending
      json_schema = :verify_comments_request
      if !JSON_SCHEMA.has_key? json_schema
        return { :error => "Could not validate verify_comments server to server message. JSON schema definition #{json_schema.to_s} was not found." }
      end
      json_errors = JSON::Validator.fully_validate(JSON_SCHEMA[json_schema], message)
      if json_errors.size > 0
        logger.error2 "Failed to sent comments to remote verification. Error in #{json_schema}"
        logger.error2 "message = #{message}"
        logger.error2 "json_schema = #{JSON_SCHEMA[json_schema]}"
        logger.error2 "errors = #{json_errors.join(', ')}"
        return { :error => "Failed to create verify_comments server to server message: #{json_errors.join(', ')}" }
      end
      # save server to server message - will be sent in next server to server ping
      sym_enc_message = message.to_json.encrypt(:symmetric, :password => servers[server_id].new_password)
      sym_enc_message = Base64.encode64(sym_enc_message)
      m = Message.new
      m.from_did = SystemParameter.did
      m.to_did = servers[server_id].new_did
      m.server = true
      m.mid = server_mid[server_id]
      m.encryption = 'sym'
      m.message = sym_enc_message
      m.save!
    end # each server_id, server_request

    response.size == 0 ? nil : { :gifts => response }

  end # self.verify_comments


end # Comment
