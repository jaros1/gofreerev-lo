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

    # common gift array JSON schema structure in new_gifts, verify_gifts, accept_gifts and delete_gifts
    # check that sha256_deleted and sha256_accepted is not in new_comments request
    new_gifts.each do |new_gift|
      if new_gift.has_key?("sha256_deleted")
        return {:error => "#{msg}System error. sha256_deleted is not allowed in new_gifts request."}
      end
      if new_gift.has_key?("sha256_accepted")
        return {:error => "#{msg}System error. sha256_accepted is not allowed in new_gifts request."}
      end
    end

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
  # login user must be friend with giver or receiver of gift
  def self.verify_gifts (new_gifts, login_user_ids)
    logger.debug2 "new_gifts = #{new_gifts.to_json}"
    logger.debug2 "login_user_ids = #{login_user_ids.to_json}"
    # new_gifts = [{"gid":"14239781115388288755","sha256":";¯\u000B6\"r\u0000\u00114»í?@A'b_O\u0017ra\u0007Á3ßx","giver_user_ids":[920],"receiver_user_ids":null,"seq":1},
    #              {"gid":"14239781115388735516","sha256":"Zøl¦_µÿ|t\u0000#*Ï\u0017=Úö´VQ­À^Bõ@°Y","giver_user_ids":[920],"receiver_user_ids":null,"seq":2}]
    # login_user_ids = ["78951805/foursquare","1092213433/instagram","1705481075/facebook"]

    return unless new_gifts

    # cache friends for login users - giver and/or receiver for gifts must be friend of login user
    login_users = User.where(:user_id => login_user_ids)
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
    users = {} # id => user_id
    gifts = {} # gid => gift
    gids = []
    gifts_user_ids = []
    seqs = {}
    new_gifts.each do |new_gift|
      seq = new_gift["seq"]
      return { :error => 'Invalid verify gifts request. Seq in gifts array must be unique' } if seqs.has_key? seq
      seqs[seq] = true
      gids << new_gift["gid"]
      gifts_user_ids += new_gift["giver_user_ids"] if new_gift["giver_user_ids"]
      gifts_user_ids += new_gift["receiver_user_ids"] if new_gift["receiver_user_ids"]
    end
    Gift.where(:gid => gids.uniq).each { |g| gifts[g.gid] = g }
    User.where(:id => gifts_user_ids.uniq).each { |u| users[u.id] = u.user_id }

    response = []
    new_gifts.each do |new_gift|
      seq = new_gift["seq"]
      sha256_client = new_gift["sha256"]

      # check if gift exists
      gid = new_gift["gid"]
      gift = gifts[gid]
      if !gift
        # gift not found -
        # todo: how to implement cross server gift sha256 signature validation?
        logger.debug2 "gid #{gid} was not found"
        response << { :seq => seq, :gid => gid, :created_at_server => false }
        next
      end

      # check mutual friends
      mutual_friend = false
      giver_user_ids = []
      new_gift["giver_user_ids"].each do |user_id|
        giver = users[user_id]
        if giver
          giver_user_ids << giver
          friend = friends[giver]
          mutual_friend = true if friend and friend <= 2
        else
          logger.warn2 "Gid #{gid} : Giver user with id #{user_id} was not found. Cannot check server sha256 signature for gift with unknown user ids."
          response << { :seq => seq, :gid => gid, :created_at_server => false }
          next
        end
      end if new_gift["giver_user_ids"]
      giver_user_ids.sort!
      receiver_user_ids = []
      new_gift["receiver_user_ids"].each do |user_id|
        receiver = users[user_id]
        if receiver
          receiver_user_ids << receiver
          friend = friends[receiver]
          mutual_friend = true if friend and friend <= 2
        else
          logger.warn2 "Gid #{gid} : Receiver user with id #{user_id} was not found. Cannot check server sha256 signature for gift with unknown user ids."
          response << { :seq => seq, :gid => gid, :created_at_server => false }
          next
        end
      end if new_gift["receiver_user_ids"]
      if !mutual_friend
        logger.debug2 "gid #{gid} is not from a friend"
        response << { :seq => seq, :gid => gid }
        next
      end
      giver_user_ids.sort!
      receiver_user_ids.sort!

      # calculate and check server side sha256 signature
      direction = nil
      if giver_user_ids.size > 0
        sha256_server_text = ([gid, sha256_client, 'giver'] + giver_user_ids).join(',')
        sha256_server = Base64.encode64(Digest::SHA256.digest(sha256_server_text))
        direction = 'giver' if gift.sha256 == sha256_server
      end
      if receiver_user_ids.size > 0
        sha256_server_text = ([gid, sha256_client, 'receiver'] + receiver_user_ids).join(',')
        sha256_server = Base64.encode64(Digest::SHA256.digest(sha256_server_text))
        direction = 'receiver' if gift.sha256 == sha256_server
      end
      if !direction
        response << { :seq => seq, :gid => gid, :created_at_server => false }
        next
      end

      # if supplied - calculate and check server side sha256_deleted signature

      # if supplied - calculate and check server side sha256_accepted signature

      # invalid signature. one or more fields in gift is invalid / has been changed by a client
      response << { :seq => seq, :gid => gid, :created_at_server => false }

    end # each new_gift

    logger.debug2 "response = #{response}"
    { :gifts => response }
  end # self.verify_gifts



  # delete gifts request from client - used after gift has been deleted on client - check server side sha256 signature and return true or false
  # sha256 is required and must be valid
  # sha256_deleted is required and is used in server side sha256_deleted signature
  # sha256_accepted is optional and should be in request if gift previously has been accepted by an other user (ekstra validation)
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
    delete_gifts.each do |delete_gift|

      # check if gift exists
      gid = delete_gift["gid"]
      gift = gifts[gid]
      if !gift
        # gift not found -
        # todo: how to implement cross server gift sha256 signature validation?
        logger.debug2 "gid #{gid} was not found"
        response << { :gid => gid, :deleted_at_server => false, :error => 'Gift was not found' }
        next
      end

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

      # check login - minimum one api login as giver or receiver is required
      gift_user_ids = (giver_user_ids + receiver_user_ids).uniq
      if (login_user_ids & gift_user_ids).size == 0
        logger.debug2 "gid #{gid} delete not allowed"
        response << { :gid => gid, :deleted_at_server => false, :error => 'Not authorized to delete this gift' }
        next
      end
      
      # translate user ids from internal id to uid/provider format before sha256 signature calculations
      giver_user_ids = giver_user_ids.collect do |id|
        user_id = users[id]
        if !user_id
          response << { :gid => gid, :deleted_at_server => false, :error => "System error. Unknown internal giver user id #{id} for gift" }
          next
        end
        user_id
      end.sort
      receiver_user_ids = receiver_user_ids.collect do |id|
        user_id = users[id]
        if !user_id
          response << { :gid => gid, :deleted_at_server => false, :error => "System error. Unknown internal receiver user id #{id} for gift" }
          next
        end
        user_id
      end.sort

      # new_gifts: sha256_server_text = ([gid, sha256_client, direction] + signature_users.collect { |u| u.user_id }).join(',')

      # old server sha256 signature was generated when gift was created
      # calculate and check sha256 signature from delete gifts request
      sha256_client = delete_gift["sha256"]
      direction = nil
      if giver_user_ids.size > 0
        sha256_server_text = ([gid, sha256_client, 'giver'] + giver_user_ids).join(',')
        sha256_server = Base64.encode64(Digest::SHA256.digest(sha256_server_text))
        direction = 'giver' if gift.sha256 == sha256_server # creator = giver
        # logger.debug2 "check 1 failed for #{gid}. sha256_server_text = #{sha256_server_text}, sha256_server = #{sha256_server}, gift.sha256 = #{gift.sha256}" unless direction
      end
      if receiver_user_ids.size > 0
        sha256_server_text = ([gid, sha256_client, 'receiver'] + receiver_user_ids).join(',')
        sha256_server = Base64.encode64(Digest::SHA256.digest(sha256_server_text))
        direction = 'receiver' if gift.sha256 == sha256_server # creator = receiver
        # logger.debug2 "check 2 failed for #{gid}. sha256_server_text = #{sha256_server_text}, sha256_server = #{sha256_server}, gift.sha256 = #{gift.sha256}" unless direction
      end
      if !direction
        response << { :gid => gid, :deleted_at_server => false, :error => 'Delete gift request failed. Unauthorized change in gift (sha256 signature)' }
        next
      end

      # sha256_accepted: if supplied - calculate and check server side sha256_accepted signature
      # old server sha256_accepted signature was generated when gift was accepted / deal was closed
      # calculate and check sha256_accepted signature from delete gifts request
      sha256_accepted_client = delete_gift["sha256_accepted"]
      if sha256_accepted_client
        if !gift.sha256_accepted
          response << { :gid => gid, :deleted_at_server => false, :error => 'Delete gift request failed. Unauthorized change in gift (sha256_accepted signature)' }
          next
        end
        sha256_accepted_server_text = ([gid, sha256_accepted_client, direction] + giver_user_ids + receiver_user_ids).join(',')
        sha256_accepted_server = Base64.encode64(Digest::SHA256.digest(sha256_accepted_server_text))
        if gift.sha256_accepted != sha256_accepted_server
          response << { :gid => gid, :deleted_at_server => false, :error => 'Delete gift request failed. Unauthorized change in gift (sha256_accepted signature)' }
          next
        end
      end

      # sha256_deleted: calculate server side sha256_deleted signature
      sha256_deleted_client = delete_gift["sha256_deleted"]
      if direction == 'giver'
        sha256_deleted_server_text = ([gid, sha256_deleted_client, 'giver'] + giver_user_ids).join(',')
      else
        sha256_deleted_server_text = ([gid, sha256_deleted_client, 'receiver'] + receiver_user_ids).join(',')
      end
      sha256_deleted_server = Base64.encode64(Digest::SHA256.digest(sha256_deleted_server_text))
      if !gift.sha256_deleted
        gift.sha256_deleted = sha256_deleted_server
        gift.save!
      end
      if gift.sha256_deleted == sha256_deleted_server
        # ok - has been deleted with identical signature in a previous request
        response << { :gid => gid, :deleted_at_server => true }
        no_errors -= 1
      else
        # error - gift has previous been deleted but signature is invalid in this request
        response << { :gid => gid, :deleted_at_server => false, :error => 'Delete gift request failed. Unauthorized change in gift (sha256_deleted signature)' }
      end

    end # each new_gift

    logger.debug2 "response = #{response}"
    { :no_errors => no_errors, :gifts => response }
  end # self.delete_gifts




end # Gift
