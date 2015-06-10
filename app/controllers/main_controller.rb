class MainController < ApplicationController

  def index
    # todo: debug problems with missing did after login
    logger.debug2 "get_session_value(:did) = #{get_session_value(:did)}"
  end

  def gifts
    # todo: debug problems with missing did after login
    logger.debug2 "get_session_value(:did) = #{get_session_value(:did)}"
    render :layout => false
  end
  def auth
    # todo: debug problems with missing did after login
    logger.debug2 "get_session_value(:did) = #{get_session_value(:did)}"
    render :layout => false
  end

end
