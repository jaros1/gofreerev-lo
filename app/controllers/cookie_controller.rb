class CookieController < ApplicationController

  session :off # session not used - all cookies will be deleted

  before_action :set_locale
  skip_filter :get_timezone
  layout 'no_cookies_layout'

  # cookie note cancel method - cookies has been removed
  def decline_cookies
  end

  private
  def set_locale
    params[:locale] = nil if params.has_key?(:locale) and xhr?
    I18n.locale = params[:locale] if valid_locale(params[:locale])
  end

  private
  def fetch_users
    # no cookie - not logged in - get dummy user
    @users = [ User.find_by_user_id('gofreerev/gofreerev') ]
  end

  # don't use session and don't use cookies in this controller
  # some rails gems writes to session or cookies
  # this should prevent rails from creating new cookies in this controller
  private
  def session
    {}
  end
  alias_method :old_cookies, :cookies
  def cookies
    old_cookies.each do |name, value|
      logger.debug2 "delete cookie #{name}"
      old_cookies.delete(name)
    end
    logger.debug2 "delete cookie _gofreerev-fb_session"
    old_cookies.delete('_gofreerev-fb_session')
    {}
  end

end
