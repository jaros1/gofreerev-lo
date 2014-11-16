class CommentsController < ApplicationController

  before_filter :login_required, :except => [:create, :index, :destroy]

  # POST /comments.js
  # Parameters: {"utf8"=>"✓", "comment"=>{"gift_id"=>"j0N0uppxbj1nmDfsWBbk", "new_deal_yn"=>"Y", "price"=>"1", "comment"=>"25"}, "commit"=>"Gem"}
  def create
    # start with empty ajax response
    @api_comment = nil
    table = 'tasks_errors'
    begin
      return format_response_key '.invalid_request_no_comment_form' unless params.has_key?(:comment)
      gift = Gift.find_by_gift_id(params[:comment][:gift_id])
      return format_response_key '.invalid_request_unknown_gift' unless gift
      table = "gift-#{gift.id}-comment-new-errors"
      return format_response_key '.not_logged_in', :table => table unless logged_in?
      return format_response_key '.invalid_request_invalid_gift', :table => table unless gift.visible_for?(@users)
      # get user from @users. Must be giver, receiver or friend of giver or receiver.
      user = @users.find { |user2| gift.visible_for?([user2]) }
      logger.debug2 "user_id = #{user.user_id}"
      return format_response_key '.deleted_user', :table => table if user.deleted_at
      comment = Comment.new
      comment.gift_id = gift.gift_id if gift
      comment.comment = params[:comment][:comment].to_s.force_encoding('UTF-8')
      if params[:comment][:new_deal_yn] == 'Y'
        comment.new_deal_yn = params[:comment][:new_deal_yn]
        comment.price = params[:comment][:price].gsub(',', '.').to_f unless invalid_price?(params[:comment][:price])
        comment.currency = @users.first.currency
      end
      # add api_comments. provider must be in api_gifts and in login in @users
      gift_providers = gift.api_gifts.collect { |ag| ag.provider }
      @users.each do |user|
        next unless gift_providers.index(user.provider)
        api_comment = ApiComment.new
        api_comment.gift_id = gift.gift_id
        api_comment.comment_id = comment.comment_id
        api_comment.provider = user.provider
        api_comment.user_id = user.user_id
        comment.api_comments << api_comment
      end
      return format_response_key '.no_providers', :table => table if comment.api_comments.size == 0

      # validate comment - price= accepts only float and model can not return invalid price errors
      comment.valid?
      comment.errors.add :price, :invalid if params[:comment][:new_deal_yn] == 'Y' and invalid_price?(params[:comment][:price])
      if comment.errors.size > 0
        return format_response_key '.comment_error', :error => comment.errors.full_messages.join(', '), :table => table
      else
        comment.save!
      end

      # return new comment to browser
      @api_comment = comment.api_comments.shuffle.first
      format_response

    rescue => e
      logger.error2  "Exception: #{e.message.to_s}"
      logger.error2  "Backtrace: " + e.backtrace.join("\n")
      @api_comment = nil
      format_response_key '.exception', :error => e.message, :table => table
    end
  end # create

  # GET /comments.js
  # params:
  #   gift_id: required
  #   first_comment_id: Used in ajax request from gifts/index page to get more comments for a gift
  def index
    @gift = nil
    @api_comments = nil
    gift = nil
    table = 'tasks_errors'
    begin
      # find gift
      return format_response_key '.gift_id_is_missing' if params[:gift_id].to_s == ""
      gift = Gift.find_by_id(params[:gift_id])
      return format_response_key '.gift_not_found' if !gift
      # gift was found.
      # any ajax error messages are now ajax injected into row under gifts link in gifts/index page
      table = "gift-#{gift.id}-links-errors"
      return format_response_key '.not_logged_in', :table => table unless logged_in?
      # check if user may see gift. Must be giver, receiver, friend with giver or friend with receiver
      return format_response_key '.gift_not_friends', :table => table unless gift.visible_for?(@users)
      # check first_comment_id
      return format_response_key '.first_comment_id_is_missing', :table => table if params[:first_comment_id].to_s == ""
      first_comment = Comment.find_by_id(params[:first_comment_id])
      return format_response_key '.first_comment_not_found', :table => table unless first_comment
      return format_response_key '.gift_comment_mismatch', :table => table unless first_comment.gift_id == gift.gift_id

      # find api gift - same sort/selection as in User.api_gifts
      # sort by gift.status_update_at and sort by api_gift.status_sort is not relevant here
      # only sort by picture_sort
      ags = gift.api_gifts
      ags = ags.sort_by { |ag| ag.picture_sort(@users) }

      api_gift = ags.first
      # ok - get next set older comments (comment.id < params[:first_comment_id])
      @first_comment_id = first_comment.id
      @api_comments = gift.api_comments_with_filter(@users, first_comment.id)
      @gift = gift
      @api_gift = api_gift
      format_response

    rescue => e
      logger.error2 "Exception: #{e.message.to_s}"
      logger.error2 "Backtrace: " + e.backtrace.join("\n")
      @old_first_comment_id = nil
      @api_comments = nil
      format_response_key '.exception', :error => e.message.to_s, :raise => I18n::MissingTranslationData, :table => table
      logger.error2 "@errors = #{@errors}"
    end
  end # index

  # DELETE /comments/933.js?giftid=1426
  # ajax request from gifts/index page
  def destroy
    table = 'tasks_errors'
    @link_id = nil
    begin
      id = params[:id]
      comment = Comment.find_by_id(id)
      return format_response_key '.unknown_comment' unless comment
      table = "gift-#{comment.gift.id}-comment-#{comment.id}-errors"
      return format_response_key '.not_logged_in', :table => table unless logged_in?
      return format_response_key '.invalid_comment', :table => table unless comment.show_delete_comment_link?(@users)
      @users.remove_deleted_users
      return format_response_key '.deleted_user', :table => table unless comment.show_delete_comment_link?(@users)

      # delete mark comment
      # delete marked comment will be ajax removed from gifts/index page for current user now
      # delete marked comment will be ajax removed from gifts/index page for other users in util/new_messages_count request
      # old delete marked comments will be deleted from database in util/new_messages_count
      comment.deleted_at = Time.new
      comment.updated_by = login_user_ids.join(',')
      if !comment.save
        return format_response_key '.comment_error', :error => comment.errors.full_messages.join(', '), :table => table
      end
      # hide row with comment
      @link_id = comment.table_row_id
      format_response
    rescue => e
      logger.error2 "Exception: #{e.message.to_s}"
      logger.error2 "Backtrace: " + e.backtrace.join("\n")
      @link_id = nil
      format_response_key '.exception', :error => e.message, :table => table
    end
  end # destroy

end
