# encoding: utf-8
class GiftsController < ApplicationController

  before_action :clear_state_cookie_store, :if => lambda {|c| !xhr?}
  before_action :login_required, :except => [:create, :index, :show]

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
