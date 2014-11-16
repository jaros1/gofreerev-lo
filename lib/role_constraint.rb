# use in routes.rb for / redirect
# 1) empty params and not logged in => use auth/index
# 2) empty params and logged in => use gifts/index
# 3) login from FB app => use fb/create
# roles:
class RoleConstraint
  def initialize(*roles)
    @roles = roles
  end

  def matches?(request)
    params = request.params
    session = request.session
    # logger.debug2  "roles = #{@roles}, roles.class = #{@roles.class}"
    # logger.debug2  "request = #{@request}, request.class = #{request.class}"
    # logger.debug2  "request.methods = #{request.methods.sort.join(', ')}"
    # logger.debug2  "params = #{params}"
    # logger.debug2  "signature = #{signature(params)}"
    if @roles.index(:logged_in) or @roles.index(:not_logged_in)
      user_ids = session[:user_ids] || []
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
    # logger.debug2  "empty = #{empty}"
    logged_in = (@roles.index(:logged_in) != nil and users.length > 0 or @roles.index(:logged_in) == nil)
    # logger.debug2  "logged_in = #{logged_in}"
    not_logged_in = (@roles.index(:not_logged_in) != nil and users.length == 0 or @roles.index(:not_logged_in) == nil)
    # logger.debug2  "not_logged_in = #{not_logged_in}"
    fb_locale = (@roles.index(:fb_locale) != nil and params[:fb_locale].to_s != '' or @roles.index(:fb_locale) == nil)
    # logger.debug2  "fb_locale = #{fb_locale}"
    signed_request = (@roles.index(:signed_request) != nil and params[:signed_request].to_s != '' or @roles.index(:signed_request) == nil)
    # logger.debug2  "signed_request = #{signed_request}"
    res = (empty and logged_in and not_logged_in and fb_locale and signed_request)
    # logger.debug2  "routes.rb / RoleConstraint:"
    # logger.debug2  "roles = #{@roles}, signature = #{signature(params)}, users.length = #{users.length}"
    # logger.debug2  "res = #{res}, empty = #{empty}, logged_in = #{logged_in}, not_logged_in = #{not_logged_in}, fb_locale = #{fb_locale}, signed_request = #{signed_request}"
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