class InboxController < ApplicationController

  before_filter :login_required
  before_filter :clear_state_cookie_store

  def index
    # todo: delete ==>
    #if login_user_ids.index('xxxxxxxxxx/google_oauth2')
    #  token = (session[:tokens] || {})['google_oauth2']
    #  logger.secret2 "token = #{token}"
    #end
    ## todo: delete <==

    # get messages - new messages are shown first in page - max 20 notifications - no need for paginate or ajax expanding page
    @notifications = Notification.where("(to_user_id in (?) or from_user_id in (?)) and internal = ?",
                                        login_user_ids, login_user_ids, 'Y').order("noti_read, created_at desc")
    for noti in @notifications do loop
      if noti.noti_read == 'N' and login_user_ids.index(noti.to_user_id)
        noti.noti_read = 'Y'
        noti.save!
      end
    end
    # temporary workaround. remove notifications for delete or delete marked gifts.
    # todo: delete notifications when gift has been delete marked
    @notifications = @notifications.find_all do |noti|
      if noti.noti_options[:giftid].to_s =~ /^[0-9]+$/
        gift = Gift.find_by_id(noti.noti_options[:giftid])
        # todo: delete notification for delete marked gift?
        gift and !gift.deleted_at
      elsif t(".#{noti.noti_key}_to_url", noti.noti_options) =~ /^\/gifts\/([0-9]+)$/
        # gift/comment notification
        gift = Gift.find_by_id($1)
        # todo: delete notification for delete marked gift?
        gift and !gift.deleted_at
      elsif t(".#{noti.noti_key}_from_url", noti.noti_options) =~ /^\/gifts\/([0-9]+)$/
        # gift/comment notification
        gift = Gift.find_by_id($1)
        # todo: delete notification for delete marked gift?
        gift and !gift.deleted_at
      else
        # other notifications
        true
      end
    end # find_all
  end # index

  def show
  end

  def destroy
  end

end
