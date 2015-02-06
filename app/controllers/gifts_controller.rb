# encoding: utf-8
class GiftsController < ApplicationController

  before_filter :clear_state_cookie_store, :if => lambda {|c| !xhr?}
  before_filter :login_required, :except => [:create, :index, :show]

  def new
  end

  # ajax request - called from gifts/index page
  # return gift in new_messages_buffer_div and return any error messages in tasks_errors table
  # both in page header
  # JS function insert_update_gifts will move new gift from div buffer to gifts table in html page
  def create
    @api_gifts = []

    logger.debug2 "request.format = #{request.format}"
    logger.debug2 "xhr? = #{xhr?}"

    # File upload plugin support - ignore rails JS post - data has already been send in a json request
    if xhr? and params[:gift][:datatype] == 'json' and request.format == 'text/javascript'
      render :nothing => true
      return
    end

    begin
      return format_response_key '.not_logged_in' unless logged_in?

      # check if user account is being deleted (do not create new gift)
      users2 = @users.find_all { |u| !u.deleted_at }
      return format_response_key '.deleted_user' if users2.size == 0
      @users = users2 if @users.size != users2.size

      # initialize gift
      gift = Gift.new
      gift.direction = 'giver' if gift.direction.to_s == ''
      gift_file = params[:gift_file]
      picture = (gift_file.class.name == 'ActionDispatch::Http::UploadedFile')
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

      gift.valid?
      return format_response_text(gift.errors.full_messages.join(', ')) if gift.errors.size > 0

      # add api_gifts - one api_gifts for each provider
      # api_gift_id will be added in post_on_<provider> tasks
      # api_picture_url may change in post_on_<provider> tasks if picture store is :api
      @users.each do |user|
        api_gift = ApiGift.new
        api_gift.gid = gift.gid
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

    # initialize gift form in top of gifts/index page
    @gift = Gift.new
    @gift.direction = params[:direction] if params[:direction].to_s != ''
    if User.dummy_users?(@users)
      # todo: this looks like an error (not logged in user)
      # http: should redirect to auth/index page
      # ajax: should return an not logged in error message
      @api_gifts = []
      return format_response
    end

    # initialize list of gifts
    # list of gifts with @users as giver or receiver + gifts med @users.friends as giver or receiver
    newest_status_update_at = Sequence.status_update_at
    newest_gift = Gift.last

    # get list with gifts:
    # - return one gift in first http request (last_row_id is blank)
    # - return 10 gifts in next ajax requests (last_row_id is not blank = status_update_at for last row in gifts/index page)
    limit = last_row_id ? 10 : 1
    @api_gifts, @last_row_id = User.api_gifts(@users, :last_status_update_at => last_row_id, :limit => limit)

    # set_last_row_id(@last_row_id) # control - is checked in next ajax request
    # if last_row_id
    #   set_last_row_at(@request_start_time)
    # else
    #   # first http request at startup - ajax request for the next 10 rows in a split second
    #   set_last_row_at(@request_start_time-GET_MORE_ROWS_INTERVAL)
    # end

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
    if gift.api_gifts.length == 1
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

end # GiftsController
