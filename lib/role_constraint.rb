# use in routes.rb for / redirect
# 1) empty params and not logged in => use auth/index
# 2) empty params and logged in => use gifts/index
# 3) login from FB app => use fb/create
# roles:
class RoleConstraint

  def initialize(*roles)
    @roles = roles
  end

  def session
    @session
  end

  def matches?(request)
    params = request.params
    @session = request.session
    # logger.debug2  "roles = #{@roles}, roles.class = #{@roles.class}" if defined? logger
    # logger.debug2  "request = #{@request}, request.class = #{request.class}" if defined? logger
    # logger.debug2  "request.methods = #{request.methods.sort.join(', ')}" if defined? logger
    # logger.debug2  "params = #{params}" if defined? logger
    # logger.debug2  "signature = #{signature(params)}" if defined? logger
    if @roles.index(:logged_in) or @roles.index(:not_logged_in)
      # todo: should use session helper methods from applicaiton controller (get_session_value)
      #       this will not work after splitting session storage in one section for each client_userid
      #       this will not work if :userids is moved to database session storage
      user_ids = get_session_value(:user_ids, request) || []
      logger.warn2 "WARNING: using get_session_value method from ActionControllerExtensions in routes/RoleConstraint. Not tested. user_ids = #{user_ids}" if defined? logger
      if user_ids.length == 0
        users = []
      else
        users = User.where('user_id in (?)', user_ids)
      end
    else
      users = []
    end
    # set bool filters for each role - all filters must be true - true if role is not in filter
    empty = (@roles.index(:empty) != nil and empty?(params) or @roles.index(:empty) == nil)
    # logger.debug2  "empty = #{empty}" if defined? logger
    logged_in = (@roles.index(:logged_in) != nil and users.length > 0 or @roles.index(:logged_in) == nil)
    logger.debug2  "logged_in = #{logged_in}" if defined? logger
    not_logged_in = (@roles.index(:not_logged_in) != nil and users.length == 0 or @roles.index(:not_logged_in) == nil)
    # logger.debug2  "not_logged_in = #{not_logged_in}" if defined? logger
    fb_locale = (@roles.index(:fb_locale) != nil and params[:fb_locale].to_s != '' or @roles.index(:fb_locale) == nil)
    # logger.debug2  "fb_locale = #{fb_locale}" if defined? logger
    signed_request = (@roles.index(:signed_request) != nil and params[:signed_request].to_s != '' or @roles.index(:signed_request) == nil)
    # logger.debug2  "signed_request = #{signed_request}"
    res = (empty and logged_in and not_logged_in and fb_locale and signed_request)
    # logger.debug2  "routes.rb / RoleConstraint:" if defined? logger
    # logger.debug2  "roles = #{@roles}, signature = #{signature(params)}, users.length = #{users.length}" if defined? logger
    # logger.debug2  "res = #{res}, empty = #{empty}, logged_in = #{logged_in}, not_logged_in = #{not_logged_in}, fb_locale = #{fb_locale}, signed_request = #{signed_request}" if defined? logger
    res
  end

  private
  def signature (params)
    signature = params.keys.sort
    signature.delete_if { |key| %w(controller action).index(key)}
  end

  private
  def empty? (params)
    signature(params).length == 0
  end

end