# encoding: utf-8
class GiftsController < ApplicationController

  before_filter :clear_state_cookie_store, :if => lambda {|c| !xhr?}
  before_filter :login_required, :except => [:create, :index, :show]
  before_filter :check_share_gift_error, :only => [:index, :show]

  def new
  end

  # ajax request - called from gifts/index page
  # return gift in new_messages_buffer_div and return any error messages in tasks_errors table
  # both in page header
  # JS function insert_update_gifts will move new gift from div buffer to gifts table in html page
  def create
    @api_gifts = []
    begin
      return format_response_key '.not_logged_in' unless logged_in?

      # check if user account is being deleted (do not create new gift)
      users2 = @users.find_all { |u| !u.deleted_at }
      return format_response_key '.deleted_user' if users2.size == 0
      @users = users2 if @users.size != users2.size

      # write warning if post_on_wall is selected and write permission on wall has been removed
      # write note if post_on_wall priv has been added in an other session and
      @users.each do |user|
        next unless get_post_on_wall_selected(user.provider) # ignore API's where post_on_wall has not been selected
        next if user.post_on_wall_authorized? == get_post_on_wall_authorized(user.provider) # no change in write permission
        if get_post_on_wall_authorized(user.provider)
          # write permission after login - now read permission - write priv. deselected or detected in an other browser session
          add_error_key '.post_on_wall_deauthorized', user.app_and_apiname_hash
          set_post_on_wall_authorized(false, user.provider, true)
        else
          # read permission after login - now write permission - write priv. added in an other browser session
          # managed in grant_write_link method
        end
      end

      # initialize gift
      gift = Gift.new
      gift.price = params[:gift][:price].gsub(',', '.').to_f unless invalid_price?(params[:gift][:price])
      gift.direction = 'giver' if gift.direction.to_s == ''
      gift.created_by = gift.direction
      gift.currency = @users.first.currency
      gift.description = params[:gift][:description]
      if params[:gift][:open_graph_url].to_s != ''
        og = OpenGraphLink.find_or_create_link(params[:gift][:open_graph_url])
        if og
          # open graph url ok and open graph meta tags was found
          gift.open_graph_url = og.url
          gift.open_graph_title = og.title
          gift.open_graph_description = og.description
          gift.open_graph_image = og.image
        end
      end
      gift_file = params[:gift_file]
      picture = (gift_file.class.name == 'ActionDispatch::Http::UploadedFile')
      if picture and !get_post_on_wall_authorized(nil)
        add_error_key '.file_upload_not_allowed',
                      :appname => APP_NAME,
                      :apiname => (@users.length > 1 ? 'login provider' : @users.first.apiname)
        picture = false # continue post without picture
      end
      if picture
        filetype = FastImage.type(gift_file.path).to_s
        if !%w(jpg jpeg gif png bmp).index(filetype)
          add_error_key '.unsupported_filetype', :filetype => filetype
          picture = false # continue post without picture
        end
      end
      if picture and gift_file.size > 2.megabytes
        add_error_key '.file_is_too_big', :maxsize => '2 Mb'
        picture = false # continue post without picture
      end
      if picture
        # perm or temp picture store - for example perm for linkedin and temp for facebook
        # ( configuration in hash constant API_GIFT_PICTURE_STORE - /config/initializers/omniauth.rb )
        picture_rel_path = new_temp_or_perm_rel_path filetype
        if picture_rel_path
          gift.app_picture_rel_path = picture_rel_path
          logger.debug2 "gift.app_picture_rel_path = #{gift.app_picture_rel_path}"
          picture_url = Picture.url :rel_path => picture_rel_path
          picture_full_os_path = Picture.full_os_path :rel_path => picture_rel_path
        else
          # error - picture store setup was not found for logged in users
          # invalid picture store setup (API_GIFT_PICTURE_STORE) or file upload should not be allowed
          providers = @users.collect { |u| u.provider }
          add_error_key '.invalid_pic_store', :providers => providers.join(', ')
          picture = false # continue post without picture
        end
      end

      gift.valid?
      gift.errors.add :price, :invalid if invalid_price?(params[:gift][:price]) # price= accepts only float and model can not return invalid price error
      logger.debug2 "gifts.errors = #{gift.errors.full_messages.join(', ')}"
      return format_response_text(gift.errors.full_messages.join(', ')) if gift.errors.size > 0

      # add api_gifts - one api_gifts for each provider
      # api_gift_id will be added in post_on_<provider> tasks
      # api_picture_url may change in post_on_<provider> tasks if picture store is :api
      @users.each do |user|
        api_gift = ApiGift.new
        api_gift.gift_id = gift.gift_id
        api_gift.provider = user.provider
        api_gift.user_id_giver = gift.direction == 'giver' ? user.user_id : nil
        api_gift.user_id_receiver = gift.direction == 'receiver' ? user.user_id : nil
        api_gift.picture = picture ? 'Y' : 'N'
        api_gift.api_picture_url = picture_url if picture # temporary or perm local url
        if !API_GIFT_PICTURE_STORE[user.provider]
          # no picture store for this provider
          # this is - provider does not support picture uploads and local perm picture store is not being used
          api_gift.picture = 'N'
          api_gift.api_picture_url = nil
        end
        gift.api_gifts << api_gift
      end
      gift.save!

      if picture
        # create dir
        Picture.create_parent_dirs :rel_path => picture_rel_path
        # move uploaded file to location in perm or temp picture store
        cmd = "mv #{gift_file.path} #{picture_full_os_path}"
        stdout, stderr, status = User.open4(cmd)
        if status != 0
          # mv failed
          logger.error2 "mv: cmd = #{cmd}"
          logger.error2 "mv: stdout = #{stdout}, stderr = #{stderr}, status = #{status}"
          # OS cleanup
          begin
            File.delete(picture_full_os_path) if File.exists?(picture_full_os_path)
            Picture.delete_empty_parent_dirs(:rel_path => picture_rel_path)
          rescue => e
            # ignore OS cleanup errors - write message on log and continue
            logger.error2 "mv: OS cleanup failed. error = #{e.message}"
          end
          # continue post without picture
          add_error_key ".file_mv_error", :error => stderr
          gift.app_picture_rel_path = nil
          gift.save!
          gift.api_gifts.each do |api_gift|
            api_gift.picture = 'N'
            api_gift.api_picture_url = nil
            api_gift.save!
          end
          picture = false
        else
          # mv ok - change file permissions
          # apache must have read access to image files
          cmd = "chmod o+r #{picture_full_os_path}"
          stdout, stderr, status = User.open4(cmd)
          if status != 0
            # chmod failed
            logger.error2 "chmod: cmd = #{cmd}"
            logger.error2 "chmod: stdout = #{stdout}, stderr = #{stderr}, status = #{status}"
            # OS cleanup
            begin
              File.delete(picture_full_os_path) if File.exists?(picture_full_os_path)
              Picture.delete_empty_parent_dirs(:rel_path => picture_rel_path)
            rescue => e
              # ignore OS cleanup errors - write message on log and continue
              logger.error2 "chmod: OS cleanup failed. error = #{e.message}"
            end
            # continue post without picture
            add_error_key ".file_chmod_error", :error => stderr
            gift.app_picture_rel_path = nil
            gift.save!
            gift.api_gifts.each do |api_gift|
              api_gift.picture = 'N'
              api_gift.api_picture_url = nil
              api_gift.save!
            end
            picture = false
          end
        end
      end

      # post on api wall(s) - priority = 5
      # status:
      # - facebook ok -
      # - google+ not implemented - The Google+ API is at current time a read only API
      # - linkedin - ok
      # - twitter - todo
      # note that post_on_<provider> is called even if post_gift_allowed? is false (ajax inject link to grant missing permission)
      no_walls = 0
      tokens = session[:tokens] || {}
      tokens.keys.each do |provider|
        next unless API_GIFT_PICTURE_STORE[provider] # skip readonly API's
        # check permissions
        next if get_write_on_wall_action(provider) == ApplicationController::WRITE_ON_WALL_NO # user has deselected post on api wall
        # schedule post_on_<provider> or generic_post_on_wall task
        task_name = "post_on_#{provider}"
        if UtilController.new.private_methods.index(task_name.to_sym)
          add_task "#{task_name}(#{gift.id})", 5
        else
          add_task "generic_post_on_wall('#{provider}',#{gift.id})", 5
        end
        no_walls += 1
      end # each provider

      # write only warning once about missing write on wall privs. once
      if no_walls == 0
        add_error_key '.no_api_walls', :appname => APP_NAME unless session[:walls] == false
      end
      session[:walls] = (no_walls > 0)

      # disable file upload button if post on provider wall was rejected for all apis
      # enable file upload button if post on wall was allowed for one provider
      add_task "disable_enable_file_upload", 5

      # delete picture after posting on api wall(s) - priority = 10
      add_task "delete_local_picture(#{gift.id})", 10 if picture and Picture.temp_app_url?(picture_url)

      # find api gift - api gift with picture is preferred
      api_gift = gift.api_gifts.sort_by { |a| a.picture }.last
      @api_gifts = ApiGift.where("id = ?", api_gift.id).includes(:gift)
      logger.debug2 "@errors.size = #{@errors.size}"
      logger.debug2 " @api_gifts.size = #{@api_gifts.size}"
      format_response
    rescue => e
      logger.error2 "Exception: #{e.message.to_s}"
      logger.error2 "Backtrace: " + e.backtrace.join("\n")
      @api_gifts = []
      format_response_key '.exception', :error => e.message
    end
  end # create

  def update
  end

  def edit
  end

  def destroy
  end

  def index
    if !logged_in?
      if xhr?
        @api_gifts = []
        @last_row_id = nil
        return format_response_key '.not_logged_in', :table => 'show-more-rows-errors'
      else
        save_flash_key 'shared.not_logged_in.redirect_flash'
        redirect_to :controller => :auth, :action => :index
        return
      end
    end

    # http request: return first gift (last_row_id = nil)
    # ajax request (show more rows): return next 10 gifts (last_row_id != nil). last_row_id == gift.status_update_at
    if xhr?
      last_row_id = params[:last_row_id].to_s
      last_row_id = nil if last_row_id == ''
      if last_row_id.to_s =~ /^[0-9]+$/
        last_row_id = last_row_id.to_i
      else
        logger.error2 "xhr request without a valid last_row_id. params[:last_row_id] = #{params[:last_row_id]}"
        @api_gifts = []
        @last_row_id = get_last_row_id()
        # format_ajax_response
        return format_response_key '.ajax_invalid_last_row_id', :last_row_id => params[:last_row_id], :table => 'show-more-rows-errors'
      end
    else
      add_error_key '.http_invalid_last_row_id', :last_row_id => params[:last_row_id] unless params[:last_row_id].to_s == ''
      last_row_id = nil
    end

    if last_row_id and get_next_set_of_rows_error?(last_row_id)
      # problem with ajax request.
      # can be invalid last_row_id - can be too many get-more-rows ajax requests - max one request every 3 seconds - more info in log
      # return "empty" ajax response with dummy row with correct last_row_id to client
      logger.debug2  "return empty ajax response with dummy row with correct last_row_id to client"
      @api_gifts = []
      @last_row_id = get_last_row_id()
      # ajax error message has already been inserted into @errors
      return format_response
    end

    # get any pictures with invalid picture urls
    # that is gifts where picture url are marked as invalid and where url lookup in /util/missing_api_picture_urls failed
    # most possible explanation is that the pictures has been deleted in api
    # but is could also be a api permission problem (gofreerev user is not allowed to see picture in api)
    # check picture url again with owner permission
    # the existing /util/missing_api_picture_urls is used to check invalid picture urls
    # done in a client js call after the page has been rendered to the user
    # see last lines in /gifts/index page
    # see onLoad tag on img
    # see js functions imgonload and report_missing_api_picture_urls
    @missing_api_picture_urls = get_missing_api_picture_urls()

    # initialize gift form in top of gifts/index page
    @gift = Gift.new
    @gift.direction = 'giver'
    @gift.open_graph_url = params[:url] if params[:url].to_s != ''
    @gift.description = params[:text] if params[:text].to_s != ''
    if User.dummy_users?(@users)
      # todo: this looks like an error (not logged in user)
      # http: should redirect to auth/index page
      # ajax: should return an not logged in error message
      @api_gifts = []
      return format_response
    end
    @gift.currency = @users.first.currency unless @gift.currency
    # logger.debug2  "index: description = #{@gift.description}"

    # initialize list of gifts
    # list of gifts with @users as giver or receiver + gifts med @users.friends as giver or receiver
    newest_status_update_at = Sequence.status_update_at
    newest_gift = Gift.last

    # get list with gifts:
    # - return one gift in first http request (last_row_id is blank)
    # - return 10 gifts in next ajax requests (last_row_id is not blank = status_update_at for last row in gifts/index page)
    limit = last_row_id ? 10 : 1
    @api_gifts, @last_row_id = User.api_gifts(@users, :last_status_update_at => last_row_id, :limit => limit)

    set_last_row_id(@last_row_id) # control - is checked in next ajax request
    if last_row_id
      set_last_row_at(@request_start_time)
    else
      # first http request at startup - ajax request for the next 10 rows in a split second
      set_last_row_at(@request_start_time-GET_MORE_ROWS_INTERVAL)
    end

    # use this gifts select for ajax debug - returns all gifts
    # gifts = Gift.where('user_id_giver is not null or user_id_receiver is not null').order('id desc') # uncomment to test ajax

    # last_row_id != nil. ajax request from end of gifts/index page - return next 10 rows to gifts/index page
    # logger.debug2  "last_row_id = #{params[:last_row_id]}, gifts.length = #{@gifts.length}"
    if !last_row_id
      # http request - return one gift - ajax request for the next 10 rows will start in a second - see shared/show_more_rows
      # remember newest gift id (global). Gifts created by friends after page load will be ajax inserted in gifts/index page
      @newest_gift_id = newest_gift.id if newest_gift
      # remember newest status update (gifts and comments). Gifts and comments with status changes after page load will be ajax replaced in gifts/index page
      @newest_status_update_at = newest_status_update_at if newest_gift
      # empty AjaxComment buffer for current user - comments created after page load will be ajax inserted in gifts/index page
      AjaxComment.where("user_id in (?)", login_user_ids).delete_all if login_user_ids.length > 0
      # insert dummy profile pictures in first row - force fixed size for empty from or to columns
      @first_gift = true
      # check write on wall settings
      @users.each do |user|
        if get_write_on_wall_action(user.provider) == ApplicationController::WRITE_ON_WALL_MISSING_PRIVS
          key, options = grant_write_link(user.provider)
          logger.secret2 "grant_write_link: key = #{key}, options = #{options}"
          add_error_key key, options if key
        end # if
      end # each user
      logger.secret2 "@errors = #{@errors}" # use logger.secret2 - @errors can have request write on wall priv. links
    end

    if false
      @api_gifts, @last_row_id = get_next_set_of_rows(gifts, last_row_id)
    end

    # show 4 last comments for each gift
    @first_comment_id = nil

    #respond_to do |format|
    #  format.html { render :action => "index" }
    #  # format.json { render json: @comment, status: :created, location: @comment }
    #  format.js {}
    #end
    format_response

  end # index

  def show
    # check gift id
    id = params[:id].to_s
    deep_link = deep_link? # deep link from api wall to gift in gofreerev
    if deep_link
      deep_link_id = id.first(20)
      deep_link_pw = id.last(10)
      api_gift = ApiGift.where("deep_link_id = ?", deep_link_id).includes(:gift).first
      gift = api_gift.gift if api_gift
    else
      gift = Gift.find_by_id(id)
    end
    if !gift
      if deep_link
        logger.debug2  "invalid deep link id"
        if User.dummy_users?(@users)
          save_flash_key '.invalid_deep_link_id_not_logged_in'
        else
          save_flash_key '.invalid_deep_link_id_logged_in'
        end
      else
        logger.debug2  "invalid gift id"
        save_flash_key '.invalid_gift_id'
      end
      if deep_link and User.dummy_users?(@users)
        # not logged in
        redirect_to :controller => :auth
      else
        # logged in
        redirect_to :action => :index
      end
      return
    end
    if deep_link and deep_link_pw != api_gift.deep_link_pw
      api_gift.deep_link_errors += 1
      api_gift.save!
      api_gift.clear_deep_link if api_gift.deep_link_errors > 10
      logger.debug2  "invalid deep link pw"
      if User.dummy_users?(@users)
        save_flash_key '.invalid_deep_link_id_not_logged_in'
      else
        save_flash_key '.invalid_deep_link_id_logged_in'
      end
      if deep_link and User.dummy_users?(@users)
        redirect_to :controller => :auth
      else
        redirect_to :action => :index
      end
      return
    end
    # check access. giver and/or receiver of gift must be a app friend
    if !deep_link and !gift.visible_for?(@users)
      logger.debug2  "no access"
      save_flash_key ('.no_access')
      redirect_to :action => :index
      return
    end

    # ok - show gift
    if deep_link or gift.open_graph_title
      @gift = api_gift
      # http://ogp.me/
      # 1) http://wptest.means.us.com/online-meta-tag-length-checker/
      #    og:title max length: facebook 94, google+ 63, twitter 70
      #    og:description max length: facebook 200, google+ 155, twitter 200
      # 2) http://www.joshspeters.com/how-to-optimize-the-ogdescription-tag-for-search-and-social
      #    og:description max lengths: Facebook 300, linkedIn 225, Google+ 200 (LinkedIn have a 256 character limit in content.description field when posting)
      # 3) http://moz.com/blog/title-tags-is-70-characters-the-best-practice-whiteboard-friday
      #    title <= 70 characters
      if gift.open_graph_title
        # gift was created with open graph url. Use og meta tags as they were
        title       = gift.open_graph_title
        description = gift.open_graph_description
      else
        # get open graph meta tags from gift direction and description
        title, description = open_graph_title_and_desc(api_gift)
      end
      # image = api_gift.picture? ? api_gift.api_picture_url : API_OG_DEF_IMAGE[api_gift.provider]
      if gift.open_graph_image
        # gift was created with an open graph url
        image = gift.open_graph_image
      elsif !api_gift.picture?
        image = API_OG_DEF_IMAGE[api_gift.provider]
      elsif Picture.api_url?(api_gift.api_picture_url)
        image = api_gift.api_picture_url
      else
        image = "#{SITE_URL[0..-2]}#{api_gift.api_picture_url}"
      end
      logger.debug2 "OG. provider    = #{api_gift.provider}"
      logger.debug2 "OG: title       = #{title}"
      logger.debug2 "OG: description = #{description}"
      logger.debug2 "OG: image       = #{image}"
      @open_graph = { :title => title,
                      :description => description,
                      :image => image,
                      :url   => api_gift.deep_link()}
      # add special twitter meta-tags if available
      # add twitter:creator if gift was created by a twitter user
      api_gift_twitter = api_gift.gift.api_gifts.find { |ag| ag.provider == 'twitter' }
      if api_gift_twitter
        created_by_user_id = api_gift.gift.created_by == 'giver' ? api_gift_twitter.user_id_giver : api_gift_twitter.user_id_receiver
        created_by = User.find_by_user_id(created_by_user_id)
        @open_graph[:twitter_creator] = '@' + created_by.api_profile_url.split('/').last if created_by.api_profile_url
        logger.debug2 "@open_graph[:twitter_creator] = #{@open_graph[:twitter_creator]}"
        # @open_graph[:twitter_creator] = Gofreerev
      end
      # facebook open graph:
      # https://developers.facebook.com/tools/debug
      # http://stackoverflow.com/questions/1138460/how-does-facebook-sharer-select-images
    elsif gift.api_gifts.length == 1
      @gift = gift.api_gifts.first
    else
      # same sort criteria as in user.api_gifts sort (gift.id not relevant here)
      api_gifts = gift.api_gifts.sort_by { |ag| ag.picture_sort(@users) }
      @gift = api_gifts.first
    end

    respond_to do |format|
      format.html {}
      # format.json { render json: @comment, status: :created, location: @comment }
      format.js {}
    end
  end # show

  # check for any share gift error message from API
  # normally share gift is done in a new tab (target=_blank) that is closed after share dialog is completed
  # exceptions:
  # - facebook does not close windows after share dialog
  private
  def check_share_gift_error
    # check for any share gift error message (facebook)
    if !xhr? and params[:share_gift].to_s != ''
      # todo: 1) redirect back to current page (index or show) to strip error_code and error_message from url?
      case params[:share_gift]
        when 'facebook'
          if params[:error_message].to_s != ''
            add_error_key 'gifts.index.share_gift_error', :apiname => provider_downcase('facebook'), :error => params[:error_message]
          end
        else
          logger.warn "Unexpected share gift signatur: params = #{params}"
      end # case
    end # if
  end # check_share_gift_error

end # GiftsController
