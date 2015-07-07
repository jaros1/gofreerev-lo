class Gift < ActiveRecord::Base

  # create_table "gifts", force: true do |t|
  #   t.string "gid",             limit: 20, null: false
  #   t.string "sha256",          limit: 45, null: false
  #   t.string "sha256_deleted",  limit: 45
  #   t.string "sha256_accepted", limit: 45
  #   t.date   "last_request_at"
  # end
  # add_index "gifts", ["gid"], name: "index_gifts_on_gid", unique: true, using: :btree


  ##############
  # attributes #
  ##############

  # 1) gid - required - readonly
  validates_presence_of :gid
  validates_uniqueness_of :gid
  attr_readonly :gid

  # 2) sha256 - required - readonly

  # 3) sha256_deleted - added when gift is deleted - readonly

  # 4) sha256_accepted - added when deal is accepted - readonly

  # 5) last_request_at - date stamp - cleanup not used gifts



  #
  # helper methods
  #


  def visible_for? (users)
    if ![Array, ActiveRecord::Relation::ActiveRecord_Relation_User].index(users.class)
      return false
    elsif users.length == 0
      return false
    elsif deleted_at
      return false
    else
      # check if user is giver or receiver
      api_gifts.each do |api_gift|
        user = users.find { |user2| user2.provider == api_gift.provider }
        next unless user
        return true if [api_gift.user_id_receiver, api_gift.user_id_giver].index(user.user_id)
      end
      # check if giver or receiver is a friend
      api_gifts.each do |api_gift|
        user = users.find { |user2| user2.provider == api_gift.provider }
        next unless user
        return true if user.app_friends.find { |f| [api_gift.user_id_receiver, api_gift.user_id_giver].index(f.user_id_receiver) }
      end
    end
    false
  end

  # visible_for


  # return last 4 comments for gifts/index page if first_comment_id is nil
  # return next 10 old comments in ajax request ii first_comment_id is not null
  # used in gifts/index (html/first_comment_id == nil) and in comments/comments (ajax/first_comment_id != nil)
  def api_comments_with_filter (login_users, first_comment_id = nil)
    # keep one api comment for each comment (multi provider comments).
    # sort:
    # 1) comments from friends
    # 2) comments from friends of friends (clickable user div)
    # 3) random sort
    logger.debug2 "get comments for gift id #{id}. sort"
    acs = api_comments
              .includes(:user, :comment)
              .where('comments.deleted_at is null')
              .references(:comments)
              .sort_by { |ac| [ac.user.friend?(login_users), ac.comment.id, rand] }
    # keep one api comment for each comment
    logger.debug2 "get comments for gift id #{id}. remove doubles"
    old_comment_id = '#' * 20
    acs = acs.find_all do |ac|
      if ac.comment_id == old_comment_id
        false
      else
        old_comment_id = ac.comment_id
        true
      end
    end
    # sort by created at
    # acs = acs.sort { |a,b| a.created_at <=> b.created_at }
    # acs = acs.sort_by { |ac| ac.created_at }
    # remember number of older comments. For show older comments link
    (0..(acs.length-1)).each { |i| acs[i].no_older_comments = i }
    # start be returning up to 4 comments for each gift
    return acs.last(4) if first_comment_id == nil
    # show older comments - return next 10 older comments
    index = acs.find_index { |ac| ac.comment.id.to_s == first_comment_id.to_s }
    # logger.debug2  "index = #{index}"
    return [] if index == nil or index == 0
    acs[0..(index-1)].last(10)
  end

  # comments_with_filter


  # display new deal check box?
  # only for open deals - and not for users deals (user is giver or receiver)
  def show_new_deal_checkbox? (users)
    logger.debug2 "users.class = #{users.class}"
    return false unless [Array, ActiveRecord::Relation::ActiveRecord_Relation_User].index(users.class) and users.size > 0
    return false if User.dummy_users?(users)
    count = 0
    api_gifts.each do |api_gift|
      user = users.find { |user2| user2.provider == api_gift.provider }
      next unless user
      count += 1
      return false if api_gift.user_id_giver == user.user_id
      return false if api_gift.user_id_receiver == user.user_id
    end # each
    raise "gift #{id} without api gifts for login user(s)" unless count > 0
    true
  end

  # show_new_deal_checkbox?

  def show_delete_gift_link? (users)
    api_gifts.each do |api_gift|
      user = users.find { |user2| user2.provider == api_gift.provider }
      next unless user
      return true if [api_gift.user_id_giver, api_gift.user_id_receiver].index(user.user_id)
    end
    return false
  end

  # show_delete_gift_link?

  def show_hide_gift_link? (users)
    !show_delete_gift_link?(users)
  end

  # show_hide_gift_link?


  # psydo attributea
  attr_accessor :file

  attr_accessor :datatype


  # todo: there is a problem with api gifts without gifts.
  def self.check_gift_and_api_gift_rel
    giftids = nil
    uncached do
      giftids = (ApiGift.all.collect { |ag| ag.gid } - Gift.all.collect { |g| g.gid }).uniq
    end
    return if giftids.size == 0
    logger.fatal2 "ApiGift without Gift. gift id's #{giftids.join(', ')}"
    raise "ApiGift without Gift. gift id's #{giftids.join(', ')}" # email from exception notifier
    # Process.kill('INT', Process.pid) # stop rails server
  end

  # receive list with newly gifts from client,
  # verify user ids, generate a sha256 digest, save gifts and return created_at_server = true/false to client
  # note that created_at_server is an boolean in this response but is an integer (server number) on client. 1 = this server
  # gift.sha256 digest is used as a control when replicating gifts between clients
  # todo line 1: use short internal user id (sequence) or use full user id (uid+provider) in client js gifts array?
  # todo line 2  the app should support replication gift from device a on app server 1 to device b on app server 2
  # todo line 3  but internal user ids can not be used across two different gofreerev-lo servers
  def self.new_gifts (new_gifts, login_user_ids)
    # logger.debug2 "new_gifts = #{new_gifts}"
    # logger.debug2 "login_user_ids = #{login_user_ids}"
    msg = "Could not create gift signature on server. "
    # check params
    return if !new_gifts or new_gifts.size == 0 # ignore empty new gifts request

    # check logged in users - should never fail
    if login_user_ids.class != Array or login_user_ids.size == 0
      # system error - util/ping + Gift.new_gifts should only be called with logged in users.
      return {:error => "#{msg}System error. Expected array with one or more login user ids."}
    end
    # order by user id - order is used in sha256 server signature
    login_users = User.where(:user_id => login_user_ids).order('user_id')
    if login_users.size < login_user_ids.size
      return {:error => "#{msg}System error. Invalid login. Expected #{login_user_ids.size} users. Found #{login_users.size} users."}
    end
    # logger.debug2 "login user ids = " + login_users.collect { |u| u.id }.join(', ')
    login_providers = login_users.collect { |u| u.provider }
    # logger.debug2 "login users internal ids = " + login_users.collect { |u| u.id }.join(', ')

    # check and create sha256 digest signatures for new gifts
    # returns created_at_server = true or an error message for each gid
    new_gifts.shuffle!
    response = []
    no_errors = 0
    # new gifts array has already been json schema validated to some extend
    new_gifts.each do |new_gift|
      # check new_gift hash: gid, sha256 and either a giver_user_ids array or a receiver_user_ids array
      gid = new_gift['gid'].to_s
      sha256_client = new_gift['sha256'].to_s
      # check giver/receiver user ids. Must have either giver or receiver but not both
      if new_gift.has_key?('giver_user_ids') and new_gift['giver_user_ids'].class == Array and new_gift['giver_user_ids'].size > 0
        giver_user_ids = new_gift['giver_user_ids']
      else
        giver_user_ids = nil
      end
      if new_gift.has_key?('receiver_user_ids') and new_gift['receiver_user_ids'].class == Array and new_gift['receiver_user_ids'].size > 0
        receiver_user_ids = new_gift['receiver_user_ids']
      else
        receiver_user_ids = nil
      end
      if !giver_user_ids and !receiver_user_ids
        response << {:gid => gid, :created_at_server => false, :error => "#{msg}giver_user_ids or receiver_user_ids property was missing"}
        no_errors += 1
        next
      end
      if giver_user_ids and receiver_user_ids
        response << {:gid => gid, :created_at_server => false, :error => "#{msg}both giver_user_ids and receiver_user_ids properties are not allowed for a new gift."}
        no_errors += 1
        next
      end

      # check authorization. login user ids from rails session and gift user ids from client must match.
      # can fail if social network logins has changed between time when gift was created at client and gifts upload to server (offline client)
      direction = giver_user_ids ? 'giver' : 'receiver'
      gift_user_ids = (giver_user_ids || receiver_user_ids).uniq
      # logger.debug2 "gid = #{gid}, direction = #{direction}, gift_user_ids = #{gift_user_ids}"
      signature_users = login_users.find_all { |u| gift_user_ids.index(u.id) }
      if signature_users.size == gift_user_ids.size
        # authorization ok. create server side sha256 digest signature
        sha256_server_text = ([gid, sha256_client, direction] + signature_users.collect { |u| u.user_id }).join(',')
        sha256_server = Base64.encode64(Digest::SHA256.digest(sha256_server_text))
        logger.debug2 "sha256_server = #{sha256_server}"
        g = Gift.find_by_gid(gid)
        if g
          # gift already exists - check signature
          if g.sha256 == sha256_server
            response << {:gid => gid, :created_at_server => true}
          else
            response << {:gid => gid, :created_at_server => false, :error => "#{msg}Gift exists but sha256 signature is invalid."}
            no_errors += 1
          end
          next
        end
        g = Gift.new
        g.gid = gid
        g.sha256 = sha256_server
        g.save!
        response << {:gid => gid, :created_at_server => true}
        # logger.debug2 "new gift #{gid} was created. sha256_server_text = #{sha256_server_text}, sha256_server = #{sha256_server}, g.sha256 = #{g.sha256}"
        # g.reload
        # logger.debug2 "g.sha256 after reload = #{g.sha256}"
        next
      end

      # authorization error. maybe api log out on client before new gift signature was created on server.
      missing_login_user_ids = gift_user_ids - login_users.collect { |u| u.id }
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
        response << {:gid => gid, :created_at_server => false,
                     :error => "#{msg}Log in has changed for #{changed_login_providers.join('. ')} since gift was created. Please log in with old #{changed_login_providers.join('. ')} user."}
      else
        response << {:gid => gid, :created_at_server => false,
                     :error => "#{msg}Log out for #{missing_login_providers.join('. ')} since gift was created. Please log in for #{missing_login_providers.join('. ')}."}
      end
      no_errors += 1

    end
    return {:gifts => response, :no_errors => no_errors}
  end # self.new_gifts


  # verify gifts request from client - used when receiving new gifts from other clients - check server side sha256 signature and return true or false
  # sha256 is required and must be valid
  # sha256_deleted and sha256_accepted are optional in request and are validated if supplied
  # client must supply sha256_accepted in request if gift has been accepted
  # client must supply sha256_deleted in request if gift has been deleted
  # params:
  # - verify_gifts: array - see verify_gifts array in JSON_SCHEMA[:ping_request]
  # - login_user_ids: from session :user_ids array - logged in users
  # - client_sid: from client ping - unique session id (one did can have multiple sids) = browser tab
  # - client_sha256: from client ping - mailbox sha256 signature - changes when api provider login changes
  # ( client_sid + client_sha256 is used as unique session id when sending and receiving remote gift verifications )
  # - not null client_sid and client_sha256 - called from util_controller.ping
  # - null client_sid and client_sha256 - called from Server.receive_verify_gifts_request (remote gift action)
  def self.verify_gifts (verify_gifts, login_user_ids, client_sid, client_sha256)
    logger.debug2 "verify_gifts = #{verify_gifts.to_json}"
    logger.debug2 "login_user_ids = #{login_user_ids.to_json}"
    if !verify_gifts
      # empty verify gifts ping from client - any remote verify gift responses ready for client?
      vgs = VerifyGift.where("client_sid = ? and client_sha256 = ? and verified_at_server is not null", client_sid, client_sha256)
      return nil if vgs.size == 0
      logger.debug2 "vgs.size = #{vgs.size}"
      response = {
          :gifts => vgs.collect do |vg|
            logger.debug2 "vg = #{vg.to_json}" if vg.error
            hash = {
                :seq => vg.client_seq,
                :gid => vg.gid,
                :verified_at_server => vg.verified_at_server
            }
            hash[:error] = vg.error unless vg.verified_at_server # only english :error format error messages in cross server communication
            hash
          end
      }
      vgs.delete_all
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
    # cache gifts (get previous server side sha256 signature and created_at timestamp)
    # cache servers (secrets for remote user sha256 signatures)
    users = {} # id => user
    gifts = {} # gid => gift
    gids = []
    gifts_user_ids = []
    seqs = {}
    server_ids = []
    servers = {}
    verify_gifts.each do |new_gift|
      seq = new_gift["seq"]
      return { :error => 'Invalid verify gifts request. Seq in gifts array must be unique' } if seqs.has_key? seq
      seqs[seq] = true
      gids << new_gift["gid"]
      gifts_user_ids += new_gift["giver_user_ids"] if new_gift["giver_user_ids"]
      gifts_user_ids += new_gift["receiver_user_ids"] if new_gift["receiver_user_ids"]
      server_id = new_gift['server_id']
      server_ids << server_id if server_id and !server_ids.index(server_id)
    end
    Gift.where(:gid => gids.uniq).each { |g| gifts[g.gid] = g }
    User.where(:id => gifts_user_ids.uniq).includes(:server_users).each { |u| users[u.id] = u }
    Server.where(:id => server_ids).each { |s| servers[s.id] = s } if server_ids.size > 0

    response = []
    server_requests = {} # server_id => array with remote gift verification request

    server_mid = {}

    # loop for each gift aciton in verify gifts request
    verify_gifts.each do |verify_gift|
      seq = verify_gift['seq']
      server_id = verify_gift['server_id']
      gid = verify_gift['gid']
      action = verify_gift['action']

      action_failed = "#{action} gift action failed"

      if server_id
        # remote gift action
        if seq >= 0
          error = "#{action_failed}. Invalid request. seq must be negative for remote gift verification"
          logger.error2 "gid #{gid} : #{error}"
          response << { :seq => seq, :gid => gid, :verified_at_server => false, :error => error, :key => 'gift_syserr_neq_seq' }
          next
        end
        if action == 'create'
          error = "#{action_failed}. Invalid request. create gift on other Gofreerev server is not allowed. server id = #{server_id}"
          logger.error2 "gid #{gid} : #{error}"
          response << { :seq => seq, :gid => gid, :verified_at_server => false, :error => error, :key => 'gift_create_remote', :options => {:server_id => server_id} }
          next
        end
        if !servers.has_key? server_id
          error = "#{action_failed}. Invalid request. Unknown server id #{server_id}"
          logger.error2 "gid #{gid} : #{error}"
          response << { :seq => seq, :gid => gid, :verified_at_server => false, :error => error, :key => 'gift_syserr_server_id', :options => {:server_id => server_id} }
          next
        end
      else
        # local gift verification
        if seq < 0
          error = "#{action_failed}. Invalid request. seq must be postive for local gift actions"
          logger.error2 "gid #{gid} : #{error}"
          response << { :seq => seq, :gid => gid, :verified_at_server => false, :error => error, :key => 'gift_syserr_pos_seq' }
          next
        end
      end

      # validate row in gift action request
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
      if (giver_user_ids.size == 0) and (receiver_user_ids.size == 0)
        error = "#{action_failed}. Invalid request. Giver user ids and receiver user ids are missing"
        logger.error2 "gid #{gid} : #{error}"
        response << { :seq => seq, :gid => gid, :verified_at_server => false, :error => error, :key => 'gift_syserr_giver_receiver' }
        next
      end
      if (action == 'create') and (giver_user_ids.size > 0) and (receiver_user_ids.size > 0)
        error = "#{action_failed}. Invalid request. Giver AND receiver are not allowed for action create"
        logger.error2 "gid #{gid} : #{error}"
        response << { :seq => seq, :gid => gid, :verified_at_server => false, :error => error, :key => 'gift_create_giver_receiver' }
        next
      end
      if (action == 'accept') and ((giver_user_ids.size == 0) or (receiver_user_ids.size == 0))
        error = "#{action_failed}. Invalid request. Giver and receiver are required for action accept"
        logger.error2 "gid #{gid} : #{error}"
        response << { :seq => seq, :gid => gid, :verified_at_server => false, :error => error, :key => 'gift_accept_giver_receiver' }
        next
      end
      if giver_user_ids.size != giver_user_ids.uniq.size
        error = "#{action_failed}. Invalid request. User ids in giver user ids list must be unique"
        logger.error2 "gid #{gid} : #{error}"
        response << { :seq => seq, :gid => gid, :verified_at_server => false, :error => error, :key => 'gift_syserr_uniq_giver' }
        next
      end
      if receiver_user_ids.size != receiver_user_ids.uniq.size
        error = "#{action_failed}. Invalid request. User ids in receiver user ids list must be unique"
        logger.error2 "gid #{gid} : #{error}"
        response << { :seq => seq, :gid => gid, :verified_server => false, :error => error, :key => 'gift_syserr_uniq_receiver' }
        next
      end

      if verify_gift["sha256_accepted"].to_s != ''
        # sha256_accepted signature in request
        if action == 'create'
          error = "#{action_failed}. Invalid request. sha256_accepted signature is not allowed for create gift action"
          logger.error2 "gid #{gid} : #{error}"
          response << { :seq => seq, :gid => gid, :verified_server => false, :error => error, :key => 'gift_create_sha256_accepted' }
          next
        end
        if giver_user_ids.size == 0
          error = "#{action_failed}. Invalid request. Giver user ids are missing for accepted gift"
          logger.error2 "gid #{gid}. #{error}"
          response << { :seq => seq, :gid => gid, :verified_at_server => false, :error => error, :key => 'gift_syserr_giver1' }
          next
        end
        if receiver_user_ids.size == 0
          error = "#{action_failed}. Invalid request. Receiver user ids are missing for accepted gift"
          logger.error2 "gid #{gid}. #{error}"
          response << { :seq => seq, :gid => gid, :verified_at_server => false, :error => error, :key => 'gift_syserr_receiver1' }
          next
        end
      elsif action == 'accept'
        # no sha256_accepted signature in request (required for action accept)
        error = "#{action_failed}. Invalid request. sha256_accepted signature is missing for gift accept action"
        logger.error2 "gid #{gid}. #{error}"
        response << { :seq => seq, :gid => gid, :verified_at_server => false, :error => error, :key => 'gift_accept_sha256_accepted' }
        next
      end

      if verify_gift["sha256_deleted"].to_s != ''
        # sha256_deleted signature in request
        if action == 'create'
          error = "#{action_failed}. Invalid request. sha256_deleted signature is not allowed for create gift action"
          logger.error2 "gid #{gid} : #{error}"
          response << { :seq => seq, :gid => gid, :verified_server => false, :error => error, :key => 'gift_create_sha256_deleted' }
          next
        end
        if action == 'accept'
          error = "#{action_failed}. Invalid request. sha256_deleted signature is not allowed for accept gift action"
          logger.error2 "gid #{gid} : #{error}"
          response << { :seq => seq, :gid => gid, :verified_server => false, :error => error, :key => 'gift_accept_sha256_deleted' }
          next
        end
      elsif action == 'delete'
        # no sha256_deleted signature in request (required for action delete)
        error = "Invalid request. sha256_deleted signature is missing for gift delete action"
        logger.error2 "gid #{gid}. #{error}"
        response << { :seq => seq, :gid => gid, :verified_at_server => false, :error => error, :key => 'gift_delete_sha256_deleted' }
        next
      end

      # read, check and optional prepare giver and receiver user ids (sha256 user signatures are used instead of user ids when communication with other Gofreerev servers)
      # check mutual friends. gift must be from login user or to/from mutual friend
      mutual_friend = false
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
          mutual_friend = true if friend and friend <= 2
        else
          error = "#{action_failed}. Giver user with id #{user_id} was not found. Cannot check server sha256 signature for gift with unknown user ids"
          logger.warn2 "Gid #{gid} : #{error}"
          response << { :seq => seq, :gid => gid, :verified_at_server => false, :error => error, :key => 'gift_syserr_giver2', :options => { :user_id => user_id } }
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
          mutual_friend = true if friend and friend <= 2
        else
          error = "#{action_failed}. Receiver user with id #{user_id} was not found. Cannot check server sha256 signature for gift with unknown user ids"
          logger.warn2 "Gid #{gid} : #{error}"
          response << { :seq => seq, :gid => gid, :verified_at_server => false, :error => error, :key => 'gift_syserr_receiver2', :options => { :user_id => user_id } }
          receiver_error = true
          break
        end
      end if verify_gift["receiver_user_ids"]
      next if receiver_error
      if !mutual_friend
        # note that friend lists on two different Gofreerev servers can be out of sync and local check can succeed and remote check can fail.
        error = "#{action_failed}. Gift is not from a friend"
        logger.debug2 "Gid #{gid}: #{error}"
        response << { :seq => seq, :gid => gid, :verified_at_server => false, :error => error, :key => 'gift_syserr_friend' }
        next
      end
      receiver_user_ids.uniq! # todo: should return an error if doublets in receiver_user_ids array
      receiver_user_ids.sort! unless server_id

      if server_id
        # remote gift action (server to server gifts message)
        # todo: sha256 signatures on this gofreerev server can be out of date
        #       must keep verify_gift row from client if verify gift request must be resent after updated sha256 signature (giver and/or receiver)
        #       could also be used in a verify gift cache on this gofreerev server
        #       don't send identical verify gifts request to other gofreerev server. send answer from cache
        # insert row in verify_gifts table. Response is added in columns verified_at_server, error and response_mid. see Server.receive_verify_gifts_response
        server_mid[server_id] = Sequence.next_server_mid unless server_mid.has_key?(server_id)
        vg = VerifyGift.new
        vg.client_sid = client_sid
        vg.client_sha256 = client_sha256
        vg.client_seq = seq
        vg.server_id = server_id
        vg.gid = gid
        vg.server_seq = Sequence.next_verify_seq
        vg.request_mid = server_mid[server_id]
        vg.save!
        # 2) insert verify_gifts request in server_requests hash
        hash = {:seq => vg.server_seq,
                :gid => gid,
                :sha256 => verify_gift["sha256"]}
        hash[:sha256_deleted] = verify_gift["sha256_deleted"] if verify_gift["sha256_deleted"]
        hash[:sha256_accepted] = verify_gift["sha256_accepted"] if verify_gift["sha256_accepted"]
        hash[:giver_user_ids] = giver_user_ids if giver_user_ids.size > 0
        hash[:receiver_user_ids] = receiver_user_ids if receiver_user_ids.size > 0
        server_requests[server_id] = [] unless server_requests.has_key? server_id
        server_requests[server_id].push(hash)
        next
      end

      # local gift action validation

      # check if gift exists
      gift = gifts[gid]
      if action == 'create'
        if gift
          logger.warn2 "warning. action is create but gid #{gid} already exists. continuing with validations only"
        end
      else
        if !gift
          error = "#{action_failed}. Gift was not found"
          logger.warn2 "gid #{gid}. #{error}"
          response << { :seq => seq, :gid => gid, :verified_at_server => false, :error => error, :key => 'gift_syserr_not_found' }
          next
        end
      end

      # calculate and check server side sha256 gift signature (direction = creator of gift)
      sha256_client = verify_gift["sha256"]
      direction = nil
      if giver_user_ids.size > 0
        sha256_input = ([gid, sha256_client, 'giver'] + giver_user_ids).join(',')
        sha256_calc = Base64.encode64(Digest::SHA256.digest(sha256_input))
        direction = 'giver' if (gift and (gift.sha256 == sha256_calc)) or ((action == 'create') and !gift)
        # logger.debug "sha256 check failed with direction = giver. sha256_input = #{sha256_input}, sha256_calc = \"#{sha256_calc}\", gift.sha256 = \"#{gift.sha256 if gift}\"" unless direction
      end
      if receiver_user_ids.size > 0
        sha256_input = ([gid, sha256_client, 'receiver'] + receiver_user_ids).join(',')
        sha256_calc = Base64.encode64(Digest::SHA256.digest(sha256_input))
        direction = 'receiver' if (gift and (gift.sha256 == sha256_calc)) or ((action == 'create') and !gift)
        # logger.debug "sha256 check failed with direction = receiver. sha256_input = #{sha256_input}, sha256_calc = \"#{sha256_calc}\", gift.sha256 = \"#{gift.sha256 if gift}\"" unless direction
      end
      if !direction
        error = "#{action_failed}. Invalid request. sha256 signature check failed for #{action} gift action"
        logger.debug2 "Gid #{gid} : #{error}"
        response << { :seq => seq, :gid => gid, :verified_at_server => false, :error => error, :key => "gift_#{action}_sha256", :options => { :action => action} }
        next
      end

      # sha256_accepted: if supplied - calculate and check server side sha256_accepted signature
      # old server sha256_accepted signature was generated when gift was accepted and deal was closed
      # calculate and check sha256_accepted signature from information received in verify gifts request
      sha256_accepted_client = verify_gift["sha256_accepted"]
      if sha256_accepted_client.to_s != ''
        # sha256_accepted in request. must be an accepted gift or an accept gift action
        if !gift.sha256_accepted and action != 'accept'
          error = "#{action_failed}. sha256_accepted signature in request but gift dont have a sha256_accepted signature on server"
          logger.warn2 "Gid #{gid} : #{error}"
          response << { :seq => seq, :gid => gid, :verified_at_server => false, :error => error, :key => 'gift_syserr_not_accepted', :options => {:action => action} }
          next
        end
        if gift.sha256_deleted and action == 'accept'
          error = "#{action_failed}. Gift has already been deleted"
          logger.warn2 "Gid #{gid} : #{error}"
          response << { :seq => seq, :gid => gid, :verified_at_server => false, :error => error, :key => 'gift_accept_deleted', :options => {:action => action} }
          next
        end
        sha256_accepted_input = ([gid, sha256_accepted_client, direction] + giver_user_ids + ['/'] + receiver_user_ids).join(',')
        sha256_accepted_calc = Base64.encode64(Digest::SHA256.digest(sha256_accepted_input))
        # sha256_accepted signature must match or request must be an accept gift action
        if !((gift.sha256_accepted == sha256_accepted_calc) or (!gift.sha256_accepted and (action == 'accept')))
          error = "#{action_failed}. Invalid sha256_accepted signature"
          logger.warn2 "Gid #{gid} : #{error}. new calculated sha256_accepted signature = #{sha256_accepted_calc}. old sha256_accepted signature on server = #{gift.sha256_accepted if gift}"
          response << {:seq => seq, :gid => gid, :verified_at_server => false, :error => error, :key => "gift_syserr_sha256_accepted", :options => {:action => action}}
          next
        end
      else
        # blank sha256_accepted in request.
        # ok for create and verify. not ok for accept but this has already been tested. not ok to delete an accept gift without a sha256_accepted signature in request
        if action == 'delete' and gift.sha256_accepted
          error = "#{action_failed}. Gift has a sha256_accepted server signature but sha256_accepted is missing in request"
          logger.warn2 "Gid #{gid} : #{error}"
          response << {:seq => seq, :gid => gid, :verified_at_server => false, :error => error, :key => 'gift_syserr_sha256_accepted_required', :options => { :action => action} }
          next
        end
      end

      # sha256_deleted: if supplied - calculate and check server side sha256_deleted signature
      # old server sha256_deleted signature was generated when gift previously was deleted
      # calculate and check sha256_deleted signature from information received in verify gifts request
      sha256_deleted_client = verify_gift["sha256_deleted"]
      if sha256_deleted_client.to_s != ''
        # sha256_deleted signature in request. must be a deleted gift or an delete gift action in progress
        if !gift.sha256_deleted and (action != 'delete')
          error = "#{action_failed}. sha256_deleted signature in request but gift has not been deleted (no deleted signature on server)"
          logger.warn2 "Gid #{gid} : #{error}"
          response << { :seq => seq, :gid => gid, :verified_at_server => false, :error => error, :key => 'gift_syserr_not_deleted', :options => {:action => action} }
          next
        end
        if gift.sha256_accepted and (sha256_accepted_client.to_s == '')
          error = "#{action_failed}. sha256_deleted signature in request but gift has previously been accepted and sha256 accepted signature was missing in request"
          logger.warn2 "Gid #{gid} : #{error}"
          response << {:seq => seq, :gid => gid, :verified_at_server => false, :error => error, :key => 'gift_syserr_sha256_accepted_required', :options => { :action => action} }
          next
        end
        sha256_deleted_input = ([gid, sha256_deleted_client, direction] + giver_user_ids + ['/'] + receiver_user_ids).join(',')
        sha256_deleted_calc = Base64.encode64(Digest::SHA256.digest(sha256_deleted_input))
        # sha256_deleted signature must match or request must be a delete gift action
        if !((gift.sha256_deleted == sha256_deleted_calc) or (!gift.sha256_deleted and (action == 'delete')))
          error = "#{action_failed}. Invalid sha256_deleted signature"
          logger.warn2 "Gid #{gid} : #{error}. new sha256_deleted calculation = #{sha256_deleted_calc}. old sha256_deleted on server = #{gift.sha256_deleted}."
          response << { :seq => seq, :gid => gid, :verified_at_server => false, :error => error, :key => 'gift_syserr_sha256_deleted', :options => {:action => action} }
        end
        logger.warn2 "warning. action was delete but gift #{gid} has already been deleted" if (action == 'delete') and gift.sha256_deleted
      end

      # no errors

      # do gift action
      case action
        when 'create'
          gift = Gift.new unless gift
          gift.gid = gid unless gift.gid
          gift.sha256 = sha256_calc
          gift.save!
        when 'verify'
          nil
        when 'accept'
          gift.update_attribute :sha256_accepted, sha256_accepted_calc
        when 'delete'
          gift.update_attribute :sha256_deleted, sha256_deleted_calc
      end # case

      # ok response for client
      response << { :seq => seq, :gid => gid, :verified_at_server => true }

    end # each new_gift

    # any remote verify gift responses ready for this client?
    vgs = VerifyGift.where("client_sid = ? and client_sha256 = ? and verified_at_server is not null", client_sid, client_sha256)
    if vgs.size > 0
      logger.debug2 "vgs.size = #{vgs.size}"
      vgs.each do |vg|
        logger.debug2 "vg = #{vg.to_json}" if vg.error
        hash = {:seq => vg.client_seq,
                :gid => vg.gid,
                :verified_at_server => vg.verified_at_server}
        hash[:error] = vg.error unless vg.verified_at_server # only english :error format error messages in cross server communication
        response.push(hash)
      end
      vgs.delete_all
    end

    logger.debug2 "response = #{response}"
    logger.debug2 "server_requests = #{server_requests}"

    # send any server to server verify gifts messages
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
          :msgtype => 'verify_gifts',
          :mid => server_mid[server_id],
          :login_users => login_user_ids,
          :verify_gifts => server_request }
      logger.debug2 "verify_gifts message = #{message}"
      # validate json message before sending
      json_schema = :verify_gifts_request
      if !JSON_SCHEMA.has_key? json_schema
        return { :error => "Could not validate verify_gifts server to server message. JSON schema definition #{json_schema.to_s} was not found." }
      end
      json_errors = JSON::Validator.fully_validate(JSON_SCHEMA[json_schema], message)
      if json_errors.size > 0
        logger.error2 "Failed to sent gifts to remote verification. Error in #{json_schema}"
        logger.error2 "message = #{message}"
        logger.error2 "json_schema = #{JSON_SCHEMA[json_schema]}"
        logger.error2 "errors = #{json_errors.join(', ')}"
        return { :error => "Failed to create verify_gifts server to server message: #{json_errors.join(', ')}" }
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
    # - local client ping, util_controller.ping, client_sid is not null, use :key+:options error format (multi-language)
    # - remote gift action, Server.receive_verify_gifts_request, client_sid is null, use :error error format (english only)
    if client_sid
      # local client ping. use :key+:options error format (multi-language support)
      response.each do |row|
        row.delete(:error) if !row[:verified_at_server] and row[:error]
      end
    else
      # remote gift action. use :error error format (english only)
      response.each do |row|
        next if row[:verified_at_server]
        row.delete(:key) if row[:key]
        row.delete(:options) if row[:options]
      end
    end
    { :gifts => response }

  end # self.verify_gifts


  # delete gifts request from client - used after gift has been deleted on client - check server side sha256 signature and return true or false
  # sha256 is required and must be valid
  # sha256_deleted is required and is used in server side sha256_deleted signature
  # sha256_accepted is optional but must be in request if gift has been accepted by an other user
  # login user must be giver or receiver of gift
  def self.delete_gifts (delete_gifts, login_user_ids)
    logger.debug2 "delete_gifts = #{delete_gifts.to_json}"
    logger.debug2 "login_user_ids = #{login_user_ids.to_json}"
    # new_gifts = [{"gid":"14239781115388288755","sha256":";¯\u000B6\"r\u0000\u00114»í?@A'b_O\u0017ra\u0007Á3ßx","giver_user_ids":[920],"receiver_user_ids":null,"seq":1},
    #              {"gid":"14239781115388735516","sha256":"Zøl¦_µÿ|t\u0000#*Ï\u0017=Úö´VQ­À^Bõ@°Y","giver_user_ids":[920],"receiver_user_ids":null,"seq":2}]
    # login_user_ids = ["78951805/foursquare","1092213433/instagram","1705481075/facebook"]

    return unless delete_gifts

    # get internal ids for logged in users - internal user ids are used in gift giver and receiver lists
    login_users = User.where(:user_id => login_user_ids)
    return { :error => 'System error. Not logged in. Delete gifts request is not allowed.'} if login_users.size == 0
    return { :error => 'System error. Invalid login user ids param in delete gifts request.'} if login_users.size != login_user_ids.size
    login_user_ids = login_users.collect { |u| u.id }

    # cache gifts and users in delete gifts request
    gids = []
    gifts_user_ids = []
    delete_gifts.each do |delete_gift|
      gid = delete_gift["gid"]
      return { :error => 'Invalid delete gifts request. Gid in gifts array must be unique' } if gids.index(gid)
      gids << delete_gift["gid"]
      gifts_user_ids += delete_gift["giver_user_ids"] if delete_gift["giver_user_ids"]
      gifts_user_ids += delete_gift["receiver_user_ids"] if delete_gift["receiver_user_ids"]
    end
    gifts = {} # gid => gift
    Gift.where(:gid => gids.uniq).each { |g| gifts[g.gid] = g }.each { |g| gifts[g.gid] = g }
    users = {} # id => user_id
    User.where(:id => gifts_user_ids.uniq).each { |u| users[u.id] = u.user_id }

    # process delete gifts request
    response = []
    no_errors = delete_gifts.size # guilty until proven innocent
    first_gift = true
    delete_gifts.each do |delete_gift|

      # validate row in delete gift request
      if delete_gift["giver_user_ids"] and delete_gift["giver_user_ids"].size > 0
        giver_user_ids = delete_gift["giver_user_ids"].uniq
      else
        giver_user_ids = []
      end
      if delete_gift["receiver_user_ids"] and delete_gift["receiver_user_ids"].size > 0
        receiver_user_ids = delete_gift["receiver_user_ids"].uniq
      else
        receiver_user_ids = []
      end
      if giver_user_ids.size == 0 and receiver_user_ids.size == 0
        response << { :gid => gid, :deleted_at_server => false, :error => 'Invalid request. Giver user ids and receiver user ids are missing.'}
        next
      end
      if giver_user_ids.size != giver_user_ids.uniq.size
        response << { :gid => gid, :deleted_at_server => false, :error => 'Invalid request. User ids in giver user ids list must be unique'}
        next
      end
      if receiver_user_ids.size != receiver_user_ids.uniq.size
        response << { :gid => gid, :deleted_at_server => false, :error => 'Invalid request. User ids in receiver user ids list must be unique'}
        next
      end

      if delete_gift["sha256_accepted"]
        if giver_user_ids.size == 0
          response << { :gid => gid, :deleted_at_server => false, :error => 'Invalid request. Giver user ids are missing for accepted gift'}
          next
        end
        if receiver_user_ids.size == 0
          response << { :gid => gid, :deleted_at_server => false, :error => 'Invalid request. Receiver user ids are missing for accepted gift'}
          next
        end
      end

      # check login - minimum one api login as giver or receiver is required
      gift_user_ids = (giver_user_ids + receiver_user_ids).uniq
      if (login_user_ids & gift_user_ids).size == 0
        logger.debug2 "gid #{gid} delete not allowed"
        response << { :gid => gid, :deleted_at_server => false, :error => 'You are not authorized to delete this gift' }
        next
      end

      # todo: add server_id (delete remote gift). same process flow as in verify remote gift
      
      # translate user ids from internal id (sequence) to uid/provider format before sha256 signature calculations
      giver_user_ids = giver_user_ids.collect do |id|
        user_id = users[id]
        if !user_id
          response << { :gid => gid, :deleted_at_server => false, :error => "Invalid request. Unknown internal giver user id #{id}" }
          next
        end
        user_id
      end.sort
      receiver_user_ids = receiver_user_ids.collect do |id|
        user_id = users[id]
        if !user_id
          response << { :gid => gid, :deleted_at_server => false, :error => "Invalid request. Unknown internal receiver user id #{id}" }
          next
        end
        user_id
      end.sort

      # check if gift exists
      gid = delete_gift["gid"]
      gift = gifts[gid]
      if !gift
        # gift not found!
        # todo: how to implement cross server gift sha256 signature validation?
        logger.debug2 "gid #{gid} was not found"
        response << { :gid => gid, :deleted_at_server => false, :error => 'Gift was not found on server' }
        next
      end

      # # todo: remove. test how client is handling undelete
      # if first_gift
      #   gid = '14258041591425804159'
      #   response << { :gid => gid, :deleted_at_server => false, :error => 'Test undelete on client after failed server delete' }
      #   first_gift = false
      #   next
      # end

      # ready for sha256 signatures calculation and check (sha256, sha256_accepted (optional) and sha256_deleted)

      # old server sha256 signature was generated when gift was created
      # calculate and check sha256 signature from information received in delete gifts row
      sha256_client = delete_gift["sha256"]
      direction = nil
      if giver_user_ids.size > 0
        sha256_input = ([gid, sha256_client, 'giver'] + giver_user_ids).join(',')
        sha256_calc = Base64.encode64(Digest::SHA256.digest(sha256_input))
        direction = 'giver' if gift.sha256 == sha256_calc # creator = giver
        # logger.debug2 "check 1 failed for #{gid}. sha256_server_text = #{sha256_server_text}, sha256_server = #{sha256_server}, gift.sha256 = #{gift.sha256}" unless direction
      end
      if receiver_user_ids.size > 0
        sha256_input = ([gid, sha256_client, 'receiver'] + receiver_user_ids).join(',')
        sha256_calc = Base64.encode64(Digest::SHA256.digest(sha256_input))
        direction = 'receiver' if gift.sha256 == sha256_calc # creator = receiver
        # logger.debug2 "check 2 failed for #{gid}. sha256_server_text = #{sha256_server_text}, sha256_server = #{sha256_server}, gift.sha256 = #{gift.sha256}" unless direction
      end
      if !direction
        response << { :gid => gid, :deleted_at_server => false, :error => 'Sha256 signature verification failed. Could be unauthorized changes in gift information' }
        next
      end

      # sha256_accepted: if supplied - calculate and check server side sha256_accepted signature
      # old server sha256_accepted signature was generated when gift was accepted and deal was closed
      # calculate and check sha256_accepted signature from information received in delete gifts request
      sha256_accepted_client = delete_gift["sha256_accepted"]
      if sha256_accepted_client
        error = 'Sha256_accepted signature verification failed. Could be unauthorized changes in gift information'
        if !gift.sha256_accepted
          logger.warn2 "Gift #{gid}. Delete gift request failed. #{error}. sha256_accepted in request but gift dont have a sha256_accepted signature on server."
          response << { :gid => gid, :deleted_at_server => false, :error => error }
          next
        end
        sha256_input = ([gid, sha256_accepted_client, direction] + giver_user_ids + ['/'] + receiver_user_ids).join(',')
        sha256_calc = Base64.encode64(Digest::SHA256.digest(sha256_input))
        if gift.sha256_accepted != sha256_calc
          logger.warn2 "Gift #{gid}. Delete gift request failed. #{error}. new sha256_accepted calculation = #{sha256_calc}. old sha256_accepted on server = #{gift.sha256_accepted}."
          response << { :gid => gid, :deleted_at_server => false, :error => error }
          next
        end
      elsif gift.sha256_accepted
        error = 'Delete gift failed. Gift has been accepted on an other device/browser. Please wait for update before deleting gift.'
        logger.debug2 error
        response << { :gid => gid, :deleted_at_server => false, :error => error }
      end

      # sha256_deleted: calculate server side sha256_deleted signature
      sha256_deleted_client = delete_gift["sha256_deleted"]
      if direction == 'giver'
        sha256_input = ([gid, sha256_deleted_client, 'giver'] + giver_user_ids).join(',')
      else
        sha256_input = ([gid, sha256_deleted_client, 'receiver'] + receiver_user_ids).join(',')
      end
      sha256_calc = Base64.encode64(Digest::SHA256.digest(sha256_input))
      if !gift.sha256_deleted
        gift.sha256_deleted = sha256_calc
        gift.save!
      end
      if gift.sha256_deleted == sha256_calc
        # ok - gift has been deleted previously with identical signature
        response << { :gid => gid, :deleted_at_server => true }
        no_errors -= 1
      else
        # error - gift has been deleted previously but signature input is invalid in this request
        response << { :gid => gid, :deleted_at_server => false, :error => 'Sha256_deleted signature verification failed. Could be unauthorized changes in gift information' }
      end

    end # each new_gift

    logger.debug2 "response = #{response}"
    { :no_errors => no_errors, :gifts => response }
  end # self.delete_gifts


end # Gift
