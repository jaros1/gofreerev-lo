require 'google/api_client'
require 'linkedin'

class UtilController < ApplicationController

  before_filter :login_required,
                :except => [:new_messages_count,
                            :like_gift, :unlike_gift, :follow_gift, :unfollow_gift, :hide_gift, :delete_gift,
                            :cancel_new_deal, :reject_new_deal, :accept_new_deal,
                            :do_tasks, :post_on_wall_yn, :share_gift, :open_graph]

  # update new message count in menu line in page header
  # called from hidden new_messages_count_link link in page header once every 15, 60 or 300 seconds
  # new_message_count is also ajax injecting gifts and comments into gifts pages
  # Parameters: {"request_fullpath"=>"/gifts", "newest_gift_id"=>"275", "newest_status_update_at"=>"417"}
  # - request_fullpath is request path for current page where ajax request was send from
  # - newest_gift_id is newest gift id when page was loaded or newest gift id in last new_messages_count request for this session
  # - newest_status_update_at is newest status_update_at when page was loaded or newest status_update_at in last new_message_count request for this session
  def new_messages_count
    if User.dummy_users?(@users)
      logger.debug2  "ignoring not logged in user"
      render :nothing => true
      return
    end

    # cleanup - destroy old delete marked gifts
    # gift was marked as deleted in util/delete_gift request
    # gift has been ajax removed from  gifts pages for other sessions in previous util/new_message_count requests
    # now is the time to destroy old delete marked gifts
    Gift.check_gift_and_api_gift_rel
    userids = @users.collect { |user| user.user_id }
    Gift.where('(api_gifts.user_id_giver in (?) or api_gifts.user_id_receiver in (?)) and gifts.deleted_at is not null and gifts.deleted_at < ?',
               userids, userids, 10.minutes.ago).includes(:api_gifts).references(:api_gifts).each do |g|
      # todo: there is a problem with api gifts without gift. - raise exception to trace problem
      Gift.check_gift_and_api_gift_rel
      logger.debug2 "before destroy gift id #{g.id}"
      g.destroy!
      logger.debug2 "after destroy gift id #{g.id}"
      Gift.check_gift_and_api_gift_rel
    end
    # cleanup inactive, deauthorized and deleted users
    # - delete deleted users after 6 minutes (CLEANUP_USER_DELETED) - delete link in users/edit page
    # - delete deauthorized users after 14 days (CLEANUP_USER_DEAUTHORIZED) - user has deauthorized Gofreerev from app settings page at api
    # - delete inactive users after 1 year (CLEANUP_USER_INACTIVE) - no user logins in 1 year
    User.where('last_login_at is not null and deleted_at is null and ' +
               '(deauthorized_at is not null and deauthorized_at < ? or last_login_at < ?)',
               CLEANUP_USER_DEAUTHORIZED.ago, CLEANUP_USER_INACTIVE.ago).update_all(:deleted_at => Time.new)
    User.where('deleted_at is not null and deleted_at < ?', CLEANUP_USER_DELETED.ago).each do |u|
      logger.debug2 "Physical delete user with id #{u.id}"
      key, options = User.delete_user(u)
      logger.debug2 t("users.destroy#{key}", options) if key
    end
    # auto friends find after multi user login - friends search for login users - once after login each login
    if @users.size > 1 and @users.find { |u| u.last_friends_find_at < u.last_login_at }
      # friends find for current login users - ajax inject any error messages into current page
      key, options = User.find_friends_batch(@users)
      add_error_key "util.find_friends_batch#{key}", options if key
    end
    # get params
    old_newest_gift_id = params[:newest_gift_id].to_i
    old_newest_status_update_at = params[:newest_status_update_at].to_i
    # return new messages count
    count = User.inbox_new_notifications(@users) || 0
    @new_messages_count = count if count > 0
    # return new comments
    # return new comments and comments with changed status (new deal proposal cancelled or rejected or deleted comment)
    re_gifts_index_page = Regexp.new '^\/([a-z]{2}\/)?gifts\/?$'
    re_gifts_show_page = Regexp.new '^\/([a-z]{2}\/)?gifts\/([0-9]+)\/?'
    if  params[:request_fullpath].match(re_gifts_index_page) or params[:request_fullpath].match(re_gifts_show_page)
      # find comments to ajax insert in gifts/index or gifts/show pages
      # logger.debug2  "find comments to ajax insert in gifts/index or gifts/show pages"
      # two sources for comments to ajax insert into gifts table
      # source 1 - comments selected to be ajax inserted for this user - todo: check where AjaxCommment is initialized
      com_ids = AjaxComment.where("user_id in (?)", login_user_ids).collect { |ac| ac.comment_id }
      com_ids.push('x') if com_ids.size == 0
      # logger.debug2  "com_ids.length = #{com_ids.length}"
      comments1 = Comment.includes(:gift).where('comment_id in (?)',com_ids)
      # source 2 - all visible gifts, but only comments with status_update_at > :newest_status_update_at
      friends = []
      @users.each do |user|
        friends = friends + user.app_friends.collect { |u| u.user_id_receiver }
        friends.push(user.user_id)
      end
      gifts2 = Gift.where('(api_gifts.user_id_giver in (?) or api_gifts.user_id_receiver in (?)) and ' +
                           'gifts.deleted_at is null and ' +
                           'comments.status_update_at > ?',
                             friends, friends, old_newest_status_update_at).includes(:comments, :api_gifts).references(:api_gifts)
      comments2 = []
      gifts2.each do |gift|
        comments2 = comments2 + gift.comments.find_all { |comment| comment.status_update_at > old_newest_status_update_at}
      end
      comments = (comments1 + comments2).uniq
      if comments.size > 0 and params[:request_fullpath].match(re_gifts_show_page)
        # gifts/show/<nnn> page - return only ajax comments for actual gift (id=<nnn>)
        # logger.debug2  "new comments before gift_id filter = #{@comments.length}"
        comments = comments.find_all { |c| c.gift.id.to_s == $2 }
        # logger.debug2  "new comments after gift_id filter = #{@comments.length}"
      end
      # do not return comment just created by current user (problem with extra flash for new comments)
      if comments.size > 0
        new_comment_ids = ApiComment.where('user_id in (?) and created_at > ? and created_at = updated_at',
                                            login_user_ids, 30.seconds.ago).collect { |ac| ac.comment_id}.uniq
        comments = comments.delete_if { |c| new_comment_ids.index(c.comment_id) } if new_comment_ids.size > 0
      end

      # remove comments for hidden gifts - that is gifts user has selected not to see
      if comments.size > 0
        old_size = comments.size
        giftids = comments.collect { |c| c.gift_id }
        hide_giftids = GiftLike.
            where("user_id in (?) and gift_id in (?)", login_user_ids, giftids).
            find_all { |gl| gl.show == 'N'}.collect { |gl| gl.gift_id }
        # remove comments for hidden gifts
        comments = comments.find_all { |c| !hide_giftids.index(c.gift_id) } if hide_giftids.length > 0
        new_size = comments.size
        # logger.debug2  "#{old_size-new_size} comments for hidden gifts was removed" if old_size != new_size
      end
      # "convert" comments to api comments
      if comments.size > 0
        commentids = comments.collect { |c| c.comment_id }
        comments = Comment.where('comment_id in (?)', commentids).includes(:api_comments)
        @api_comments = comments.collect { |c| c.api_comments.shuffle.first }
      end
      # empty AjaxComment buffer - only return ajax comments once
      AjaxComment.where('user_id in (?)', login_user_ids).destroy_all
      # delete old deleted marked comments
      Comment.where("deleted_at is not null and deleted_at < ?", 10.minutes.ago).each do |c|
        begin
          c.destroy!
        rescue => e
          logger.warn2 "Error when deleting comment id #{c.id}. #{e.message}"
        end # each c
      end
    end
    # return newly created gifts. Input newest_gift_id when user page was loaded or newest gift_id in last new_messages_count request
    # return newly updated (or deleted) gifts. Input newest_status_update_at when user page was loaded or newest_status_update_at in last new_message:count request
    # 0 if not called from gifts/index page
    new_newest_gift_id = Gift.last.id if old_newest_gift_id > 0
    new_newest_status_update_at = Sequence.status_update_at if old_newest_status_update_at > 0
    if old_newest_gift_id > 0 and (new_newest_gift_id > old_newest_gift_id or new_newest_status_update_at > old_newest_status_update_at)
      # called from gifts/index page and new gifts created since page load or last new_messages_count request
      # return new newest_gift_id value and any new gifts visible to user
      @new_newest_gift_id = new_newest_gift_id
      @new_newest_status_update_at = new_newest_status_update_at
      @api_gifts, last_status_update_at = User.api_gifts(@users,
                                                         :newest_gift_id => old_newest_gift_id,
                                                         :newest_status_update_at => old_newest_status_update_at,
                                                         :include_delete_marked_gifts => true) # include delete marked gifts
      @api_gifts = nil if @api_gifts.length == 0
    end
    # remove any ajax comments for gifts in gifts array - that is gifts that will be ajax inserted or replaced in gifts html table
    if @api_comments and @api_gifts and @api_comments.size > 0 and @api_gifts.size > 0
      # logger.debug2  "remove any comments that is included in gifts"
      # logger.debug2  "old @comments.size = #{@comments.size}, comments = " + @comments.collect { |c| c.id }.join(', ') if @comments
      @api_comments = @api_comments.delete_if { |c| @api_gifts.find_all { |g| c.gift_id == g.gift_id }.first }
      @api_comments = nil if @api_comments.size == 0
      # logger.debug2  "new @comments.size = #{@comments.size}, comments = " + @comments.collect { |c| c.id }.join(', ') if @comments
    end
    logger.debug2  "@gifts.size = #{@api_gifts.size}, gifts = " + @api_gifts.collect { |g| g.id }.join(', ') if @api_gifts
    logger.debug2  "@comments.size = #{@api_comments.size}, comments = " + @api_comments.collect { |c| c.id }.join(', ') if @api_comments
    logger.debug2  "@new_newest_gift_id = #{@new_newest_gift_id}"
    logger.debug2  "@new_newest_status_update_at = #{@new_newest_status_update_at}"
  end # new_messages_count

  # get array of gift ids with invalid picture url
  # temp api url can have changed / picture may have been deleted
  # Parameters: {"gifts"=>{"ids"=>"161"}}
  def missing_api_picture_urls
    begin
      if !params.has_key?("api_gifts") or !params[:api_gifts].has_key?(:ids) or params[:api_gifts][:ids] == ''
        return format_response_key('.mis_api_pic_no_param')
      end
      ids = params[:api_gifts][:ids].split(',')
      logger.debug2 "ids = #{ids}"
      api_gifts = ApiGift.where("id in (?)", ids)

      # get new picture urls if possible. Stategies for finding a new valid url:
      # 1) api_gift_id and deleted_at_api != 'Y'
      #    1a) logged in as creator - recheck api wall
      #    1b) not logged in as creator - skip - check later with creator login
      # 2) no api_gift_id or deleted_at_api == 'Y'
      #    2a) other provider with an valid api_gift_url - use url as workaround - mark invalid urls with error timestamp
      #    2b) invalid url and api_gift_id and deleted_at_api != 'Y' and logged in as creator - recheck api wall and use if valid
      #    2b) invalid url and api_gift_id and deleted_at_api != 'Y' and not

      # todo: 3 - max request picture url once every hour
      tokens = session[:tokens]
      return format_response_key('.mis_api_pic_no_tokens') unless tokens
      api_clients = {}
      api_gifts.each do |api_gift|
        if !api_gift.picture? or api_gift.api_picture_url.to_s == ""
          logger.debug2 "Ignoring api_gift #{api_gift.id} where picture has been deleted (refresh gifts/index page in browser)"
          next
        end
        if Picture.app_url?(api_gift.api_picture_url)
          # local url / picture on server, but picture was not found (by browser)
          # check if file exists. Could be a file protection problems
          full_os_path = Picture.full_os_path :url => api_gift.api_picture_url
          rel_path = Picture.rel_path :url => api_gift.api_picture_url
          if File.exists? full_os_path
            # picture exists on filesystem but was reported as missing by browser/js
            # must be invalid file protection for /images/temp/ or /images/perm/ folder
            logger.error2 "picture #{rel_path} exists in file system but was not found by browser. check file protection"
            add_error_key '.mis_api_pic_file_exists', :rel_path => rel_path
            next
          end
          # local picture file has been deleted. Continue. Maybe picture is available from an other api provider
        else
          # api url. recheck that picture has move or has been deleted
          image_type = FastImage.type(api_gift.api_picture_url).to_s
          # flickr: check for redirect to https://s.yimg.com/pw/images/photo_unavailable.gif
          if image_type == 'gif' and api_gift.provider == 'flickr' and FastImage.size(api_gift.api_picture_url) == [500, 374]
            # size = size for deleted flickr picture - check redirected url
            redirected_url = ApiGift.http_get(api_gift.api_picture_url, 30, 3, true)
            image_type = '' if redirected_url == 'https://s.yimg.com/pw/images/photo_unavailable.gif'
          end
          if %w(jpg jpeg gif png bmp).index(image_type)
            # api url still exists. Could be a temporary problem
            # todo: write warning in log, ignore error and blank api_gift.api_picture_url_on_error_at
            logger.warn2 "api gift #{api_gift.id} url #{api_gift.api_picture_url} exists, but was not found by browser"
            # add_error_key '.mis_api_pic_url_exists', :url => api_gift.api_picture_url
            api_gift.api_picture_url_on_error_at = nil
            api_gift.save!
            next
          end
        end
        # correct that api picture url does not exist - error mark api gift
        api_gift.api_picture_url_on_error_at = Time.now
        api_gift.save!

        # check api wall - skip check if logged in user not is creator of post/picture
        created_by_user_id = api_gift.gift.created_by == 'giver' ? api_gift.user_id_giver : api_gift.user_id_receiver
        created_by_user = login_user_ids.index(created_by_user_id)
        if api_gift.api_gift_id and api_gift.deleted_at_api != 'Y' and !created_by_user
          # recheck api wall later as user created_by_user_id
          logger.debug2 "check api gift #{api_gift.id} later with creator #{created_by_user_id} permissions"
          next
        end

        # check api wall. logged in user is creator of post/picture
        if api_gift.api_gift_id and api_gift.deleted_at_api != 'Y'
          # check api wall

          # check/initialize api client
          api_client = api_clients[api_gift.provider]
          if !api_client
            # initialize api client for provider
            token = tokens[api_gift.provider]
            if !token
              logger.warn2 "received api_gift.id #{api_gift.id} for provider #{api_gift.provider}, but user is not connected with provider #{api_gift.provider}"
              add_error_key '.mis_api_pic_no_token', api_gift.app_and_apiname_hash
              next
            end

            # todo: refactor - use generic init_api_client(provider, token) method
            key, options = init_api_client(api_gift.provider, token)
            if key.class == String
              add_error_key key, options
              next
            end
            api_clients[api_gift.provider] = api_client = key
            #case api_gift.provider
            #  when 'facebook' then
            #    api_client = init_api_client_facebook(token)
            #  when 'google_oauth2' then
            #    api_client = nil # readonly api - no uploads
            #  when 'instagram' then
            #    api_client = nil # readonly api - no uploads
            #  when 'linkedin' then
            #    api_client = nil # image shared wih url to local picture store
            #  when 'twitter' then
            #    api_client = init_api_client_twitter(token)
            #  else
            #    logger.error2 "initialize api client for #{api_gift.provider} not implemented, api_gift.id = #{api_gift.id}"
            #    @errors << ['.mis_api_pic_not_implemented1', api_gift.app_and_apiname_hash ]
            #    next
            #end
            api_clients[api_gift.provider] = api_client
          end
          # api client initialized

          # get new picture url from API
          if api_client
            begin
              # check api wall
              key, options = get_api_picture_url(api_gift.provider, api_gift, false, api_client) # just_posted = false
              #case api_gift.provider
              #  when 'facebook'
              #    key, options = get_api_picture_url_facebook(api_gift, false, api_client)
              #  when 'twitter'
              #    key, options = get_api_picture_url_twitter(api_gift, false, api_client)
              #  else
              #    logger.error2 "No get_api_picture_url_#{api_gift.provider} method"
              #    @errors << ['.mis_api_pic_not_implemented2', api_gift.app_and_apiname_hash ]
              #    next
              #end
              if key
                key = "util.do_tasks#{key}" if key.first == '.'
                add_error_key key, options
                next
              end
              # ok - post/picture os still on api wall and new api gift picture url has been received
              next
            rescue ApiPostNotFound => e
              # identical api error response if picture is deleted or if user is not allowed to see picture
              logger.debug2 "api gift #{api_gift.id} has been deleted on #{api_gift.provider} wall."
              api_gift.deleted_at_api = 'Y'
              api_gift.save!
              # Continue. Maybe picture url is available from an other api provider
            rescue AppNotAuthorized => e
              # access token expired or user has deauthorized app
              logger.debug2 "#{api_gift.provider} access token expired or user has deauthorized app"
              add_error_key '.mis_api_pic_deauth', {:appname => APP_NAME, :provider => provider_downcase(api_gift.provider)}
              # log out and skip chek any other api gifts for this provider
              api_clients.delete(api_gift.provider)
              logout(api_gift.provider)
              api_gifts.delete_if { |ag| ag.provider == api_gift.provider }
              next
            end # rescue
          end
          # end check api wall
        end

        # api gift no longer on api wall. Check if picture url is available from an other api provider
        # that is - user was logged in with multiple api providers when gift was created
        # could be local perm path for linked used for a linkedin api gift
        # could be a facebook api url used for an not facebook api provider
        api_gift.reload
        new_api_picture_url = nil
        api_gift.gift.api_gifts.delete_if { |ag| ag.id == api_gift.id }.each do |api_gift2|
          next if !api_gift2.picture?
          next if api_gift2.api_picture_url_on_error_at
          next if api_gift2.api_picture_url.to_s == ""
          image_type2 = FastImage.type(api_gift2.api_picture_url).to_s
          logger.debug2 "api_gift: provider #{api_gift2.provider}, api_picture_url = #{api_gift2.api_picture_url}, image_type2 = #{image_type2}"
          next unless %w(jpg jpeg gif png bmp).index(image_type2)
          new_api_picture_url = api_gift2.api_picture_url
          break
        end # each api_gift2
        if !new_api_picture_url
          logger.debug2 "api_gift id #{api_gift.id} - did not found api picture url for other provider"
          api_gift.picture = 'N'
          api_gift.api_picture_url = nil
          api_gift.api_picture_url_on_error_at = nil
          api_gift.save!
          next
        end

        # use api_picture_url from other provider
        logger.debug2 "api gift id #{api_gift.id} - found api picture url for an other provider"
        logger.debug2 "old provider #{api_gift.provider}"
        logger.debug2 "url = #{new_api_picture_url}"
        api_gift.api_picture_url = new_api_picture_url
        api_gift.api_picture_url_on_error_at = nil
        api_gift.save!

      end # each api_gift

      format_response

    rescue => e
      logger.debug2 "Exception: #{e.message.to_s} (#{e.class})"
      logger.debug2 "Backtrace: " + e.backtrace.join("\n")
      format_response_key '.mis_api_pic_exception', :error => e.message
    end
  end # missing_api_picture_urls


  #
  # gift link ajax methods
  #

  private
  def check_gift_action (action)
    gift = nil
    actions = %w(like unlike follow unfollow hide delete)
    if !actions.index(action)
      logger.error2 "Invalid call. action #{action}. allowed actions are #{actions.join(', ')}"
      return [gift, '.invalid_action', {:action => action, :raise => I18n::MissingTranslationData}]
    end
    gift_id = params[:gift_id]
    gift = Gift.find_by_id(gift_id)
    if !gift
      logger.debug2 "Gift with id #{gift_id} was not found"
      return [gift, '.gift_not_found', {:raise => I18n::MissingTranslationData}]
    end
    logger.debug2 "logged_in? = #{logged_in?}"
    return [gift, '.not_logged_in', {:raise => I18n::MissingTranslationData}] unless logged_in?
    return [gift, '.gift_deleted', {:raise => I18n::MissingTranslationData}] if gift.deleted_at
    if !gift.visible_for?(@users)
      logger.debug2 "#{User.debug_info(@users)} is/are not allowed to see gift id #{gift_id}"
      return [gift, '.not_authorized', {:raise => I18n::MissingTranslationData}]
    end
    @users.remove_deleted_users
    if !gift.visible_for?(@users)
      logger.debug2 "Found one or more deleted accounts. Remaining users #{User.debug_info(@users)} is/are not allowed to see gift id #{gift_id}"
      return [gift, '.deleted_user', {:raise => I18n::MissingTranslationData}]
    end
    method_name = "show_#{action}_gift_link?".to_sym
    show_action = gift.send(method_name, @users)
    if !show_action
      logger.debug2 "#{action} link no longer active for gift with id #{gift_id}"
      return [gift, '.not_allowed', {:raise => I18n::MissingTranslationData}]
    end
    # ok
    gift
  end # check_gift_action

  private
  def format_gift_action_exception (gift, exception)
    logger.error2 "Action   : #{params[:action]}"
    logger.error2 "Exception: #{exception.message.to_s}"
    logger.error2 "Backtrace: " + exception.backtrace.join("\n")
    format_response_key '.exception',
                    :error => exception.message.to_s,
                    :raise => I18n::MissingTranslationData,
                    :table => gift ? "gift-#{gift.id}-links-errors" : "tasks_errors"
  end # format_gift_action_exception


  public
  def like_gift
    @gift_link_id = @gift_link_href = @gift_link_text = nil
    gift = nil
    params[:action] = 'like_follow_gift' # render this js.erb view
    begin
      gift, key, options = check_gift_action('like')
      if key
        return format_response_key key, options.merge(:table => gift ? "gift-#{gift.id}-links-errors" : "tasks_errors")
      end
      # like gift
      @users.each do |user|
        gl = GiftLike.where("user_id = ? and gift_id = ?", user.user_id, gift.gift_id).first
        if gl
          gl.like = 'Y'
        else
          gl = GiftLike.new
          gl.user_id = user.user_id
          gl.gift_id = gift.gift_id
          gl.like = 'Y'
          gl.show = 'Y'
          gl.follow = nil
        end
        gl.save!
      end # each user
      # like gift ok - change link in gifts/index page
      @gift_link_id = "gift-#{gift.id}-like-unlike-link"
      @gift_link_href = util_unlike_gift_path(:gift_id => gift.id)
      @gift_link_text = t('gifts.api_gift.unlike_gift')
      format_response_key
    rescue => e
      format_gift_action_exception(gift, e)
    end
  end # like_gift

  def unlike_gift
    @gift_link_id = @gift_link_href = @gift_link_text = nil
    gift = nil
    params[:action] = 'like_follow_gift' # render this js.erb view
    begin
      gift, key, options = check_gift_action('unlike')
      if key
        return format_response_key key, options.merge(:table => gift ? "gift-#{gift.id}-links-errors" : "tasks_errors")
      end
      # unlike gift
      @users.each do |user|
        gl = GiftLike.where("user_id = ? and gift_id = ?", user.user_id, gift.gift_id).first
        if gl and gl.like == 'Y'
          gl.like = 'N';
          gl.save!
        end
      end # each user
      # unlike gift ok - change link in gifts/index page
      @gift_link_id = "gift-#{gift.id}-like-unlike-link"
      @gift_link_href = util_like_gift_path(:gift_id => gift.id)
      @gift_link_text = t('gifts.api_gift.like_gift')
      format_response_key
    rescue => e
      format_gift_action_exception(gift, e)
    end
  end # unlike_gift

  def follow_gift
    @gift_link_id = @gift_link_href = @gift_link_text = nil
    gift = nil
    params[:action] = 'like_follow_gift' # render this js.erb view
    begin
      gift, key, options = check_gift_action('follow')
      if key
        return format_response_key key, options.merge(:table => gift ? "gift-#{gift.id}-links-errors" : "tasks_errors")
      end
      # follow gift
      @users.each do |user|
        gl = GiftLike.where("user_id = ? and gift_id = ?", user.user_id, gift.gift_id).first
        if gl
          gl.follow = 'Y'
        else
          gl = GiftLike.new
          gl.user_id = user.user_id
          gl.gift_id = gift.gift_id
          gl.like = 'N'
          gl.show = 'Y'
          gl.follow = 'Y'
        end
        gl.save!
      end # each user
      # follow gift ok - change link in gifts/index page
      @gift_link_id = "gift-#{gift.id}-follow-unfollow-link"
      @gift_link_href = util_unfollow_gift_path(:gift_id => gift.id)
      @gift_link_text = t('gifts.api_gift.unfollow_gift')
      format_response_key
    rescue => e
      format_gift_action_exception(gift, e)
    end
  end # follow_gift

  def unfollow_gift
    @gift_link_id = @gift_link_href = @gift_link_text = nil
    gift = nil
    params[:action] = 'like_follow_gift' # render this js.erb view
    begin
      gift, key, options = check_gift_action('unfollow')
      if key
        return format_response_key key, options.merge(:table => gift ? "gift-#{gift.id}-links-errors" : "tasks_errors")
      end
      # unfollow gift
      @users.each do |user|
        gl = GiftLike.where("user_id = ? and gift_id = ?", user.user_id, gift.gift_id).first
        if !gl
          gl = GiftLike.new
          gl.user_id = user.user_id
          gl.gift_id = gift.gift_id
          gl.like = 'N'
          gl.show = 'Y'
        end
        gl.follow = 'N'
        gl.save!
      end # each user
      # unfollow gift ok - change link in gifts/index page
      @gift_link_id = "gift-#{gift.id}-follow-unfollow-link"
      @gift_link_href = util_follow_gift_path(:gift_id => gift.id)
      @gift_link_text = t('gifts.api_gift.follow_gift')
      format_response_key
    rescue => e
      format_gift_action_exception(gift, e)
    end
  end # unfollow_gift

  def hide_gift
    @gift_id = nil
    gift = nil
    params[:action] = 'hide_delete_gift' # render this js.erb view
    begin
      # validate hide gift
      gift, key, options = check_gift_action('hide')
      if key
        return format_response_key key, options.merge(:table => gift ? "gift-#{gift.id}-links-errors" : "tasks_errors")
      end
      # hide gift - db
      @users.each do |user|
        gl = GiftLike.where("user_id = ? and gift_id = ?", user.user_id, gift.gift_id).first
        if gl
          gl.show = 'N'
        else
          gl = GiftLike.new
          gl.user_id = user.user_id
          gl.gift_id = gift.gift_id
          gl.like = 'N'
          gl.follow = 'N'
          gl.show = 'N'
        end
        gl.save!
      end
      # hide gift ok - remove gift from gifts/index page
      @gift_id = gift.id
      format_response_key
    rescue => e
      format_gift_action_exception(gift, e)
    end
  end # hide_gift

  def delete_gift
    @gift_id = nil
    gift = nil
    params[:action] = 'hide_delete_gift' # render this js.erb view
    begin
      # validate delete gift
      gift, key, options = check_gift_action('delete')
      if key
        return format_response_key key, options.merge(:table => gift ? "gift-#{gift.id}-links-errors" : "tasks_errors")
      end
      # delete mark gift. Delete marked gifts will be ajax removed from other sessions within the
      # next 5 minutes and will be physical deleted after 5 minutes
      gift.deleted_at = Time.new
      gift.save!
      if gift.received_at and gift.price and gift.price != 0.0
        # recalculate balance - todo: should only recalculate balance from previous gift and forward
        gift.giver.recalculate_balance if gift.giver
        gift.receiver.recalculate_balance if gift.receiver
      end
      # delete gift ok - remove gift from gifts/index page
      @gift_id = gift.id
      format_response_key
    rescue => e
      format_gift_action_exception(gift, e)
    end
  end # delete_gift


  #
  # comment link ajax methods
  #

  # helper for cancel_new_deal, reject_new_deal and accept_new_deal
  # input: params[:comment_id] and action in %w(cancel reject accept)
  # returns array [comment, key, options] - key and options are used for error messages
  private
  def check_new_deal_action (action)
    comment = key = options = nil
    actions = %w(cancel reject accept)
    if !actions.index(action)
      logger.error2 "Invalid call. action #{action}. allowed actions are #{actions.join(', ')}"
      return [comment, '.invalid_action', {:raise => I18n::MissingTranslationData} ]
    end
    comment_id = params[:comment_id]
    comment = Comment.find_by_id(comment_id)
    if !comment
      logger.warn2 "Comment with id #{comment_id} was not found. Possible error as deleted comments are ajax removed from gifts/index page within 5 minutes"
      return [comment, '.comment_not_found', {:raise => I18n::MissingTranslationData}]
    end
    return [comment, '.not_logged_in', {:raise => I18n::MissingTranslationData}] unless logged_in?
    gift = comment.gift
    return [comment, '.gift_deleted', {:raise => I18n::MissingTranslationData}] if gift.deleted_at
    if !gift.visible_for?(@users)
      if action == 'cancel'
        # cancel proposal - changed friend relation
        logger.debug2 "Login users are no longer allowed to see gift id #{gift_id}. Could be removed friend. Could be system error"
      else
        # rejected or accept proposal
        logger.error2 "System error. Login users are not allowed to see gift id #{gift_id}"
      end
      return [comment, '.not_authorized', {:raise => I18n::MissingTranslationData}]
    end
    @users.remove_deleted_users
    if !gift.visible_for?(@users)
      logger.debug2 "Found one or more deleted accounts. Remaining users #{User.debug_info(@users)} is/are not allowed to see gift id #{gift_id}"
      return [comment, '.deleted_user', {:raise => I18n::MissingTranslationData}]
    end
    return [comment, gift, '.comment_deleted', {:raise => I18n::MissingTranslationData}] if comment.deleted_at
    method_name = "show_#{action}_new_deal_link?".to_sym
    show_action = comment.send(method_name, @users)
    if !show_action
      logger.debug2  "#{action} link no longer active for comment with id #{comment_id}"
      return [comment, '.not_allowed', {:raise => I18n::MissingTranslationData}]
    end
    # ok
    comment
  end # check_new_deal_action

  # Parameters: {"comment_id"=>"478"}
  public
  def cancel_new_deal
    @link_id = nil
    table = 'tasks_errors' # tasks errors table in top of page
    params[:action] = 'cancel_reject_new_deal' # render this js.erb view
    begin
      # validate new deal reject action
      comment, key, options = check_new_deal_action('cancel')
      table = "gift-#{comment.gift.id}-comment-#{comment.id}-errors" if comment # ajax error table under comment row
      return format_response_key key, options.merge(:table => table) if key
      gift = comment.gift
      # cancel agreement proposal
      comment.new_deal_yn = nil
      comment.updated_by = login_user_ids.join(',')
      comment.save!
      # hide link
      @link_id = "gift-#{gift.id}-comment-#{comment.id}-cancel-link"
      format_response_key 'cancel_reject_new_deal', :table => table
    rescue => e
      logger.error2 "Exception: #{e.message.to_s}"
      logger.error2 "Backtrace: " + e.backtrace.join("\n")
      @link_id = nil
      format_response_key '.exception', :error => e.message.to_s, :raise => I18n::MissingTranslationData, :table => table
      logger.error2 "@errors = #{@errors}"
    end
  end # cancel_new_deal

  def reject_new_deal
    @link_id = nil
    table = 'tasks_errors' # tasks errors table in top of page
    params[:action] = 'cancel_reject_new_deal' # render this js.erb view
    begin
      # validate new deal reject action
      comment, key, options = check_new_deal_action('reject')
      table = "gift-#{comment.gift.id}-comment-#{comment.id}-errors" if comment # ajax error table under comment row
      return format_response_key key, options.merge(:table => table) if key
      gift = comment.gift
      # reject agreement proposal
      comment.accepted_yn = 'N'
      comment.updated_by = login_user_ids.join(',')
      comment.save!
      # hide links
      # todo: other comment changes? Maybe an other layout, style, color for accepted gift/comments
      # todo: change gift and comment for other users after reject (new messages count ajax)?
      @link_id = "gift-#{gift.id}-comment-#{comment.id}-reject-link"
      format_response_key '.ok', :table => table
    rescue => e
      logger.error2 "Exception: #{e.message.to_s}"
      logger.error2 "Backtrace: " + e.backtrace.join("\n")
      @link_id = nil
      format_response_key '.exception', :error => e.message.to_s, :raise => I18n::MissingTranslationData, :table => table
      logger.error2 "@errors = #{@errors}"
    end
  end # reject_new_deal

  def accept_new_deal
    @api_gifts = nil
    table = 'tasks_errors' # tasks errors table in top of page
    begin
      # validate new deal action
      comment, key, options = check_new_deal_action('accept')
      table = "gift-#{comment.gift.id}-comment-#{comment.id}-errors" if comment # ajax error table under comment row
      return format_response_key key, options.merge(:table => table) if key
      # accept agreement proposal - mark proposal as accepted - callbacks sent notifications and updates gift
      # logger.debug2  "comment.currency = #{comment.currency}"
      # find correct updated_by users
      # 1) user_id must be in api_gifts
      # 2) user_id must be in @users
      # 3) provider must be in api comments
      api_comment_providers = comment.api_comments.collect { |ac| ac.provider }
      updated_by = []
      gift = comment.gift
      api_gift = nil
      gift.api_gifts.each do |ag|
        user_id = ag.user_id_giver || ag.user_id_receiver
        if !login_user_ids.index(user_id)
          # logger.debug2 "ignoring user_id #{user_id} - not logged in"
          nil # ignore api gift row not created by login users
        elsif !api_comment_providers.index(ag.provider)
          # logger.debug2 "ingoring user_id #{user_id} - no new proposal for this provider"
          nil # ignore api gift rows without new proposal from other user
        else
          # ok - match between gift creator, current logged in user and new deal proposal provider
          # logger.debug2 "found valid updated_by user_id #{user_id}"
          updated_by << user_id
          api_gift = ag
        end
      end
      if updated_by.size == 0
        # system error - should have been rejected in check_new_deal_action('accept')
        logger.error2 "Could not find valid updated_by user ids. gift id #{gift.id}, comment id #{comment.id}"
        logger.error2 "gift created by " + gift.api_gifts.collect { |ag| ag.user_id_giver || ag.user_id_receiver }.join(', ')
        logger.error2 "logged in users " + @users.collect { |u| u.user_id }.join(', ')
        logger.error2 "new deal providers " + api_comment_providers.join(', ')
        return format_response_key '.invalid_updated_by', :table => table
      end
      comment.accepted_yn = 'Y'
      comment.updated_by = updated_by.join(',')
      comment.save!
      gift.reload
      if gift.price and gift.price != 0.0
        # recalculate new balance for giver and receiver
        gift.reload
        gift.api_gifts.each do |api_gift|
          api_gift.giver.recalculate_balance unless api_gift.giver.dummy_user?
          api_gift.receiver.recalculate_balance unless api_gift.receiver.dummy_user?
        end # each api_gift
        # todo: ajax inject change balance in page header
      end

      # use a discount version af new_messages_count to ajax replace accepted deal in gifts/index page for current user
      # that is without @new_messages_count, @comments, only with this accepted gift and without new values for new-newest-gift-id andnew-newest-status-update-at
      # only client insert_update_gifts JS function is called
      # next new_mesage_count request will ajax replace this gift once more, but that is a minor problem
      api_gift.reload
      @api_gifts = [api_gift]
      format_response_key '.ok', :table => table
    rescue => e
      logger.error2 "Exception: #{e.message.to_s}"
      logger.error2 "Backtrace: " + e.backtrace.join("\n")
      format_response_key '.exception', :error => e.message.to_s, :raise => I18n::MissingTranslationData, :table => table
      logger.error2 "@errors = #{@errors}"
      @api_gifts = nil
    end
  end # accept_new_deal

  # return currency for page header.
  # see .user_currency_new class event handler in see my.js
  # todo: user has to click twice on currency LOV to see list of currencies (first onfocus event and next onclick event)
  def currencies
    if User.dummy_users?(@users)
      render :nothing => true
    else
      logger.debug2 "return currencies to client on onfocus event"
      render :layout => false
    end
  end

  # process tasks from queue
  # that is tasks that could slow request/response cycle or information that is not available on server (client timezone)
  # tasks:
  # - download user profile image from login provider after login (ok)
  # - get permissions from login provider after login (todo: twitter)
  # - get friend lists from login provider after login (ok)
  # - get currency rates for a new date (ok)
  # - upload post and optional picture to login provider (ok)
  def do_tasks
    begin
      # todo: debug why IE is not setting state before redirecting to facebook in facebook/autologin
      logger.debug2 "session[:session_id] = #{session[:session_id]}, session[:state] = #{session[:state]}"
      # save timezone received from javascript
      set_timezone(params[:timezone])
      # todo: debug problems with session[:last_row_id]
      logger.debug2 "session[:last_row_id] = #{get_last_row_id()}"
      # cleanup old tasks
      Task.where("created_at < ? and ajax = ?", 2.minute.ago, 'Y').destroy_all
      Task.where("created_at < ? and ajax = ?", 10.minute.ago, 'N').destroy_all
      Task.where("session_id = ? and ajax = ?", session[:session_id], 'Y').order('priority, id').each do |at|
        at.destroy
        if !logged_in?
          logger.warn2 "not logged in. Ignoring task #{at.task}"
          next
        end
        # all tasks must have exception handlers with backtrace.
        # Exception handler for eval will not display backtrace within the called task
        logger.debug2 ""
        logger.debug2 "executing task #{at.task}\n"
        begin
          eval(at.task)
        rescue => e
          logger.debug2 "error when processing task #{at.task}"
          logger.debug2 "Exception: #{e.message.to_s}"
          logger.debug2 "Backtrace: " + e.backtrace.join("\n")
          add_error_key '.do_task_exception', :task => at.task, :error => e.message.to_s
        end
        # logger.debug2  "task #{at.task}, response = #{res}"
        # next unless res
        ## check response from task. Must be a valid input to translate
        #begin
        #  key, options = res
        #  key2 = key
        #  key2 = 'shared.translate_ajax_errors' + key if key2.to_s.first(1) == '.'
        #  options = {} unless options
        #  options[:raise] = I18n::MissingTranslationData
        #  t key2, options
        #rescue I18n::MissingTranslationData => e
        #  res = [ '.ajax_task_missing_translate_key', { :key => key, :task => at.task, :response => res, :exception => e.message.to_s } ]
        #rescue I18n::MissingInterpolationArgument => e
        #  logger.debug2  "exception = #{e.message.to_s}"
        #  logger.debug2  "response = #{res}"
        #  argument = $1 if e.message.to_s =~ /:(.+?)\s/
        #  logger.debug2  "argument = #{argument}"
        #  res = [ '.ajax_task_missing_translate_arg', { :key => key, :task => at.task, :argument => argument, :response => res, :exception => e.message.to_s } ]
        #rescue => e
        #  logger.debug2  "invalid response from task #{at.task}. Must be nil or a valid input to translate. Response: #{res}"
        #  res = [ '.ajax_task_invalid_response', { :task => at.task, :response => res, :exception => e.message.to_s }]
        #end
        # logger.debug2  "task = #{at.task}, res = #{res}"
      end
      logger.debug2 "@errors.size = #{@errors.size}"
      if @errors.size == 0
        render :nothing => true
      else
        format_response
      end
    rescue => e
      logger.debug2  "Exception: #{e.message.to_s} (#{e.class})"
      logger.debug2  "Backtrace: " + e.backtrace.join("\n")
      format_response_key '.do_tasks_exception', :error => e.message.to_s
    end
  end # do_tasks

  private
  def fetch_exchange_rates
    begin
      key, options = ExchangeRate.fetch_exchange_rates
      return add_error_key key, options if key
    rescue => e
      logger.debug2  "Exception: #{e.message.to_s} (#{e.class})"
      logger.debug2  "Backtrace: " + e.backtrace.join("\n")
      raise
    end
  end

  private
  def get_login_user_and_token (provider, task)
    login_user = token = nil
    # find user id and token for provider
    login_user = @users.find { |user| user.provider == provider }
    login_user_id = login_user.user_id if login_user
    return [login_user, token,
            'util.do_tasks.login_user_id_not_found',
            {:provider => provider, :apiname => provider_downcase(provider), :task => task}] unless login_user_id
    login_user = User.find_by_user_id(login_user_id)
    return [login_user, token,
            'util.do_tasks.login_user_id_unknown',
            {:provider => provider, :apiname => provider_downcase(provider), :user_id => login_user_id, :task => task}] unless login_user
    # get token for api requests
    token = (session[:tokens] || {})[provider]
    return [login_user, token,
            'util.do_tasks.login_token_not_found',
            {:provider => provider, :apiname => provider_downcase(provider), :task => task}] if token.to_s == ""
    # logger.debug2  "token = #{token}"
    # ok
    return [login_user, token]
  end # get_login_user_and_token

  private
  def get_login_user_and_api_client (provider, task)
    api_client = nil
    login_user, token, key, options = get_login_user_and_token(provider, task)
    return [login_user, api_client, key, options] if key
    logger.secret2 "provider = #{provider}, token = #{token}"

    key, options = init_api_client(provider, token) # returns [key, options] (error) or [api_client, nil] (ok)
    api_client, key = key, nil if key.class != String
    [login_user, api_client, key, options]
  end # get_login_user_and_api_client

  def get_gift_and_deep_link (id, login_user, provider)
    api_gift = deep_link = nil

    # find and check gift and api_gift
    gift = Gift.find_by_id(id)
    return [gift, api_gift, deep_link, '.post_on_api_unknown_gift_id', { :provider => provider, :id => id }] unless gift
    api_gift = ApiGift.find_by_gift_id_and_provider(gift.gift_id, provider)
    return [gift, api_gift, deep_link, '.post_on_api_invalid_gift_id', { :provider => provider, :id => gift.id }] unless api_gift
    return [gift, api_gift, deep_link, '.post_on_api_invalid_gift_id', { :provider => provider, :id => gift.id }] unless [api_gift.user_id_giver, api_gift.user_id_receiver].index(login_user.user_id)
    return [gift, api_gift, deep_link, '.post_on_api_old_gift', { :provider => provider, :id => gift.id }] unless gift.created_at > 5.minute.ago
    return [gift, api_gift, deep_link, '.post_on_api_deleted_gift', { :provider => provider, :id => gift.id }] if gift.deleted_at

    # check picture if any - must exists in /images/temp folder before post on API wall
    return [gift, api_gift, deep_link, '.gift_posted_6_html', { :apiname => provider}] if api_gift.picture? and !gift.rel_path_picture_exists?

    # initialize and check deep link
    deep_link = api_gift.init_deep_link()
    if error = api_gift.deep_link_invalid?
      # error in deep link page - stop post on API and return error message with deep link and error to gifts/index page
      return [gift, api_gift, deep_link, ".gift_posted_7_html", { :apiname => provider, :link => deep_link, :error => error }]
    end

    # ok
    return [gift, api_gift, deep_link]
  end # get_gift_and_deep_link


  ## ajax inject error message to gifts/index page if post_login_<provider> task was not found
  ## there must be one post_login_<provider> task for each login provider to download friend list
  #private
  #def post_login_not_found(provider)
  #  begin
  #
  #    # no post_login_<provider> task was found (app. controller.login)
  #    # write error message to developer with instructions how to fix this problem
  #    logger.error2 "util.post_login_#{provider} method was not found. please create a post login task to download friend list from login provider"
  #    [ '.post_login_task_not_found', {:provider => provider}]
  #
  #  rescue => e
  #    logger.debug2  "Exception: #{e.message.to_s}"
  #    logger.debug2  "Backtrace: " + e.backtrace.join("\n")
  #    raise
  #  end
  #end

  # returns [login_user, api_client, friends_hash, new_user, key, options] array
  # key + options are used as input to translate after errors
  private
  def post_login_update_friends (provider)
    friends_hash = new_user = nil
    login_user, api_client, key, options = get_login_user_and_api_client(provider, __method__)
    return [login_user, api_client, friends_hash, new_user, key, options] if key
    login_user_id = login_user.user_id

    # update user
    # note what many fields are updated in User.find_or_create_user doing login
    # only use this method for fields that are not updated in login process
    if api_client.respond_to? :gofreerev_get_user
      # fetch info about login user from API
      user_hash, key, options = api_client.gofreerev_get_user logger
      logger.debug2 "user_hash = #{user_hash}, key = #{key}, options = #{options}"
      return [login_user, api_client, friends_hash, new_user, key, options] if key
      # update user
      key, options = login_user.update_api_user_from_hash user_hash
      return [login_user, api_client, friends_hash, new_user, key, options] if key
      login_user.reload
      logger.debug2 "api_profile_picture_url = #{login_user.api_profile_picture_url}"
    else
      logger.debug "no gofreerev_get_user method was found for #{provider} api client"
    end

    # get API friends
    if !api_client.respond_to? :gofreerev_get_friends
      # api client without gofreerev_get_friends method - cannot download and update friend list from api provider
      key, options = ['.api_client_gofreerev_get_friends', login_user.app_and_apiname_hash]
      return [login_user, api_client, friends_hash, new_user, key, options]
    end
    begin
      friends_hash, key, options = api_client.gofreerev_get_friends logger
    rescue AppNotAuthorized => e
      # app has been deauthorized after login and before executing post login task for this provider
      logout(provider)
      key, options = ['.post_login_fl_not_authorized', login_user.app_and_apiname_hash]
      return [login_user, api_client, friends_hash, new_user, key, options]
    end
    return [login_user, api_client, friends_hash, new_user, key, options] if key

    # update friends list in db (api friend = Y/N)
    new_user, key, options = Friend.update_api_friends_from_hash :login_user_id => login_user_id, :friends_hash => friends_hash
    [login_user, api_client, friends_hash, new_user, key, options]
  end # post_login_update_friends

  # generic post login task - used if post_login_<provider> does not exist
  # upload and updates friend list and updates user balance
  private
  def generic_post_login (provider)
    begin
      # get login user, initialize api client, get and update friends information
      login_user, api_client, friends_hash, new_user, key, options = post_login_update_friends(provider)
      #logger.debug2 "login_user   = #{login_user}"
      #logger.debug2 "api_client   = #{api_client}"
      #logger.debug2 "friends_hash = #{friends_hash}"
      #logger.debug2 "new_user     = #{new_user}"
      #logger.debug2 "key          = #{key}"
      #logger.debug2 "options      = #{options}"
      return add_error_key(key, options) if key

      # update number of friends.
      # facebook: number of friends is not 100 % correct as not all friends are returned from facebook api
      # todo: how to set number of friends for follows/followed_by networks (twitter)
      # todo: is number of friends use for anything?
      login_user.update_attribute(:no_api_friends, friends_hash.size)

      # update balance
      today = Date.parse(Sequence.get_last_exchange_rate_date)
      login_user.recalculate_balance if today and login_user.balance_at != today

      # warning if empty friend list in post login
      # could be a new user - could be that app is not authorized to see friends
      # ignore empty friend list in facebook oauth 2.x facebook
      return add_error_key('.post_login_no_friends', login_user.app_and_apiname_hash) if friends_hash.size == 0 and !%w(facebook).index(provider)

      # special post login message to new users (refresh page when friend list has been downloaded)
      return add_error_key('.post_login_new_user', login_user.app_and_apiname_hash) if new_user

      # ok
      nil
    rescue AppNotAuthorized
      logout :provider => provider
      return add_error_key('.linkedin_access_denied', {:provider => provider})
    rescue LinkedIn::Errors::AccessDeniedError => e
      return add_error_key('.linkedin_access_denied', {:provider => provider}) if e.message.to_s =~ /Access to connections denied/
      logger.debug2  "Exception: #{e.message.to_s} (#{e.class})"
      logger.debug2  "Backtrace: " + e.backtrace.join("\n")
      raise
    rescue => e
      logger.debug2  "Exception: #{e.message.to_s} (#{e.class})"
      logger.debug2  "Backtrace: " + e.backtrace.join("\n")
      raise
    end
  end # generic_post_login

  # post login task for facebook - get permissions and friends - using koala gem
  # called from do_tasks - ajax requests after login
  # must return nil or a valid input to translate
  #private
  #def post_login_facebook
  #  begin
  #    ## get facebook user and facebook api client (koala)
  #    provider = "facebook"
  #
  #    # get login user, initialize api client, get and update friends information
  #    login_user, api_client, friends_hash, new_user, key, options = post_login_update_friends(provider)
  #    return [key, options] if key.class == String
  #    login_user_id = login_user.user_id
  #
  #    # get user information - permissions and picture
  #    api_request = 'me?fields=permissions,picture'
  #    # logger.debug2  "api_request = #{api_request}"
  #    api_response = api_client.get_object api_request
  #    # logger.debug2  "api_response = #{api_response.to_s}"
  #
  #    # update permissions
  #    login_user.permissions = api_response['permissions']['data']
  #    login_user.permissions = {} if login_user.permissions == []
  #    login_user.save!
  #
  #    # update profile picture - picture received in auth/create is too small
  #    image = api_response['picture']['data']['url'] if api_response['picture'] and api_response['picture']['data']
  #    logger.debug2 "image = #{image}"
  #    key, options = User.update_profile_image(login_user_id, image)
  #    return [key, options] if key # error when updating profile picture information
  #
  #    # special post login message to new users
  #    return ['.post_login_new_user', login_user.app_and_apiname_hash ] if new_user
  #
  #    # ok
  #    nil
  #  rescue => e
  #    logger.debug2  "Exception: #{e.message.to_s}"
  #    logger.debug2  "Backtrace: " + e.backtrace.join("\n")
  #    raise
  #  end
  #end # post_login_facebook



  ## post login task for flickr - get connections
  ## using flickraw gem
  ## called from do_tasks - ajax requests after login
  ## must return nil or a valid input to translate  private
  #private
  #def post_login_flickr
  #  begin
  #
  #    # get flickr login user flickraw api client
  #    provider = "flickr"
  #
  #    # get login user, initialize api client, get and update friends information
  #    login_user, api_client, friends_hash, new_user, key, options = post_login_update_friends(provider)
  #    return [key, options] if key.class == String
  #
  #    # 3) update balance
  #    login_user.recalculate_balance if login_user.balance_at != Date.today
  #
  #    # special post login message to new users
  #    return ['.post_login_new_user', login_user.app_and_apiname_hash ]if new_user
  #
  #    # ok
  #    nil
  #
  #  rescue => e
  #    logger.debug2  "Exception: #{e.message.to_s} (#{e.class})"
  #    logger.debug2  "Backtrace: " + e.backtrace.join("\n")
  #    raise
  #  end
  #end # post_login_flickr
  
  ## post login task for foursquare - get friends - using foursquare2 gem
  ## called from do_tasks - ajax requests after login
  ## must return nil or a valid input to translate
  ## friends information is included in auth_hash that is received in post auth/create,
  ## but friends update can take some time and is done here in post_login_foursquare
  #private
  #def post_login_foursquare
  #  begin
  #    # get facebook user and foursquare2 api client
  #    provider = "foursquare"
  #
  #    # get login user, initialize api client, get and update friends information
  #    login_user, api_client, friends_hash, new_user, key, options = post_login_update_friends(provider)
  #    return [key, options] if key.class == String
  #
  #    # special post login message to new users
  #    return ['.post_login_new_user', login_user.app_and_apiname_hash ]if new_user
  #
  #    # ok
  #    nil
  #  rescue => e
  #    logger.debug2  "Exception: #{e.message.to_s}"
  #    logger.debug2  "Backtrace: " + e.backtrace.join("\n")
  #    raise
  #  end
  #end # post_login_foursquare

  ## post login task for google+
  ## using google-api-client
  ## called from do_tasks - ajax requests after login
  ## must return nil or a valid input to translate
  #private
  #def post_login_google_oauth2
  #  begin
  #    # get google user and api client
  #    provider = "google_oauth2"
  #
  #    # get login user, initialize api client, get and update friends information
  #    login_user, api_client, friends_hash, new_user, key, options = post_login_update_friends(provider)
  #    return [key, options] if key.class == String
  #
  #    # 3) update balance
  #    login_user.recalculate_balance if login_user.balance_at != Date.today
  #
  #    # special post login message to new users
  #    return ['.post_login_new_user', login_user.app_and_apiname_hash ]if new_user
  #
  #    # ok
  #    nil
  #  rescue => e
  #    logger.error2  "Exception: #{e.message.to_s}"
  #    logger.error2  "Backtrace: " + e.backtrace.join("\n")
  #    raise
  #  end
  #end # post_login_google_oauth2

  ## post login task for instagram - get follows and followed-by friend lists
  ## using instagram gem
  ## called from do_tasks - ajax requests after login
  ## must return nil or a valid input to translate  private
  #private
  #def post_login_instagram
  #  begin
  #
  #    # get instagram user and instagram api client
  #    provider = "instagram"
  #
  #    # get login user, initialize api client, get and update friends information
  #    login_user, api_client, friends_hash, new_user, key, options = post_login_update_friends(provider)
  #    return [key, options] if key.class == String
  #
  #    # 3) update balance
  #    login_user.recalculate_balance if login_user.balance_at != Date.today
  #
  #    # special post login message to new users
  #    return ['.post_login_new_user', login_user.app_and_apiname_hash ]if new_user
  #
  #    # ok
  #    nil
  #
  #  rescue => e
  #    logger.debug2  "Exception: #{e.message.to_s} (#{e.class})"
  #    logger.debug2  "Backtrace: " + e.backtrace.join("\n")
  #    raise
  #  end
  #end # post_login_instagram
  

  ## post login task for linkedIn - get connections
  ## using linked gem
  ## is using old version 0.4.4 - map error in 0.4.6 - https://github.com/hexgnu/linkedin/issues/216
  ## called from do_tasks - ajax requests after login
  ## must return nil or a valid input to translate  private
  #private
  #def post_login_linkedin
  #  begin
  #
  #    # get linkedin user and linkedin api client
  #    provider = "linkedin"
  #
  #    # get login user, initialize api client, get and update friends information
  #    login_user, api_client, friends_hash, new_user, key, options = post_login_update_friends(provider)
  #    return [key, options] if key.class == String
  #
  #    # 3) update balance
  #    login_user.recalculate_balance if login_user.balance_at != Date.today
  #
  #    # special post login message to new users
  #    return ['.post_login_new_user', login_user.app_and_apiname_hash ]if new_user
  #
  #    # ok
  #    nil
  #
  #  rescue LinkedIn::Errors::AccessDeniedError => e
  #    return ['.linkedin_access_denied', {:provider => provider}] if e.message.to_s =~ /Access to connections denied/
  #    logger.debug2  "Exception: #{e.message.to_s} (#{e.class})"
  #    logger.debug2  "Backtrace: " + e.backtrace.join("\n")
  #    raise
  #  rescue => e
  #    logger.debug2  "Exception: #{e.message.to_s} (#{e.class})"
  #    logger.debug2  "Backtrace: " + e.backtrace.join("\n")
  #    raise
  #  end
  #end # post_login_linkedin


  ## post login task for twitter - get friends
  ## using twitter gem
  ## called from do_tasks - ajax requests after login
  ## must return nil or a valid input to translate  private
  #private
  #def post_login_twitter
  #  begin
  #
  #    # get twitter user, friends and twitter api client
  #    provider = "twitter"
  #
  #    # get login user, initialize api client, get and update friends information
  #    login_user, api_client, friends_hash, new_user, key, options = post_login_update_friends(provider)
  #    return [key, options] if key.class == String
  #
  #    # 3) update balance
  #    login_user.recalculate_balance if login_user.balance_at != Date.today
  #
  #    # special post login message to new users
  #    return ['.post_login_new_user', login_user.app_and_apiname_hash ]if new_user
  #
  #    # ok
  #    nil
  #
  #  rescue => e
  #    logger.debug2  "Exception: #{e.message.to_s} (#{e.class})"
  #    logger.debug2  "Backtrace: " + e.backtrace.join("\n")
  #    raise
  #  end
  #end # post_login_twitter


  ## post login task for vkontakte - get friends
  ## using vkontakte gem
  ## called from do_tasks - ajax requests after login
  ## must return nil or a valid input to translate  private
  #private
  #def post_login_vkontakte
  #  begin
  #
  #    # get vkontakte user (no "api client" for vkontakte)
  #    provider = "vkontakte"
  #
  #    # get login user, initialize api client, get and update friends information
  #    login_user, api_client, friends_hash, new_user, key, options = post_login_update_friends(provider)
  #    return [key, options] if key.class == String
  #
  #    # 3) update balance
  #    login_user.recalculate_balance if login_user.balance_at != Date.today
  #
  #    # special post login message to new users
  #    return ['.post_login_new_user', login_user.app_and_apiname_hash ]if new_user
  #
  #    # ok
  #    nil
  #
  #  rescue => e
  #    logger.debug2  "Exception: #{e.message.to_s} (#{e.class})"
  #    logger.debug2  "Backtrace: " + e.backtrace.join("\n")
  #    raise
  #  end
  #end # post_login_vkontakte
  
  
  # recalculate user balance
  # use after login, at new day, after new deal, after deleted deal etc
  def recalculate_user_balance (id)
    begin
      # check id
      user = User.find_by_id(id)
      return ['.recal_user_bal_unknown_id',{}] unless user
      return ['.recal_user_bal_invalid_id',{}] unless login_user_ids.index(user.user_id)

      # recalculate balance for user or for user combination
      today = Date.parse(Sequence.get_last_exchange_rate_date)
      if user.share_account_id
        users = User.where('share_account_id = ? and (balance_at is null or balance_at <> ?)', user.share_account_id, today)
        if users.size > 0
          # todo. User.recalculate_balance class method is not tested
          res = User.recalculate_balance(users)
        end
      else
        res = user.recalculate_balance if !user.balance_at or user.balance_at != today
      end
      ['.recal_user_cal_pending',{}] unless res

      nil

    rescue => e
      logger.debug2  "Exception: #{e.message.to_s} (#{e.class})"
      logger.debug2  "Backtrace: " + e.backtrace.join("\n")
      raise
    end
  end # recalculate_user_balance


  # get url for api gift picture on facebook wall - size >= 200 x 200
  # used in post_in_facebook and in missing_api_picture_urls
  # raises ApiPostNotFoundException if post/picture was not found (missing permission or post/picture has been deleted)
  # that is - get_api_picture_url_facebook is also used to check for missing read stream permission
  # return nil (ok) or [key, options] error input to translate
  # params:
  # - just_posted - true if called from post_on_facebook - false if called from missing_api_picture_urls
  # - api_client - koala api client
  private
  def get_api_picture_url_facebook (api_gift, just_posted=true, api_client) # api is Koala API client

    return nil if api_gift.deleted_at_api == 'Y' # ignore - post/picture has been deleted from facebook wall

    provider = "facebook"
    login_user, token, key, options = get_login_user_and_token(provider, __method__)
    return [key, options] if key

    #if !api_client
    #  # get access token and initialize koala api client
    #  raise "api_client is nil"
    #  api_client = init_api_client_facebook(token)
    #end

    # two koala api request. 1) get picture and object_id, 2) get an array with different size pictures

    # 1) get picture and object id
    object_id = nil
    begin
      # check read access to facebook wall and get object_id for next api request (only for post with picture)
      res1 = api_client.get_object api_gift.api_gift_id
      # logger.debug2 "res1 = #{res1}"
      api_gift.api_gift_url = res1['link']
      object_id, picture = res1['object_id'], res1['picture']
      image_type = FastImage.type(picture) if picture.to_s != ""
      logger.debug2 "first lookup: object_id = #{object_id}, picture = #{picture}, image type = #{image_type}"
      if api_gift.picture?
        if %w(jpg jpeg gif png bmp).index(image_type.to_s)
          # valid (small) picture url received from facebook
          api_gift.api_picture_url = picture
          api_gift.api_picture_url_updated_at = Time.now
          api_gift.api_picture_url_on_error_at = nil
        else
          # unexpected error - found post, but did not get a valid picture url
          logger.debug2 "Did not get a picture url from api. Must be problem with missing access token, picture != Y or deleted_at_api == Y"
          logger.debug2 "res1 = #{res1}"
          return ['.no_api_picture_url', {:apiname => login_user.apiname}]
        end
      end
      api_gift.save!
    rescue Koala::Facebook::ClientError => e
      if e.fb_error_type == 'GraphMethodException' and e.fb_error_code == 100
        # identical error response if picture is deleted or if user is not allowed to see picture
        # picture not found - maybe picture has been deleted - maybe a permission problem
        # granting read_stream or changing visibility of app setting to public can solve the problem
        # read_stream permission will be requested if error is raise when posting on facebook wall
        logger.debug2 "Handling Koala::Facebook::ClientError, GraphMethodException' with FB error code 100."
        logger.debug2 "just_posted = #{just_posted}"

        # problem with upload and permissions
        # could not get full_picture url for an uploaded picture
        # the problem appeared after changing app visibility from friends to only me
        # that is - app is not allowed to get info about the uploaded picture!!

        if !FACEBOOK_READ_STREAM
          # facebook oauth 2.2 - read_stream priv. requires special approval process - skip request.
          api_gift.deleted_at_api = 'Y'
          api_gift.save!
          if just_posted
            return ['.fb_pic_post_declined_permission_html', {:appname => APP_NAME, :apiname => login_user.apiname} ]
          else
            return nil
          end
        end

        # just display a warning and continue. Request read_stream permission from user if read_stream priv. is missing
        api_gift.deleted_at_api = 'Y' if just_posted
        api_gift.save!
        # (re)check permissions
        if login_user.read_gifts_allowed?
          # check if user has removed read stream priv.
          login_user.get_permissions_facebook(api_client)
        end
        if login_user.read_gifts_allowed?
          if !just_posted
            # called from missing_api_picture_urls - user has deleted post on api wall
            logger.debug2 "user has deleted post on api wall - ok"
            return nil
          end
          # just posted + read permission to call - error - this should not happen.
          logger.debug2 "just posted + read permission to call - error - this should not happen"
          key = api_gift.picture? ? '.fb_pic_post_unknown_problem' : '.fb_msg_post_unknown_problem'
          return [key, {:appname => APP_NAME, :apiname => login_user.apiname}]
        else
          # message with link to grant missing read stream priv.
          logger.debug2 "user.permissions = #{login_user.permissions}"
          # check if user has declined read_stream permission
          if api_gift.picture? and login_user.permissions.find { |p| p['permission'] == 'read_stream' and p['status'] == 'declined'}
            # used has declined read_stream permissions and fb dialog can not be used to get read_stream permission.
            key =  '.fb_pic_' + (just_posted ? 'post' : 'check') + '_declined_permission_html'
            return [key, {:appname => APP_NAME, :apiname => login_user.apiname }]
          end

          oauth = Koala::Facebook::OAuth.new(API_ID[provider], API_SECRET[provider], API_CALLBACK_URL[provider])
          url = oauth.url_for_oauth_code(:permissions => 'read_stream', :state => set_state_cookie_store('read_stream'))
          logger.debug2 "url = #{url}"
          # note: 4 translations:
          # - fb_msg_post_missing_permission_html - just posted - without picture
          # - fb_pic_post_missing_permission_html - just posted - with picture - missing read permission
          # - fb_msg_check_missing_permission_html - not used
          # - fb_pic_check_missing_permission_html - old post - check picture url - missing read permission
          key =  '.fb_' + (api_gift.picture? ? 'pic' : 'msg') + '_' + (just_posted ? 'post' : 'check') + '_missing_permission_html'
          return [key, {:appname => APP_NAME, :apiname => login_user.apiname, :url => url}]
        end

      elsif e.fb_error_type == 'OAuthException' and e.fb_error_code == 190 and [460, 458].index(e.fb_error_subcode)
        # Koala::Facebook::ClientError
        # 1) fb_error_type    = OAuthException (String)
        #    fb_error_code    = 190 (Fixnum)
        #    fb_error_subcode = 460 (Fixnum)
        #    fb_error_message = Error validating access token: The session has been invalidated because the user has changed the password. (String)
        #    http_status      = 400 (Fixnum)
        #    response_body    = {"error":{"message":"Error validating access token: The session has been invalidated because the user has changed the password.","type":"OAuthException","code":190,"error_subcode":460}}
        # 2) fb_error_type    = OAuthException (String)
        #    Koala::Facebook::ClientError
        #    fb_error_code    = 190 (Fixnum)
        #    fb_error_subcode = 458 (Fixnum)
        #    fb_error_message = Error validating access token: The user has not authorized application 391393607629383. (String)
        #    http_status      = 400 (Fixnum)
        #    response_body    = {"error":{"message":"Error validating access token: The user has not authorized application 391393607629383.","type":"OAuthException","code":190,"error_subcode":458}}
        raise AppNotAuthorized ;
      else
        # unhandled koala / facebook exception
        e.logger = logger
        e.puts_exception("#{__method__}: ")
        raise
      end
    end # rescue
    return nil unless object_id # post without picture

    if object_id
      # post with picture
      # 2) get best size picture from facebook. picture with size >= 200 x 200 or largest picture
      # picture must be min 200 x 200 for open graph links on facebook
      # https://developers.facebook.com/tools/debug)
      begin
        res2 = api_client.get_object object_id
        # logger.debug2 "res2 = #{res2}"
        images = res2["images"]
        if images.class == Array and images.size > 0
          logger.debug2 "second lookup: images = #{images}"
          image = nil
          images.each do |hash|
            image = hash["source"] if hash["height"].to_i >= 200 and hash["width"].to_i >= 200
          end
          image = images.first["source"] unless image
          logger.debug2 "image = #{image}"
          api_gift.api_picture_url = image
          api_gift.save!
        else
          logger.warn2 "second lookup: no images array was returned from facebook API request. Keeping old picture"
          logger.warn2 "res2 = #{res2}"
        end
      rescue Koala::Facebook::ClientError => e
        # unhandled koala / facebook exception
        e.logger = logger
        e.puts_exception("#{__method__}: ")
        raise
      end
    end

    # ok
    nil

  end # get_api_picture_url_facebook

  # get url for api gift picture on flickr wall - size >= 200 x 200
  # used in post_in_flickr and in missing_api_picture_urls
  # raises ApiPostNotFoundException if post/picture was not found (missing permission or post/picture has been deleted)
  # that is - get_api_picture_url_flickr is also used to check for missing read permission
  # return nil (ok) or [key, options] error input to translate
  # params:
  # - just_posted - true if called from post_on_flickr - false if called from missing_api_picture_urls
  # - api_client - flickraw api client
  private
  def get_api_picture_url_flickr (api_gift, just_posted, api_client) # api is flickraw API client

    provider = "flickr"

    images = nil
    begin
      # http://www.flickr.com/services/api/flickr.photos.getSizes.html
      images = api_client.photos.getSizes :photo_id => api_gift.api_gift_id
    rescue FlickRaw::FailedResponse => e
      #   1: Photo not found - The photo id passed was not a valid photo id.
      #   2: Permission denied - The calling user does not have permission to view the photo.
      # 100: Invalid API Key - The API key passed was not valid or has expired.
      # 105: Service currently unavailable - The requested service is temporarily unavailable.
      # 106: Write operation failed - The requested operation failed due to a temporary issue.
      # 111: Format "xxx" not found - The requested response format was not found.
      # 112: Method "xxx" not found - The requested method was not found.
      # 114: Invalid SOAP envelope - The SOAP envelope send in the request could not be parsed.
      # 115: Invalid XML-RPC Method Call - The XML-RPC request document could not be parsed.
      # 116: Bad URL found - One or more arguments contained a URL that has been used for abuse on Flickr.
      # exception: 'flickr.photos.getSizes' - Photo not found
      # e.methods = !, !=, !~, <=>, ==, ===, =~, __debug_binding, __debug_context, __debug_file, __debug_line, __id__, __send__, `, acts_like?, as_json, backtrace,
      # binding_n, blame_file!, blamed_files, blank?, breakpoint, capture, class, class_eval, clone, code, copy_blame!, debugger, deep_dup, define_singleton_method, describe_blame, display, dup,
      # duplicable?, enable_warnings, enum_for, eql?, equal?, exception, extend, freeze, frozen?, gem, hash, html_safe?, in?, inspect, instance_eval, instance_exec, instance_of?, instance_values,
      # instance_variable_defined?, instance_variable_get, instance_variable_names, instance_variable_set, instance_variables, is_a?, kind_of?, load, load_dependency, message, method, methods, msg,
      # nil?, object_id, presence, present?, pretty_inspect, pretty_print, pretty_print_cycle, pretty_print_inspect, pretty_print_instance_variables, private_methods, protected_methods, psych_to_yaml,
      # public_method, public_methods, public_send, quietly, remove_instance_variable, require, require_dependency, require_or_load, respond_to?, send, set_backtrace, silence, silence_stderr,
      # silence_stream, silence_warnings, singleton_class, singleton_methods, suppress, suppress_warnings, taint, tainted?, tap, to_enum, to_json, to_param, to_query, to_s, to_yaml,
      # to_yaml_properties, trust, try, try!, unloadable, untaint, untrust, untrusted?, with_options, with_warnings
      # e.code = 1
      if e.code == 1 and !just_posted
        # 1: Photo not found - The photo id passed was not a valid photo id.
        # mark api gift as deleted at api. util.missing_api_picture_urls may replace deleted flickr picture with picture from an other login provider
        logger.debug2 "user has deleted post on api wall - ok"
        api_gift.deleted_at_api = 'Y'
        api_gift.save!
        return nil
      end
      raise AppNotAuthorized if e.code == 100 # 100: Invalid API Key - The API key passed was not valid or has expired. Reconnect is required
      # other flickr exceptions - display flickr exception to user
      logger.error2 "exception: #{e.message}"
      logger.error2 "e.code = #{e.code}"
      raise
    end

    if images.class == FlickRaw::ResponseList and images.length > 0
      logger.debug2 "images = #{images}"
      image = nil
      images.reverse_each do |hash|
        image = hash.source if hash.height.to_i >= 200 and hash.width.to_i >= 200
      end
      image = images.last.source unless image
      logger.debug2 "image = #{image}"
      api_gift.api_picture_url = image
      api_gift.save!
    else
      logger.warn2 "no images array was returned from flickr API request. Keeping old picture"
      logger.warn2 "images = #{images}"
    end

    # ok
    nil

  end # get_api_picture_url_flickr


  # get_api_picture_url_linkedin is not relevant. Picture is stored in Gofreerev for Linkedin.


  # recheck post on twitter
  # mark as deleted if post has been deleted
  # get new api_picture_url if picture url has changed
  # called from missing_api_picture_urls if image has been moved or deleted
  private
  def get_api_picture_url_twitter (api_gift, just_posted=true, api_client) # api is twitter API client

    provider = "twitter"

    # check twitter post
    begin
      x = api_client.status api_gift.api_gift_id
      logger.debug2 "x = #{x}"
      logger.debug2 "x.class = #{x.class}"
      api_gift.api_picture_url = x.media.first.media_url.to_s if api_gift.picture?
    rescue Twitter::Error::NotFound => e # todo: other twitter exceptions?
      logger.debug2 "Exception: e = #{e.message} (#{e.class})"
      if just_posted
        raise
      else
        api_gift.deleted_at_api = 'Y'
      end
    end
    api_gift.save!

    # ok
    nil

  end # get_api_picture_url_twitter


  # recheck post on vkontakte
  # mark as deleted if post has been deleted
  # get new api_picture_url if picture url has changed
  # called from missing_api_picture_urls if image has been moved or deleted
  private
  def get_api_picture_url_vkontakte (api_gift, just_posted=true, api_client) # api is vkontakte API client

    # check vkontakte post
    begin
      x = api_client.photos.getById :photos => api_gift.api_gift_id
      if x.class != Array or x.length != 1
        raise VkontaktePhotoGet.new "Expected array with one photo. Response = #{x} (#{x.class})"
      end
      x = x.first
      if x.class != Hash or !x.has_key?('src_big')
        raise VkontaktePhotoGet.new "Expected hash with scr_big. Response = #{x} (#{x.class})"
      end
      api_gift.api_picture_url = x['src_big']
    rescue Vkontakte::App::VkException => e
      logger.debug2 "Exception: e = #{e.message} (#{e.class})"
      logger.debug2 "e.methods = #{e.methods.sort.join(', ')}"
      # todo: check exception. Only ok if picture has been deleted at VK and !just_posted
      api_gift.deleted_at_api = 'Y'
    end
    api_gift.save!
    logger.debug2 "api_gift.api_picture_url = #{api_gift.api_picture_url}"

    # ok
    nil

  end # get_api_picture_url_vkontakte
  
  
  # generic get_api_picture_url_<provider>
  # just_posted: true if called from generic_post_on_wall, false if called from missing_api_picture_urls
  private
  def get_api_picture_url (provider, api_gift, just_posted, api_client)

    return nil if api_gift.deleted_at_api == 'Y' # ignore - post/picture has been deleted

    method = "get_api_picture_url_#{provider}".to_sym
    if !private_methods.index(method)
      logger.error2 "System error. private method #{method} was not found in app. controller"
      return ['util.do_tasks.get_api_picture_url_missing',
              {:provider => provider, :apiname => provider_downcase(provider), :appname => APP_NAME} ]
    end
    logger.debug2 "calling #{method}"
    send(method, api_gift, just_posted, api_client)
  end # get_api_picture_url


  # change user.post_on_wall_yn. ajax request from auth/index page
  # written to session and db
  public
  def post_on_wall_yn
    provider = params[:provider]
    begin
      logger.debug2 "params = #{params}"
      # check provider
      return format_response_key('.unknown_provider', :apiname => provider) unless valid_omniauth_provider?(provider)
      # check post_on_wall_yn
      post_on_wall = case params[:post_on_wall]
                       when 'true' then
                         'Y'
                       when 'false' then
                         'N'
                       else
                         logger.error2 "Invalid post_on_wall value received from client. params = #{params}"
                         return format_response_key('.unknown_post_on_wall', :apiname => provider)
                     end # case

      # get user
      login_user, token, key, options = get_login_user_and_token(provider, __method__)
      return format_response_key(key, options) if key

      # update user
      login_user.update_attribute('post_on_wall_yn', post_on_wall)
      set_post_on_wall_selected((post_on_wall == 'Y'), provider, false)

      # update auth/index web page
      # normal no feedback from post_on_wall_yn ajax request
      # exception for post_on_wall = 'Y', read priv. in this session and write priv. in an other browser session
      # (difference between permissions in user table and post_on_wall permission in session table)
      if get_post_on_wall_selected(provider) and !get_post_on_wall_authorized(provider) and login_user.post_on_wall_authorized?
        # special case. permission to post on wlll has been granted in an other browser session
        # user should reconnect to update permissions and allow Gofreerev to post on wall also in this browser session
        return gift_posted_3c(login_user)
      end
      # empty response
      format_response
    rescue => e
      logger.debug2 "Exception: #{e.message.to_s} (#{e.class})"
      logger.debug2 "Backtrace: " + e.backtrace.join("\n")
      format_response_key '.exception',
                          :error => e.message, :provider => provider, :apiname => provider_downcase(provider)
    end
  end # post_on_wall_yn

  # share accounts ajax request from auth/index and users/index?friends=me pages
  # params = {"share_level"=>"3", "email"=>"jane@smith.com"}
  # share_level:
  #   0: no sharing
  #   1: shared balance across API providers (email not used)
  #   2: share balance and static friend lists across API providers (email not used)
  #   3: share balance and dynamic friend lists across API providers - save access token in db
  #   4: share balance, dynamic friend lists and allow single sign-on - save access token in db
  # email. used for friends suggestions. FB notification are used for shared accounts with a FB account. optional email is only used for shared accounts without a FB account
  public
  def share_accounts
    table = 'share_accounts_errors'
    begin
      logger.debug2 "params = #{params}"
      return format_response_key('.not_logged_in') unless logged_in?
      # get params & simple param validation
      share_level = params[:share_level].to_s
      return format_response_key('.unknown_share_accounts', :table => table) unless %w(0 1 2 3 4).index(share_level)
      share_level = share_level.to_i
      if [3,4].index(share_level)
        # check session variables access token and expires_at.
        # rules:
        # a) access token and expires_at must be present for each login provider
        # b) access token and expires_at is loaded from db after 4) single sign-on login with negative expires_at
        # c) check that access token is not expired
        # d) share_level 3 (dynamic friend lists) is allowed with negative expires_at loaded from database - re-login not required
        # e) share_level 4 (single sign-on) is not allowed with negative expires_at loaded from database - re-login required
        tokens = session[:tokens] || {}
        expires_at = session[:expires_at] || {}
        logger.debug2 "expires_at = #{session[:expires_at]}"
        refresh_tokens = session[:refresh_tokens] || {}
        reconnect_required = []
        @users.each do |user|
          provider = user.provider
          return format_response_key('.no_access_token', user.app_and_apiname_hash.merge(:table => table)) if tokens[provider].to_s == ''
          return format_response_key('.no_expires_at', user.app_and_apiname_hash.merge(:table => table)) if expires_at[provider].to_s == ''
          reconnect_required << provider_downcase(provider) if share_level == 4 and expires_at[provider] < 0
        end
        logger.debug2 "expires_at = #{expires_at}, share_level = #{share_level}, reconnect_required = #{reconnect_required}"
        if reconnect_required.size > 0
          # share level 4 - single sign-on - not allowed if auth. info has been loaded from db - reconnect is required for one or more providers
          return format_response_key('.reconnect_required', { :table => table, :apinames => reconnect_required.sort.join(', ')})
        end
      end
      # get email
      old_share_account_ids = @users.find_all { |u| u.share_account_id }.collect { |u| u.share_account_id }.uniq
      if [1,2].index(share_level)
        # keep any old email
        emails = ShareAccount.where(:share_account_id => old_share_account_ids).collect { |sa| sa.email }.find_all { |x| x}.uniq
        logger.debug2 "share level 1 and 2. keep any old email. emails = #{emails}"
        email = emails.first if emails.size == 1
      end
      if [3,4].index(share_level)
        # use email from share accounts modal dialog form
        email = params[:email].to_s
        email = nil if email == ''
      end
      # set or reset share_account_id for logged in users
      if share_level == 0
        share_account_id = nil
      else
        share_account_id = ShareAccount.get_share_account_id(share_level, email) # share balance and friend lists
      end
      # logger.debug2 "expires_at = #{expires_at}"
      @users.each do |user|
        user.update_attribute(:share_account_id, share_account_id)
        if share_level < 3
          # clear any old auth. information from db
          user.update_attribute(:access_token, nil) if user.access_token
          user.update_attribute(:access_token_expires, nil) if user.access_token_expires
          user.update_attribute(:refresh_token, nil) if user.refresh_token
        elsif expires_at[user.provider] > 0
          # ok to save auth. info in db - user has selected share level 3 or 4
          user.update_attribute(:access_token, tokens[user.provider].to_yaml)
          user.update_attribute(:access_token_expires, expires_at[user.provider])
          user.update_attribute(:refresh_token, refresh_tokens[user.provider])
        end
      end
      ShareAccount.where(:id => old_share_account_ids, :no_users => 1).each do |sa|
        user = sa.users.first
        sa.destroy
        user.share_account_clear
      end if old_share_account_ids.size > 0
      # return share_accounts_div to client
      @email = email
      format_response
    rescue => e
      logger.debug2 "Exception: #{e.message.to_s} (#{e.class})"
      logger.debug2 "Backtrace: " + e.backtrace.join("\n")
      format_response_key '.exception', :error => e.message, :table => table
    end
  end # share_accounts


  # grant_write_twitter is called from gifts/index page
  # also called from generic_post_on_wall if write priv. is missing (ajax inject into gifts/index page)
  # used for twitter and vkontakte where read/write priv. is handled internal in Gofreerev (API login with write access)
  # also used for flickr if write permission has been granted in an other browser session
  public
  def grant_write
    provider = params[:provider]
    @provider = nil
    begin
      # check provider
      return format_response_key('.invalid_provider') unless valid_omniauth_provider?(provider)
      # get user
      login_user, token, key, options = get_login_user_and_token(provider, __method__)
      return format_response_key(key, options) if key
      # check if grant write is allowed
      if API_POST_PERMITTED[provider] == API_POST_PERMISSION_IN_APP
        # 1) allowed for API's with API_POST_PERMITTED[provider] = API_POST_PERMISSION_IN_APP
        # that is twitter and vkontakte where write permission to API wall is handled in Gofreerev
        # change twitter user permissions from read to write
        # set write allowed in db and session
        login_user.update_attribute('permissions', 'write') # todo: only twitter and vkontakte
        set_post_on_wall_authorized(true, provider, false)
      elsif API_POST_PERMITTED[provider] == API_POST_PERMISSION_MIXED and
          get_post_on_wall_selected(provider) and
          !get_post_on_wall_authorized(provider) and
          login_user.post_on_wall_authorized?
        # 2) allowed for API's with API_POST_PERMITTED[provider] = API_POST_PERMISSION_MIXED
        # that is flickr and linkedin AND write permission has been authorized in an other browser session
        # set write allowed in session
        set_post_on_wall_authorized(true, provider, false)
      else
        # not 1) or 2)
        return format_response_key('.not_allowed', login_user.app_and_apiname_hash)
      end
      # hide ajax injected link to grant write permission to twitter wall + change text and title for access field for provider
      @provider = provider
      @access_title_2 = t 'auth.index.access_title_2', :appname => APP_NAME, :apiname => provider_downcase(provider)
      @access_link_text_2 = t 'auth.index.access_link_text_2'
      # logger.debug2 "@provider = #{@provider}, @access_link_text_2 = #{@access_link_text_2}, @access_title_2 = #{@access_title_2}"
      # ok
      format_response_key '.ok', login_user.app_and_apiname_hash
    rescue => e
      logger.debug2 "Exception: #{e.message.to_s} (#{e.class})"
      logger.debug2 "Backtrace: " + e.backtrace.join("\n")
      format_response_key '.exception',
                          :error => e.message, :provider => provider, :apiname => provider_downcase(provider)
    end
  end # grant_write


  # # grant_write_twitter is called from gifts/index page
  # # also called from generic_post_on_wall if write priv. is missing (ajax inject into gifts/index page)
  # public
  # def grant_write_twitter
  #   provider = __method__.to_s.split('_').last # twitter
  #   params[:action] = 'grant_write'
  #   @link = nil
  #   begin
  #     # get user
  #     login_user, token, key, options = get_login_user_and_token(provider, __method__)
  #     return format_response_key(key, options) if key
  #     # change twitter user permissions from read to write
  #     login_user.update_attribute('permissions', 'write')
  #     set_post_on_wall_authorized(true, provider, false)
  #     # hide ajax injected link to grant write permission to twitter wall
  #     @link = "grant_write_div_#{provider}"
  #     # ok
  #     format_response_key '.ok', login_user.app_and_apiname_hash
  #   rescue => e
  #     logger.debug2 "Exception: #{e.message.to_s} (#{e.class})"
  #     logger.debug2 "Backtrace: " + e.backtrace.join("\n")
  #     format_response_key '.exception',
  #                         :error => e.message, :provider => provider, :apiname => provider_downcase(provider)
  #   end
  # end # grant_write_twitter
  #
  # # grant_write_vkontakte is called from gifts/index page
  # # also called from generic_post_on_wall if write priv. is missing (ajax inject into gifts/index page)
  # public
  # def grant_write_vkontakte
  #   provider = __method__.to_s.split('_').last # vkontakte
  #   params[:action] = 'grant_write'
  #   @link = nil
  #   begin
  #     # get user
  #     login_user, token, key, options = get_login_user_and_token(provider, __method__)
  #     return format_response_key(key, options) if key
  #     # change vkontakte user permissions from read to write
  #     login_user.update_attribute('permissions', 'write')
  #     set_post_on_wall_authorized(true, provider, false)
  #     # hide ajax injected link to grant write permission to vkontakte wall
  #     @link = "grant_write_div_#{provider}"
  #     logger.debug2 "@link = #{@link}"
  #     # ok
  #     format_response_key '.ok', login_user.app_and_apiname_hash
  #   rescue => e
  #     logger.debug2 "Exception: #{e.message.to_s} (#{e.class})"
  #     logger.debug2 "Backtrace: " + e.backtrace.join("\n")
  #     format_response_key '.exception',
  #                         :error => e.message, :provider => provider, :apiname => provider_downcase(provider)
  #   end
  # end # grant_write_vkontakte

  
  # hide grant_write_<provider> link in gifts/index page
  # that is - set user.post_on_wall_yn to N and hide link
  public
  def hide_grant_write
    provider = params[:provider]
    @div = nil
    begin
      # check provider
      return format_response_key('.unknown_provider', :provider => provider) unless valid_omniauth_provider?(provider)
      # get user
      login_user, token, key, options = get_login_user_and_token(provider, __method__)
      return format_response_key(key, options) if key
      # disable post on wall <=> do not ajax inject links to authorize post on wall permission
      # login_user.update_attribute :post_on_wall_yn, 'N'
      set_post_on_wall_selected(false, provider,false)
      # delete ajax injected link to grant write permission to api provider wall
      @div = "grant_write_div_#{provider}"
      @checkbox = "post_#{provider}" # only auth/index page
      logger.debug2 "@div = #{@div}, @checkbox = #{@checkbox}"
      # ok
      format_response_key '.ok', login_user.app_and_apiname_hash
    rescue => e
      logger.debug2 "Exception: #{e.message.to_s} (#{e.class})"
      logger.debug2 "Backtrace: " + e.backtrace.join("\n")
      format_response_key '.exception',
                          :error => e.message, :provider => provider, :apiname => provider_downcase(provider)
    end
  end # hide_grant_write


  # generic post on wall task - todo: refactor post_on_<provider> code to this method
  private
  def generic_post_on_wall (provider, id)
    begin
      # get login user + initialize api client
      login_user, api_client, key, options = get_login_user_and_api_client(provider, __method__)
      return add_error_key(key, options) if key
      login_user_id = login_user.user_id

      # check user privs before post on wall
      # ( permissions is also checked in gifts/create before scheduling this task )
      case get_write_on_wall_action(login_user.provider)
        when ApplicationController::WRITE_ON_WALL_NO then
          return nil # ignore
        when ApplicationController::WRITE_ON_WALL_YES then
          nil # continue
        when ApplicationController::WRITE_ON_WALL_MISSING_PRIVS then
          key, options = grant_write_link(provider)
          return add_error_key(key, options) # inject link to grant missing priv.
      end

      # check if Gofreerev_post_on_wall method has been implemented for api client
      # cannot post on api wall without a gofreerev_post_on_wall method.
      # see application_controller.init_api_client_<provider> for examples
      if !api_client.respond_to? :gofreerev_post_on_wall
        return add_error_key('.api_client_gofreerev_post_on_wall', login_user.app_and_apiname_hash)
      end

      # get gift, api_gift and deep_link
      gift, api_gift, deep_link, key, options = get_gift_and_deep_link(id, login_user, provider)
      return add_error_key(key, options) if key
      description_with_deep_link = "#{gift.description} - #{deep_link}"

      # helpers ( app helpers are not available in instance method api_client.gofreerev_post_on_wall)
      # open_graph: array where post text is splitted in title and description
      # it is up to each api_client.gofreerev_post_on_wall instance method how to use max text and open graph lengths
      # see array constants API_MAX_TEXT_LENGTHS, API_OG_TITLE_SIZE and API_OG_DESC_SIZE
      # linkedin is using open_graph array for post
      open_graph = open_graph_title_and_desc(api_gift)

      # gift_posted_on_wall_api_wall. values:
      #  1: "Gift posted in here but not on your %{apiname} wall. #{error}" # unhandled error message
      #  2: "Gift posted in here and on your %{apiname} wall"
      #  3: "Gift posted in here but not on your %{apiname} wall." # missing privileges
      #  4: "Gift posted in here but not on your %{apiname} wall. Duplicate status message on #{apiname} wall."
      #  5: "Gift posted in here but not on your %{apiname} wall. Post on #{apiname} wall not implemented."
      #  6: "Gift with picture was not posted on your %{apiname} wall. Internal error. Picture was not found."
      #  7: "Gift was not posted on your %{apiname} wall. Error in deep link."
      #  8: "Gift posted here but not on your %{apiname}. You have removed %{appname} from %{apiname}"
      #  9: "Gift posted here but not on your %{apiname} wall. Post on %{apiname} requires a photo attachment or PhantomJS enabled"
      # 10: "Gift posted here but not in your %{apiname} wall. Authorization expired."

      # start with 1 unknown error
      gift_posted_on_wall_api_wall = 1
      error = 'unknown error'
      truncated = false

      # post on wall. cases:
      #  1) post with picture but picture does not exist (error)
      #  2) post with picture
      #  3) post without picture and text2picture = 0 (always - flickr & vkontakte)
      #  4) post without picture and text2picture = i and text length > i (i=140 twitter)
      #  5) post without picture
      begin
        if api_gift.picture? and !gift.rel_path_picture_exists?
          # case 1: post with picture but picture was not found.
          # There must be some error handling in gifts/create that is missing
          gift_posted_on_wall_api_wall = 6
          api_gift.api_gift_id = nil
        elsif api_gift.picture?
          # case 2: post on wall with picture
          picture_url = Picture.url_from_rel_path api_gift.gift.app_picture_rel_path # used in a later check
          picture_full_os_path = Picture.full_os_path_from_rel_path api_gift.gift.app_picture_rel_path
          api_gift.api_gift_id, api_gift.api_gift_url, truncated = api_client.gofreerev_post_on_wall :logger => logger,
                                                                                                     :api_gift => api_gift,
                                                                                                     :open_graph => open_graph,
                                                                                                     :picture => picture_full_os_path

        elsif API_TEXT_TO_PICTURE[provider] == 0 or
            API_TEXT_TO_PICTURE[provider].class == Fixnum and description_with_deep_link.length > API_TEXT_TO_PICTURE[provider]
          # case 3 and 4.
          filetype = FastImage.type(gift.open_graph_image).to_s if gift.open_graph_image
          if filetype != ''
            # open graph url - use image from open graph meta tags
            picture_rel_path = Picture.new_temp_rel_path(filetype)
            picture_full_os_path = Picture.full_os_path :rel_path => picture_rel_path
            # download
            File.open(picture_full_os_path, 'wb') do |fo|
              fo.write open(gift.open_graph_image).read
            end
            # upload
            api_gift.api_gift_id, api_gift.api_gift_url, truncated = api_client.gofreerev_post_on_wall :logger => logger,
                                                                                                       :api_gift => api_gift,
                                                                                                       :open_graph => open_graph,
                                                                                                       :picture => picture_full_os_path
            FileUtils.rm picture_full_os_path if File.exists?(picture_full_os_path)
          else
            # convert text to image
            picture_full_os_path = Picture.create_png_image_from_text gift.description, 800
            api_gift.api_gift_id, api_gift.api_gift_url, truncated = api_client.gofreerev_post_on_wall :logger => logger,
                                                                                                       :api_gift => api_gift,
                                                                                                       :open_graph => open_graph,
                                                                                                       :picture => picture_full_os_path
            FileUtils.rm picture_full_os_path if File.exists?(picture_full_os_path)
          end
        else
          # case 5: post on wall without picture
          api_gift.api_gift_id, api_gift.api_gift_url, truncated = api_client.gofreerev_post_on_wall :logger => logger,
                                                                                                     :api_gift => api_gift,
                                                                                                     :open_graph => open_graph
        end
        if api_gift.api_gift_id
          # post ok - post id received from API
          api_gift.save!
          gift_posted_on_wall_api_wall = 2 # Gift posted in here and on your api wall
        elsif gift_posted_on_wall_api_wall == 1
          error = 'unknown error. No post id was returned from API'
        end
          #rescue VkontakteCreateAlbumException => e
          #rescue VkontakteAlbumMissingException => e
          #rescue VkontakteUploadserverException => e
          #rescue VkontaktePostException => e
          #rescue VkontakteSaveException => e
      rescue AccessTokenExpired => e
        logger.debug2 "#{provider} access token has expired"
        gift_posted_on_wall_api_wall = 10
        logout(provider)
      rescue PostNotAllowed => e
        # missing write permission to api wall or permission to write on api wall has been removed
        set_post_on_wall_authorized(false, provider, false)
        key, options = grant_write_link(provider)
        return add_error_key(key, options)
      rescue AppNotAuthorized => e
        # user has deauthorized app
        logger.debug2 "#{provider} user has deauthorizd app"
        logout(provider)
        gift_posted_on_wall_api_wall = 8
      rescue DupPostOnWall => e
        # delete gift and ignore error OAuthException, code: 506, message: (#506) Duplicate status message [HTTP 400]
        # Gift posted in here but not on your facebook wall. Duplicate status message on facebook wall.
        # error should not happen any longer as deep link now is included in message
        gift_posted_on_wall_api_wall = 4
      rescue ImageNotFound => e
        # required image was not found (flickr and vkontakte)
        # possible reasons:
        #   a) missing picture attachment (should have been validated in browser before post)
        #   b) picture to text convert disabled API_TEXT_TO_PICTURE[provider] == nil
        gift_posted_on_wall_api_wall = 9
      rescue PhantomjsNotFound => e
        # text to image convert failed (case 3 and 4) in Picture.create_png_image_from_text
        # phantomjs was not found on server. Please disable text to image convert or install phantomjs on server
        # used for flickr and vkontakte where picture attachment is required
        gift_posted_on_wall_api_wall = 11
      rescue => e
        logger.debug2 "Exception: #{e.message.to_s} (#{e.class})"
        logger.debug2 "Backtrace: " + e.backtrace.join("\n")
        gift_posted_on_wall_api_wall = 1
        error = e.message
      end

      # post post-on-wall processing. Return error message, check read permission to wall if picture attachment

      if gift_posted_on_wall_api_wall != 2
        # error or warning
        logger.debug2 "error or warning: gift_posted_on_wall_api_wall = #{gift_posted_on_wall_api_wall}"
        api_gift.picture = 'N'
        api_gift.api_picture_url = nil
        api_gift.save!
        add_error_key ".gift_posted_#{gift_posted_on_wall_api_wall}_html",
                      login_user.app_and_apiname_hash.merge(:error => error)
      elsif (!api_gift.picture? or (api_gift.picture? and Picture.perm_app_url?(picture_url)))
        # post ok - no picture or picture with perm app url
        # no need to check read permission to gift on api wall
        # return posted message
        logger.debug2 "post ok without picture"
        # return [".gift_posted_#{gift_posted_on_wall_api_wall}_html", login_user.app_and_apiname_hash.merge(:error => error)]
        # gift_posted_on_wall_api_wall == 2
        gift_posted_on_wall_api_wall = '2b' if truncated
        add_error_key ".gift_posted_#{gift_posted_on_wall_api_wall}_html", login_user.app_and_apiname_hash.merge(:error => error)
      else
        logger.debug2 "post ok with picture"
        # post ok - gift posted in api wall
        # check read permission to gift and get picture url with best size > 200 x 200
        # must have read access to post on api wall to display picture in Gofreerev
        key, options = get_api_picture_url(provider, api_gift, true, api_client) # just_posted = true
        return add_error_key(key, options) if key

        # post ok and no permission problems
        # no errors - return posted message
        # return [".gift_posted_#{gift_posted_on_wall_api_wall}_html", :apiname => login_user.apiname, :error => error]
        # gift_posted_on_wall_api_wall == 2
        gift_posted_on_wall_api_wall = '2b' if truncated
        add_error_key ".gift_posted_#{gift_posted_on_wall_api_wall}_html", :apiname => login_user.apiname, :error => error
      end

    rescue => e
      logger.debug2  "Exception: #{e.message.to_s} (#{e.class})"
      logger.debug2  "Backtrace: " + e.backtrace.join("\n")
      raise
    end
  end # generic_post_on_wall


  ## post on facebook wall - with or without picture
  ## picture is temporary saved local, but is deleted when the picture has been posted in wall(s)
  ## task was inserted in gifts/create
  #private
  #def post_on_facebook (id)
  #  begin
  #    # get facebook user and koala api client
  #    provider = "facebook"
  #    login_user, api_client, key, options = get_login_user_and_api_client(provider)
  #    return [key, options] if key
  #    login_user_id = login_user.user_id
  #
  #    # check user privs before post in facebook wall
  #    # ( permissions is also checked before scheduling post_on_facebook task )
  #    case login_user.get_write_on_wall_action
  #      when User::WRITE_ON_WALL_NO then
  #        return nil # ignore
  #      when User::WRITE_ON_WALL_YES then
  #        nil # continue
  #      when User::WRITE_ON_WALL_MISSING_PRIVS then
  #        return grant_write_link(provider) # inject link to grant missing priv.
  #    end
  #
  #    # get gift, api_gift and deep_link
  #    gift, api_gift, deep_link, key, options = get_gift_and_deep_link(id, login_user, provider)
  #    return [key, options] if key
  #
  #    # gift_posted_on_wall_api_wall. values:
  #    #  1: "Gift posted in here but not on your %{apiname} wall. #{error}" # unhandled error message
  #    #  2: "Gift posted in here and on your %{apiname} wall"
  #    #  3: "Gift posted in here but not on your %{apiname} wall." # missing privileges
  #    #  4: "Gift posted in here but not on your %{apiname} wall. Duplicate status message on #{apiname} wall."
  #    #  5: "Gift posted in here but not on your %{apiname} wall. Post on #{apiname} wall not implemented."
  #    gift_posted_on_wall_api_wall = 1
  #    error = 'unknown error'
  #
  #    # post with or without picture - link is a deep link from facebook wall to gift in gofreerev
  #    # link will be clickable if public url
  #    # link will be not clickable if localhost or server behind firewall
  #
  #    # https://developers.facebook.com/docs/graph-api/reference/user/feed/
  #    begin
  #      # todo: add method gift.temp_picture_exists?
  #      if api_gift.picture? and !gift.rel_path_picture_exists?
  #        # post with picture but picture was not found.
  #        # There must be some error handling in gifts/create that is missing
  #        gift_posted_on_wall_api_wall = 6
  #      elsif api_gift.picture?
  #        # status post with picture
  #        picture_url = Picture.url :rel_path => gift.app_picture_rel_path
  #        picture_full_os_path = Picture.full_os_path :rel_path => gift.app_picture_rel_path
  #        filetype = gift.app_picture_rel_path.split('.').last
  #        content_type = "image/#{filetype}"
  #        # ( post as an open graph story - gift picture store must be :local - is shown as a like in activity log / not on wall )
  #        #   api_response = api_client.put_connections("me", "og.likes", :object => deep_link)
  #        api_response = api_client.put_picture(picture_full_os_path,
  #                                              content_type,
  #                                              {:message => "#{gift.description} - #{deep_link}"
  #                                              })
  #        # api_response = {"id"=>"1396226023933952", "post_id"=>"100006397022113_1396195803936974"} (Hash)
  #        api_gift.api_gift_id = api_response['post_id']
  #      else
  #        # status post without picture
  #        # gift.description = "#{gift.description} - #{link}" # link only as text
  #        # gift.description = "<a href='#{link}'>#{gift.description}</a>" # html code as text
  #        api_response = api_client.put_connections('me', 'feed',
  #                                                  :message => "#{gift.description} - #{deep_link}"
  #        )
  #        # api_response = {"id"=>"100006397022113_1396235850599636"}
  #        api_gift.api_gift_id = api_response['id']
  #      end
  #      logger.debug2 "api_response = #{api_response} (#{api_response.class.name})"
  #      gift_posted_on_wall_api_wall = 2 # Gift posted in here and on your facebook wall
  #    rescue Koala::Facebook::ClientError => e
  #      e.logger = logger
  #      e.puts_exception("#{__method__}: ")
  #      if e.fb_error_type == 'OAuthException' && e.fb_error_code == 506
  #        # delete gift and ignore error OAuthException, code: 506, message: (#506) Duplicate status message [HTTP 400]
  #        gift_posted_on_wall_api_wall = 4 # Gift posted in here but not on your facebook wall. Duplicate status message on facebook wall.
  #      elsif e.fb_error_type == 'OAuthException' && e.fb_error_code == 200
  #        # e.response_body = {"error":{"message":"(#200) The user hasn't authorized the application to perform this action","type":"OAuthException","code":200}}
  #        # check if permission to post i api wall has been removed
  #        error = e.to_s
  #        login_user.get_permissions_facebook(api_client)
  #        if !login_user.post_on_wall_authorized?
  #          # permission to post on api wall has been removed.
  #          # show request_post_gift_priv_link link in gifts/index page
  #          return grant_write_link(provider)
  #        else
  #          # permission to post on api wall has NOT been removed. Unknown error
  #          gift_posted_on_wall_api_wall = 1 # unknown error. no translation
  #          api_gift.clear_deep_link
  #        end
  #      elsif e.fb_error_type == 'OAuthException' && e.fb_error_code == 190
  #        # user has deauthorized gofreerev / removed gofreerev in facebook app setting page
  #        # Koala::Facebook::ClientError
  #        # fb_error_type    = OAuthException (String)
  #        # fb_error_code    = 190 (Fixnum)
  #        # fb_error_subcode = 458 (Fixnum)
  #        # fb_error_message = Error validating access token: The user has not authorized application 193177257554775. (String)
  #        # http_status      = 400 (Fixnum)
  #        # response_body    = {"error":{"message":"Error validating access token: The user has not authorized application 193177257554775.","type":"OAuthException","code":190,"error_subcode":458}}
  #        # logout and return error message to user
  #        logout(provider)
  #        gift_posted_on_wall_api_wall = 8
  #      else
  #        # unhandled exceptions
  #        gift_posted_on_wall_api_wall = 1 # unknown error. no translation
  #        error = e.to_s
  #        api_gift.clear_deep_link
  #      end
  #    rescue Koala::Facebook::ServerError => e
  #      e.logger = logger
  #      e.puts_exception("#{__method__}: ")
  #      gift_posted_on_wall_api_wall = 1 # unknown error. no translation
  #      error = e.fb_error_message.to_s
  #      api_gift.clear_deep_link
  #    end # rescue
  #
  #    if gift_posted_on_wall_api_wall != 2
  #      # error or warning
  #      api_gift.picture = 'N'
  #      api_gift.save!
  #      return [".gift_posted_#{gift_posted_on_wall_api_wall}_html",
  #              login_user.app_and_apiname_hash.merge(:error => error) ]
  #    elsif (!api_gift.picture? or (api_gift.picture? and Picture.perm_app_url?(picture_url)))
  #      # post ok - no picture or picture with perm app url
  #      # no need to check read permission to gift on api wall
  #      # return posted message
  #      return [".gift_posted_#{gift_posted_on_wall_api_wall}_html", :apiname => login_user.apiname, :error => error]
  #    else
  #      # post ok - gift posted in facebook wall
  #      # check read permissioin to gift and get picture url with best size > 200 x 200
  #      # must have read access to post on facebook wall to display picture in gofreerev
  #      # 1) use api_gift.api_gift_id to get object_id (picture size in first request is too small)
  #      key, options = get_api_picture_url(provider, api_gift, true, api_client)
  #      return [key, options] if key
  #
  #      # post ok and no permission problems
  #      # no errors - return posted message
  #      return [".gift_posted_#{gift_posted_on_wall_api_wall}_html", :apiname => login_user.apiname, :error => error]
  #    end
  #
  #  rescue => e
  #    logger.debug2 "Exception: #{e.message.to_s} (#{e.class})"
  #    logger.debug2 "Backtrace: " + e.backtrace.join("\n")
  #    raise
  #  end
  #end # post_on_facebook

  ## post on flickr wall - with or without picture
  ## picture is temporary saved local, but is deleted when the picture has been posted in wall(s)
  ## task was inserted in gifts/create
  #private
  #def post_on_flickr (id)
  #  begin
  #    # get flickr login user flickraw api client
  #    provider = "flickr"
  #    login_user, api_client, key, options = get_login_user_and_api_client(provider)
  #    return [key, options] if key
  #    login_user_id = login_user.user_id
  #
  #    # check user privs before post in flickr wall
  #    # ( permissions is also checked before scheduling post_on_flickr task )
  #    case login_user.get_write_on_wall_action
  #      when User::WRITE_ON_WALL_NO then
  #        return nil # ignore
  #      when User::WRITE_ON_WALL_YES then
  #        nil # continue
  #      when User::WRITE_ON_WALL_MISSING_PRIVS then
  #        return grant_write_link(provider) # inject link to grant missing priv.
  #    end
  #
  #    # get gift, api_gift and deep_link
  #    gift, api_gift, deep_link, key, options = get_gift_and_deep_link(id, login_user, provider)
  #    return [key, options] if key
  #
  #    # gift_posted_on_wall_api_wall. values:
  #    #  1: "Gift posted in here but not on your %{apiname} wall. #{error}" # unhandled error message
  #    #  2: "Gift posted in here and on your %{apiname} wall"
  #    #  3: "Gift posted in here but not on your %{apiname} wall." # missing privileges
  #    #  4: "Gift posted in here but not on your %{apiname} wall. Duplicate status message on #{apiname} wall."
  #    #  5: "Gift posted in here but not on your %{apiname} wall. Post on #{apiname} wall not implemented."
  #    gift_posted_on_wall_api_wall = 1
  #    error = 'unknown error'
  #
  #    # post with or without picture - link is a deep link from flickr wall to gift in gofreerev
  #    # link will be clickable if public url
  #    # link will be not clickable if localhost or server behind firewall
  #
  #    begin
  #      # todo: add method gift.temp_picture_exists?
  #      if api_gift.picture? and !gift.rel_path_picture_exists?
  #        # post with picture but picture was not found.
  #        # There must be some error handling in gifts/create that is missing
  #        gift_posted_on_wall_api_wall = 6
  #      elsif api_gift.picture?
  #        # post on flickr with picture - use picture as it is and use description with deep as description
  #        picture_url = Picture.url :rel_path => gift.app_picture_rel_path
  #        picture_full_os_path = Picture.full_os_path :rel_path => gift.app_picture_rel_path
  #        logger.debug2 "picture_full_os_path = #{picture_full_os_path}"
  #        # ( post as an open graph story - gift picture store must be :local - is shown as a like in activity log / not on wall )
  #        #   api_response = api_client.put_connections("me", "og.likes", :object => deep_link)
  #        api_response = api_client.upload_photo picture_full_os_path, :description => "#{gift.description} - #{deep_link}"
  #        # api_response = {"id"=>"1396226023933952", "post_id"=>"100006397022113_1396195803936974"} (Hash)
  #        api_gift.api_gift_id = api_response
  #      elsif API_TEXT_TO_PICTURE[provider] != 0
  #        # post in flickr without picture and convert text to image is not enabled
  #        # can not post on flickr without a picture
  #        gift_posted_on_wall_api_wall = 9
  #      else
  #        # post on flickr without picture - convert text to image and use deep link as description
  #        picture_full_os_path = Picture.create_png_image_from_text gift.description, 800
  #        api_response = api_client.upload_photo picture_full_os_path, :description => deep_link
  #        FileUtils.rm picture_full_os_path
  #        # api_response = {"id"=>"1396226023933952", "post_id"=>"100006397022113_1396195803936974"} (Hash)
  #        api_gift.api_gift_id = api_response
  #      end
  #      if api_gift.api_gift_id
  #        api_gift.api_gift_url = "#{API_URL[provider]}photos/gofreerev/#{api_response}/"
  #        api_gift.save!
  #      end
  #      logger.debug2 "api_response = #{api_response} (#{api_response.class.name})"
  #      gift_posted_on_wall_api_wall = 2 # Gift posted in here and on your flickr wall
  #    rescue Koala::Facebook::ClientError => e # todo: change exception handler - invalid exception for flickraw
  #      e.logger = logger
  #      e.puts_exception("#{__method__}: ")
  #      if e.fb_error_type == 'OAuthException' && e.fb_error_code == 506
  #        # delete gift and ignore error OAuthException, code: 506, message: (#506) Duplicate status message [HTTP 400]
  #        gift_posted_on_wall_api_wall = 4 # Gift posted in here but not on your flickr wall. Duplicate status message on flickr wall.
  #      elsif e.fb_error_type == 'OAuthException' && e.fb_error_code == 200
  #        # e.response_body = {"error":{"message":"(#200) The user hasn't authorized the application to perform this action","type":"OAuthException","code":200}}
  #        # check if permission to post i api wall has been removed
  #        error = e.to_s
  #        login_user.get_permissions_flickr(api_client)
  #        if !login_user.post_on_wall_authorized?
  #          # permission to post on api wall has been removed.
  #          # show request_post_gift_priv_link link in gifts/index page
  #          return grant_write_link(provider)
  #        else
  #          # permission to post on api wall has NOT been removed. Unknown error
  #          gift_posted_on_wall_api_wall = 1 # unknown error. no translation
  #          api_gift.clear_deep_link
  #        end
  #      elsif e.fb_error_type == 'OAuthException' && e.fb_error_code == 190
  #        # user has deauthorized gofreerev / removed gofreerev in flickr app setting page
  #        # Koala::Facebook::ClientError
  #        # fb_error_type    = OAuthException (String)
  #        # fb_error_code    = 190 (Fixnum)
  #        # fb_error_subcode = 458 (Fixnum)
  #        # fb_error_message = Error validating access token: The user has not authorized application 193177257554775. (String)
  #        # http_status      = 400 (Fixnum)
  #        # response_body    = {"error":{"message":"Error validating access token: The user has not authorized application 193177257554775.","type":"OAuthException","code":190,"error_subcode":458}}
  #        # logout and return error message to user
  #        logout(provider)
  #        gift_posted_on_wall_api_wall = 8
  #      else
  #        # unhandled exceptions
  #        gift_posted_on_wall_api_wall = 1 # unknown error. no translation
  #        error = e.to_s
  #        api_gift.clear_deep_link
  #      end
  #    rescue Koala::Facebook::ServerError => e
  #      e.logger = logger
  #      e.puts_exception("#{__method__}: ")
  #      gift_posted_on_wall_api_wall = 1 # unknown error. no translation
  #      error = e.fb_error_message.to_s
  #      api_gift.clear_deep_link
  #    end # rescue
  #
  #    if gift_posted_on_wall_api_wall != 2
  #      # error or warning
  #      logger.debug2 "error or warning: gift_posted_on_wall_api_wall = #{gift_posted_on_wall_api_wall}"
  #      api_gift.picture = 'N'
  #      api_gift.save!
  #      return [".gift_posted_#{gift_posted_on_wall_api_wall}_html",
  #              login_user.app_and_apiname_hash.merge(:error => error) ]
  #    elsif (!api_gift.picture? or (api_gift.picture? and Picture.perm_app_url?(picture_url)))
  #      # post ok - no picture or picture with perm app url
  #      # no need to check read permission to gift on api wall
  #      # return posted message
  #      logger.debug2 "post ok without picture"
  #      return [".gift_posted_#{gift_posted_on_wall_api_wall}_html", :apiname => login_user.apiname, :error => error]
  #    else
  #      logger.debug2 "post ok with picture"
  #      # post ok - gift posted in flickr wall
  #      # check read permissioin to gift and get picture url with best size > 200 x 200
  #      # must have read access to post on flickr wall to display picture in gofreerev
  #      # 1) use api_gift.api_gift_id to get object_id (picture size in first request is too small)
  #      key, options = get_api_picture_url(provider, api_gift, true, api_client)
  #      return [key, options] if key
  #
  #      # post ok and no permission problems
  #      # no errors - return posted message
  #      return [".gift_posted_#{gift_posted_on_wall_api_wall}_html", :apiname => login_user.apiname, :error => error]
  #    end
  #
  #  rescue => e
  #    logger.debug2 "Exception: #{e.message.to_s} (#{e.class})"
  #    logger.debug2 "Backtrace: " + e.backtrace.join("\n")
  #    raise
  #  end
  #end # post_on_flickr
  
  
  # post on google+ not implemented. The Google+ API is a read only API
  # private
  # def post_on_google_oauth2 (id)
  # end

  #def post_on_linkedin (id)
  #  begin
  #    # get linkedin user and linkedin api client
  #    provider = "linkedin"
  #    login_user, api_client, key, options = get_login_user_and_api_client(provider)
  #    return [key, options] if key
  #    login_user_id = login_user.user_id
  #
  #    # check user privs before post in linkedin wall
  #    # ( permissions is also checked before scheduling post_on_linkedin task )
  #    case login_user.get_write_on_wall_action
  #      when User::WRITE_ON_WALL_NO # ignore
  #        logger.debug2 "User::WRITE_ON_WALL_NO - Ignore post_on_linkedin wall."
  #        return nil
  #      when User::WRITE_ON_WALL_YES then nil # continue
  #      when User::WRITE_ON_WALL_MISSING_PRIVS # inject link to grant missing priv.
  #        logger.debug2 "User::WRITE_ON_WALL_MISSING_PRIVS - inject link into gifts/index page"
  #        return grant_write_link(provider)
  #    end
  #
  #    # get gift, api_gift and deep_link
  #    gift, api_gift, deep_link, key, options = get_gift_and_deep_link(id, login_user, provider)
  #    return [key, options] if key
  #
  #    # todo: add offers/seeks to description
  #    # todo: add picture
  #    # todo: add url for gift
  #    begin
  #
  #      # http://stackoverflow.com/questions/15183107/rails-linked-post-message
  #      # http://developer.linkedin.com/documents/share-api#toggleview:id=ruby
  #      # Node                Parent Node    Value 	Notes
  #      # comment             share          Text of member's comment.        Post must contain comment and/or (content/title and content/submitted-url).
  #      #                                                                     Max length is 700 characters.
  #      # content             share          Parent node for information on shared document
  #      # title               share/content  Title of shared document         Post must contain comment and/or (content/title and content/submitted-url).
  #      #                                                                     Max length is 200 characters.
  #      # submitted-url       share/content  URL for shared content           Post must contain comment and/or (content/title and content/submitted-url).
  #      # submitted-image-url share/content  URL for image of shared content  Invalid without (content/title and content/submitted-url).
  #      # description         share/content  Description of shared content    Max length of 256 characters.
  #      # note that linkedin uses meta property="og:description as default description
  #      # todo: check layout with and without picture
  #      # todo: check description length. <= 256 use only description. length <= 700. Use only comment. Length between 700 and 956 use comment and description
  #      # my test says: title 60, description 245 and comment 600 characters
  #      image_url = Picture.url :rel_path => gift.app_picture_rel_path if api_gift.picture? and gift.rel_path_picture_exists?
  #      # logger.debug2 "image_url = #{image_url}"
  #      image_url = SITE_URL + image_url.from(1) if image_url and image_url.first == '/'
  #      text = "#{format_direction_without_user(api_gift)} #{gift.description}"
  #      # logger.debug2 "picture = #{api_gift.picture?}, text.length = #{text.length}, image_url = #{image_url}"
  #
  #
  #      comment = nil
  #      content = { "submitted-url" => deep_link }
  #      content["title"], content["description"] = open_graph_title_and_desc(api_gift)
  #      comment = text if text.length > API_OG_TITLE_SIZE[:linkedin]
  #      content["submitted-image-url"] = image_url if api_gift.picture?
  #      #if api_gift.picture?
  #      #  # title (max 200 characters) required for post with image.
  #      #  content["submitted-image-url"] = image_url
  #      #  # layout rules for post with image on linkedin:
  #      #  case
  #      #    when text.length <= 200
  #      #      content["title"] = text
  #      #      content["description"] = '.'
  #      #    when text.length <= 456
  #      #      content["title"] = text.first(200)
  #      #      content["description"] = text.from(200)
  #      #    else
  #      #      raise "linkedin post with picture and text length > 456 is not implemented"
  #      #  end
  #      #else
  #      #  case
  #      #    when text.length <= 700
  #      #      comment = text
  #      #    else
  #      #      raise "linkedin post without picture and text length > 700 is not implemented"
  #      #  end
  #      #end
  #      logger.debug2 "content = #{content}, comment = #{comment}"
  #      x = api_client.add_share :content => content, :comment => comment
  #    rescue LinkedIn::Errors::AccessDeniedError => e
  #      logger.debug2  "LinkedIn::Errors::AccessDeniedError"
  #      logger.debug2  "e.message = #{e.message}"
  #      api_gift.clear_deep_link
  #      if e.message.to_s =~ /^\(403\)/
  #        # e.message = (403): Access to posting shares denied
  #        # inject link in tasks_errors table in gifts/index page to allow user to grant missing write permission
  #        return grant_write_link(provider)
  #      end
  #      raise
  #    end
  #
  #    # check response from client.add_share request
  #    if x.class != Net::HTTPCreated
  #      api_gift.clear_deep_link
  #      logger.debug2 "no exception from client.add_share, but post was not created"
  #      logger.debug2 "x = #{x} (#{x.class})"
  #      logger.debug2 "x.body = #{x.body} (#{x.body.class})"
  #      return ['.gift_posted_1_html', {:apiname => provider, :error => x.body}]
  #    end
  #
  #    # post on linkedin ok
  #    logger.debug2 "x = #{x} (#{x.class})"
  #    # logger.debug2 "x.methods = #{x.methods.sort.join(', ')}"
  #    logger.debug2 "x.body = #{x.body} (#{x.body.class})"
  #    #post_on_linkedin: x.body = {
  #    #    "updateKey": "UNIU-310307710-5824797827771314176-SHARE",
  #    #    "updateUrl": "http://www.linkedin.com/updates?discuss=&scope=310307710&stype=M&topic=5824797827771314176&type=U&a=omJz"
  #    #}
  #
  #    # extract update post id and post url - url for image is not relevant for linkedin - picture is stored at gofreerev
  #    # todo: update_url redirects to linkedin login page
  #    update_key = $1 if x.body.to_s =~ /"updateKey": "(.*?)"/
  #    update_url = $1 if x.body.to_s =~ /"updateUrl": "(.*?)"/
  #    logger.debug2 "update key = #{update_key}, update_url = #{update_url}"
  #    api_gift.api_gift_id = update_key
  #    api_gift.api_gift_url = update_url # note that post on linkedin wall is created in a batch process. Will work in one or 2 minutes
  #    api_gift.save!
  #
  #    # https://developer.linkedin.com/documents/share-api
  #    # You can use the update key to request the XML or JSON representation of the newly created share.
  #    # This can be achieved by making a GET call to http://www.linkedin-ei.com/v1/people/~/network/updates/key={update_key}
  #    # (setting {update_key} to the value you received in the previous response)
  #    # can not lookup post in linkedin wall at this time - post is created batch - will be created in one or two minutes
  #    # x2 = client.shares :key => update_key
  #    # logger.debug2 "x2 = #{x2} (#{x2.class})"
  #    # logger.debug2 "x2.methods = #{x2.methods.sort.join(', ')}"
  #
  #    # no errors - return posted message
  #    return [".gift_posted_2_html", :apiname => provider, :error => nil]
  #
  #  rescue => e
  #    logger.debug2  "Exception: #{e.message.to_s} (#{e.class})"
  #    logger.debug2  "Backtrace: " + e.backtrace.join("\n")
  #    raise
  #  end
  #end # post_on_linkedin

  #private
  #def post_on_twitter (id)
  #  begin
  #    # get twitter user, friends and twitter api client
  #    provider = "twitter"
  #    login_user, api_client, key, options = get_login_user_and_api_client(provider)
  #    return [key, options] if key
  #    login_user_id = login_user.user_id
  #
  #    # check user privs before post in twitter wall
  #    # ( permissions is also checked before scheduling post_on_twitter task )
  #    case login_user.get_write_on_wall_action
  #      when User::WRITE_ON_WALL_NO then return nil # ignore
  #      when User::WRITE_ON_WALL_YES then nil # continue
  #      when User::WRITE_ON_WALL_MISSING_PRIVS then return grant_write_link(provider) # inject link to grant missing priv.
  #    end
  #
  #    # get gift, api_gift and deep_link
  #    gift, api_gift, deep_link, key, options = get_gift_and_deep_link(id, login_user, provider)
  #    return [key, options] if key
  #
  #    # tweet with deep link in tweet message
  #    # tweet format: [offers/seeks] + gift.description + " - " + SITE_URL/gifts/xx/123456789012345678901234567890
  #    # description will be truncated if tweet length > 140
  #    # expect description longer than 70 characters to be truncated in tweet
  #    # full description is available in deep link
  #    # todo: maybe inject text in picture.
  #    text = "#{format_direction_without_user(api_gift)}#{api_gift.gift.description}"
  #    deep_link = " - #{api_gift.init_deep_link}"
  #    text = text.first(140-deep_link.length) if text.length + deep_link.length > 140
  #    tweet = "#{text}#{deep_link}"
  #
  #    # post tweet
  #    # todo: use text to image convert if long tweet and text to image is enabled for twitter.
  #    x = nil
  #    begin
  #      if api_gift.picture?
  #        # http://rubydoc.info/github/jnunemaker/twitter/Twitter/Client:update_with_media
  #        full_os_path = Picture.full_os_path :rel_path => gift.app_picture_rel_path
  #        x = api_client.update_with_media(tweet, File.new(full_os_path))
  #      else
  #        x = api_client.update(tweet)
  #      end
  #    rescue Twitter::Error, Timeout::Error => e
  #      # maybe a problem with timeout for twitter post.
  #      # https://github.com/sferik/twitter/issues/516
  #      # https://github.com/sferik/twitter/issues/401
  #      # todo: Could return warning to user and repeat post on twitter a few times
  #      logger.debug2  "Exception: #{e.message.to_s} (#{e.class})"
  #      logger.debug2  "Backtrace: " + e.backtrace.join("\n")
  #      raise
  #    end
  #    return ['.gift_posted_1_html', {:apiname => provider, :error => "Expected Twitter::Tweet. Found #{x.class}"}] if x.class != Twitter::Tweet
  #
  #    # save post id and picture url
  #    api_gift.api_picture_url = x.media.first.media_url.to_s if api_gift.picture?
  #    api_gift.api_gift_id  = x.id.to_s
  #    api_gift.api_gift_url = x.url.to_s
  #    api_gift.save!
  #
  #    # no errors - return posted message
  #    return [".gift_posted_2_html", :apiname => provider, :error => nil]
  #
  #  rescue => e
  #    logger.debug2  "Exception: #{e.message.to_s} (#{e.class})"
  #    logger.debug2  "Backtrace: " + e.backtrace.join("\n")
  #    raise
  #  end
  #end # post_on_twitter


  ## post on vkontakte wall - with or without picture
  ## picture is temporary saved local, but is deleted when the picture has been posted in wall(s)
  ## task was inserted in gifts/create
  #private
  #def post_on_vkontakte (id)
  #  begin
  #    # get vkontakte login user vkontakte api client
  #    provider = "vkontakte"
  #
  #    login_user, api_client, key, options = get_login_user_and_api_client(provider)
  #    return [key, options] if key
  #    login_user_id = login_user.user_id
  #
  #    # check user privs before post in vkontakte wall
  #    # ( permissions is also checked before scheduling post_on_vkontakte task )
  #    case login_user.get_write_on_wall_action
  #      when User::WRITE_ON_WALL_NO then
  #        return nil # ignore
  #      when User::WRITE_ON_WALL_YES then
  #        nil # continue
  #      when User::WRITE_ON_WALL_MISSING_PRIVS then
  #        return grant_write_link(provider) # inject link to grant missing priv.
  #    end
  #
  #    # get gift, api_gift and deep_link
  #    gift, api_gift, deep_link, key, options = get_gift_and_deep_link(id, login_user, provider)
  #    return [key, options] if key
  #
  #    # gift_posted_on_wall_api_wall. values: # todo: refresh from en.yml locale
  #    #  1: "Gift posted in here but not on your %{apiname} wall. #{error}" # unhandled error message
  #    #  2: "Gift posted in here and on your %{apiname} wall"
  #    #  3: "Gift posted in here but not on your %{apiname} wall." # missing privileges
  #    #  4: "Gift posted in here but not on your %{apiname} wall. Duplicate status message on #{apiname} wall."
  #    #  5: "Gift posted in here but not on your %{apiname} wall. Post on #{apiname} wall not implemented."
  #    gift_posted_on_wall_api_wall = 1
  #    error = 'unknown error'
  #
  #    begin
  #      # post with or without picture - link is a deep link from vkontakte wall to gift in gofreerev
  #      # link will be clickable if public url
  #      # link will be not clickable if localhost or server behind firewall
  #      # todo: add method gift.temp_picture_exists?
  #      if api_gift.picture? and !gift.rel_path_picture_exists?
  #        # post with picture but picture was not found.
  #        # There must be some error handling in gifts/create that is missing
  #        gift_posted_on_wall_api_wall = 6
  #      elsif api_gift.picture?
  #        # post on vkontakte with picture - use picture as it is and use description with deep as description
  #        picture_url = Picture.url_from_rel_path api_gift.gift.app_picture_rel_path
  #        api_response = api_client.gofreerev_post_on_wall api_gift, logger
  #        # api_response = {"id"=>"1396226023933952", "post_id"=>"100006397022113_1396195803936974"} (Hash)
  #        api_gift.api_gift_id = api_response
  #      elsif API_TEXT_TO_PICTURE[provider] != 0
  #        # post in vkontakte without picture and convert text to image is not enabled
  #        # can not post on vkontakte without a picture
  #        gift_posted_on_wall_api_wall = 9
  #      else
  #        # post on vkontakte without picture - convert text to image and use deep link as description
  #        api_response = api_client.gofreerev_post_on_wall api_gift, logger
  #        # api_response = {"id"=>"1396226023933952", "post_id"=>"100006397022113_1396195803936974"} (Hash)
  #        api_gift.api_gift_id = api_response
  #      end
  #      if api_gift.api_gift_id
  #        api_gift.api_gift_url = "#{API_URL[provider]}photo#{api_response}"
  #        api_gift.save!
  #        logger.debug2 "api_response = #{api_response} (#{api_response.class.name})"
  #        gift_posted_on_wall_api_wall = 2 # Gift posted in here and on your vkontakte wall
  #      end
  #        #rescue VkontakteCreateAlbumException => e
  #        #rescue VkontakteAlbumMissingException => e
  #        #rescue VkontakteUploadserverException => e
  #        #rescue VkontaktePostException => e
  #        #rescue VkontakteSaveException => e
  #    rescue AccessTokenExpired => e
  #      logger.debug2 "#{provider} access token has expired"
  #      gift_posted_on_wall_api_wall = 10
  #      logout(provider)
  #    rescue => e
  #      logger.debug2 "Exception: #{e.message.to_s} (#{e.class})"
  #      logger.debug2 "Backtrace: " + e.backtrace.join("\n")
  #      gift_posted_on_wall_api_wall = 1
  #      error = e.message
  #    end
  #
  #    if gift_posted_on_wall_api_wall != 2
  #      # error or warning
  #      logger.debug2 "error or warning: gift_posted_on_wall_api_wall = #{gift_posted_on_wall_api_wall}"
  #      api_gift.picture = 'N'
  #      api_gift.save!
  #      return [".gift_posted_#{gift_posted_on_wall_api_wall}_html",
  #              login_user.app_and_apiname_hash.merge(:error => error)]
  #    elsif (!api_gift.picture? or (api_gift.picture? and Picture.perm_app_url?(picture_url)))
  #      # post ok - no picture or picture with perm app url
  #      # no need to check read permission to gift on api wall
  #      # return posted message
  #      logger.debug2 "post ok without picture"
  #      return [".gift_posted_#{gift_posted_on_wall_api_wall}_html", login_user.app_and_apiname_hash.merge(:error => error)]
  #    else
  #      logger.debug2 "post ok with picture"
  #      # post ok - gift posted in flickr wall
  #      # check read permissioin to gift and get picture url with best size > 200 x 200
  #      # must have read access to post on flickr wall to display picture in gofreerev
  #      # 1) use api_gift.api_gift_id to get object_id (picture size in first request is too small)
  #      key, options = get_api_picture_url(provider, api_gift, true, api_client)
  #      return [key, options] if key
  #
  #      # post ok and no permission problems
  #      # no errors - return posted message
  #      return [".gift_posted_#{gift_posted_on_wall_api_wall}_html", :apiname => login_user.apiname, :error => error]
  #    end
  #
  #  rescue => e
  #    logger.debug2 "Exception: #{e.message.to_s} (#{e.class})"
  #    logger.debug2 "Backtrace: " + e.backtrace.join("\n")
  #    raise
  #  end
  #end # post_on_vkontakte


    # check after post_on_<provider>'s' if user have write access to any api wall
  # disable if user does not have granted write permission to any api wall
  # enable if user have granted write permission to one api wall
  # todo: should also change title ......
  def disable_enable_file_upload
    begin
      # reload @users - permissions can have changed in post_in_<provider> tasks
      @users = @users.collect { |user| user.reload }
      # disabled = !@gift_file. See do_tasks.js.erb
      @gift_file = get_post_on_wall_authorized(nil)
      logger.debug2  "@gift_file = #{@gift_file}"
      nil
    rescue => e
      logger.debug2  "Exception: #{e.message.to_s} (#{e.class})"
      logger.debug2  "Backtrace: " + e.backtrace.join("\n")
      raise
    end
  end # disable_file_upload

  # delete local picture file that was used when posting picture in api wall(s) - see post_on_facebook etc.
  private
  def delete_local_picture (id)
    begin
      logger.debug2  ""

      # get and check gift
      gift = Gift.find_by_id(id)
      return add_error_key('.post_on_api_unknown_gift_id', { :provider => 'API', :id => id }) unless gift
      return add_error_key('.post_on_api_old_gift', { :provider => 'API', :id => gift.id }) unless gift.created_at > 5.minute.ago

      # check local picture file
      return add_error_key('.no_local_picture', { :provider => 'API', :id => id }) unless gift.app_picture_rel_path
      app_picture_full_os_path = Picture.full_os_path :rel_path => gift.app_picture_rel_path
      app_picture_url          = Picture.url :rel_path => gift.app_picture_rel_path
      return add_error_key('.local_picture_not_found', { :provider => 'API', :id => id }) unless File.exist?(app_picture_full_os_path)

      # delete file
      perm_app_picture = Picture.perm_app_url?(app_picture_url)
      if !perm_app_picture
        File.delete(app_picture_full_os_path) if File.exists?(app_picture_full_os_path)
        gift.app_picture_rel_path = nil
        gift.save!
      end

      # check temp picture after posting on api walls
      # should be set in post_in_<provider> tasks, but not after exceptions
      gift.api_gifts.each do |api_gift|
        if Picture.temp_app_url?(api_gift.api_picture_url)
          # temp url - delete or replace with perm url
          # replace with perm url is only a workaround/fallback for this gift
          if perm_app_picture
            api_gift.api_picture_url = app_picture_url
            logger.warn "fallback after post_on_#{api_gift.provider} failure. Added perm app url for gift id #{gift.id}"
          else
            api_gift.api_picture_url = nil
            api_gift.picture = 'N'
            logger.debug2 "fallback after post_on_#{api_gift.provider} failure. Blanked picture url for gift id #{gift.id}"
          end
          api_gift.save!
        end
      end

      nil

    rescue => e
      logger.debug2  "#{__method__}: Exception: #{e.message.to_s} (#{e.class})"
      logger.debug2  "#{__method__}: Backtrace: " + e.backtrace.join("\n")
      raise
    end
  end # delete_local_picture

  # message for expired access tokens for user share level 3 (dynamic friend lists) and 4 (single sign-on login)
  # post login service message to user about any expired access tokens
  private
  def check_expired_tokens(user_id, first_login)
    begin
      logger.debug2 "user_id = #{user_id}, first_login = #{first_login}"
      # user_id = 790, first_login = true
      nil
    rescue => e
      logger.debug2  "#{__method__}: Exception: #{e.message.to_s} (#{e.class})"
      logger.debug2  "#{__method__}: Backtrace: " + e.backtrace.join("\n")
      raise
    end
  end # check_expired_tokens


  # return share post link - only allowed for giver or receiver
  # return error message or redirect to share link page in a new tab
  public
  def share_gift
    table = "tasks_errors" # ajax error table in page header
    begin
      # set id for ajax error table
      gift_id = params[:gift_id]
      return format_response_key('.no_gift_id', :table => table) if gift_id.to_s == ''
      return format_response_key('.invalid_gift_id', :table => table) unless gift_id.to_s =~ /^[1-9]\d*$/
      table = "gift-#{gift_id}-links-errors" # ajax error table under gifts links
      # share gift is only allowed for giver/receiver. Login is required.
      return format_response_key('.not_logged_in', :table => table) unless logged_in?
      # check share provider (share providers are not the same as login providers (omniauth))
      provider = params["provider"]
      return format_response_key('.no_provider', :table => table) if provider.to_s == ''
      return format_response_key('.unknown_provider', :table => table) unless valid_share_provider?(provider)
      g = Gift.find_by_id(gift_id)
      return format_response_key('.unknown_gift_id', :table => table) unless g
      ags = g.api_gifts.find_all { |ag| !ag.deleted_at and (login_user_ids.index(ag.user_id_giver) or login_user_ids.index(ag.user_id_receiver)) }
      return format_response_key('.not_allowed', :table => table) if ags.size == 0
      ag = ags.first if ags.size == 1
      ag = ags.find { |ag2| ag2.provider == provider } unless ag
      if !ag
        # choice api gift provider for share gift link
        # sort:
        # 1) use api post with pictures before api post without pictures
        # 2) use api post with deep link before api post without deep link
        # 3) random
        ags = ags.sort_by { |ag| [ (ag.picture == 'Y' ? 1 : 2), (ag.deep_link ? 1 : 2), rand] }
        ag = ags.first
      end
      sleep(3)
      ag.init_deep_link unless ag.deep_link
      ag.provider = provider # share gift provider
      # find set max length for text/description in share gift link. -1: no text, 0: no limit
      # case
      #   when provider == 'twitter'
      #     # normal limit is 140 characters. But only 83 characters are allowed in twitter share link description
      #     max_lng = API_POST_MAX_TEXT_LENGTHS[provider] - 57
      #   when %w(google_oauth2 linkedin).index(provider)
      #     # no text in share gift link
      #     max_lng = -1
      #   when (API_POST_MAX_TEXT_LENGTHS.has_key?(provider) and [NilClass, Fixnum].index(API_POST_MAX_TEXT_LENGTHS[provider].class))
      #     # facebook, pinterest, vkontakte
      #     max_lng = API_POST_MAX_TEXT_LENGTHS[provider]
      #   else
      #     # google+, linkedin: no text
      #     nil
      # end # case
      # extra params. used for provider specific params in share gift link
      extra = case provider
                  when 'facebook'
                    API_ID[:facebook]
                 when 'twitter'
                    # normal limit is 140 characters. But only 83 characters are allowed in twitter share link description
                    # use server side text truncation (preserve tags in text)
                    tweet = "#{g.human_value(:direction)}#{g.description}"
                    # sanitize JS string - do not use ' - do not use line breaks
                    # todo: refactor to a string method?
                    linebreak = " "
                    tweet = tweet.gsub("'", '"')
                    tweet = tweet.gsub(/\r\n/, linebreak)
                    tweet = tweet.gsub(/\n/, linebreak)
                    tweet = tweet.gsub(/\r/, linebreak)
                    tweet, truncated = Gift.truncate_twitter_text tweet, max_lng
                    max_lng = -1 # no client side text lookup
                    tweet
                  else
                    ''
              end
      # call JS method share_gift(provider, gift_id, link, max_lng, extra)
      @api_gift = ag
      @extra = extra
      logger.debug2 "provider = #{@api_gift.provider}"
      logger.debug2 "gift_id  = #{@api_gift.gift.id}"
      logger.debug2 "link     = #{@api_gift.deep_link}"
      logger.debug2 "extra    = '#{@extra}'"
      # share_gift: gift_id  = 342
      # share_gift: link     = https://dev1.gofreerev.com/en/gifts/v5pudlxfcswd1jkmtksthvodpvwn8i
      # share_gift: max_lng  = 47950
      # share_gift: extra    = '193177257554775'

      # ok - redirect to share link page in new tab
      format_response

    rescue => e
      logger.debug2 "Exception: #{e.message.to_s} (#{e.class})"
      logger.debug2 "Backtrace: " + e.backtrace.join("\n")
      format_response_key '.exception', :error => e.message, :table => table
    end
  end # share_gift


  # wrapper for User.find_friends_batch
  # run as a batch task without login user array.
  # rror message if not relevant for current login user(s)
  # write any error messages from User.find_friends_batch to log
  private
  def find_friends_batch
    begin
      key, options = User.find_friends_batch
      if key
        msg = t key, options
        logger.error2 msg
      end
      # ok
      nil
    rescue => e
      logger.debug2  "Exception: #{e.message.to_s} (#{e.class})"
      logger.debug2  "Backtrace: " + e.backtrace.join("\n")
      raise
    end
  end # find_friends_batch


  # check external url from gifts/index page (create new gift)
  # get open graph tags from html page and return link preview in a div
  public
  def open_graph
    table = "tasks_errors" # ajax error table in page header
    begin
      return format_response_key('.not_logged_in', {}) unless logged_in?
      url = params[:url]
      logger.debug2 "url = #{url}"
      @og = OpenGraphLink.find_or_create_link(url)
      format_response
    rescue => e
      logger.debug2 "Exception: #{e.message.to_s} (#{e.class})"
      logger.debug2 "Backtrace: " + e.backtrace.join("\n")
      format_response_key '.exception', :error => e.message, :table => table
    end
  end


end # UtilController
