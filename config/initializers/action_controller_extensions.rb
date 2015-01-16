module ActionControllerExtensions

  private
  def get_sessionid
    request.session_options[:id]
  end

  # generic session setter/getter
  # some session data are stored in different sections for each client_userid
  # some session data are stored encrypted in database (4kb limit for cookies)
  # keys:
  #   :client_userid - 1, 2 etc. From client local storage login - sent to rails all client get/post requests
  #   :created - show cookie note in page header for new sessions - hidden after 30 seconds
  #   :expires_at - unix timestamps for API access tokens
  #   :flash_id - id to current flash message
  #   :language - en, da etc
  #   :refresh_tokens - API refresh tokens - only used for Google+
  #   :state - random string :state in oauth API requests. set before calling API and check after returning from API
  #   :timezone - timezone from JS or oauth login
  #   :tokens - API access tokens
  #   :user_ids - user_id array for logged in users

  private
  def get_session_value (key)
    session[key]
  end
  def get_session_array_value (key, index)
    session[key][index]
  end
  def set_session_value (name, value)
    session[name] = value
    value
  end
  def set_session_array_value (name, value, index)
    session[name][index] = value
  end
  def delete_session_array_value( name, index)
    session[name].delete(index)
  end

end

ActionController::Base.send :include, ActionControllerExtensions
RoleConstraint.send :include, ActionControllerExtensions