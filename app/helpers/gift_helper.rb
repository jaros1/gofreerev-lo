# encoding: utf-8
module GiftHelper

  # show like/unlike link for gift under gift text and picture
  def link_to_gift_like_unlike (gift)
    if gift.show_like_gift_link?(@users)
      key, path = '.like_gift', util_like_gift_path(:gift_id => gift.id)
    else
      key, path = '.unlike_gift', util_unlike_gift_path(:gift_id => gift.id)
    end
    link_to t(key), path,
            :id => "gift-#{gift.id}-like-unlike-link", :class => "gift-action-link",
            :remote => true, :data => { :type => :script }, :format => :js,
            :method => :post
  end # link_to_gift_like_unlike

  # show follow/do not follow link for gift under gift text and picture
  # default is to follow gift as giver, receiver or commenter
  def link_to_gift_follow_unfollow (gift)
    if gift.show_follow_gift_link?(@users)
      key, path = '.follow_gift', util_follow_gift_path(:gift_id => gift.id)
    else
      key, path = '.unfollow_gift', util_unfollow_gift_path(:gift_id => gift.id)
    end
    link_to t(key), path,
            :id => "gift-#{gift.id}-follow-unfollow-link", :class => "gift-action-link",
            :remote => true, :data => { :type => :script }, :format => :js,
            :method => :post
  end # link_to_gift_follow_unfollow

  def link_to_gift_hide (gift)
    link_to t('.hide_gift'), util_hide_gift_path(:gift_id => gift.id),
            :id => "gift-#{gift.id}-hide-link", :class => "gift-action-link",
            :remote => true, :data => { :confirm => t('.confirm_hide_gift'), :type => :script }, :format => :js ,
            :method => :post
  end


  def lov_to_share_gift (gift)
    # link_to t('.share_gift'), '#', :onclick => 'alert("not implemented")'
    name = "share_gift_#{gift.id}"
    share_lov_text = t 'gifts.api_gift.share_lov_text'
    options = [[share_lov_text, '']] + SHARE_GIFT_API_NAME.to_a.collect { |a| a.reverse }.sort_by { |a| a[0] }
    select_tag name, options_for_select(options), :onchange => 'get_share_gift_link(this)', :id => name
  end # link_to_share_gift


    # it could be nice with a popup dialog box with three choices. a) hide and keep balance, b) destroy and update balance, c) cancel
  # but no build in JS function for this
  # must send a/b choice to util/delete_gift. must cancel require on c
  # some maybe useful links:
  # - http://www.pjmccormick.com/nicer-rails-confirm-dialogs-and-not-just-delete-methods
  # - http://stackoverflow.com/questions/7435859/custom-rails-confirm-box-with-rails-confirm-override
  # - http://rors.org/demos/custom-confirm-in-rails
  def link_to_delete_gift (gift)
    # confirm delete texts
    # - confirm_delete_gift_1 if delete gift effects user balance
    # - confirm_delete_gift_2 if delete gift does not effect user balance
    confirm_delete_gift_options = { :price => gift.price, :currency => gift.currency }
    if gift.received_at and gift.price and gift.price != 0.0
      # todo: check if login users are givers or
      directions = []
      gift.api_gifts.each do |ag|
        directions << 'giver' if login_user_ids.index(ag.user_id_giver)
        directions << 'receiver' if login_user_ids.index(ag.user_id_receiver)
      end
      directions = directions.uniq
      return nil if directions.size == 0 # error
      if directions.size == 2
        # no confirm box - login users are giver and receiver of gift
        keyno = 2
      else
        keyno = 1
        direction = directions.first
        user_names = gift.api_gifts.
            collect { |ag| direction == 'giver' ?  ag.receiver.short_user_name : ag.giver.short_user_name}.
            join(', ')
        confirm_delete_gift_options[:user_name] = user_names
      end
    else
      keyno = 2
    end
    confirm_delete_gift_key = ".confirm_delete_gift_#{keyno}"
    link_to t('.delete_gift'), util_delete_gift_path(:gift_id => gift.id),
            :id => "gift-#{gift.id}-delete-link", :class => "gift-action-link",
            :remote => true,
            :data => { :confirm => t(confirm_delete_gift_key, confirm_delete_gift_options), :type => :script }, :format => :js,
            :method => :post
  end # link_to_delete_gift


  def link_to_comment_options (comment, action)
    key = action == 'delete' ? 'delete_comment' : "#{action}_new_deal"
    { :id => "gift-#{comment.gift.id}-comment-#{comment.id}-#{action}-link",
      :class => 'comment-action-link',
      :remote => true, :format => :js,
      :method => action == 'delete' ? :delete : :post,
      :data => { :confirm => t(".confirm_#{key}"), :type => :script }
    }
  end

  # the giftid param is used as extra information in url for comment-action-link event (cancel, accept, reject, delete)
  # cleanup any old ajax error messages before new ajax delete comment request
  # see $(".comment-action-link").bind("click" in my.js
  def link_to_cancel_new_deal (comment)
    link_to t('.cancel_new_deal'),
            util_cancel_new_deal_path(:comment_id => comment.id, :giftid => comment.gift.id),
            link_to_comment_options(comment, 'cancel')
  end

  def link_to_accept_new_deal (comment)
    link_to t('.accept_new_deal'),
            util_accept_new_deal_path(:comment_id => comment.id, :giftid => comment.gift.id),
            :id => "gift-#{comment.gift.id}-comment-#{comment.id}-accept-link", :class => 'comment-action-link',
            :remote => true, :format => :js, :method => :post, :data => { :confirm => t('.confirm_accept_new_deal'),
                                                                          :type => :script }
  end

  def link_to_reject_new_deal (comment)
    link_to t('.reject_new_deal'),
            util_reject_new_deal_path(:comment_id => comment.id, :giftid => comment.gift.id),
            :id => "gift-#{comment.gift.id}-comment-#{comment.id}-reject-link", :class => 'comment-action-link',
            :remote => true, :format => :js, :method => :post, :data => { :confirm => t('.confirm_reject_new_deal'),
                                                                          :type => :script }
  end

  def link_to_delete_comment (comment)
    link_to t('.delete_comment'),
            comment_path(comment.id, :giftid => comment.gift.id),
            link_to_comment_options(comment, 'delete')
  end

end
