
class Comment < ActiveRecord::Base

  # create_table "comments", force: true do |t|
  #   t.string   "cid",                   null: false
  #   t.string   "sha256",     limit: 45, null: false
  #   t.datetime "created_at"
  #   t.datetime "updated_at"
  # end
  # add_index "comments", ["cid"], name: "index_comments_on_cid", unique: true, using: :btree


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
  public
  def self.verify_comments (verify_comments, login_user_ids, client_sid, client_sha256)
    logger.debug2 "verify_comments = #{verify_comments.to_json}"
    logger.debug2 "login_user_ids = #{login_user_ids.to_json}"
    logger.debug2 "client_sid     = #{client_sid}"
    logger.debug2 "client_sha256  = #{client_sha256}"
    is_server_msg = (client_sha256.to_s == '')
    logger.debug2 "is_server_msg  = #{is_server_msg}"

    if !verify_comments
      # empty verify comments request (ping) from client - any remote comment responses ready for this client?
      vcs = VerifyComment.where("client_sid = ? and client_sha256 = ? and verified_at_server is not null", client_sid, client_sha256)
      return nil if vcs.size == 0
      logger.debug2 "vcs.size = #{vcs.size}"
      client_response_array = []
      vcs.each do |vc|
        logger.debug2 "vc = #{vc.to_json}" if vc.error
        hash = {
            :seq => vc.client_seq,
            :cid => vc.cid,
            :verified_at_server => vc.verified_at_server
        }
        hash[:error] = vc.error unless vc.verified_at_server # only english :error format error messages in cross server communication.
        Gift.client_response_array_add client_response_array, hash, nil, vc.original_client_request # client_sid = nil
      end
      vcs.delete_all
      return {:comments => client_response_array }
    end

    # cache friends for login users - giver and/or receiver for comments must be friend of login user - with some few exceptions
    login_users = User.where(:user_id => login_user_ids).includes(:server_users)
    if login_users.size == 0 or login_users.size != login_user_ids.size
      return Gift.format_error_response(
          { :error => 'System error. Invalid Comment.verify_comments call. Expected array with login user ids for current logged in users', :key => 'login_users'},
          client_sid, nil)
    end
    login_providers = login_users.collect { |u| u.provider }
    User.cache_friend_info(login_users)
    friends = {}
    login_users.each do |u|
      friends.merge!(u.friends_hash)
    end

    # cache users (user_id's are used in server side sha256 signature)
    # cache comments (get previous server side sha256 signature)
    # cache gifts (get previous server side sha256 signature) - only accept, reject and some delete actions
    # cache servers (secrets for remote user sha256 signatures)
    users = {} # id => user
    comments = {} # cid => comment
    cids = []
    comments_user_ids = []
    seqs = {}
    server_ids = []
    servers = {}
    gids = []
    gifts = {}
    verify_comments.each do |new_comment|
      seq = new_comment["seq"]
      return Gift.format_error_response(
          { :error => 'Invalid verify comments request. Seq in comments array must be unique', :key => 'req_seqs_unique' },
          client_sid, nil) if seqs.has_key? seq
      seqs[seq] = true
      cids << new_comment["cid"]
      comments_user_ids += new_comment["user_ids"]
      comments_user_ids += new_comment["new_deal_action_by_user_ids"] if new_comment["new_deal_action_by_user_ids"]
      # todo: get known users for gift on an other Gofreerev server?
      if new_comment["gift"] # and !new_comment["gift"]["server_id"]
        # todo: remove this comment? comment with gift signature info. gift is also on this Gofreerev server
        comments_user_ids += new_comment["gift"]["giver_user_ids"] if new_comment["gift"]["giver_user_ids"]
        comments_user_ids += new_comment["gift"]["receiver_user_ids"] if new_comment["gift"]["receiver_user_ids"]
      end
      server_id = new_comment['server_id']
      server_ids << server_id if server_id and !server_ids.index(server_id)
      server_id = new_comment["gift"] ? new_comment["gift"]["server_id"] : nil
      server_ids << server_id if server_id and !server_ids.index(server_id)
      gids << new_comment["gift"]["gid"] if new_comment["gift"]
    end
    Comment.where(:cid => cids.uniq).each { |c| comments[c.cid] = c }
    User.where(:id => comments_user_ids.uniq).includes(:server_users).each { |u| users[u.id] = u }
    Server.where(:id => server_ids).each { |s| servers[s.id] = s } if server_ids.size > 0
    Gift.where(:gid => gids.uniq).each { |g| gifts[g.gid] = g }

    client_response_array = []
    server_verify_comms_requests = {} # server_id => array with remote commments verification request
    server_verify_comments_mid = {} # one mid (unique message id) for each remote server in verify comments request
    server_verify_gifts_requests = {} # server_id => array with remote gifts verification request (gift hash in verify comments request)
    server_verify_gifts_mid = {} # one mid (unique message id) for each remote server in verify gifts request (gift hash in verify comments request)

    verify_comments.each do |verify_comment|
      seq = verify_comment['seq']
      comment_server_id = verify_comment['server_id']
      cid = verify_comment['cid']
      action = verify_comment['action']
      if %w(cancel accept reject).index(action)
        action_failed = "#{action} new deal proposal failed"
      else
        action_failed = "#{action} comment failed"
      end

      # logical validate row in verify comment request (has already been JSON validated)

      if comment_server_id
        # remote comment action
        if seq >= 0
          error = "System error. #{action_failed}. Invalid request. seq must be negative for #{action} comment action on other Gofreerev servers"
          logger.error2 "cid #{cid} : #{error}"
          Gift.client_response_array_add(
              client_response_array,
              { :seq => seq, :cid => cid, :verified_at_server => false, :error => error, :key => 'comment_syserr_neq_seq' },
              client_sid, verify_comment)
          next
        end
        if action == 'create'
          error = "System error. #{action_failed}. Invalid request. create comment on other Gofreerev server is not allowed. server id = #{comment_server_id}"
          logger.error2 "cid #{cid} : #{error}"
          Gift.client_response_array_add(
              client_response_array,
              { :seq => seq, :cid => cid, :verified_at_server => false, :error => error, :key => 'comment_create_remote', :options => {:server_id => comment_server_id, :action => action} },
              client_sid, verify_comment)
          next
        end
        if !servers.has_key? comment_server_id
          error = "#{action_failed}. Invalid request. Unknown server id #{comment_server_id}"
          logger.error2 "cid #{cid} : #{error}"
          Gift.client_response_array_add(
              client_response_array,
              { :seq => seq, :cid => cid, :verified_at_server => false, :error => error, :key => 'comment_syserr_server_id', :options => {:server_id => comment_server_id, :action => action} },
              client_sid, verify_comment)
          next
        end
      else
        # local comment action
        if seq < 0
          error = "System error. #{action_failed}. Invalid request. seq must be postive for local comment actions"
          logger.error2 "cid #{cid} : #{error}"
          Gift.client_response_array_add(
              client_response_array,
              { :seq => seq, :cid => cid, :verified_at_server => false, :error => error, :key => 'comment_syserr_pos_seq', :options => { :action => action }},
              client_sid, verify_comment)
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
        error = "System error. #{action_failed}. Invalid request. user_ids is missing"
        logger.error2 "cid #{cid} : #{error}"
        Gift.client_response_array_add(
            client_response_array,
            { :seq => seq, :cid => cid, :verified_at_server => false, :error => error, :key => 'comment_syserr_user', :options => { :action => action} },
            client_sid, verify_comment)
        next
      end
      if comment_user_ids.size != comment_user_ids.uniq.size
        error = "System error. #{action_failed}. Invalid request. Comment user ids must be unique"
        logger.error2 "cid #{cid} : #{error}"
        Gift.client_response_array_add(
            client_response_array,
            { :seq => seq, :cid => cid, :verified_at_server => false, :error => error, :key => 'comment_syserr_uniq_user', :options => { :action => action} },
            client_sid, verify_comment)
        next
      end

      # read new_deal_action_by_user_ids and check doublets
      if verify_comment["new_deal_action_by_user_ids"] and verify_comment["new_deal_action_by_user_ids"].size > 0
        new_deal_action_by_user_ids1 = verify_comment["new_deal_action_by_user_ids"]
      else
        new_deal_action_by_user_ids1 = []
      end
      if new_deal_action_by_user_ids1.size != new_deal_action_by_user_ids1.uniq.size
        error = "System error. #{action_failed}. Invalid request. User ids in new_deal_action_by_user_ids must be unique"
        logger.error2 "cid #{cid} : #{error}"
        Gift.client_response_array_add(
            client_response_array,
            { :seq => seq, :cid => cid, :verified_at_server => false, :error => error, :key => 'comment_syserr_uniq_action_user', :options => { :action => action } },
            client_sid, verify_comment)
        next
      end
      # consistency check (action, sha256_action and new_deal_action_by_user_ids)
      b1_new_deal_action = %w(cancel accept reject).index(action) ? true : false
      b2_sha256_action = verify_comment["sha256_action"].to_s != '' ? true : false
      b3_new_deal_action_by_user_ids = new_deal_action_by_user_ids1.size > 0 ? true : false
      if b1_new_deal_action
        # cancel, accept or reject new deal proposal - sha256_action and new_deal_action_by_user_ids are required
        if !b2_sha256_action
          error = "System error. #{action_failed}. Invalid request. sha256_action signature is missing for #{action} new deal proposal"
          logger.error2 "cid #{cid} : #{error}"
          Gift.client_response_array_add(
              client_response_array,
              { :seq => seq, :cid => cid, :verified_at_server => false, :error => error, :key => 'comment_syserr_no_sha256_action1', :options => { :action => action} },
              client_sid, verify_comment)
          next
        elsif !b3_new_deal_action_by_user_ids
          error = "System error. #{action_failed}. Invalid request. new_deal_action_by_user_ids is missing for #{action} new deal proposal"
          logger.error2 "cid #{cid} : #{error}"
          Gift.client_response_array_add(
              client_response_array,
              { :seq => seq, :cid => cid, :verified_at_server => false, :error => error, :key => 'comment_syserr_no_action_user1', :options => { :action => action} },
              client_sid, verify_comment)
          next
        end
      elsif action == 'create'
        # create new comment. sha256_action and new_deal_action_by_user_id are not allowed
        if b2_sha256_action
          error = "System error. #{action_failed}. Invalid request. sha256_action signature is not allowed for create comment"
          logger.error2 "cid #{cid} : #{error}"
          Gift.client_response_array_add(
              client_response_array,
              { :seq => seq, :cid => cid, :verified_at_server => false, :error => error, :key => 'comment_create_sha256_action', :options => { :action => action} },
              client_sid, verify_comment)
          next
        end
        if b3_new_deal_action_by_user_ids
          error = "System error. #{action_failed}. Invalid request. new_deal_action_by_user_ids must be blank for create comment"
          logger.error2 "cid #{cid} : #{error}"
          Gift.client_response_array_add(
              client_response_array,
              { :seq => seq, :cid => cid, :verified_at_server => false, :error => error, :key => 'comment_create_action_user', :options => { :action => action } },
              client_sid, verify_comment)
          next
        end
      elsif b2_sha256_action != b3_new_deal_action_by_user_ids
        # verify and delete. optional sha256_action and new_deal_action_by_user_id
        if b2_sha256_action
          error = "System error. #{action_failed}. Invalid request. sha256_action signature without new_deal_action_by_user_ids is not allowed"
          logger.error2 "cid #{cid} : #{error}"
          Gift.client_response_array_add(
              client_response_array,
              { :seq => seq, :cid => cid, :verified_at_server => false, :error => error, :key => 'comment_syserr_no_action_user2', :options => { :action => action} },
              client_sid, verify_comment)
        else
          error = "System error. #{action_failed}. Invalid request. new_deal_action_by_user_ids without sha256_action is not allowed"
          logger.error2 "cid #{cid} : #{error}"
          Gift.client_response_array_add(
              client_response_array,
              { :seq => seq, :cid => cid, :verified_at_server => false, :error => error, :key => 'comment_syserr_no_sha256_action2', :options => { :action => action} },
              client_sid, verify_comment)
        end
        next
      end

      # sha256_deleted
      # - optional for verify
      # - not allowed for create new comment and cancel, accept, reject new deal proposal
      # - required for delete comment
      if %w(create cancel accept reject).index(action) and verify_comment['sha256_deleted'].to_s != ''
        error = "System error. #{action_failed}. Invalid request. sha256_deleted signature is not allowed for #{action} comment"
        logger.error2 "cid #{cid} : #{error} "
        Gift.client_response_array_add(
            client_response_array,
            { :seq => seq, :cid => cid, :verified_at_server => false, :error => error, :key => "comment_other_sha256_deleted_not_allowed", :options => { :action => action } },
            client_sid, verify_comment)
        next
      end
      if action == 'delete' and verify_comment['sha256_deleted'].to_s == ''
        error = "System error. #{action_failed}. Invalid request. sha256_deleted signature is required for delete comment"
        logger.error2 "cid #{cid} : #{error} "
        Gift.client_response_array_add(
            client_response_array,
            { :seq => seq, :cid => cid, :verified_at_server => false, :error => error, :key => 'comment_delete_sha256_deleted_required', :options => { :action => action } },
            client_sid, verify_comment)
        next
      end

      # prepare comment user ids (creator of comment / new deal proposal)
      # a) use internal user ids uid/provider if comment is on this Gofreerev server (local check only)
      # b) use sha256 user signatures if comment is on an other Gofreerev server (used in server to server verify comments message
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
          error = "#{action_failed}. user with id #{user_id} was not found. Cannot check server sha256 signature for comment"
          logger.warn2 "Cid #{cid} : #{error}"
          Gift.client_response_array_add(
              client_response_array,
              { :seq => seq, :cid => cid, :verified_at_server => false, :error => error, :key => 'comment_syserr_user', :options => { :user_id => user_id, :action => action } },
              client_sid, verify_comment)
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
      if %w(create cancel).index(action) and (comment_user_ids.size != comment_and_login_user_ids.size)
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
          gift_hash_required = false
          # local create comment action. login users must also be comment users
          if comment_user_ids.size != comment_and_login_user_ids.size
            # nice informative error message
            logger.debug2 "comment_user_ids           = #{comment_user_ids.to_json}"
            logger.debug2 "comment_and_login_user_ids = #{comment_and_login_user_ids.to_json}"
            logger.debug2 "changed_login_providers    = #{changed_login_providers.to_json}"
            logger.debug2 "missing_login_providers    = #{missing_login_providers.to_json}"
            if changed_login_providers.size > 0
              error = "#{action_failed}. Could not create comment signature on server. Log in has changed for #{changed_login_providers.join('. ')} since comment was created in browser client. Please log in with old #{changed_login_providers.join('. ')} user(s)"
              logger.debug2 "Cid #{cid} : #{error}"
              Gift.client_response_array_add(
                  client_response_array,
                  {:seq => seq, :cid => cid, :verified_at_server => false, :error => error, :key => 'comment_create_change_login', :options => {:providers => changed_login_providers.join('. '), :action => action}},
                  client_sid, verify_comment)
            else
              error = "#{action_failed}. Could not create comment signature on server. Log out for #{missing_login_providers.join('. ')} since comment was created in browser client. Please log in for #{missing_login_providers.join('. ')}"
              logger.debug2 "Cid #{cid} : #{error}"
              Gift.client_response_array_add(
                  client_response_array,
                  {:seq => seq, :cid => cid, :verified_at_server => false, :error => error, :key => 'comment_create_missing_login', :options => {:providers => missing_login_providers.join('. '), :action => action} },
                  client_sid, verify_comment)
            end
            next
          end
        when 'verify'
          # verify: no restrictions. normally comment from a friend or from a friend of a friend but with some few exceptions
          # but clients will only replicate comments with mutual friends and that should be sufficient security
          gift_hash_required = false
        when 'cancel'
          # cancel: minimum one shared login user ids and comment user ids.
          # todo: remote cancel. security check on both servers (sending/this and receiving/remote server) or only on receiving/remote server?
          gift_hash_required = false
          if comment_and_login_user_ids.length == 0
            # login changed between client cancel new deal proposal and server cancel new proposal request (offline client?)
            if changed_login_providers.size > 0
              error = "#{action_failed}. Could not cancel new deal proposal on server. Log in has changed for #{changed_login_providers.join('. ')} since new deal proposal was cancelled in browser client. Please log in with old #{changed_login_providers.join('. ')} user(s)"
              logger.debug2 "Cid #{cid} : #{error}"
              Gift.client_response_array_add(
                  client_response_array,
                  {:seq => seq, :cid => cid, :verified_at_server => false, :error => error, :key => 'comment_cancel_change_login', :options => {:providers => changed_login_providers.join('. '), :action => action} },
                  client_sid, verify_comment)
            else
              error = "#{action_failed}. Could not cancel new deal proposal on server. Log out for #{missing_login_providers.join('. ')} since new deal proposal was cancelled in browser client. Please log in for #{missing_login_providers.join('. ')}"
              logger.debug2 "Cid #{cid} : #{error}"
              Gift.client_response_array_add(
                  client_response_array,
                  {:seq => seq, :cid => cid, :verified_at_server => false, :error => error, :key => 'comment_cancel_missing_login', :options => {:providers => missing_login_providers.join('. '), :action => action} },
                  client_sid, verify_comment)
            end
            next
          end
        when 'accept'
          # accept: comment hash is required - login users must be creators of comment (minimum one user)
          gift_hash_required = true
        when 'reject'
          # reject: comment hash is required - login users must be creators of comment (minimum one user)
          gift_hash_required = true
        when 'delete'
          # delete: comment hash is required if not one shared login user ids and comment user ids ()
          # todo: remote delete. security check on both servers (sending/this and receiving/remote server) or only on receiving/remote server?
          gift_hash_required = (comment_and_login_user_ids.length == 0)
      end # case
      logger.debug2 "cid = #{cid}, action = #{action}, gift_hash_required = #{gift_hash_required}"

      # prepare new_deal_action_by_user_ids
      # a) use internal user ids uid/provider if comment is on this Gofreerev server (local check only)
      # b) use sha256 user signatures if comment is on an other Gofreerev server (used in server to server verify comments message
      # used for comments with comment.new_deal = true and action = verify comment or cancel, accept or reject new deal proposal
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
          error = "#{action_failed}. user with id #{user_id} was not found. Cannot check server sha256_action signature for comment with unknown new_deal_action_user_ids"
          logger.warn2 "Cid #{cid} : #{error}"
          Gift.client_response_array_add(
              client_response_array,
              { :seq => seq, :cid => cid, :verified_at_server => false, :error => error, :key => 'comment_syserr_deal_user', :options => { :user_id => user_id, :action => action } },
              client_sid, verify_comment)
          user_error = true
          break
        end
      end
      next if user_error
      new_deal_action_by_user_ids2.uniq! # todo: should return an error if doublets in giver_user_ids array
      new_deal_action_by_user_ids2.sort! unless comment_server_id

      # read gift hash - required for server side authorization check for some actions (accept, reject and delete if comment is deleted by giver or receiver of comment)
      # also used in new_deal_action_by_user_ids - authorization check
      if gift_hash_required and verify_comment['gift'].to_s == ''
        error = "#{action_failed}. Invalid request. Data for gift signature check is missing. Required for accept and reject new deal proposal and for comment deleted by giver or receiver of gift"
        logger.debug2 "Cid #{cid} : #{error} "
        Gift.client_response_array_add(
            client_response_array,
            { :seq => seq, :cid => cid, :verified_at_server => false, :error => error, :key => 'comment_syserr_gift', :options => { :aciton => action } },
            client_sid, verify_comment)
        next
      end
      if !gift_hash_required and verify_comment['gift'].to_s != ''
        # comment hash is NOT required for this comment/action.
        # occurs after page load when verify_comments_request is sent to server before friend list has been downloaded in /util/do_tasks
        logger.debug "Cid #{cid}. Warning. Gift hash is ignored. Only required for accept and reject new deal proposal and for comment deleted by giver or receiver of comment. Action was #{action}"
      end
      if gift_hash_required
        # copy/paste from Gift.verify comments. prepare comment giver_user_ids and receiver_user_ids for cross server communication. check comment.sha256 and find direction and creator of comment
        # a) accept or reject new deal proposal - login users must be creator of gift
        # b) action is delete and login users must be giver or receiver of gift
        verify_gift = verify_comment['gift']
        gift_server_id = verify_gift['server_id']
        if gift_server_id and !servers.has_key? gift_server_id
          error = "#{action_failed}. Invalid request. Invalid gift signature data. Unknown gift.server_id #{gift_server_id}"
          logger.error2 "cid #{cid} : #{error} "
          Gift.client_response_array_add(
              client_response_array,
              { :seq => seq, :cid => cid, :verified_at_server => false, :error => error, :key => 'comment_syserr_gift_server_id', :options => { :server_id => gift_server_id, :action => action } },
              client_sid, verify_comment)
          next
        end
        gid = verify_gift['gid']

        # validate gift hash
        if verify_gift["giver_user_ids"] and (verify_gift["giver_user_ids"].size > 0)
          giver_user_ids2 = verify_gift["giver_user_ids"]
        else
          giver_user_ids2 = []
        end
        if verify_gift["receiver_user_ids"] and (verify_gift["receiver_user_ids"].size > 0)
          receiver_user_ids2 = verify_gift["receiver_user_ids"]
        else
          receiver_user_ids2 = []
        end
        if (giver_user_ids2.size == 0) and (receiver_user_ids2.size == 0)
          error = "System error. #{action_failed}. Invalid request. Invalid gift signature data. Giver user ids and receiver user ids are missing"
          logger.error2 "cid #{cid} : #{error}"
          Gift.client_response_array_add(
              client_response_array,
              { :seq => seq, :cid => cid, :verified_at_server => false, :error => error, :key => 'comment_syserr_gift_no_giver_receiver', :options => { :action => action} },
              client_sid, verify_comment)
          next
        end
        if (giver_user_ids2.size > 0) and (receiver_user_ids2.size > 0) and %w(accept reject).index(action)
          error = "System error. #{action_failed}. Invalid request. Invalid gift signature data. Giver AND receiver are not allowed for #{action} new deal proposal"
          logger.error2 "gid #{gid} : #{error}"
          Gift.client_response_array_add(
              client_response_array,
              { :seq => seq, :cid => cid, :verified_at_server => false, :error => error, :key => 'comment_syserr_gift_giver_and_receiver', :options => { :action => action } },
              client_sid, verify_comment)
          next
        end
        if giver_user_ids2.size != giver_user_ids2.uniq.size
          error = "System error. #{action_failed}. Invalid request. Invalid gift signature data. User ids in gift giver user ids list must be unique"
          logger.error2 "cid #{cid} : #{error}"
          Gift.client_response_array_add(
              client_response_array,
              { :seq => seq, :cid => cid, :verified_at_server => false, :error => error, :key => 'comment_syserr_gift_uniq_giver', :options => { :action => action } },
              client_sid, verify_comment)
          next
        end
        if receiver_user_ids2.size != receiver_user_ids2.uniq.size
          error = "System error. #{action_failed}. Invalid request. Invalid gift signature data. User ids in gift receiver user ids list must be unique"
          logger.error2 "cid #{cid} : #{error} "
          Gift.client_response_array_add(
              client_response_array,
              { :seq => seq, :cid => cid, :verified_at_server => false, :error => error, :key => 'comment_syserr_gift_uniq_receiver', :options => { :action => action } },
              client_sid, verify_comment)
          next
        end

        # read and prepare giver_user_ids and receiver_user_ids
        # - using internal user ids when checking gift sha256 signature local - see giver_user_ids1
        # - using sha256 user signatures instead of internal user ids when communication with other Gofreerev servers - see giver_user_ids2
        # comment.gift hash is used for accept, reject and some deletes
        # - accept and reject: compare comment creator and login users (remote partial validation - local full validation)
        # - delete comment: compare comment.gift.givers and comment.gift.receives with login users (validated remote and local)

        if comment_server_id
          # sending verify comment request to other Gofreerev server.
          # use sha256 user signatures for server for comment
          server_id = comment_server_id
        elsif gift_server_id
          # sending verify comments request to other Gofreerev server.
          # use sha256 user signatures for server for gift
          server_id = gift_server_id
        else
          # 100 local gift verification. use only internal user ids uid/provider
          server_id = nil
        end

        # check if giver or receiver is login user. required but not sufficient for accept and reject. required and sufficient for delete comment
        giver_receiver_is_login_user = false
        giver_user_ids1 = []
        giver_user_ids2 = []
        giver_error = false
        verify_gift['giver_user_ids'].each do |user_id|
          if server_id and user_id < 0 # unknown remote user - used negative user id as it is
            giver_user_ids2 << user_id
            next
          end
          giver = users[user_id]
          if giver
            # giver_user_ids1 - internal user ids - used in local gift sha256 check
            giver_user_ids1 << giver.user_id
            # giver_user_ids2 - user sha256 signatures - used in verify remote comment server to server request
            if server_id
              # remote comment or remote gift verification
              su = giver.server_users.find { |su| (su.server_id == server_id) and su.verified_at }
              if su
                # verified server user. use sha256 signature as user id and pseudo user id as fallback information (changed sha256 signature)
                giver_user_ids2.push({ :sha256 => giver.calc_sha256(servers[server_id].secret),
                                      :pseudo_user_id => su.remote_pseudo_user_id,
                                      :sha256_updated_at => giver.sha256_updated_at.to_i
                                    })
              else
                giver_user_ids2 << -giver.id # unknown remote giver
              end
            else
              # local comment verification - use user id as it is
              giver_user_ids2 << giver.user_id
            end
            friend = friends[giver.user_id]
            giver_receiver_is_login_user = true if friend == 1
          else
            error = "#{action_failed}. Invalid gift signature data. Gift giver user with id #{user_id} was not found"
            logger.warn2 "Cid #{cid} : #{error}"
            Gift.client_response_array_add(
                client_response_array,
                { :seq => seq, :cid => cid, :verified_at_server => false, :error => error, :key => 'comment_syserr_gift_giver', :options => { :user_id => user_id, :action => action } },
                client_sid, verify_comment)
            giver_error = true
            break
          end
        end if verify_gift['giver_user_ids']
        next if giver_error
        giver_user_ids1.sort! unless gift_server_id
        # logger.debug2 "todo: check translation from internal user ids to user signatures:"
        # logger.debug2 "verify_gift['giver_user_ids'] = #{verify_gift['giver_user_ids'].to_json}"
        logger.debug2 "giver_user_ids1 = #{giver_user_ids1.to_json}"
        logger.debug2 "giver_user_ids2 = #{giver_user_ids2.to_json}"

        receiver_user_ids1 = []
        receiver_user_ids2 = []
        receiver_error = false
        verify_gift['receiver_user_ids'].each do |user_id|
          if server_id and user_id < 0
            # unknown remote user
            receiver_user_ids2 << user_id
            next
          end
          receiver = users[user_id]
          if receiver
            # receiver_user_ids1 - internal user ids - used in local gift sha256 check
            receiver_user_ids1 << receiver.user_id
            # receiver_user_ids2 - user sha256 signatures - used in verify remote comment server to server request
            if server_id
              # remote comment or remote gift verification
              su = receiver.server_users.find { |su| (su.server_id == server_id) and su.verified_at }
              if su
                # verified server user. use sha256 signature as user id and pseudo user id as fallback information (changed sha256 signature)
                receiver_user_ids2.push({ :sha256 => receiver.calc_sha256(servers[server_id].secret),
                                         :pseudo_user_id => su.remote_pseudo_user_id,
                                         :sha256_updated_at => receiver.sha256_updated_at.to_i
                                       })
              else
                receiver_user_ids2 << -receiver.id # unknown receiver
              end
            else
              # local comment verification
              receiver_user_ids2 << receiver.user_id
            end
            friend = friends[receiver.user_id]
            giver_receiver_is_login_user = true if friend == 1
          else
            error = "#{action_failed}. Invalid gift signature data. Gift receiver user with id #{user_id} was not found"
            logger.warn2 "Cid #{cid} : #{error}"
            Gift.client_response_array_add(
                client_response_array,
                { :seq => seq, :cid => cid, :verified_at_server => false, :error => error, :key => 'comment_syserr_gift_receiver', :options => { :user_id => user_id, :action => action } },
                client_sid, verify_comment)
            receiver_error = true
            break
          end
        end if verify_gift['receiver_user_ids']
        next if receiver_error
        receiver_user_ids1.sort! unless gift_server_id
        # logger.debug2 "todo: check translation from internal user ids to user signatures:"
        # logger.debug2 "verify_gift['receiver_user_ids'] = #{verify_gift['receiver_user_ids'].to_json}"
        # logger.debug2 "receiver_user_ids1 = #{receiver_user_ids1.to_json}"
        # logger.debug2 "receiver_user_ids2 = #{receiver_user_ids2.to_json}"

        if !giver_receiver_is_login_user
          # comment authorization failed. not logged in as giver or receiver (=login user is not gift creator). cancel, accept and delete are not allowed
          if action == 'delete'
            # delete comment. We are in gift_hash_required section. comment was not deleted by creator of comment
            error = "#{action failed}. delete comment is not allowed. Not logged in as comment creator or as giver or receiver of gift"
            logger.debug2 "cid #{cid} : #{error}"
            Gift.client_response_array_add(
                client_response_array,
                { :seq => seq, :cid => cid, :verified_at_server => false, :error => error, :key => 'comment_delete_not_auth', :options => { :action => action } },
                client_sid, verify_comment)
          else
            # accept or reject new deal proposal. not logged in as giver or receiver of gift
            error = "#{action_failed}. #{action} new del proposal is not allowed. Not logged in as gift creator"
            logger.debug2 "cid #{cid} : #{error}"
            Gift.client_response_array_add(
                client_response_array,
                { :seq => seq, :cid => cid, :verified_at_server => false, :error => error, :key => 'comment_accept_not_auth', :options => { :action => action } },
                client_sid, verify_comment)
          end
          next
        end

        if !gift_server_id

          # gift on this Gofreerev server. authorization validation now. check sha256 and find direction = comment creator (giver or receiver)

          # check if gift exists
          # todo: see todo issue 441 and 443
          gift = gifts[gid]
          if !gift
            # gift not found
            error = "#{action_failed}. gift #{gid} was not found"
            logger.warn2 "cid #{cid} : #{error}"
            Gift.client_response_array_add(
                client_response_array,
                { :seq => seq, :cid => cid, :verified_at_server => false, :error => error, :key => 'comment_syserr_gift_not_found', :options => { :action => action, :gid => gid } },
                client_sid, verify_comment)
            next
          end

          # calculate and check server side gift sha256 signature using internal user ids format uid/provider
          gift_sha256_client = verify_gift["sha256"]
          gift_direction = nil
          if giver_user_ids1.size > 0
            gift_sha256_input = ([gid, gift_sha256_client, 'giver'] + giver_user_ids1).join(',')
            gift_sha256_calc = Base64.encode64(Digest::SHA256.digest(gift_sha256_input))
            gift_direction = 'giver' if gift.sha256 == gift_sha256_calc
            logger.debug "sha256 check failed with gift_direction = giver. gift_sha256_input = #{gift_sha256_input}, gift_sha256_calc = #{gift_sha256_calc}, gift.sha256 = #{gift.sha256}" unless gift_direction
          end
          if receiver_user_ids1.size > 0
            gift_sha256_input = ([gid, gift_sha256_client, 'receiver'] + receiver_user_ids1).join(',')
            gift_sha256_calc = Base64.encode64(Digest::SHA256.digest(gift_sha256_input))
            gift_direction = 'receiver' if gift.sha256 == gift_sha256_calc
            logger.debug "sha256 check failed with gift_direction = receiver. gift_sha256_input = #{gift_sha256_input}, gift_sha256_calc = #{gift_sha256_calc}, gift.sha256 = #{gift.sha256}" unless gift_direction
          end
          if !gift_direction
            error = "#{action_failed}. authorization check failed. gift sha256 signature check failed for #{action} comment"
            logger.debug2 "cid #{cid} : #{error}"
            Gift.client_response_array_add(
                client_response_array,
                { :seq => seq, :cid => cid, :verified_at_server => false, :error => error, :key => "comment_syserr_gift_sha256", :options => { :action => action} },
                client_sid, verify_comment)
            next
          end

          # check authorization.
          # delete authorization has already been checked. see if !giver_receiver_is_login_user.
          # now checking accept and reject new deal proposal authorization (login user must be creator of comment)
          if %w(accept reject).index(action)
            # accept and reject: compare comment creator and login users (remote partial validation - local full validation)
            gift_creator_user_ids = gift_direction == 'giver' ? giver_user_ids1 : receiver_user_ids1
            gift_creator_login_user_ids = login_user_ids & gift_creator_user_ids
            if gift_creator_login_user_ids.length == 0
              error = "#{action_failed}. Not authorized. New deal proposal can only be accepted and rejected by creator of gift"
              logger.debug2 "cid #{cid} : #{error}"
              # logger.debug2 "login_user_ids           = #{login_user_ids.to_json}"
              # logger.debug2 "gift_creator_user_ids = #{gift_creator_user_ids.to_json}"
              Gift.client_response_array_add(
                  client_response_array,
                  { :seq => seq, :cid => cid, :verified_at_server => false, :error => error, :key => 'comment_accept_gift_not_auth', :options => { :action => action } },
                  client_sid, verify_comment)
              next
            end
          end

        end # if !comment_server_id (local validation)

        # end gift hash check
      end # if gift_hash_required

      # new_deal_action_by_user_ids - authorization check
      # - verify: verify old new deal proposal with a new deal action. that is a cancelled, accepted or rejected new deal proposal
      #           server does not know whether new deal proposal was cancelled, accepted or rejected. server can only see sha256_action signature
      #           new deal action is client side only information
      #           no server side new_deal_action_by_user_ids authorization check
      # - cancel: compare login users, comment users and new_deal_action_by_user_id - intersection - minimum one user - can be checked both remote and local
      # - accept: compare login users, creator of comment and new_deal_action_by_user_id - intersection - minimum one user - can only be checked local on server where comment was created
      # - reject: compare login users, creator of comment and new_deal_action_by_user_id - intersection - minimum one user - can only be checked local on server where comment was created
      # - delete: as "verify" - no server side authorization check
      if action == 'cancel'
        intersect = comment_and_login_user_ids & new_deal_action_by_user_ids2
        if intersect.length == 0
          error = "#{action_failed}. Authorization check failed. Proposal must be cancelled by creator of new deal proposal"
          logger.debug2 "cid #{cid} : #{error} "
          logger.debug2 "comment users            = #{comment_user_ids.join(', ')}"
          logger.debug2 "login users              = #{login_user_ids.join(', ')}"
          logger.debug2 "new deal action by users = #{new_deal_action_by_user_ids2.join(', ')}"
          Gift.client_response_array_add(
              client_response_array,
              { :seq => seq, :cid => cid, :verified_at_server => false, :error => error, :key => 'comment_cancel_new_deal_user', :options => { :action => action } },
              client_sid, verify_comment)
          next
        end
        if intersect.length < new_deal_action_by_user_ids2.length
          logger.warn2 "cid #{cid}. Warning. Difference between expected and received new_deal_action_by_user_ids"
          logger.debug2 "expected #{comment_and_login_user_ids.join(', ')}"
          logger.debug2 "received #{new_deal_action_by_user_ids2.join(', ')}"
        end
      end

      if %w(accept reject).index(action) and !comment_server_id and !gift_server_id
        # local validation only

        # todo: gift is on an other Gofreerev server and direction, creators and gift_creator_login_user_ids are unitialized at this point. repeat this check after server to server verify gift and verify comment messages

        logger.debug2 "gift_creator_login_user_ids = #{gift_creator_login_user_ids.to_json}"
        logger.debug2 "new_deal_action_by_user_ids2 = #{new_deal_action_by_user_ids2.to_json}"
        intersect = gift_creator_login_user_ids & new_deal_action_by_user_ids2
        if intersect.length == 0
          error = "#{action_failed}. Invalid \"new_deal_action_by_user_ids\". New deal proposal must be accepted or rejected by creator of gift"
          logger.debug2 "cid #{cid} : #{error}"
          logger.debug2 "comment created by users = #{gift_creator_user_ids.join(', ')}"
          logger.debug2 "login users              = #{login_user_ids.join(', ')}"
          logger.debug2 "new deal action by users = #{new_deal_action_by_user_ids2.join(', ')}"
          Gift.client_response_array_add(
              client_response_array,
              { :seq => seq, :cid => cid, :verified_at_server => false, :error => error, :key => "comment_accept_new_deal_user", :options => { :action => action } },
              client_sid, verify_comment)
          next
        end
        if intersect.length < new_deal_action_by_user_ids2.length
          logger.debug2 "cid #{cid}. Warning. Difference between expected and received new_deal_action_by_user_ids. One or more missing users"
          logger.debug2 "expected #{gift_creator_login_user_ids.join(', ')}"
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
        server_verify_comments_mid[comment_server_id] = Sequence.next_server_mid unless server_verify_comments_mid.has_key?(comment_server_id)
        vc = VerifyComment.new
        vc.client_sid = client_sid
        vc.client_sha256 = client_sha256
        vc.client_seq = seq
        vc.server_id = comment_server_id
        vc.cid = cid
        vc.server_seq = Sequence.next_verify_seq
        vc.request_mid = server_verify_comments_mid[comment_server_id]
        vc.original_client_request = verify_comment.to_json
        vc.save!
        logger.debug2 "vc = #{vc.to_json}"

        # 2) insert verify_comments request in server_requests hash
        comment_hash = {:seq => vc.server_seq,
                :cid => cid,
                :sha256 => verify_comment["sha256"],
                :action => action}
        comment_hash[:sha256_action] = verify_comment["sha256_action"] if verify_comment["sha256_action"]
        comment_hash[:sha256_deleted] = verify_comment["sha256_deleted"] if verify_comment["sha256_deleted"]
        comment_hash[:user_ids] = user_ids
        comment_hash[:new_deal_action_by_user_ids] = new_deal_action_by_user_ids2 if verify_comment["sha256_action"]
        if gift_hash_required
          gift_hash = {:gid => gid, :sha256 => verify_gift['sha256']}
          gift_hash[:giver_user_ids] = giver_user_ids2 if giver_user_ids2.length > 0
          gift_hash[:receiver_user_ids] = receiver_user_ids2 if receiver_user_ids2.length > 0
          # optional comment.gift.server_id - use sha256 signature for server id in server to server communication
          if !verify_comment["gift"]["server_id"]
            # comment on remote server. gift on this server
            gift_hash[:server_id] = Server.server_id_to_sha256_hash[0]
          elsif verify_comment["gift"]["server_id"] != comment_server_id
            # comment and gift on two different Gofreerev servers
            gift_hash[:server_id] = Server.server_id_to_sha256_hash[comment_server_id]
          else
            # comment and gift are other Gofreerev server
            nil
          end
          comment_hash[:gift] = gift_hash
        end

        # add comment_hash to server_verify_comms_requests hash
        # - one array for each remote Gofreerev server with verify gifts requests
        # - one array for each remote Gofreerev server with fallback info used in case of invalid verify comments json message
        server_verify_comms_requests[comment_server_id] = { :server_requests => [], :json_error_info => []} unless server_verify_comms_requests.has_key? comment_server_id
        json_error_info = verify_comment, vc
        server_verify_comms_requests[comment_server_id][:server_requests].push(comment_hash)
        server_verify_comms_requests[comment_server_id][:json_error_info].push(json_error_info)
        next

      end # if comment_server_id

      # comment is on this Gofreerev server.

      if gift_server_id
        # gift is on an other Gofreerev server
        # check gift sha256, find direction, creator of gift and check action authorization with a verify gifts server to server message

        # case 1: client ping. comment on this Gofreerev server. gift on an other Gofreerev server
        #         save original client request in verify_comments (todo: add login_user_ids to verify_comments table)
        #         create and save a verify gifts request in verify gifts table
        #         send a server to server verify gifts request
        #         wait for and receive a verify gifts response from other server
        #         save response in verify_gifts table
        #         repeat original verify comment request in next client ping and return response (todo: check unchanged login)

        # case 2: client ping. comment on other Gofreerev server. gift on this or a third Gofreerev server
        #         save original client request in verify comments
        #         send a server to server verify comments request
        #         other server: receive verify comments request
        #         other server: save original verify comments request in verify_comments
        #         other server: send verify gifts request to a third server
        #         other server: receive verify gifts response from third server
        #         other server: save response in

        # check if verify comments request is in verify_comments table.
        # a) not found: first verify_comments request before sending verify_gifts request to other Gofreerev server
        # b) found    : second verify_comments request after receiving verify_gifts response from other Gofreerev server
        # using sha256 index on verify_comments table as helper when checking for old verify comments request
        original_verify_comm_request = verify_comment.to_json
        original_vc_request_sha256 = Base64.encode64(Digest::SHA256.digest(original_verify_comm_request))
        vc = VerifyComment.find_by_original_client_request_sha256_and_original_client_request(original_vc_request_sha256, original_verify_comm_request)
        if !vc

          logger.debug2 "comment.gift is on an other Gofreerev server. Make verify gifts request and wait for verify gift response before continuing with verify comments request"

          # insert row in verify_comments table including login user ids. request will be retried after receiving verify gifts response from other Gofreerev server
          # response from server verify gifts will be saved in verify_gifts table.
          # using identical server_seq and request_mid in verify_gifts and verify_comments table
          # server.receive_verify_gifts_response will use this information to find and retry original verify comments request
          server_verify_gifts_mid[gift_server_id] = Sequence.next_server_mid unless server_verify_gifts_mid.has_key?(gift_server_id)
          vc = VerifyComment.new
          vc.client_sid = client_sid
          vc.client_sha256 = client_sha256
          vc.client_seq = seq
          vc.server_id = comment_server_id || 0
          vc.cid = cid
          vc.server_seq = Sequence.next_verify_seq
          vc.request_mid = server_verify_gifts_mid[gift_server_id]
          vc.original_client_request = original_verify_comm_request
          vc.original_client_request_sha256 = original_vc_request_sha256
          vc.login_user_ids = login_user_ids.to_json # array
          vc.save!
          logger.debug2 "vc = #{vc.to_json}"

          vg = VerifyGift.new
          vg.client_sid = nil
          vg.client_sha256 = nil
          vg.client_seq = vc.server_seq
          vg.server_id = gift_server_id
          vg.gid = gid
          vg.server_seq = vc.server_seq # link between verify comments request and verify gifts response
          vg.request_mid = vc.request_mid
          vg.original_client_request = verify_gift.to_json
          vg.save!
          logger.debug2 "vg = #{vg.to_json}"

          # create server to server verify gifts request. simple verify check. only with sha256, giver and receiver and verify sha256 signature only
          verify_gift_request = {:seq => vc.server_seq, :gid => gid, :sha256 => verify_gift["sha256"], :action => 'verify'}
          verify_gift_request[:giver_user_ids] = giver_user_ids2 if giver_user_ids2.size > 0
          verify_gift_request[:receiver_user_ids] = receiver_user_ids2 if receiver_user_ids2.size > 0
          logger.debug2 "verify_gift_request = #{verify_gift_request}"

          # add verify_gifts request to server_verify_gifts_requests hash
          # - one array for each remote Gofreerev server with verify gifts requests
          # - one array for each remote Gofreerev server with fallback info used in case of invalid verify gifts json message
          server_verify_gifts_requests[gift_server_id] = { :server_requests => [], :json_error_info => []} unless server_verify_gifts_requests.has_key? gift_server_id
          json_error_info = verify_comment, vc, vg
          # logger.debug2 "verify_gift_request = #{verify_gift_request.to_json}"
          # logger.debug2 "verify_comment = #{verify_comment.to_json}"
          # logger.debug2 "vc = #{vc.to_json}"
          # logger.debug2 "vg = #{vg.to_json}"
          # logger.debug2 "json_error_info = #{json_error_info.to_json}"
          server_verify_gifts_requests[gift_server_id][:server_requests].push(verify_gift_request)
          server_verify_gifts_requests[gift_server_id][:json_error_info].push(json_error_info)
          # logger.debug2 "server_verify_gifts_requests = #{server_verify_gifts_requests.to_json}"

          # wait for verify gifts response and new identical verify comments request
          logger.debug2('todo: add verify_comments call to server.receive_verify_gifts_response')
          next

        end # if !vc


        # verify comments request was already in verify comments table
        # must be second call after receiving verify gifts response from other Gofreerev server
        # see server.receive_verify_gifts_response - pending_verify_comms_requests loop

        # 1) must have login_user_ids information. always ok. called from server.receive_verify_gifts_response
        # 2) must have corresponding row in verify gifts table (server_seq)
        # 3) response from verify gifts request must be ready
        #    - verified_at_server is not null
        #    - response_mid is not null
        #    - direction is not null
        logger.debug2 "comment.gift is on a other Gofreerev server. Old identical verify comment request found in verify_comments table"
        logger.debug2 "vc = #{vc.to_json}"
        # vc = {
        #     "id":29,"client_sid":null,"client_sha256":null,"client_seq":63,"server_id":0,
        #     "cid":"14488910629803885142","server_seq":49,"verified_at_server":null,
        #     "created_at":"2015-12-08T16:05:28.000Z","updated_at":"2015-12-08T16:05:28.000Z",
        #     "error":null,"request_mid":95,"response_mid":null,
        #      "original_client_request":"{\"seq\":63,\"cid\":\"14488910629803885142\",\"sha256\":\"åñ N\\u001EÈ«\\u0011@Û\\bþë$XæròEE¼Qù¤\\u0007êßê\",\"action\":\"reject\",\"sha256_action\":\"¼=Ý\\\"¬b^\\u0011ó(é.¥ó·{(b\\u0004aZ`éüÜ\\u0014»è\",\"user_ids\":[2],\"new_deal_action_by_user_ids\":[3],\"gift\":{\"gid\":\"14481197074000741072\",\"sha256\":\"é%Bòóô~hË·¹òÕyÍ¬\\u0006åbd\\u0017ÿ77d¿ñ\",\"giver_user_ids\":[3],\"server_id\":1}}",
        #     "login_user_ids":"[\"1563545817212684/facebook\"]",
        #     "original_client_request_sha256":"Cmi3CLMkW8IQ/95gLvb1pRYnNA8CS5/DqS6KTY3LIyo=\n"
        # }

        vg = VerifyGift.find_by_server_seq(vc.server_seq)
        if !vg
          error = "System error. #{action_failed}. Authorization check failed. Expected verify gift response was not found in verify_gifts table"
          logger.error2 "Cid #{cid} : #{error}"
          Gift.client_response_array_add(
              client_response_array,
              { :seq => seq, :cid => cid, :verified_at_server => false, :error => error, :key => 'comment_syserr_gift_res_not_found_1', :options => { :action => action } },
              client_sid, verify_comment)
          next
        end
        logger.debug2 "vg = #{vg.to_json}"
        # vg = {
        #    "id":34,"client_sid":null,"client_sha256":null,"client_seq":50,"server_id":1,
        #    "gid":"14481197074000741072","server_seq":50,
        #    "verified_at_server":false,"created_at":"2015-12-09T08:49:15.000Z","updated_at":"2015-12-09T08:49:17.000Z",
        #    "error":" gift action failed. Invalid request. sha256 signature check failed",
        #    "request_mid":97,"response_mid":84,
        #    "original_client_request":"{\"gid\":\"14481197074000741072\",\"sha256\":\"é%Bòóô~hË·¹òÕyÍ¬\\u0006åbd\\u0017ÿ77d¿ñ\",\"giver_user_ids\":[3],\"server_id\":1}",
        #    "direction":null}
        if ![true, false].index(vg.verified_at_server)
          error = "System error. #{action_failed}. Authorization check failed. Expected verify gift response was not found in verify_gifts table"
          logger.error2 "Cid #{cid} : #{error}"
          Gift.client_response_array_add(
              client_response_array,
              { :seq => seq, :cid => cid, :verified_at_server => false, :error => error, :key => 'comment_syserr_gift_res_not_found_2', :options => { :action => action } },
              client_sid, verify_comment)
          next
        end
        if !vg.verified_at_server
          error = "#{action_failed}. Authorization check failed. Verify gift failed with error message \"#{vg.error}\""
          logger.error2 "Cid #{cid} : #{error}"
          Gift.client_response_array_add(
              client_response_array,
              { :seq => seq, :cid => cid, :verified_at_server => false, :error => error, :key => 'comment_syserr_gift_invalid', :options => { :action => action, :error => vg.error } },
              client_sid, verify_comment)
          next
        end
        if vg.direction.to_s == ''
          error = "System error. #{action_failed}. Authorization check failed. Verify gift response without direction"
          logger.error2 "Cid #{cid} : #{error}"
          Gift.client_response_array_add(
              client_response_array,
              { :seq => seq, :cid => cid, :verified_at_server => false, :error => error, :key => 'comment_syserr_gift_no_direction', :options => { :action => action } },
              client_sid, verify_comment)
          next
        end
        if !%w(giver receiver).index(vg.direction)
          error = "System error. #{action_failed}. Authorization check failed. Invalid direction in verify gift response"
          logger.error2 "Cid #{cid} : #{error}"
          Gift.client_response_array_add(
              client_response_array,
              { :seq => seq, :cid => cid, :verified_at_server => false, :error => error, :key => 'comment_syserr_gift_direction', :options => { :action => action } },
              client_sid, verify_comment)
          next
        end

        # check authorization.
        # delete authorization has already been checked. see if !giver_receiver_is_login_user.
        # now checking accept and reject new deal proposal authorization (login user must be creator of comment)
        if %w(accept reject).index(action)
          # accept and reject: compare comment creator and login users (remote partial validation - local full validation)
          gift_creator_user_ids = vg.direction == 'giver' ? giver_user_ids1 : receiver_user_ids1
          gift_creator_login_user_ids = login_user_ids & gift_creator_user_ids
          if gift_creator_login_user_ids.length == 0
            error = "#{action_failed}. Not authorized. New deal proposal can only be accepted and rejected by creator of gift"
            logger.debug2 "cid #{cid} : #{error}"
            logger.debug2 "vg.direction          = #{vg.direction}"
            logger.debug2 "giver_user_ids1       = #{giver_user_ids1.to_json}"
            logger.debug2 "giver_user_ids2       = #{giver_user_ids2.to_json}"
            logger.debug2 "receiver_user_ids1    = #{receiver_user_ids1}"
            logger.debug2 "receiver_user_ids2    = #{receiver_user_ids2}"
            logger.debug2 "login_user_ids        = #{login_user_ids.to_json}"
            logger.debug2 "gift_creator_user_ids = #{gift_creator_user_ids.to_json}"
            Gift.client_response_array_add(
                client_response_array,
                { :seq => seq, :cid => cid, :verified_at_server => false, :error => error, :key => 'comment_accept_gift_not_auth', :options => { :action => action } },
                client_sid, verify_comment)
            next
          end
        end

        # # check if verify gifts response already is in verify_gifts table and continue with authorization validation
        # # wait for verify gifts response if verify gifts request has already been sent to other gofreerev server - resend verify comment request to this Gofreerev server
        # # timeout if waiting more when x seconds for verify gifts response from other Gofreerev server
        # # read direction and make authorization check
        # error = "System error. #{action_failed}. Authorization check failed. Gift and comment are on different Gofreerev servers. Not yet implemented"
        # logger.error2 "Cid #{cid} : #{error}"
        # Gift.client_response_array_add(
        #     client_response_array,
        #     { :seq => seq, :cid => cid, :verified_at_server => false, :error => error, :key => 'comment_syserr_gift_auth_not_impl', :options => { :action => action } },
        #     client_sid, verify_comment)
        # next

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
          Gift.client_response_array_add(
              client_response_array,
              { :seq => seq, :cid => cid, :verified_at_server => false, :error => error, :key => 'comment_syserr_not_found', :options => { :action => action } },
              client_sid, verify_comment)
          next
        end
      end

      # calculate and check server side comment sha256 signature
      sha256_client = verify_comment["sha256"]
      sha256_input = ([cid, sha256_client] + user_ids).join(',')
      sha256_calc = Base64.encode64(Digest::SHA256.digest(sha256_input))
      if comment and comment.sha256 != sha256_calc
        error = "#{action_failed}. Invalid request. sha256 signature check failed"
        logger.debug "cid #{cid} : #{error}"
        Gift.client_response_array_add(
            client_response_array,
            { :seq => seq, :cid => cid, :verified_at_server => false, :error => error, :key => "comment_sha256", :options => { :action => action} },
            client_sid, verify_comment)
        next
      end

      # sha256_action: if supplied - calculate and check server side sha256_action signature
      # old server sha256_action signature was generated when new_deal propocal was cancelled, accepted or rejected
      # calculate and check sha256_action signature from information received in verify comments request
      sha256_action_client = verify_comment["sha256_action"]
      if sha256_action_client.to_s != ''
        # sha256_action in request.
        # must be a previously cancelled, accepted or rejected new deal proposal (sha256_action signature must be identical)
        # or a new cancel, accept or reject new deal proposal action (calculate and save sha256_action signature)
        if action == 'create'
          Raise "system error. create new comment + sha256_action in request has already been checked. See comment_create_sha256_action check previously in this method"
        end
        if !comment.sha256_action and %w(verify delete).index(action)
          error = "#{action_failed}. sha256_action signature in request but comment does not have a sha256_action signature on server"
          logger.warn2 "Cid #{cid} : #{error}"
          Gift.client_response_array_add(
              client_response_array,
              { :seq => seq, :cid => cid, :verified_at_server => false, :error => error, :key => 'comment_syserr_not_action', :options => {:action => action} },
              client_sid, verify_comment)
          next
        end
        if comment.sha256_deleted and %w(cancel accept reject).index(action)
          error = "#{action_failed}. Comment has been deleted"
          logger.warn2 "Cid #{cid} : #{error}"
          Gift.client_response_array_add(
              client_response_array,
              { :seq => seq, :cid => cid, :verified_at_server => false, :error => error, :key => 'comment_action_deleted', :options => {:action => action} },
              client_sid, verify_comment)
          next
        end
        # todo: use new_deal_action_by_user_ids instead of user_ids in sha256_action signature?
        sha256_action_input = ([cid, sha256_action_client] + user_ids).join(',')
        sha256_action_calc = Base64.encode64(Digest::SHA256.digest(sha256_action_input))
        if !comment.sha256_action
          # ok. must be a new cancel, reject or accept new deal proposal request
        elsif comment.sha256_action != sha256_action_calc
          # invalid sha256_action signature
          #  1) a verify or a delete comment request with invalid sha256_action in request (system error)
          #  2) a cancel, reject or accept new deal proposal with invalid sha256_action (crossed transactions - cancel by client a, reject by client b)
          error = "#{action_failed}. Invalid sha256_action signature"
          logger.warn2 "Cid #{cid} : #{error}. new sha256_action calculation = #{sha256_action_calc}. old sha256_action on server = #{comment.sha256_action if comment}."
          if %w(verify delete).index(action)
            Gift.client_response_array_add(
                client_response_array,
                { :seq => seq, :cid => cid, :verified_at_server => false, :error => error, :key => 'comment_sha256_action_syserr', :options => { :action => action } },
                client_sid, verify_comment)
          else
            Gift.client_response_array_add(
                client_response_array,
                { :seq => seq, :cid => cid, :verified_at_server => false, :error => error, :key => 'comment_sha256_action_cross', :options => { :action => action } },
                client_sid, verify_comment)
          end
          next
        else
          logger.warn2 "warning. action is #{action} but cid #{cid} has already been #{action}-ed. continuing with validations only"
        end

        # if !((comment.sha256_action == sha256_action_calc) or (!comment.sha256_action and %w(cancel accept reject).index(action)))
        #   error = "#{action_failed}. Invalid sha256_action signature"
        #   logger.warn2 "Cid #{cid} : #{error}. new sha256_action calculation = #{sha256_action_calc}. old sha256_action on server = #{comment.sha256_action if comment}."
        #   Gift.client_response_array_add(
        #       client_response_array,
        #       { :seq => seq, :cid => cid, :verified_at_server => false, :error => error, :key => 'comment_sha256_action', :options => { :action => action } },
        #       client_sid, verify_comment)
        #   next
        # end
        # if %w(cancel accept reject).index(action) and comment.sha256_action
        #   logger.warn2 "warning. action is #{action} but cid #{cid} has already been #{action}-ed. continuing with validations only"
        # end

      else
        # blank sha256_action in request.
        # ok for create and verify. not ok for cancel, accept and reject but this has already been tested. not ok to delete a cancelled, accepted or rejected new deal proposal without a sha256_action signature in request
        if action == 'delete' and comment.sha256_action
          error = "#{action_failed}. Comment has a sha256_action server signature but sha256_action is missing in request"
          logger.warn2 "Gid #{gid} : #{error}"
          Gift.client_response_array_add(
              client_response_array,
              {:seq => seq, :cid => cid, :verified_at_server => false, :error => error, :key => 'comment_syserr_sha256_action_required1', :options => { :action => action } },
              client_sid, verify_comment)
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
          Gift.client_response_array_add(
              client_response_array,
              { :seq => seq, :cid => cid, :verified_at_server => false, :error => error, :key => 'comment_syserr_not_deleted', :options => {:action => action} },
              client_sid, verify_comment)
          next
        end
        if comment.sha256_action and (sha256_action_client.to_s == '')
          error = "#{action_failed}. sha256_deleted signature in request but new deal proposal has previously been cancelled, accepted or rejected and sha256_action signature is missing in request"
          logger.warn2 "Cid #{cid} : #{error}"
          Gift.client_response_array_add(
              client_response_array,
              {:seq => seq, :cid => cid, :verified_at_server => false, :error => error, :key => 'comment_syserr_sha256_action_required2', :options => { :action => action} },
              client_sid, verify_comment)
          next
        end
        sha256_deleted_input = ([cid, sha256_deleted_client] + user_ids).join(',')
        sha256_deleted_calc = Base64.encode64(Digest::SHA256.digest(sha256_deleted_input))
        if !((comment.sha256_deleted == sha256_deleted_calc) or (!comment.sha256_deleted and (action == 'delete')))
          error = "#{action_failed}. Invalid sha256_deleted signature"
          logger.warn2 "Cid #{cid} : #{error}. new sha256_deleted calculation = #{sha256_deleted_calc}. old sha256_deleted on server = #{comment.sha256_deleted}."
          Gift.client_response_array_add(
              client_response_array,
              { :seq => seq, :cid => cid, :verified_at_server => false, :error => error, :key => 'comment_sha256_deleted', :options => {:action => action} },
              client_sid, verify_comment)
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
      Gift.client_response_array_add client_response_array, { :seq => seq, :cid => cid, :verified_at_server => true }, client_sid, verify_comment

    end # each new_comment


    # any remote verify comment response ready for this client?
    vcs = VerifyComment.where("client_sid = ? and client_sha256 = ? and verified_at_server is not null", client_sid, client_sha256)
    if vcs.size > 0
      logger.debug2 "vcs.size = #{vcs.size}"
      vcs.each do |vc|
        logger.debug2 "vc = #{vc.to_json}" if vc.error
        hash = {:seq => vc.client_seq,
                :gid => vc.gid,
                :verified_at_server => vc.verified_at_server}
        hash[:error] = vc.error unless vc.verified_at_server # only english :error format error messages in cross server communication
        Gift.client_response_array_add client_response_array, hash, nil, vc.original_client_request
      end
      vcs.delete_all
    end

    logger.debug2 "client_response_array = #{client_response_array}"
    logger.debug2 "server_verify_comms_requests = #{server_verify_comms_requests}"

    # send any server to server verify comments messages (comment on remote server)
    server_verify_comms_requests.each do |server_id, server_requests_hash|

      cids = server_requests_hash[:server_requests].collect { |sr| sr[:cid] }
      logger.debug2 "forwarding verify comment actions for comments #{cids.join(', ')} to Gofreerev server #{servers[server_id].site_url}"

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
          # unknown or unverified user - user unknown on other Gofreerev server <server_id> - use negative user id
          login_user_ids.push(-login_user.id)
        end
      end

      # build and validate json verify comments server to server message
      message_hash = {
          :msgtype => 'verify_comments',
          :mid => server_verify_comments_mid[server_id],
          :login_users => login_user_ids,
          :verify_comments => server_requests_hash[:server_requests] }
      logger.debug2 "verify_comments message_hash = #{message_hash}"

      # check that json schema exists
      json_schema = :verify_comments_request
      if !JSON_SCHEMA.has_key? json_schema

        # error message in log
        logger.error2 "Failed to sent comments to remote verification. JSON schema #{json_schema} was not found"
        error = "System error. Failed to sent comments to remote verification. JSON schema #{json_schema} was not found"

        # cleanup + return fatal json error in client_response_array
        logger.debug2 "Cleanup after JSON error and return error message to client"
        server_requests_hash[:json_error_info].each do |json_error_info|
          verify_comment, vc = json_error_info
          logger.debug2 "server_id      = #{server_id}"
          logger.debug2 "verify_comment = #{verify_comment.to_json}"
          logger.debug2 "vc             = #{vc.to_json}"
          # return error message to client
          Gift.client_response_array_add(
              client_response_array,
              { :seq => verify_comment['seq'], :cid => verify_comment['cid'], :verified_at_server => false,
                :error => error, :key => 'no_json', :options => {:schema => json_schema} },
              client_sid, verify_comment)
          vc.destroy!
        end

        next # unable to check json - don't send verify comments server to server message

        # return Gift.format_error_response(
        #     { :error => "System error. Could not validate verify_comments server to server message. JSON schema definition #{json_schema.to_s} was not found.",
        #       :key => 'no_json', :options => { :schema => json_schema} },
        #     client_sid, nil)

      end

      # check that json is valid
      json_errors = JSON::Validator.fully_validate(JSON_SCHEMA[json_schema], message_hash)
      if json_errors.size > 0

        # write error message in server log
        json_error = json_errors.join(', ')
        logger.error2 "Failed to sent comments to remote verification. Error in #{json_schema}"
        logger.error2 "message = #{message_hash}"
        logger.error2 "json_schema = #{JSON_SCHEMA[json_schema]}"
        logger.error2 "errors = #{json_error}"
        error = "System error. Failed to sent comments to remote verification. JSON error in verify_comments server to server message: #{json_error}."

        # cleanup + return fatal json error in client_response_array
        logger.debug2 "Cleanup after JSON error and return error message to client"
        server_requests_hash[:json_error_info].each do |json_error_info|
          verify_comment, vc = json_error_info
          logger.debug2 "server_id      = #{server_id}"
          logger.debug2 "verify_comment = #{verify_comment.to_json}"
          logger.debug2 "vc             = #{vc.to_json}"
          # return error message to client
          Gift.client_response_array_add(
              client_response_array,
              { :seq => verify_comment['seq'], :cid => verify_comment['cid'], :verified_at_server => false,
                :error => error, :key => 'invalid_json', :options => {:schema => json_schema, :error => json_error} },
              client_sid, verify_comment)
          vc.destroy!
        end # server_requests_hash[:json_error_info] loop

        next # don't send invalid verify comments server to server message

        # return Gift.format_error_response(
        #     { :error => "Failed to create verify_comments server to server message: #{json_errors.join(', ')}",
        #       :key => 'invalid_json', :options => { :schema => json_schema, :error => json_errors.join(', ')} },
        #     client_sid, nil)

      end # if

      # save mix encrypted server to server message - will be sent in next server to server ping
      key, message = servers[server_id].mix_encrypt_message_hash message_hash
      m = Message.new
      m.from_did = SystemParameter.did
      m.to_did = servers[server_id].new_did
      m.server = true
      m.mid = server_verify_comments_mid[server_id]
      m.key = key
      m.message = message
      m.save!

    end # server_verify_comms_requests loop


    # send any server to server verify gifts messages (gift on remote server)
    server_verify_gifts_requests.each do |server_id, server_requests_hash|
      # translate login user ids to sha256 signatures (verified server users) or negative user ids (unknown users)
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
          # unknown or unverified user - user unknown on other Gofreerev server <server_id> - use negative user id
          login_user_ids.push(-login_user.id)
        end
      end

      # build and validate json verify gifts server to server message
      message_hash = {
          :msgtype => 'verify_gifts',
          :mid => server_verify_gifts_mid[server_id],
          :login_users => login_user_ids,
          :verify_gifts => server_requests_hash[:server_requests] }
      logger.debug2 "verify_gifts message_hash = #{message_hash}"

      # check that json schema exists
      json_schema = :verify_gifts_request
      if !JSON_SCHEMA.has_key? json_schema

        # error message in log
        logger.error2 "Failed to sent gifts to remote verification. JSON schema #{json_schema} was not found"
        error = "System error. Failed to sent gifts to remote verification. JSON schema #{json_schema} was not found"

        # cleanup + return fatal json error in client_response_array
        logger.debug2 "Cleanup after JSON error and return error message to client"
        server_requests_hash[:json_error_info].each do |json_error_info|
          verify_comment, vc, vg = json_error_info
          logger.debug2 "server_id      = #{server_id}"
          logger.debug2 "verify_comment = #{verify_comment.to_json}"
          logger.debug2 "vc             = #{vc.to_json}"
          logger.debug2 "vg             = #{vg.to_json}"
          # return error message to client
          Gift.client_response_array_add(
              client_response_array,
              { :seq => verify_comment['seq'], :cid => verify_comment['cid'], :verified_at_server => false,
                :error => error, :key => 'no_json', :options => {:schema => json_schema} },
              client_sid, verify_comment)
          vc.destroy!
          vg.destroy!
        end

        next # unable to check json - don't send verify gifts server to server message

        # return Gift.format_error_response(
        #     { :error => "System error. Could not validate verify_gifts server to server message. JSON schema definition #{json_schema.to_s} was not found.",
        #       :key => 'no_json', :options => { :schema => json_schema} },
        #     client_sid, nil)

      end

      # check that json is valid
      json_errors = JSON::Validator.fully_validate(JSON_SCHEMA[json_schema], message_hash)
      if json_errors.size > 0

        # write error message in server log
        json_error = json_errors.join(', ')
        logger.error2 "Failed to sent gifts to remote verification. Error in #{json_schema}"
        logger.error2 "message = #{message_hash}"
        logger.error2 "json_schema = #{JSON_SCHEMA[json_schema]}"
        logger.error2 "errors = #{json_error}"
        error = "System error. Failed to sent gifts to remote verification. JSON error in verify_gifts server to server message: #{json_error}."

        # cleanup + return fatal json error in client_response_array
        logger.debug2 "Cleanup after JSON error and return error message to client"
        server_requests_hash[:json_error_info].each do |json_error_info|
          verify_comment, vc, vg = json_error_info
          logger.debug2 "server_id      = #{server_id}"
          logger.debug2 "verify_comment = #{verify_comment.to_json}"
          logger.debug2 "vc             = #{vc.to_json}"
          logger.debug2 "vg             = #{vg.to_json}"
          # return error message to client
          Gift.client_response_array_add(
              client_response_array,
              { :seq => verify_comment['seq'], :cid => verify_comment['cid'], :verified_at_server => false,
                :error => error, :key => 'invalid_json', :options => {:schema => json_schema, :error => json_error} },
              client_sid, verify_comment)
          vc.destroy!
          vg.destroy!
        end # server_requests_hash[:json_error_info] loop

        next # don't send invalid verify gifts server to server message

        # return Gift.format_error_response(
        #     { :error => "Failed to create verify_gifts server to server message: #{json_errors.join(', ')}",
        #       :key => 'invalid_json', :options => { :schema => json_schema, :error => error} },
        #     client_sid, nil)

      end # if

      # save mix encrypted server to server message - will be sent in next server to server ping
      key, message = servers[server_id].mix_encrypt_message_hash message_hash
      m = Message.new
      m.from_did = SystemParameter.did
      m.to_did = servers[server_id].new_did
      m.server = true
      m.mid = server_verify_comments_mid[server_id]
      m.key = key
      m.message = message
      m.save!

    end # server_verify_gifts_requests loop


    return nil if client_response_array.size == 0
    client_response_array.size == 0 ? nil : { :comments => client_response_array }

  rescue InvalidResponse => e
    # exception in Comment.client_response_array_push - invalid response format
    logger.debug2 "Exception: #{e.message.to_s} (#{e.class})"
    logger.debug2 "Backtrace: " + e.backtrace.join("\n")
    return { :error => e.message }
  end # self.verify_comments


end # Comment
