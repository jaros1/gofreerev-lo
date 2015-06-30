
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
      # any remote comment response ready for this client?
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

    # cache friends for login users - giver and/or receiver for gifts must be friend of login user - with some few exceptions
    login_users = User.where(:user_id => login_user_ids).includes(:server_users)
    if login_users.size == 0 or login_users.size != login_user_ids.size
      return { :error => 'System error. Expected array with login user ids for current logged in users'}
    end
    login_providers = login_users.collect { |u| u.provider }
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
      comments_user_ids += new_comment["new_deal_action_by_user_ids"] if new_comment["new_deal_action_by_user_ids"]
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
      comment_server_id = verify_comment['server_id']
      cid = verify_comment['cid']
      action = verify_comment['action']

      # validate row in verify comment request

      if comment_server_id
        # remote comment action
        if seq >= 0
          logger.error2 "cid #{cid}. Invalid request. seq must be negative for remote comment actions"
          response << { :seq => seq, :cid => cid, :verified_at_server => false}
          next
        end
        if action == 'create'
          logger.error2 "cid #{cid}. Invalid request. create comment on other Gofreerev server is not allowed. server id = #{comment_server_id}"
          response << { :seq => seq, :cid => cid, :verified_at_server => false}
          next
        end
        if !servers.has_key? comment_server_id
          logger.error2 "cid #{cid}. Invalid request. Unknown server id #{comment_server_id}"
          response << { :seq => seq, :cid => cid, :verified_at_server => false}
          next
        end
      else
        # local comment action
        if seq < 0
          logger.error2 "cid #{cid}. Invalid request. seq must be postive for local comment actions"
          response << { :seq => seq, :cid => cid, :verified_at_server => false}
          next
        end
      end

      # read user_ids + check doublets
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

      # read new_deal_action_by_user_ids and check doublets
      if verify_comment["new_deal_action_by_user_ids"] and verify_comment["new_deal_action_by_user_ids"].size > 0
        new_deal_action_by_user_ids1 = verify_comment["new_deal_action_by_user_ids"]
      else
        new_deal_action_by_user_ids1 = []
      end
      if new_deal_action_by_user_ids1.size != new_deal_action_by_user_ids1.uniq.size
        logger.error2 "cid #{cid}. Invalid request. User ids in new_deal_action_by_user_ids must be unique."
        response << { :seq => seq, :cid => cid, :verified_at_server => false }
        next
      end
      # consistency check (action, sha256_action and new_deal_action_by_user_ids)
      b1_new_deal_action = %w(cancel accept reject).index(action) ? true : false
      b2_sha256_action = verify_comment["sha256_action"].to_s != '' ? true : false
      b3_new_deal_action_by_user_ids = new_deal_action_by_user_ids1.size > 0 ? true : false
      if b1_new_deal_action
        # cancel, accept or reject new deal proposal - sha256_action and new_deal_action_by_user_ids are required
        if !b2_sha256_action
          logger.error2 "cid #{cid}. Invalid request. sha256_action is missing for #{action} new deal proposal"
          response << { :seq => seq, :cid => cid, :verified_at_server => false }
          next
        elsif !b3_new_deal_action_by_user_ids
          logger.error2 "cid #{cid}. Invalid request. new_deal_action_by_user_ids is missing for #{action} new deal proposal"
          response << { :seq => seq, :cid => cid, :verified_at_server => false }
          next
        end
      elsif action == 'create'
        # create new comment. sha256_action and new_deal_action_by_user_id are not allowed
        if b2_sha256_action
          logger.error2 "cid #{cid}. Invalid request. sha256_action is not allowed for create new comment"
          response << { :seq => seq, :cid => cid, :verified_at_server => false }
          next
        end
        if b3_new_deal_action_by_user_ids
          logger.error2 "cid #{cid}. Invalid request. new_deal_action_by_user_ids is not allowed for create new comment"
          response << { :seq => seq, :cid => cid, :verified_at_server => false }
          next
        end
      elsif b2_sha256_action != b3_new_deal_action_by_user_ids
        # verify and delete. optional sha256_action and new_deal_action_by_user_id
        if b2_sha256_action
          logger.error2 "cid #{cid}. Invalid request. sha256_action without new_deal_action_by_user_ids is not allowed. #{action} comment request"
        else
          logger.error2 "cid #{cid}. Invalid request. new_deal_action_by_user_ids without sha256_action is not allowed. #{action} comment request"
        end
        response << { :seq => seq, :cid => cid, :verified_at_server => false }
        next
      end

      # sha256_deleted
      # - optional for verify
      # - not allowed for create new comment and cancel, accept, reject new deal proposal
      # - required for delete comment
      if %w(create cancel accept reject).index(action) and verify_comment['sha256_deleted'].to_s != ''
        logger.error2 "cid #{cid}. Invalid request. sha256_deleted is not allowed for action #{action}"
        response << { :seq => seq, :cid => cid, :verified_at_server => false }
        next
      end
      if action == 'delete' and verify_comment['sha256_deleted'].to_s == ''
        logger.error2 "cid #{cid}. Invalid request. sha256_deleted is required for action delete"
        response << { :seq => seq, :cid => cid, :verified_at_server => false }
        next
      end

      # check if comment exists (local only)
      if !comment_server_id
        # local comment action
        comment = comments[cid]
        if action == 'create'
          if comment
            logger.warn2 "cid #{cid} already exists"
            response << { :seq => seq, :cid => cid, :verified_at_server => false }
            next
          end
        else
          if !comment
            logger.warn2 "cid #{cid} was not found"
            response << { :seq => seq, :cid => cid, :verified_at_server => false }
            next
          end
        end
      end

      # prepare comment user ids (sha256 user signatures are used instead of user ids when communication with other Gofreerev servers)
      user_ids = []
      user_error = false
      comment_and_login_user_ids = []
      comment_user_ids.each do |user_id|
        if comment_server_id and user_id < 0 # unknown remote user - used negative user id as it is
          user_ids << user_id
          next
        end
        user = users[user_id]
        if user
          if comment_server_id
            # remote comment verification
            su = user.server_users.find { |su| (su.server_id == comment_server_id) and su.verified_at }
            if su
              # verified server user. use sha256 signature as user id and pseudo user id as fallback information (changed sha256 signature)
              user_ids.push({ :sha256 => user.calc_sha256(servers[comment_server_id].secret),
                                    :pseudo_user_id => su.remote_pseudo_user_id,
                                    :sha256_updated_at => user.sha256_updated_at.to_i
                                  })
            else
              user_ids << -user.id # unknown remote user
            end
          else
            # local comment verification - use user id as it is
            user_ids << user.user_id
          end
          friend = friends[user.user_id]
          comment_and_login_user_ids << user.user_id if friend == 1 # comment user = login user. used in create, cancel & delete authorization check
        else
          logger.warn2 "Cid #{cid} : user with id #{user_id} was not found. Cannot check server sha256 signature for comment with unknown user ids."
          response << { :seq => seq, :cid => cid, :verified_at_server => false }
          user_error = true
          break
        end
      end
      next if user_error
      user_ids.uniq! # todo: should return an error if doublets in giver_user_ids array
      user_ids.sort! unless comment_server_id

      # user_ids - authorization check
      # - create: login user ids and comment user ids must be identical - create only allowed for local comments
      # - verify: no restrictions. normally comment from a friend or from a friend of a friend but with some few exceptions
      # - cancel: minimum one shared login user ids and comment user ids.
      # - accept: gift hash is required - login users must be creators of gift (minimum one user)
      # - reject: gift hash is required - login users must be creators of gift (minimum one user)
      # - delete: gift hash is required if not one shared login user ids and comment user ids ()
      case action
        when 'create'
          # create: login user ids and comment user ids must be identical - create only allowed for local comments
          gift_hash_required = false
          # local create comment action. login users must also be comment users
          if comment_user_ids != comment_and_login_user_ids
            # authorization error. write nice error message in log. maybe api log out on client before new comment signature was created on server.
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
              logger.debug2 "Could not create comment signature on server. Cid #{cid}. Log in has changed for #{changed_login_providers.join('. ')} since comment was created. Please log in with old #{changed_login_providers.join('. ')} user."
            else
              logger.debug2 "Could not create comment signature on server. Cid #{cid}. Log out for #{missing_login_providers.join('. ')} since comment was created. Please log in for #{missing_login_providers.join('. ')}."
            end
            response << { :seq => seq, :cid => cid, :verified_at_server => false }
            next
          end
        when 'verify'
          # verify: no restrictions. normally comment from a friend or from a friend of a friend but with some few exceptions
          # but clients will only replicate gifts with mutual friends and that should be sufficient security
          gift_hash_required = false
        when 'cancel'
          # cancel: minimum one shared login user ids and comment user ids.
          # todo: remote cancel. security check on both servers (sending/this and receiving/remote server) or only on receiving/remote server?
          gift_hash_required = false
          if comment_and_login_user_ids.length == 0
            # login changed between client cancel new deal proposal and server request (maybe offline client)
            # todo: better error message. See error messages in create.
            logger.debug2 "Could not cancel new deal proposal. Cid #{cid}. No login users was found for comment"
            response << { :seq => seq, :cid => cid, :verified_at_server => false }
            next
          end
        when 'accept'
          # accept: gift hash is required - login users must be creators of gift (minimum one user)
          gift_hash_required = true
        when 'reject'
          # reject: gift hash is required - login users must be creators of gift (minimum one user)
          gift_hash_required = true
        when 'delete'
          # delete: gift hash is required if not one shared login user ids and comment user ids ()
          # todo: remote delete. security check on both servers (sending/this and receiving/remote server) or only on receiving/remote server?
          gift_hash_required = (comment_and_login_user_ids.length == 0)
      end # case
      logger.debug2 "cid = #{cid}, action = #{action}, gift_hash_required = #{gift_hash_required}"

      # prepare new_deal_action_by_user_ids (sha256 user signatures are used instead of user ids when communication with other Gofreerev servers).
      # only used for comments with comment.new_deal = true and action = verify comment or cancel, accept or reject new deal proposal
      # new_deal_action_by_user_ids must be a subset of login user ids (except verify)
      # new_deal_action_by_user_ids must also be:
      # - verify: no restrictions (client side security - gifts are replicated only between mutual friends)
      # - cancel: a subset of comment creators
      # - accept: a subset of gift creators - see required gifts hash
      # - reject: a subset of gift creators - see required gifts hash
      new_deal_action_by_user_ids2 = []
      new_deal_and_login_user_ids = []
      user_error = false
      new_deal_action_by_user_ids1.each do |user_id|
        if comment_server_id and user_id < 0 # unknown remote user - used negative user id as it is
          new_deal_action_by_user_ids2 << user_id
          next
        end
        user = users[user_id]
        if user
          if comment_server_id
            # remote comment verification
            su = user.server_users.find { |su| (su.server_id == comment_server_id) and su.verified_at }
            if su
              # verified server user. use sha256 signature as user id and pseudo user id as fallback information (changed sha256 signature)
              new_deal_action_by_user_ids2.push({ :sha256 => user.calc_sha256(servers[comment_server_id].secret),
                              :pseudo_user_id => su.remote_pseudo_user_id,
                              :sha256_updated_at => user.sha256_updated_at.to_i
                            })
            else
              new_deal_action_by_user_ids2 << -user.id # unknown remote user
            end
          else
            # local comment verification - use user id as it is
            new_deal_action_by_user_ids2 << user.user_id
          end
          friend = friends[user.user_id]
          new_deal_and_login_user_ids << user.user_id if friend == 1 # new deal action by user = login user. used in authorization check
        else
          logger.warn2 "Cid #{cid} : user with id #{user_id} was not found. Cannot check server sha256 signature for comment with unknown new_deal_action_user_ids."
          response << { :seq => seq, :cid => cid, :verified_at_server => false }
          user_error = true
          break
        end
      end
      next if user_error
      new_deal_action_by_user_ids2.uniq! # todo: should return an error if doublets in giver_user_ids array
      new_deal_action_by_user_ids2.sort! unless comment_server_id

      # todo: read gift hash - required for server side authorization check some actions (accept, reject and delete if comment is deleted by giver or receiver of gift)
      # also used in new_deal_action_by_user_ids - authorization check
      if gift_hash_required and verify_comment['gift'].to_s == ''
        logger.debug2 "Cid #{cid}. Invalid request. Gift hash is missing. Required for accept, reject and comment deleted by giver or receiver of gift. Action was #{action}"
        response << { :seq => seq, :cid => cid, :verified_at_server => false }
        next
      end
      if !gift_hash_required and verify_comment['gift'].to_s != ''
        # gift hash is required for this comment/action.
        # can occur after page load where verify_comments_request is sent to server before friend list has been downloaded in /util/do_tasks
        logger.debug "Cid #{cid}. Warning. Gift hash is ignored. Only required for accept, reject and comment deleted by giver or receiver of gift. Action was #{action}"
      end
      if gift_hash_required
        # section from Gift.verify gifts. prepare giver_user_ids and receiver_user_ids for cross server communication. check gift.sha256 and find creator of gift.
        verify_gift = verify_comment['gift']
        gift_server_id = verify_gift['server_id']
        if gift_server_id and !servers.has_key? gift_server_id
          logger.error2 "cid #{cid}. Invalid request. Unknown gift.server_id #{gift_server_id}"
          response << { :seq => seq, :cid => cid, :verified_at_server => false}
          next
        end
        gid = verify_gift['gid']

        # validate row in verify gift request
        if verify_gift["giver_user_ids"] and verify_gift["giver_user_ids"].size > 0
          giver_user_ids = verify_gift["giver_user_ids"].uniq
        else
          giver_user_ids = []
        end
        if verify_gift["receiver_user_ids"] and verify_gift["receiver_user_ids"].size > 0
          receiver_user_ids = verify_gift["receiver_user_ids"].uniq
        else
          receiver_user_ids = []
        end
        if giver_user_ids.size == 0 and receiver_user_ids.size == 0
          logger.error2 "cid #{cid}. Invalid request. Gift giver user ids and gift receiver user ids are missing."
          response << { :seq => seq, :cid => cid, :verified_at_server => false}
          next
        end
        if giver_user_ids.size != giver_user_ids.uniq.size
          logger.error2 "cid #{cid}. Invalid request. User ids in gift giver user ids list must be unique."
          response << { :seq => seq, :cid => cid, :verified_at_server => false}
          next
        end
        if receiver_user_ids.size != receiver_user_ids.uniq.size
          logger.error2 "cid #{cid}. Invalid request. User ids in gift receiver user ids list must be unique"
          response << { :seq => seq, :cid => cid, :verified_at_server => false}
          next
        end

        # check if gift exists - only if gift is on this Gofreerev server
        if !gift_server_id
          # local gifts verification - gift must exist
          gift = gifts[gid]
          if !gift
            # gift not found -
            # todo: how to implement cross server gift sha256 signature validation?
            logger.warn2 "cid #{cid}. gift #{gid} was not found"
            response << { :seq => seq, :cid => cid, :verified_at_server => false }
            next
          end
        end

        # read and prepare giver_user_ids and receiver_user_ids (sha256 user signatures are used instead of user ids when communication with other Gofreerev servers)
        # gift hash used for accept, reject and some deletes
        # - accept and reject: compare gift creator and login users (remote partial validation - local full validation)
        # - delete gift: compare gift gift givers and gift receives with login users (validated remote and local)

        # check if giver or receiver is login user. required but not sufficient for accept and reject. required and sufficient for delete gift
        giver_receiver_is_login_user = false
        giver_user_ids = []
        giver_error = false
        verify_gift["giver_user_ids"].each do |user_id|
          if server_id and user_id < 0 # unknown remote user
            giver_user_ids << user_id
            next
          end
          giver = users[user_id]
          if giver
            if server_id
              # remote gift verification
              su = giver.server_users.find { |su| (su.server_id == server_id) and su.verified_at }
              if su
                # verified server user. use sha256 signature as user id and pseudo user id as fallback information (changed sha256 signature)
                giver_user_ids.push({ :sha256 => giver.calc_sha256(servers[server_id].secret),
                                      :pseudo_user_id => su.remote_pseudo_user_id,
                                      :sha256_updated_at => giver.sha256_updated_at.to_i
                                    })
              else
                giver_user_ids << -giver.id # unknown giver
              end
            else
              # local gift verification
              giver_user_ids << giver.user_id
            end
            friend = friends[giver.user_id]
            giver_receiver_is_login_user = true if friend == 1
          else
            logger.warn2 "Cid #{cid} : Gift giver user with id #{user_id} was not found. Cannot check server sha256 signature for gift with unknown user ids."
            response << { :seq => seq, :cid => cid, :verified_at_server => false }
            giver_error = true
            break
          end
        end if verify_gift["giver_user_ids"]
        next if giver_error
        giver_user_ids.uniq! # todo: should return an error if doublets in giver_user_ids array
        giver_user_ids.sort! unless server_id

        receiver_user_ids = []
        receiver_error = false
        verify_gift["receiver_user_ids"].each do |user_id|
          if server_id and user_id < 0
            # unknown remote user
            receiver_user_ids << user_id
            next
          end
          receiver = users[user_id]
          if receiver
            if server_id
              # remote gift verification
              su = receiver.server_users.find { |su| (su.server_id == server_id) and su.verified_at }
              if su
                # verified server user. use sha256 signature as user id and pseudo user id as fallback information (changed sha256 signature)
                receiver_user_ids.push({ :sha256 => receiver.calc_sha256(servers[server_id].secret),
                                         :pseudo_user_id => su.remote_pseudo_user_id,
                                         :sha256_updated_at => receiver.sha256_updated_at.to_i
                                       })
              else
                receiver_user_ids << -receiver.id # unknown receiver
              end
            else
              # local gift verification
              receiver_user_ids << receiver.user_id
            end
            friend = friends[receiver.user_id]
            giver_receiver_is_login_user = true if friend == 1
          else
            logger.warn2 "Cid #{cid} : Gift receiver user with id #{user_id} was not found. Cannot check server sha256 signature for gift with unknown user ids."
            response << { :seq => seq, :cid => cid, :verified_at_server => false }
            receiver_error = true
            break
          end
        end if verify_gift["receiver_user_ids"]
        next if receiver_error
        receiver_user_ids.uniq! # todo: should return an error if doublets in receiver_user_ids array
        receiver_user_ids.sort! unless server_id
        if !giver_receiver_is_login_user
          # gift authorization failed. not logged in as giver or receiver (or as gift creator)
          if action == 'delete'
            # delete comment
            logger.debug2 "cid #{cid}. delete comment is not allowed. Not logged in as gift giver or gift receiver"
          else
            # accept or reject new deal proposal
            logger.debug2 "cid #{cid}. #{} new del proposal is not allowed. Not logged in as gift creator"
          end
          response << { :seq => seq, :cid => cid, :verified_at_server => false }
          next
        end

        if !gift_server_id

          # full local validation. check sha256 and find direction = gift creator (giver or receiver)

          # calculate and check server side sha256 signature
          gift_sha256_client = verify_gift["sha256"]
          gift_direction = nil
          if giver_user_ids.size > 0
            gift_sha256_input = ([gid, gift_sha256_client, 'giver'] + giver_user_ids).join(',')
            gift_sha256_calc = Base64.encode64(Digest::SHA256.digest(gift_sha256_input))
            gift_direction = 'giver' if gift.sha256 == gift_sha256_calc
            logger.debug "sha256 check failed with gift_direction = giver. gift_sha256_input = #{gift_sha256_input}, gift_sha256_calc = #{gift_sha256_calc}, gift.sha256 = #{gift.sha256}" unless gift_direction
          end
          if receiver_user_ids.size > 0
            gift_sha256_input = ([gid, gift_sha256_client, 'receiver'] + receiver_user_ids).join(',')
            gift_sha256_calc = Base64.encode64(Digest::SHA256.digest(gift_sha256_input))
            gift_direction = 'receiver' if gift.sha256 == gift_sha256_calc
            logger.debug "sha256 check failed with gift_direction = receiver. gift_sha256_input = #{gift_sha256_input}, gift_sha256_calc = #{gift_sha256_calc}, gift.sha256 = #{gift.sha256}" unless gift_direction
          end
          if !gift_direction
            logger.debug2 "cid #{cid}. gift sha256 check failed"
            response << { :seq => seq, :cid => cid, :verified_at_server => false }
            next
          end

          # check authorization. delete authorization has already been checked. Now checking accept and reject new deal proposal authorization
          if %w(accept reject).index(action)
            # accept and reject: compare gift creator and login users (remote partial validation - local full validation)
            gift_creator_user_ids = gift_direction == 'giver' ? giver_user_ids : receiver_user_ids
            gift_creator_login_user_ids = login_user_ids & gift_creator_user_ids
            if gift_creator_login_user_ids.length == 0
              logger.debug2 "cid #{cid}. new deal proposal can only be accepted and rejected by creator of gift"
              response << { :seq => seq, :cid => cid, :verified_at_server => false }
              next
            end
          end

        end # if !gift_server_id (local validation)

        # end gift hash check
      end # if gift_hash_required

      # new_deal_action_by_user_ids - authorization check
      # - verify: verify old comment with a new deal action. that is a cancelled, accepted or rejected new deal proposal
      #           server does not know whether new deal proposal was cancelled, accepted or rejected. server can only see sha256_action signature
      #           new deal action is client side only information
      #           no server side new_deal_action_by_user_ids authorization check
      # - cancel: compare login users, comment users and new_deal_action_by_user_id - intersection - minimum one user - can be checked both remote and local
      # - accept: compare login users, creator of gift and new_deal_action_by_user_id - intersection - minimum one user - can only be checked local on server where gift was created
      # - reject: compare login users, creator of gift and new_deal_action_by_user_id - intersection - minimum one user - can only be checked local on server where gift was created
      if action == 'cancel'
        intersect = comment_and_login_user_ids & new_deal_action_by_user_ids2
        if intersect.length == 0
          logger.debug2 "cid #{cid}. Invalid cancel new deal request. Must be cancelled by owner of proposal"
          logger.debug2 "comment users            = #{comment_user_ids.join(', ')}"
          logger.debug2 "login users              = #{login_user_ids.join(', ')}"
          logger.debug2 "new deal action by users = #{new_deal_action_by_user_ids2.join(', ')}"
          response << { :seq => seq, :cid => cid, :verified_at_server => false }
          next
        end
        if intersect.length < new_deal_action_by_user_ids2.length
          logger.debug2 "cid #{cid}. Warning. Difference between expected and received new_deal_action_by_user_ids"
          logger.debug2 "expected #{comment_and_login_user_ids.join(', ')}"
          logger.debug2 "received #{new_deal_action_by_user_ids2.join(', ')}"
        end
      end

      if %w(accept reject).index(action) and !gift_server_id
        # full local validation.
        intersect = gift_creator_login_user_ids & new_deal_action_by_user_ids2
        if intersect.length == 0
          logger.debug2 "cid #{cid}. Invalid #{action} new deal request. Must be accepted/rejected by creator of gift"
          logger.debug2 "gift created by rs       = #{gift_creator_user_ids.join(', ')}"
          logger.debug2 "login users              = #{login_user_ids.join(', ')}"
          logger.debug2 "new deal action by users = #{new_deal_action_by_user_ids2.join(', ')}"
          response << { :seq => seq, :cid => cid, :verified_at_server => false }
          next
        end
        if intersect.length < new_deal_action_by_user_ids2.length
          logger.debug2 "cid #{cid}. Warning. Difference between expected and received new_deal_action_by_user_ids"
          logger.debug2 "expected #{gift_creator_login_user_ids.join(', ')}"
          logger.debug2 "received #{new_deal_action_by_user_ids2.join(', ')}"
        end
      end

      if comment_server_id
        # remote comment verification (server to server verify comments message)
        # todo: sha256 signatures on this gofreerev server can be out of date
        #       must keep verify_comment row from client if verify comment request must be resent after updated sha256 signature (comment.user_ids)
        #       could also be used in a verify comment cache on this gofreerev server
        #       don't send identical verify comments request to other gofreerev server
        # 1) insert row in verify_comments table
        server_mid[comment_server_id] = Sequence.next_server_mid unless server_mid.has_key?(comment_server_id)
        vg = VerifyComment.new
        vg.client_sid = client_sid
        vg.client_sha256 = client_sha256
        vg.client_seq = seq
        vg.server_id = comment_server_id
        vg.cid = cid
        vg.server_seq = Sequence.next_verify_seq
        vg.request_mid = server_mid[comment_server_id]
        vg.save!
        # 2) insert verify_comments request in server_requests hash
        comment_hash = {:seq => vg.server_seq,
                :cid => cid,
                :sha256 => verify_comment["sha256"],
                :action => action}
        comment_hash[:sha256_action] = verify_comment["sha256_action"] if verify_comment["sha256_action"]
        comment_hash[:sha256_deleted] = verify_comment["sha256_deleted"] if verify_comment["sha256_deleted"]
        comment_hash[:user_ids] = user_ids
        comment_hash[:new_deal_action_by_user_ids] = new_deal_action_by_user_ids2 if verify_comment["sha256_action"]
        if gift_hash_required
          gift_hash = {:gid => verify_gift['gid'], :sha256 => verify_gift['sha256']}
          gift_hash[:giver_user_ids] = giver_user_ids if giver_user_ids.length > 0
          gift_hash[:receiver_user_ids] = receiver_user_ids if receiver_user_ids.length > 0
          # optional gift.server_id - use sha256 signature for server id in server to server communication
          # todo: how to handle cross server validation (comment on one server - gift on an other server)?
          if !gift_server_id
            # comment on remote server. gift on this server
            gift_hash[:server_id] = Server.server_id_to_sha256_hash[0]
          elsif comment_server_id != gift_server_id
            gift_hash[:server_id] = Server.server_id_to_sha256_hash[gift_server_id]
          end
          comment_hash[:gift] = gift_hash
        end
        server_requests[comment_server_id] = [] unless server_requests.has_key? comment_server_id
        server_requests[comment_server_id].push(comment_hash)
        next
      end

      # local comment action validation

      # calculate and check server side comment sha256 signature
      sha256_client = verify_comment["sha256"]
      sha256_input = ([cid, sha256_client] + user_ids).join(',')
      sha256_calc = Base64.encode64(Digest::SHA256.digest(sha256_input))
      if comment and comment.sha256 != sha256_calc
        logger.debug "Comment #{cid}. #{action} comment request failed. new sha256 calculation = #{sha256_calc}, old sha256 on server = #{comment.sha256}"
        response << { :seq => seq, :cid => cid, :verified_at_server => false }
        next
      end

      # sha256_action: if supplied - calculate and check server side sha256_action signature
      # old server sha256_action signature was generated when new_deal propocal was cancelled, accepted or rejected
      # calculate and check sha256_action signature from information received in verify comments request
      sha256_action_client = verify_comment["sha256_action"]
      if sha256_action_client.to_s != ''
        if !comment.sha256_action
          logger.warn2 "Comment #{cid}. Verify comment request failed. sha256_action in request but comment does not have a sha256_action signature on server."
          response << { :seq => seq, :cid => cid, :verified_at_server => false }
          next
        end
        sha256_action_input = ([cid, sha256_action_client] + user_ids).join(',')
        sha256_action_calc = Base64.encode64(Digest::SHA256.digest(sha256_action_input))
        if comment.sha256_action != sha256_action_calc
          logger.warn2 "Comment #{cid}. Verify comment request failed. new sha256_action calculation = #{sha256_action_calc}. old sha256_action on server = #{comment.sha256_action}."
          response << { :seq => seq, :cid => cid, :verified_at_server => false }
          next
        end
      end

      # sha256_deleted: if supplied - calculate and check server side sha256_deleted signature
      # old server sha256_deleted signature was generated when comment previously was deleted
      # calculate and check sha256_deleted signature from information received in verify comments request
      sha256_deleted_client = verify_comment["sha256_deleted"]
      if sha256_deleted_client
        if !comment.sha256_deleted and action != 'delete'
          logger.warn2 "Comment #{cid}. Verify comment request failed. sha256_deleted in request but comment dont have a sha256_deleted signature on server."
          response << { :seq => seq, :cid => cid, :verified_at_server => false }
          next
        end
        sha256_deleted_input = ([cid, sha256_deleted_client] + user_ids).join(',')
        sha256_deleted_calc = Base64.encode64(Digest::SHA256.digest(sha256_deleted_input))
        if comment.sha256_deleted != sha256_deleted_calc and action != 'delete'
          logger.warn2 "Comment #{cid}. Verify comment request failed. new sha256_deleted calculation = #{sha256_deleted_calc}. old sha256_deleted on server = #{comment.sha256_deleted}."
          response << { :seq => seq, :cid => cid, :verified_at_server => false }
        end
      end

      # no errors

      # actions:
      case action
        when 'create'
          c = Comment.new
          c.cid = cid
          c.sha256 = sha256_calc
          c.save!
        when 'verify'
          nil
        when 'cancel', 'accept', 'reject'
          comment.update_attribute :sha256_action, sha256_action_calc
        when 'delete'
          comment.update_attribute :sha256_deleted, sha256_deleted_calc
      end # case

      response << { :seq => seq, :cid => cid, :verified_at_server => true }

    end # each new_comment

    # any remote verify comment response ready for this client?
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

    response.size == 0 ? nil : { :comments => response }

  end # self.verify_comments


end # Comment
