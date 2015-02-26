
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


end # Comment
