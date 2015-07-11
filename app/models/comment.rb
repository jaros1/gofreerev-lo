
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

      # Could not create comment signature on server. Invalid authorization. Expected 2 users. Found 1 users
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

    # cache friends for login users - giver and/or receiver for comments must be friend of login user - with some few exceptions
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

      action_failed = "#{action} comment action failed"

      # validate row in verify comment request

      if comment_server_id
        # remote comment action
        if seq >= 0
          error = "#{action_failed}. Invalid request. seq must be negative for remote comment actions"
          logger.error2 "cid #{cid} : #{error}"
          response << { :seq => seq, :cid => cid, :verified_at_server => false, :error => error, :key => 'comment_syserr_neq_seq' }
          next
        end
        if action == 'create'
          error = "#{action_failed}. Invalid request. create comment on other Gofreerev server is not allowed. server id = #{comment_server_id}"
          logger.error2 "cid #{cid} : #{error}"
          response << { :seq => seq, :cid => cid, :verified_at_server => false, :error => error, :key => 'comment_create_remote', :options => {:server_id => comment_server_id} }
          next
        end
        if !servers.has_key? comment_server_id
          error = "#{action_failed}. Invalid request. Unknown server id #{comment_server_id}"
          logger.error2 "cid #{cid} : #{error}"
          response << { :seq => seq, :cid => cid, :verified_at_server => false, :error => error, :key => 'comment_syserr_server_id', :options => {:server_id => comment_server_id} }
          next
        end
      else
        # local comment action
        if seq < 0
          error = "#{action_failed}. Invalid request. seq must be postive for local comment actions"
          logger.error2 "cid #{cid} : #{error}"
          response << { :seq => seq, :cid => cid, :verified_at_server => false, :error => error, :key => 'comment_syserr_pos_seq'}
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
        error = "#{action_failed}. Invalid request. user_ids is missing"
        logger.error2 "cid #{cid} : #{error}"
        response << { :seq => seq, :cid => cid, :verified_at_server => false, :error => error, :key => 'comment_syserr_user' }
        next
      end
      if comment_user_ids.size != comment_user_ids.uniq.size
        error = "#{action_failed}. Invalid request. User ids in user_ids must be unique"
        logger.error2 "cid #{cid} : #{error}"
        response << { :seq => seq, :cid => cid, :verified_at_server => false, :error => error, :key => 'comment_syserr_uniq_user' }
        next
      end

      # read new_deal_action_by_user_ids and check doublets
      if verify_comment["new_deal_action_by_user_ids"] and verify_comment["new_deal_action_by_user_ids"].size > 0
        new_deal_action_by_user_ids1 = verify_comment["new_deal_action_by_user_ids"]
      else
        new_deal_action_by_user_ids1 = []
      end
      if new_deal_action_by_user_ids1.size != new_deal_action_by_user_ids1.uniq.size
        error = "#{action_failed}. Invalid request. User ids in new_deal_action_by_user_ids must be unique"
        logger.error2 "cid #{cid} : #{error}"
        response << { :seq => seq, :cid => cid, :verified_at_server => false, :error => error, :key => 'comment_syserr_uniq_action_user' }
        next
      end
      # consistency check (action, sha256_action and new_deal_action_by_user_ids)
      b1_new_deal_action = %w(cancel accept reject).index(action) ? true : false
      b2_sha256_action = verify_comment["sha256_action"].to_s != '' ? true : false
      b3_new_deal_action_by_user_ids = new_deal_action_by_user_ids1.size > 0 ? true : false
      if b1_new_deal_action
        # cancel, accept or reject new deal proposal - sha256_action and new_deal_action_by_user_ids are required
        if !b2_sha256_action
          error = "#{action_failed}. Invalid request. sha256_action is missing for #{action} new deal proposal"
          logger.error2 "cid #{cid} : #{error}"
          response << { :seq => seq, :cid => cid, :verified_at_server => false, :error => error, :key => 'comment_syserr_no_sha256_action1', :options => { :action => action} }
          next
        elsif !b3_new_deal_action_by_user_ids
          error = "#{action_failed}. Invalid request. new_deal_action_by_user_ids is missing for #{action} new deal proposal"
          logger.error2 "cid #{cid} : #{error}"
          response << { :seq => seq, :cid => cid, :verified_at_server => false, :error => error, :key => 'comment_syserr_no_action_user1', :options => { :action => action} }
          next
        end
      elsif action == 'create'
        # create new comment. sha256_action and new_deal_action_by_user_id are not allowed
        if b2_sha256_action
          error = "#{action_failed}. Invalid request. sha256_action is not allowed for create new comment"
          logger.error2 "cid #{cid} : #{error}"
          response << { :seq => seq, :cid => cid, :verified_at_server => false, :error => error, :key => 'comment_create_sha256_action' }
          next
        end
        if b3_new_deal_action_by_user_ids
          error = "#{action_failed}. Invalid request. new_deal_action_by_user_ids is not allowed for create new comment"
          logger.error2 "cid #{cid} : #{error}"
          response << { :seq => seq, :cid => cid, :verified_at_server => false, :error => error, :key => 'comment_create_action_user' }
          next
        end
      elsif b2_sha256_action != b3_new_deal_action_by_user_ids
        # verify and delete. optional sha256_action and new_deal_action_by_user_id
        if b2_sha256_action
          error = "#{action_failed}. Invalid request. sha256_action without new_deal_action_by_user_ids is not allowed. #{action} comment request"
          logger.error2 "cid #{cid} : #{error}"
          response << { :seq => seq, :cid => cid, :verified_at_server => false, :error => error, :key => 'comment_syserr_no_action_user2', :options => { :action => action} }
        else
          error = "#{action_failed}. Invalid request. new_deal_action_by_user_ids without sha256_action is not allowed. #{action} comment request"
          logger.error2 "cid #{cid} : #{error}"
          response << { :seq => seq, :cid => cid, :verified_at_server => false, :error => error, :key => 'comment_syserr_no_sha256_action2', :options => { :action => action} }
        end
        next
      end

      # sha256_deleted
      # - optional for verify
      # - not allowed for create new comment and cancel, accept, reject new deal proposal
      # - required for delete comment
      if %w(create cancel accept reject).index(action) and verify_comment['sha256_deleted'].to_s != ''
        error = "#{action_failed}. Invalid request. sha256_deleted is not allowed for action #{action}"
        logger.error2 "cid #{cid} : #{error} "
        response << { :seq => seq, :cid => cid, :verified_at_server => false, :error => error, :key => "comment_other_sha256_deleted_not_allowed" }
        next
      end
      if action == 'delete' and verify_comment['sha256_deleted'].to_s == ''
        error = "#{action_failed}. Invalid request. sha256_deleted is required for action delete"
        logger.error2 "cid #{cid} : #{error} "
        response << { :seq => seq, :cid => cid, :verified_at_server => false, :error => error, :key => 'comment_delete_sha256_deleted_required' }
        next
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
          error = "#{action_failed}. user with id #{user_id} was not found. Cannot check server sha256 signature for comment with unknown user ids"
          logger.warn2 "Cid #{cid} : #{error}"
          response << { :seq => seq, :cid => cid, :verified_at_server => false, :error => error, :key => 'comment_syserr_user', :options => { :user_id => user_id } }
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
      # - accept: comment hash is required - login users must be creators of comment (minimum one user)
      # - reject: comment hash is required - login users must be creators of comment (minimum one user)
      # - delete: comment hash is required if not one shared login user ids and comment user ids

      # compare comment user ids and login user ids - used in create and cancel in error messages
      if %w(create cancel).index(action) and (comment_user_ids != comment_and_login_user_ids)
        # authorization error. write nice error message in log. maybe api log out on client before new comment signature was created on server.
        missing_login_user_ids = comment_user_ids - login_users.collect { |u| u.id }
        missing_login_users = User.where(:id => missing_login_user_ids)
        missing_login_providers = missing_login_users.collect { |u| u.provider }
        # logger.debug2 "missing_login_user_ids = #{missing_login_user_ids.join(', ')}"
        # logger.debug2 "missing login users = " + missing_login_users.collect { |u| u.debug_info }.join(', ')
        # split missing login users in missing login and changed login
        changed_login_providers = login_providers & missing_login_providers
        missing_login_providers = missing_login_providers - changed_login_providers
      end # if

      case action
        when 'create'
          # create: login user ids and comment user ids must be identical - create only allowed for local comments
          comment_hash_required = false
          # local create comment action. login users must also be comment users
          if comment_user_ids != comment_and_login_user_ids
            # nice informative error message
            if (changed_login_providers.size > 0)
              error = "Could not create comment signature on server. Log in has changed for #{changed_login_providers.join('. ')} since comment was created on client. Please log in with old #{changed_login_providers.join('. ')} user"
              logger.debug2 "Cid #{cid} : #{error}"
              response << {:seq => seq, :cid => cid, :verified_at_server => false, :error => error, :key => 'comment_create_change_login', :options => {:providers => changed_login_providers.join('. ')}}
            else
              error = "Could not create comment signature on server. Log out for #{missing_login_providers.join('. ')} since comment was created on client. Please log in for #{missing_login_providers.join('. ')}"
              logger.debug2 "Cid #{cid} : #{error}"
              response << {:seq => seq, :cid => cid, :verified_at_server => false, :error => error, :key => 'comment_create_missing_login', :options => {:providers => missing_login_providers.join('. ')}}
            end
            next
          end
        when 'verify'
          # verify: no restrictions. normally comment from a friend or from a friend of a friend but with some few exceptions
          # but clients will only replicate comments with mutual friends and that should be sufficient security
          comment_hash_required = false
        when 'cancel'
          # cancel: minimum one shared login user ids and comment user ids.
          # todo: remote cancel. security check on both servers (sending/this and receiving/remote server) or only on receiving/remote server?
          comment_hash_required = false
          if comment_and_login_user_ids.length == 0
            # login changed between client cancel new deal proposal and server cancel new proposal request (offline client?)
            if (changed_login_providers.size > 0)
              error = "Could not cancel new deal proposal on server. Log in has changed for #{changed_login_providers.join('. ')} since new deal proposal was cancelled on client. Please log in with old #{changed_login_providers.join('. ')} user"
              logger.debug2 "Cid #{cid} : #{error}"
              response << {:seq => seq, :cid => cid, :verified_at_server => false, :error => error, :key => 'comment_cancel_change_login', :options => {:providers => changed_login_providers.join('. ')}}
            else
              error = "Could not cancel new deal proposal on server. Log out for #{missing_login_providers.join('. ')} since new deal proposal was cancelled on client. Please log in for #{missing_login_providers.join('. ')}"
              logger.debug2 "Cid #{cid} : #{error}"
              response << {:seq => seq, :cid => cid, :verified_at_server => false, :error => error, :key => 'comment_cancel_missing_login', :options => {:providers => missing_login_providers.join('. ')}}
            end
            next
          end
        when 'accept'
          # accept: comment hash is required - login users must be creators of comment (minimum one user)
          comment_hash_required = true
        when 'reject'
          # reject: comment hash is required - login users must be creators of comment (minimum one user)
          comment_hash_required = true
        when 'delete'
          # delete: comment hash is required if not one shared login user ids and comment user ids ()
          # todo: remote delete. security check on both servers (sending/this and receiving/remote server) or only on receiving/remote server?
          comment_hash_required = (comment_and_login_user_ids.length == 0)
      end # case
      logger.debug2 "cid = #{cid}, action = #{action}, comment_hash_required = #{comment_hash_required}"

      # prepare new_deal_action_by_user_ids (sha256 user signatures are used instead of user ids when communication with other Gofreerev servers).
      # only used for comments with comment.new_deal = true and action = verify comment or cancel, accept or reject new deal proposal
      # new_deal_action_by_user_ids must be a subset of login user ids (except verify)
      # new_deal_action_by_user_ids must also be:
      # - verify: no restrictions (client side security - comments are replicated only between mutual friends)
      # - cancel: a subset of comment creators
      # - accept: a subset of comment creators - see required comments hash
      # - reject: a subset of comment creators - see required comments hash
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
          error = "#{action_failed}. user with id #{user_id} was not found. Cannot check server sha256 signature for comment with unknown new_deal_action_user_ids"
          logger.warn2 "Cid #{cid} : #{error}"
          response << { :seq => seq, :cid => cid, :verified_at_server => false, :error => error, :key => 'comment_syserr_deal_user', :options => { :user_id => user_id } }
          user_error = true
          break
        end
      end
      next if user_error
      new_deal_action_by_user_ids2.uniq! # todo: should return an error if doublets in giver_user_ids array
      new_deal_action_by_user_ids2.sort! unless comment_server_id

      # read comment hash - required for server side authorization check for some actions (accept, reject and delete if comment is deleted by giver or receiver of comment)
      # also used in new_deal_action_by_user_ids - authorization check
      if comment_hash_required and verify_comment['comment'].to_s == ''
        error = "#{action_failed}. Invalid request. Gift hash is missing. Required for accept, reject and comment deleted by giver or receiver of comment. Action was #{action}"
        logger.debug2 "Cid #{cid} : #{error} "
        response << { :seq => seq, :cid => cid, :verified_at_server => false, :error => error, :key => 'comment_syserr_comment', :options => { :aciton => action } }
        next
      end
      if !comment_hash_required and verify_comment['comment'].to_s != ''
        # comment hash is NOT required for this comment/action.
        # occurs after page load when verify_comments_request is sent to server before friend list has been downloaded in /util/do_tasks
        logger.debug "Cid #{cid}. Warning. Gift hash is ignored. Only required for accept, reject and comment deleted by giver or receiver of comment. Action was #{action}"
      end
      if comment_hash_required
        # copy/pastye from Gift.verify comments. prepare comment giver_user_ids and receiver_user_ids for cross server communication. check comment.sha256 and find direction and creator of comment
        verify_comment = verify_comment['comment']
        comment_server_id = verify_comment['server_id']
        if comment_server_id and !servers.has_key? comment_server_id
          error = "#{action_failed}. Invalid request. Unknown comment.server_id #{comment_server_id}"
          logger.error2 "cid #{cid} : #{error} "
          response << { :seq => seq, :cid => cid, :verified_at_server => false, :error => error, :key => 'comment_syserr_comment_server_id'}
          next
        end
        gid = verify_comment['gid']

        # validate row in verify comment request
        if verify_comment["giver_user_ids"] and (verify_comment["giver_user_ids"].size > 0)
          giver_user_ids = verify_comment["giver_user_ids"].uniq
        else
          giver_user_ids = []
        end
        if verify_comment["receiver_user_ids"] and (verify_comment["receiver_user_ids"].size > 0)
          receiver_user_ids = verify_comment["receiver_user_ids"].uniq
        else
          receiver_user_ids = []
        end
        if (giver_user_ids.size == 0) and (receiver_user_ids.size == 0)
          error = "#{action_failed}. Invalid request. Gift giver user ids and comment receiver user ids are missing"
          logger.error2 "cid #{cid} : #{error}"
          response << { :seq => seq, :cid => cid, :verified_at_server => false, :error => error, :key => 'comment_syserr_comment_no_giver_receiver'}
          next
        end
        if (giver_user_ids.size > 0) and (receiver_user_ids.size > 0) and %w(accept reject).index(action)
          error = "#{action_failed}. Invalid request. Gift giver AND receiver are not allowed for #{action} new deal proposal"
          logger.error2 "gid #{gid} : #{error}"
          response << { :seq => seq, :cid => cid, :verified_at_server => false, :error => error, :key => 'comment_syserr_comment_giver_and_receiver' }
          next
        end
        if giver_user_ids.size != giver_user_ids.uniq.size
          error = "#{action_failed}. Invalid request. User ids in comment giver user ids list must be unique"
          logger.error2 "cid #{cid} : #{error}"
          response << { :seq => seq, :cid => cid, :verified_at_server => false, :error => error, :key => 'comment_syserr_comment_uniq_giver'}
          next
        end
        if receiver_user_ids.size != receiver_user_ids.uniq.size
          error = "#{action_failed}. Invalid request. User ids in comment receiver user ids list must be unique"
          logger.error2 "cid #{cid} : #{error} "
          response << { :seq => seq, :cid => cid, :verified_at_server => false, :error => error, :key => 'comment_syserr_comment_uniq_receiver'}
          next
        end


        # read and prepare giver_user_ids and receiver_user_ids (sha256 user signatures are used instead of user ids when communication with other Gofreerev servers)
        # comment hash used for accept, reject and some deletes
        # - accept and reject: compare comment creator and login users (remote partial validation - local full validation)
        # - delete comment: compare comment comment givers and comment receives with login users (validated remote and local)

        # check if giver or receiver is login user. required but not sufficient for accept and reject. required and sufficient for delete comment
        giver_receiver_is_login_user = false
        giver_user_ids = []
        giver_error = false
        verify_comment["giver_user_ids"].each do |user_id|
          if server_id and user_id < 0 # unknown remote user
            giver_user_ids << user_id
            next
          end
          giver = users[user_id]
          if giver
            if server_id
              # remote comment verification
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
              # local comment verification
              giver_user_ids << giver.user_id
            end
            friend = friends[giver.user_id]
            giver_receiver_is_login_user = true if friend == 1
          else
            error = "#{action_failed}. Gift giver user with id #{user_id} was not found. Cannot check server sha256 signature for comment with unknown user ids"
            logger.warn2 "Cid #{cid} : #{error}"
            response << { :seq => seq, :cid => cid, :verified_at_server => false, :error => error, :key => 'comment_syserr_giver', :options => { :user_id => user_id } }
            giver_error = true
            break
          end
        end if verify_comment["giver_user_ids"]
        next if giver_error
        giver_user_ids.uniq! # todo: should return an error if doublets in giver_user_ids array
        giver_user_ids.sort! unless server_id

        receiver_user_ids = []
        receiver_error = false
        verify_comment["receiver_user_ids"].each do |user_id|
          if server_id and user_id < 0
            # unknown remote user
            receiver_user_ids << user_id
            next
          end
          receiver = users[user_id]
          if receiver
            if server_id
              # remote comment verification
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
              # local comment verification
              receiver_user_ids << receiver.user_id
            end
            friend = friends[receiver.user_id]
            giver_receiver_is_login_user = true if friend == 1
          else
            error = "#{action_failed}. Gift receiver user with id #{user_id} was not found. Cannot check server sha256 signature for comment with unknown user ids"
            logger.warn2 "Cid #{cid} : #{error}"
            response << { :seq => seq, :cid => cid, :verified_at_server => false, :error => error, :key => 'comment_syserr_receiver', :options => { :user_id => user_id } }
            receiver_error = true
            break
          end
        end if verify_comment["receiver_user_ids"]
        next if receiver_error
        receiver_user_ids.uniq! # todo: should return an error if doublets in receiver_user_ids array
        receiver_user_ids.sort! unless server_id
        if !giver_receiver_is_login_user
          # comment authorization failed. not logged in as giver or receiver (=not logged in as comment creator)
          if action == 'delete'
            # delete comment
            error = "delete comment is not allowed. Not logged in as comment creator, comment giver or comment receiver"
            logger.debug2 "cid #{cid} : #{error}"
            response << { :seq => seq, :cid => cid, :verified_at_server => false, :error => error, :key => 'comment_delete_not_auth' }
          else
            # accept or reject new deal proposal
            error = "#{action} new del proposal is not allowed. Not logged in as comment creator"
            logger.debug2 "cid #{cid} : #{error}"
            response << { :seq => seq, :cid => cid, :verified_at_server => false, :error => error, :key => 'comment_delete_comment_not_creator' }
          end
          next
        end

        if comment_server_id
          # todo: now validating authorization for accept, reject new deal proposal or delete comment
          #       comment is on an other Gofreerev server
          #       check response from previous server to server request is ready (new request, wait, ready or timeout)
          #       new request:
          #       send comment verify request to other gofreerev server
          #       comment must exist on other server and comment sha256 signature must be correct
          #       other Gofreerev server must return direction to this Gofreerev server (null=invalid sha256, giver or receiver)
          #       this Gofreerev server must save verify comment request in db and process request after receiving response from other Gofreerev server (ready)
          #       reuse verify_comments table? reuse verify_comments server to server message
          #       use negative seq for comments without server id but comment hash with server id?
          #       check page reload problem. no friends array. first verify comments request with comment hash (=negative seq)?!
          error = "#{action_failed}. Authorization check failed. Gift and comment are on different Gofreerev servers. Not implemented"
          logger.error2 "Cid #{cid} : #{error}"
          response << { :seq => seq, :cid => cid, :verified_at_server => false, :error => error, :key => 'comment_syserr_comment_auth_not_impl' }
          next
        end

        if !comment_server_id

          # full local validation. check sha256 and find direction = comment creator (giver or receiver)

          # check if comment exists
          # todo: see todo issue 441 and 443
          comment = comments[gid]
          if !comment
            # comment not found
            error = "#{action_failed}. comment #{gid} was not found"
            logger.warn2 "cid #{cid} : #{error}"
            response << { :seq => seq, :cid => cid, :verified_at_server => false, :error => error, :key => 'comment_syserr_comment_not_found' }
            next
          end

          # calculate and check server side sha256 signature
          comment_sha256_client = verify_comment["sha256"]
          comment_direction = nil
          if giver_user_ids.size > 0
            comment_sha256_input = ([gid, comment_sha256_client, 'giver'] + giver_user_ids).join(',')
            comment_sha256_calc = Base64.encode64(Digest::SHA256.digest(comment_sha256_input))
            comment_direction = 'giver' if comment.sha256 == comment_sha256_calc
            logger.debug "sha256 check failed with comment_direction = giver. comment_sha256_input = #{comment_sha256_input}, comment_sha256_calc = #{comment_sha256_calc}, comment.sha256 = #{comment.sha256}" unless comment_direction
          end
          if receiver_user_ids.size > 0
            comment_sha256_input = ([gid, comment_sha256_client, 'receiver'] + receiver_user_ids).join(',')
            comment_sha256_calc = Base64.encode64(Digest::SHA256.digest(comment_sha256_input))
            comment_direction = 'receiver' if comment.sha256 == comment_sha256_calc
            logger.debug "sha256 check failed with comment_direction = receiver. comment_sha256_input = #{comment_sha256_input}, comment_sha256_calc = #{comment_sha256_calc}, comment.sha256 = #{comment.sha256}" unless comment_direction
          end
          if !comment_direction
            error = "#{action_failed}. comment sha256 signature check failed for #{action} comment action"
            logger.debug2 "cid #{cid} : #{error}"
            response << { :seq => seq, :cid => cid, :verified_at_server => false, :error => error, :key => "comment_syserr_comment_sha256", :options => { :action => action} }
            next
          end

          # check authorization.
          # delete authorization has already been checked. see if !giver_receiver_is_login_user.
          # now checking accept and reject new deal proposal authorization (login user must be creator of comment)
          if %w(accept reject).index(action)
            # accept and reject: compare comment creator and login users (remote partial validation - local full validation)
            comment_creator_user_ids = comment_direction == 'giver' ? giver_user_ids : receiver_user_ids
            comment_creator_login_user_ids = login_user_ids & comment_creator_user_ids
            if comment_creator_login_user_ids.length == 0
              error = "#{action_failed}. Not authorized. new deal proposal can only be accepted and rejected by creator of comment"
              logger.debug2 "cid #{cid} : #{error}"
              response << { :seq => seq, :cid => cid, :verified_at_server => false, :error => error, :key => 'comment_syserr_comment_not_auth' }
              next
            end
          end

        end # if !comment_server_id (local validation)

        # end comment hash check
      end # if comment_hash_required

      # new_deal_action_by_user_ids - authorization check
      # - verify: verify old new deal proposal with a new deal action. that is a cancelled, accepted or rejected new deal proposal
      #           server does not know whether new deal proposal was cancelled, accepted or rejected. server can only see sha256_action signature
      #           new deal action is client side only information
      #           no server side new_deal_action_by_user_ids authorization check
      # - cancel: compare login users, comment users and new_deal_action_by_user_id - intersection - minimum one user - can be checked both remote and local
      # - accept: compare login users, creator of comment and new_deal_action_by_user_id - intersection - minimum one user - can only be checked local on server where comment was created
      # - reject: compare login users, creator of comment and new_deal_action_by_user_id - intersection - minimum one user - can only be checked local on server where comment was created
      if action == 'cancel'
        intersect = comment_and_login_user_ids & new_deal_action_by_user_ids2
        if intersect.length == 0
          error = "#{action_failed}. Invalid cancel new deal request. Must be cancelled by creator of new deal proposal"
          logger.debug2 "cid #{cid} : #{error} "
          logger.debug2 "comment users            = #{comment_user_ids.join(', ')}"
          logger.debug2 "login users              = #{login_user_ids.join(', ')}"
          logger.debug2 "new deal action by users = #{new_deal_action_by_user_ids2.join(', ')}"
          response << { :seq => seq, :cid => cid, :verified_at_server => false, :error => error, :key => 'comment_cancel_new_deal_user' }
          next
        end
        if intersect.length < new_deal_action_by_user_ids2.length
          logger.warn2 "cid #{cid}. Warning. Difference between expected and received new_deal_action_by_user_ids"
          logger.debug2 "expected #{comment_and_login_user_ids.join(', ')}"
          logger.debug2 "received #{new_deal_action_by_user_ids2.join(', ')}"
        end
      end

      if %w(accept reject).index(action) and !comment_server_id
        # local validation only
        intersect = comment_creator_login_user_ids & new_deal_action_by_user_ids2
        if intersect.length == 0
          error = "#{action_failed}. Invalid #{action} new deal request. Must be accepted/rejected by creator of comment"
          logger.debug2 "cid #{cid} : #{error}"
          logger.debug2 "comment created by rs       = #{comment_creator_user_ids.join(', ')}"
          logger.debug2 "login users              = #{login_user_ids.join(', ')}"
          logger.debug2 "new deal action by users = #{new_deal_action_by_user_ids2.join(', ')}"
          response << { :seq => seq, :cid => cid, :verified_at_server => false, :error => error, :key => "comment_#{action}_new_deal_user" }
          next
        end
        if intersect.length < new_deal_action_by_user_ids2.length
          logger.debug2 "cid #{cid}. Warning. Difference between expected and received new_deal_action_by_user_ids. One or more missing users"
          logger.debug2 "expected #{comment_creator_login_user_ids.join(', ')}"
          logger.debug2 "received #{new_deal_action_by_user_ids2.join(', ')}"
        end
      end # if

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
        if comment_hash_required
          comment_hash = {:gid => verify_comment['gid'], :sha256 => verify_comment['sha256']}
          comment_hash[:giver_user_ids] = giver_user_ids if giver_user_ids.length > 0
          comment_hash[:receiver_user_ids] = receiver_user_ids if receiver_user_ids.length > 0
          # optional comment.server_id - use sha256 signature for server id in server to server communication
          # todo: how to handle cross server validation (comment on one server - comment on an other server)?
          if !comment_server_id
            # comment on remote server. comment on this server
            comment_hash[:server_id] = Server.server_id_to_sha256_hash[0]
          elsif comment_server_id != comment_server_id
            comment_hash[:server_id] = Server.server_id_to_sha256_hash[comment_server_id]
          end
          comment_hash[:comment] = comment_hash
        end
        server_requests[comment_server_id] = [] unless server_requests.has_key? comment_server_id
        server_requests[comment_server_id].push(comment_hash)
        next
      end

      # local comment action validation

      # check if comment exists
      comment = comments[cid]
      if action == 'create'
        if comment
          logger.warn2 "warning. action is create but cid #{cid} already exists. continuing with validations only"
        end
      else
        if !comment
          error = "#{action_failed}. Comment was not found"
          logger.warn2 "cid #{cid} : #{error}"
          response << { :seq => seq, :cid => cid, :verified_at_server => false, :error => error, :key => 'comment_syserr_not_found' }
          next
        end
      end

      # calculate and check server side comment sha256 signature
      sha256_client = verify_comment["sha256"]
      sha256_input = ([cid, sha256_client] + user_ids).join(',')
      sha256_calc = Base64.encode64(Digest::SHA256.digest(sha256_input))
      if comment and comment.sha256 != sha256_calc
        error = "#{action_failed}. Invalid request. sha256 signature check failed for #{action} comment action"
        logger.debug "cid #{cid} : #{error}"
        response << { :seq => seq, :cid => cid, :verified_at_server => false, :error => error, :key => "comment_#{action}_sha256", :options => { :action => action} }
        next
      end

      # sha256_action: if supplied - calculate and check server side sha256_action signature
      # old server sha256_action signature was generated when new_deal propocal was cancelled, accepted or rejected
      # calculate and check sha256_action signature from information received in verify comments request
      sha256_action_client = verify_comment["sha256_action"]
      if sha256_action_client.to_s != ''
        # sha256_action in request. must be a previously cancelled, accepted or rejected new deal proposal or a new cancel, accept or reject new deal proposal action
        if !comment.sha256_action and !%w(cancel accept reject).index(action)
          error = "#{action_failed}. sha256_action signature in request but comment does not have a sha256_action signature on server"
          logger.warn2 "Cid #{cid} : #{error}"
          response << { :seq => seq, :cid => cid, :verified_at_server => false, :error => error, :key => 'comment_syserr_not_action', :options => {:action => action} }
          next
        end
        if comment.sha256_deleted and %w(cancel accept reject).index(action)
          error = "#{action_failed}. Comment has already been deleted"
          logger.warn2 "Cid #{cid} : #{error}"
          response << { :seq => seq, :cid => cid, :verified_at_server => false, :error => error, :key => 'comment_action_deleted', :options => {:action => action} }
          next
        end
        # todo: use new_deal_action_by_user_ids instead of user_ids in sha256_action signature?
        sha256_action_input = ([cid, sha256_action_client] + user_ids).join(',')
        sha256_action_calc = Base64.encode64(Digest::SHA256.digest(sha256_action_input))
        if !((comment.sha256_action == sha256_action_calc) or (!comment.sha256_action and %w(cancel accept reject).index(action)))
          error = "#{action_failed}. Invalid sha256_accepted signature"
          logger.warn2 "Cid #{cid} : #{error}. new sha256_action calculation = #{sha256_action_calc}. old sha256_action on server = #{comment.sha256_action if comment}."
          response << { :seq => seq, :cid => cid, :verified_at_server => false, :error => error, :key => 'comment_syserr_sha256_action', :options => {:action => action}}
          next
        end
      else
        # blank sha256_action in request.
        # ok for create and verify. not ok for cancel, accept and reject but this has already been tested. not ok to delete a cancelled, accepted or rejected new deal proposal without a sha256_action signature in request
        if action == 'delete' and comment.sha256_action
          error = "#{action_failed}. Comment has a sha256_action server signature but sha256_action is missing in request"
          logger.warn2 "Gid #{gid} : #{error}"
          response << {:seq => seq, :cid => cid, :verified_at_server => false, :error => error, :key => 'comment_syserr_sha256_action_required', :options => { :action => action} }
          next
        end
      end

      # sha256_deleted: if supplied - calculate and check server side sha256_deleted signature
      # old server sha256_deleted signature was generated when comment previously was deleted
      # calculate and check sha256_deleted signature from information received in verify comments request
      sha256_deleted_client = verify_comment["sha256_deleted"]
      if sha256_deleted_client.to_s != ''
        # sha256_deleted signature in request. must be a deleted comment or an delete comment action in progress
        if !comment.sha256_deleted and (action != 'delete')
          error = "#{action_failed}. sha256_deleted signature in request but comment has not been deleted (no deleted signature on server)"
          logger.warn2 "Cid #{cid} : #{error}"
          response << { :seq => seq, :cid => cid, :verified_at_server => false, :error => error, :key => 'comment_syserr_not_deleted', :options => {:action => action} }
          next
        end
        if comment.sha256_action and (sha256_action_client.to_s == '')
          error = "#{action_failed}. sha256_deleted signature in request but new deal proposal has previously been cancelled, accepted or rejected and sha256 action signature was missing in request"
          logger.warn2 "Cid #{cid} : #{error}"
          response << {:seq => seq, :cid => cid, :verified_at_server => false, :error => error, :key => 'comment_syserr_sha256_action_required', :options => { :action => action} }
          next
        end
        sha256_deleted_input = ([cid, sha256_deleted_client] + user_ids).join(',')
        sha256_deleted_calc = Base64.encode64(Digest::SHA256.digest(sha256_deleted_input))
        if !((comment.sha256_deleted == sha256_deleted_calc) or (!comment.sha256_deleted and (action == 'delete')))
          error = "#{action_failed}. Invalid sha256_deleted signature"
          logger.warn2 "Cid #{cid} : #{error}. new sha256_deleted calculation = #{sha256_deleted_calc}. old sha256_deleted on server = #{comment.sha256_deleted}."
          response << { :seq => seq, :cid => cid, :verified_at_server => false, :error => error, :key => 'gift_syserr_sha256_deleted', :options => {:action => action} }
        end
        logger.warn2 "warning. action was delete but comment #{cid} has already been deleted" if (action == 'delete') and comment.sha256_deleted
      end

      # no errors

      # actions:
      case action
        when 'create'
          c = Comment.new unless comment
          c.cid = cid unless c.cid
          c.sha256 = sha256_calc
          c.save!
        when 'verify'
          nil
        when 'cancel', 'accept', 'reject'
          comment.update_attribute :sha256_action, sha256_action_calc
        when 'delete'
          comment.update_attribute :sha256_deleted, sha256_deleted_calc
      end # case

      # ok response for client
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

    return nil if response.size == 0

    # return correct format error message
    # - local client ping, util_controller.ping, client_sid is not null, use :key+:options error format (multi-language support)
    # - remote gift action, Server.receive_verify_gifts_request, client_sid is null, use :error error format (english only)
    if client_sid
      # local client ping. use :key+:options error format (multi-language support)
      response.each do |row|
        # todo: check error format. must have :key + :options
        row.delete(:error) if !row[:verified_at_server] and row[:error]
      end
    else
      # remote gift action. use :error error format (english only)
      response.each do |row|
        next if row[:verified_at_server]
        # todo: check error format. must have :error
        row.delete(:key) if row[:key]
        row.delete(:options) if row[:options]
      end
    end
    { :comments => response }

  end # self.verify_comments


end # Comment
