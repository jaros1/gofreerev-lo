class AboutController < ApplicationController

  def index
    @sections = %w(about betatest cookies privacy disclaimer )
  end

  # unsubscribe friend suggestion email from Gofreerev
  # params:
  #   noti_id: noti_id + password
  #   choice: 1-unsubscribe all, 2: unsubscribe for users
  def unsubscribe
    # check param email_id: noti_id + "password", total 40 characters
    noti_id_and_password = params[:email_id].to_s
    if noti_id_and_password.to_s == ''
      save_flash_key '.email_no_id'
      redirect_to :controller => :auth, :action => :index
      return
    end
    if noti_id_and_password.size != 40
      save_flash_key '.email_not_found'
      redirect_to :controller => :auth, :action => :index
      return
    end
    noti_id = noti_id_and_password.to_s.first(20)
    password = noti_id_and_password.last(20)
    noti_key_prefix = 'friends_find_'
    # check Notification - noti_key friends_find_ ..., external and password
    n = Notification.find_by_noti_id(noti_id)
    noti_options = n.noti_options if n
    if !n or n.internal != 'N' or n.noti_key.first(noti_key_prefix.size) != noti_key_prefix or n.noti_options[:password] != password
      # debug information
      if !n
        logger.debug2 "Notification was not found"
      elsif n.internal != 'N'
        logger.debug2 "Noti id #{n.id} : not an external notification"
      elsif n.noti_key.first(noti_key_prefix.size) != noti_key_prefix
        logger.debug2 "Noti id #{n.id} : not a #{noti_key_prefix} notification"
      elsif n.noti_options[:password] != password
        logger.debug2 "Noti id #{n.id} : invalid password"
      end
      save_flash_key '.email_not_found'
      redirect_to :controller => :auth, :action => :index
      return
    end
    email = noti_options[:email].to_s
    us = Unsubscribe.where('email = ? and user_id is null', email).first
    if us
      # email already unsubscribed
      save_flash_key '.ok1'
      redirect_to :controller => :auth, :action => :index
      return
    end

    # choice 1: unsubscribe email
    choice = params[:choice].to_s
    choice = '1' unless %w(1 2).index(choice)
    if choice == '1'
      us = Unsubscribe.new
      us.email = email
      us.save!
      Unsubscribe.where('email = ? and user_id is not null', email).delete_all
      save_flash_key '.ok1'
      redirect_to :controller => :auth, :action => :index
      return
    end
    # choice 2: unsubscribe email for selected Gofreerev users
    login_user_ids = noti_options[:login_users].to_s.split(',')
    login_users = User.where(:user_id => login_user_ids)
    login_users.each do |login_user|
      us = Unsubscribe.where('email = ? and user_id = ?', email, login_user.user_id).first
      if !us
        us = Unsubscribe.new
        us.email = email
        us.user_id = login_user.user_id
        us.save!
      end
    end
    save_flash_key '.ok2'
    redirect_to :controller => :auth, :action => :index
  end

  # ads - fairphone competition deadline 31/12-2014 (getting test data and test users for this app)
  def ad1
    language = session[:language] || 'en'
    @image = "ad_1_#{language}.jpg"
    @image_landscape = "ad_1_#{language}_landscape.jpg"
  end

end
