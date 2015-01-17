module ActionControllerExtensions

  private
  def get_sessionid
    request.session_options[:id]
  end
  def get_client_userid
    session[:client_userid] || 0
  end
  def get_secret
    session[:secret] = String.generate_random_string(256) unless session[:secret]
    logger.debug2 "secret = #{session[:secret]}"
    session[:secret]
  end

  def find_or_create_session
    return @s if @s
    @s = Session.find_by_session_id_and_client_userid(get_sessionid, get_client_userid)
    @s = Session.new unless @s
    @s.secret = get_secret unless @s.secret
    @s.created_at = Time.zone.now if @s.new_record?
    @s.session_id = get_sessionid if @s.new_record?
    @s.client_userid = get_client_userid if @s.new_record?
    @s
  end
  def save_session
    if @s.new_record? or @s.changed?
      @s.updated_at = Time.zone.now
      @s.save
    end
  end

  # generic session setter/getter
  # some session data are stored in different sections for each client_userid
  # some session data are stored encrypted in database (4kb limit for cookies)
  # keys:
  #   :client_userid - 0, 1, 2 etc. From client local storage login - sent to rails all client get/post requests
  #   :created - show cookie note in page header for new sessions - hidden after 30 seconds
  #   :expires_at - unix timestamps for API access tokens
  #   :flash_id - id to current flash message
  #   :language - en, da etc
  #   :last_row_at - old show-more-rows functionality - see get_last_row_at/set_last_row_at
  #   :last_row_id - old show-more-rows functionality - see get_last_row_id/set_last_row_id
  #   :refresh_tokens - API refresh tokens - only used for Google+
  #   :state - random string :state in oauth API requests. set before calling API and check after returning from API
  #   :timezone - timezone from JS or oauth login
  #   :tokens - API access tokens
  #   :user_ids - user_id array for logged in users

  private
  def get_session_value (key)
    key = key.to_sym
    return session[key] if [:client_userid, :timezone].index(key)
    find_or_create_session()
    save_session()
    eval("@s.#{key}")
  end
  def get_session_array_value (key, index)
    find_or_create_session()
    save_session()
    eval("@s.#{key}")[index]
  end
  def set_session_value (key, value)
    key = key.to_sym
    if [:client_userid, :timezone].index(key)
      @s = nil if key == :client_userid and (session[key] || 0) != (value || 0) # client_userid has changed
      session[key] = value
    else
      find_or_create_session()
      @s.set_column_value(key, value)
      save_session()
    end
    value
  end
  def set_session_array_value (key, value, index)
    key = key.to_sym
    hash = get_session_value(key)
    hash[index] = value
    set_session_value(key, hash)
    value
  end
  def delete_session_array_value( key, index)
    key = key.to_sym
    hash = get_session_value(key)
    value = hash.delete(index)
    set_session_value(key, hash)
    value
  end

end

ActionController::Base.send :include, ActionControllerExtensions
RoleConstraint.send :include, ActionControllerExtensions