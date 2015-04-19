# encoding: utf-8
module ApplicationHelper

  # debug
  def dump_session_variables
    logger.debug2  "session.to_hash = #{session.to_hash}"
  end

  # link_to helpers - used in page footer
  def link_to_cvs
    link_to CVS_NAME, CVS_URL, { :target => '_blank'}
  end
  def link_to_charles_eisenstein
    link_to 'Charles Eisenstein', 'http://charleseisenstein.net/', { :target => '_blank' }
  end
  def link_to_sacred_economics
    link_to 'Sacred Economics', 'http://sacred-economics.com/', { :target => '_blank' }
  end

  # partial helpers
  def render_partial_with_language (folder, partialname)
    language = get_session_value(:language)
    logger.debug2  "folder = #{folder}, partialname = #{partialname}, language = #{language}"
    language = nil if language == BASE_LANGUAGE
    unless language
      # no language or english
      return (render(:partial => "#{folder}/#{partialname}"))
    end
    # check for language specific partial
    partialname2 = "#{partialname}_#{language}"
    filename = Rails.root.join('app', 'views', folder, "_#{partialname2}.html.erb").to_s
    logger.debug2  "filename = #{filename}"
    partialname2 = partialname unless File.exists?(filename)
    render :partial => "#{folder}/#{partialname2}"
  end # render_application_partial

  # application layout helpers
  # active currencies to by used in page header LOV
  def currencies
    active_currencies = ExchangeRate.active_currencies
    Money::Currency.table.find_all do |a|
      !active_currencies or active_currencies.size == 0 or active_currencies.index(a[1][:iso_code]) or a[1][:iso_code] == BASE_CURRENCY
    end.collect do |a|
      [ "#{a[1][:iso_code]} #{a[1][:name]}".first(CURRENCY_LOV_LENGTH), a[1][:iso_code] ]
    end
  end
  def selected_currency
    return [] unless @users.size > 0
    user = @users.first
    return [] if user.dummy_user?
    a = Money::Currency.table.find { |a| a[1][:iso_code] == user.currency }
    return [] unless a
    [ [ "#{a[1][:iso_code]} #{a[1][:name]}".first(CURRENCY_LOV_LENGTH), a[1][:iso_code] ]]
  end

  def header_log_in_link_url
    url_for :controller => :auth, :action => :index
  end
  def header_log_out_link_url
    url_for :controller => :auth, :action => :destroy, :id => "all"
  end
  def render_page_footer
    render_partial_with_language('layouts', 'page_footer')
  end # render_page_footer


  # format prices - user currency is used for default separators
  # todo: angularJS - moved to formatPrice filter
  def format_price (price)
    return nil unless price
    # logger.debug2  "@user_currency_separator = #{@user_currency_separator}, @user_currency_delimiter = #{@user_currency_delimiter}"
    number_with_precision(price, :precision => 2, :separator => @user_currency_separator, :delimiter => @user_currency_delimiter)
  end

  def format_user_balance (user, login_users)
    # logger.debug2  "user = #{user.user_id}, login_users = " + login_users.collect { |user| user.user_id }.join(', ')
    return nil unless user.class == User and [Array, ActiveRecord::Relation::ActiveRecord_Relation_User].index(login_users.class)
    return nil if login_users.length == 0
    balance = user.balance
    return nil unless balance
    return nil unless balance.size > 1
    from_amount = balance[BALANCE_KEY]
    from_currency = 'USD'
    to_currencies = login_users.collect { |login_user| login_user.currency }.uniq
    if to_currencies.length > 1
      logger.debug2  "todo: error, login procedure should ensure one and only one currency for logged in users"
    end
    to_currency = to_currencies.first
    logger.debug2  "to_currency = #{to_currency}"
    if balance.size == 2 and user.currency == login_users.first.currency
      # short format. only one currency in balance hash. Return this without any conversion if login user currency
      return format_price(from_amount) if user.currency == login_users.first.currency
    end # æøå
    # exchange from_amount
    if from_currency == to_currency
      # logger.debug2  "no exchange: to_amount = from_amount = #{from_amount}"
      to_amount = from_amount
      to_currency = ''
    elsif (to_amount = ExchangeRate.exchange(from_amount, from_currency, to_currency))
      # logger.debug2  "exchange ok: from_amount = #{from_amount}, from_currency = #{from_currency}, to_amount = #{to_amount}, to_currency = #{to_currency}"
      to_currency = ''
    else
      # exchange rate was not ready - show original user balance with currency - exchange rate should be ready in next request
      # logger.debug2  "exchange rate not ready: from_amount = #{from_amount}, from_currency = #{from_currency}"
      to_amount = from_amount
      to_currency = ' ' + from_currency
    end
    # format: -0,90 (-47,77 DKK, 49,76 SEK, -0,08 USD) - to_currency will normally be blank
    format_price(to_amount) + to_currency + ' (' + balance.find_all { |name, value| name != BALANCE_KEY }.collect { |name,value| format_price(value) + ' ' + name }.join(', ') + ')'
  end # format_user_balance

  def format_user_last_login (friend)
    return nil unless friend.last_login_at
    dif = Time.new - friend.last_login_at
    months = (dif / 1.month).floor
    weeks = (dif / 1.week).floor
    days = (dif / 1.day).floor
    hours = ((dif - days.days) / 1.hour).floor
    t '.last_login_text', :months => months, :weeks => weeks, :days => days, :hours => hours
  end

  def format_date (date)
    return nil unless date
    l date.to_date, :format => :short
  end

  def format_time (time)
    l time, :format => :short
  end

  # todo: config sanitize
  def my_sanitize (text)
    # also used in Picture.create_png_image_from_text
    sanitize(text.to_s).gsub(/\n/, '<br/>').html_safe
  end # my_sanitize


  # todo: translate value for key provider.
  def my_sanitize_hash (hash)
    hash.each do |name, value|
      if name.to_s == 'provider'
        hash[name] = provider_downcase(value)
      else
        hash[name] = my_sanitize (value.to_s.force_encoding('utf-8'))
      end
    end
  end # my_sanitize_hash


  #def format_direction (api_gift)
  #  gift = api_gift.gift
  #  case gift.direction
  #    when 'giver'
  #      t 'gifts.index.direction_giver', :username => api_gift.giver.short_or_full_user_name(@user)
  #    when 'receiver'
  #      t 'gifts.index.direction_receiver', :username => api_gift.receiver.short_or_full_user_name(@user)
  #    when 'both'
  #      t 'gifts.index.direction_giver_and_receiver', :givername => api_gift.giver.short_user_name, :receivername => api_gift.receiver.short_user_name
  #    else
  #      raise "invalid direction for gift #{gift.id}"
  #  end # case
  #end # format_direction

  def inbox_new_notifications
    n = User.inbox_new_notifications(@users)
    # logger.debug2 "users = " + @users.collect { |u| u.user_id }.join(', ') + ", n = #{n}"
    n
  end

  def title
    n = inbox_new_notifications()
    return APP_NAME unless n
    "(#{n}) #{APP_NAME}"
  end # title

  # todo: angularJS: moved to formatGiftLinkText filter
  def format_gift_param (api_gift)
    gift = api_gift.gift
    optional_price = nil ? "#{t('.optional_price', :price => format_price(nil))}" : nil
    { :date           => format_date(gift.received_at || gift.created_at),
      :direction      => format_direction_with_user(api_gift),
      :optional_price => optional_price,
      :text           =>  my_sanitize('gift.description deleted from server')
    }
  end # format_gift_param

  def format_comment_key (comment)
    case
      when comment.new_deal_yn != 'Y' then '.comment_text'
      when comment.accepted_yn == 'Y' then '.accepted_text'
      when comment.accepted_yn == 'N' then '.rejected_text'
      else '.proposal_text'
    end
  end # format_comment_key

  def format_comment_param (comment)
    optional_price = comment.price ? "#{t('.optional_price', :price => format_price(comment.price))} #{comment.currency}" : nil
    { :date => format_date(comment.created_at),
      :optional_price => optional_price,
      :text => my_sanitize(comment.comment) }
  end # format_comment_param
  
  def invite_friend_url (friend)
    provider = friend.provider
    case provider
      when 'facebook'
        # url - friend request url
        title = t 'shared.invite_friends.invite_friends_message_title', :appname => APP_NAME
        message = t 'shared.invite_friends.invite_friends_message_body'
        # remove last_row_id - not an ajax message when returning from facebook
        logger.debug2 "@request_fullpath = #{@request_fullpath}"
        request_fullpath = @request_fullpath
        request_fullpath = request_fullpath.gsub(/&last_row_id=[0-9]+/,'')
        request_fullpath = request_fullpath.gsub(/\?last_row_id=[0-9]+&/,'?')
        logger.debug2 "request_fullpath = #{request_fullpath}"
        # no koala gem method for generation a invite friends url
        # https://developers.facebook.com/docs/reference/dialogs/requests/
        url = "https://#{Koala.config.dialog_host}/dialog/apprequests" +
            "?app_id=#{API_ID[provider]}" +
            "&redirect_uri=#{CGI.escape(SITE_URL + request_fullpath)}" +
            "&message=#{CGI.escape(message.to_str)}" +
            "&title=#{CGI.escape(title.to_str)}" +
            "&to=#{friend.uid}"
        # logger.debug2  "url = #{url}"
        url
      else
        # invite friend is not implemented for this provider - return link to api user profile
        # todo: use email to send a invitation to use gofreerev?
        # todo: check JS libraries for Google+, Linkedin and Twitter.
        api_profile_url(friend)
    end # case
  end # invite_friend_url

  # todo: generalize, different url for each API (FB, GP, LI etc)
  # todo: angularJS - moved to formatInviteFriendsLink filter
  def invite_friends_url (login_user)
    if login_user.class != User
      # invalid call - login_user was missing in invite_friends_url call
      msg = t 'shared.invite_friends.invalid_call'
      logger.debug2 msg
      return "javascript: alert('#{msg}')"
    end
    provider = login_user.provider
    case provider
      when 'facebook'
        # url - friend request url
        title = t 'shared.invite_friends.invite_friends_message_title', :appname => APP_NAME
        message = t 'shared.invite_friends.invite_friends_message_body'
        # no koala gem method for generation a invite friends url
        # https://developers.facebook.com/docs/reference/dialogs/requests/
        url = "https://#{Koala.config.dialog_host}/dialog/apprequests" +
            "?app_id=#{API_ID[provider]}" +
            "&redirect_uri=#{CGI.escape(SITE_URL + @request_fullpath)}" +
            "&message=#{CGI.escape(message.to_str)}" +
            "&title=#{CGI.escape(title.to_str)}" +
            "&filters=" + CGI.escape("['app_non_users']")
        # logger.debug2  "url = #{url}"
        url
      else
        # invite provider friends is not implemented
        msg = t 'shared.invite_friends.not_implemented', login_user.app_and_apiname_hash
        "javascript: alert('#{msg}')"
    end # case
  end # invite_friends_url

  def invite_friend (friend)
    login_user = @users.find { |u| u.provider == friend.provider }
    if %w(facebook).index(friend.provider)
      # use API invite functionality - only facebook has implemented this
      link_to t('shared.invite_friend.invite_friend_link_text'), invite_friend_url(friend)
    else
      # use client email with dummy email address
      options = { :to_username => friend.user_name,
                  :from_username => login_user.user_name,
                  :url => "#{SITE_URL}#{I18n.locale}/auth"}
      mail_to t('shared.invite_friend.invite_friend_mailto_email'), t('shared.invite_friend.invite_friend_mailto_link_text'),
              :subject => t('shared.invite_friend.invite_friend_mailto_subject', friend.app_and_apiname_hash),
              :body => t('shared.invite_friend.invite_friend_mailto_body', friend.app_and_apiname_hash.merge(options) )
    end
  end

  # todo: angularJS - moved to formatInviteFriendsLink filter
  def invite_friends_link (login_user)
    if %w(facebook).index(login_user.provider)
      # use API invite functionality - only facebook has implemented this
      link_to provider_camelize(login_user.provider), invite_friends_url(login_user), :title => t('shared.invite_friends.invite_friends_link_title', :appname => APP_NAME, :apiname => login_user.apiname)
    else
      # use client email with dummy email address
      options = { :from_username => login_user.user_name,
                  :url => "#{SITE_URL}#{I18n.locale}/auth"}
      mail_to t('shared.invite_friends.invite_friends_mailto_email'), provider_camelize(login_user.provider),
              :subject => t('shared.invite_friends.invite_friends_mailto_subject', login_user.app_and_apiname_hash),
              :body => t('shared.invite_friends.invite_friends_mailto_body', login_user.app_and_apiname_hash.merge(options) )
    end
  end

  def ajax_tasks?
    return false if @disable_ajax_tasks # facebook autologin page - wait with ajax tasks to gifts/index page
    ajax_tasks = (Task.where("session_id = ? and ajax = ?", get_sessionid, 'Y').count > 0)
    # logger.debug2 "session_id = #{get_sessionid}, ajax_tasks = #{ajax_tasks}"
    ajax_tasks
  end

  def link_to_logout
    if @request_fullpath.to_s =~ /\/cookie\//
      # problem with log out link and InvalidAuthenticityToken error (no session in cookie controller). redirect to login/logout page
      link_to t('layouts.page_header..header_log_out_link_text'), auth_path
    else
      link_to t('layouts.page_header..header_log_out_link_text'), header_log_out_link_url, :method => 'delete'
    end
  end

  # return select list with language code and language text
  # used in page header and in users/edit page
  def selected_languages
    codes = Rails.application.config.i18n.available_locales.collect { |locale| locale.to_s }
    codes.collect { |code| [t("shared.languages.#{code}"), code]}.sort_by { |a| a[1] }
  end

  # check for disconnected shared account. Added in User.add_shared_accounts
  # for example used in users/index page when showing friend lists for disconnected shared accounts
  def disconnected_shared_provider? (provider)
    login_user = @users.find { |u| u.provider == provider}
    (login_user and (login_user.disconnected_shared_account == true))
  end

end # ApplicationHelper
