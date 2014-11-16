# translation key used in notifications. 4 elements.
# noti_type:
NOTI_KEY_1 = {1 => 'new_comment',
              2 => 'new_proposal',
              3 => 'cancelled_proposal',
              4 => 'rejected_proposal',
              5 => 'accepted_proposal'}
# gift type/status
NOTI_KEY_2 = {1 => 'giver',
              2 => 'receiver',
              3 => 'giver_and_receiver'}
# user group.
NOTI_KEY_3 = {1 => '',
              2 => '_other',
              3 => '_follow'}
NOTI_KEY_4 = "1" # version


class Comment < ActiveRecord::Base

  belongs_to :gift, :class_name => 'Gift', :primary_key => :gift_id, :foreign_key => :gift_id
  has_many :api_comments, :class_name => 'ApiComment', :primary_key => :comment_id, :foreign_key => :comment_id, :dependent => :destroy

  before_create :before_create
  before_update :before_update
  # before_destroy :before_destroy
  after_create :after_create
  after_update :after_update

  # https://github.com/jmazzi/crypt_keeper - text columns are encrypted in database
  # encrypt_add_pre_and_postfix/encrypt_remove_pre_and_postfix added in setters/getters for better encryption
  # this is different encrypt for each attribute and each db row
  # _before_type_cast methods are used by form helpers and are redefined
  crypt_keeper :comment, :currency, :price, :encryptor => :aes, :key => ENCRYPT_KEYS[28]



  ##############
  # attributes #
  ##############

  # 1) comment_id - required - not encrypted - readonly
  validates_presence_of :comment_id
  validates_uniqueness_of :comment_id
  attr_readonly :comment_id
  before_validation(on: :create) do
    self.comment_id = self.new_encrypt_pk unless self.comment_id
  end

  def comment_id=(new_comment_id)
    return self['comment_id'] if self['comment_id']
    self['comment_id'] = new_comment_id
  end

  # 3) comment - required - String in model - encrypted text in db
  def comment
    # logger.debug2  "comment = #{read_attribute(:comment)} (#{read_attribute(:comment).class.name})"
    return nil unless (extended_comment = read_attribute(:comment))
    encrypt_remove_pre_and_postfix(extended_comment, 'comment', 31)
  end
  def comment=(new_comment)
    # logger.debug2  "new_comment = #{new_comment} (#{new_comment.class.name})"
    if new_comment
      check_type('comment', new_comment, 'String')
      write_attribute :comment, encrypt_add_pre_and_postfix(new_comment, 'comment', 31)
    else
      write_attribute :comment, nil
    end
  end
  alias_method :comment_before_type_cast, :comment
  def comment_was
    return comment unless comment_changed?
    return nil unless (extended_comment = attribute_was(:comment))
    encrypt_remove_pre_and_postfix(extended_comment, 'comment', 31)
  end


  # 4) Gift id - required - unencrypted string

  # 5) currency - only for agreement proposal - String in model - encrypted text in db - update not allowed
  attr_readonly :currency
  validates_inclusion_of :currency, :allow_blank => true, :in => Money::Currency.table.collect { |a| [  a[1][:iso_code] ][0] }

  def currency
    return nil unless (extended_currency = read_attribute(:currency))
    # logger.debug2  "currency = #{extended_currency}"
    encrypt_remove_pre_and_postfix(extended_currency, 'currency', 32)
  end # currency
  def currency=(new_currency)
    if !new_record?
      nil
    elsif new_currency
      check_type('currency', new_currency, 'String')
      write_attribute :currency, encrypt_add_pre_and_postfix(new_currency, 'currency', 32)
    else
      write_attribute :currency, nil
    end
  end # currency=
  alias_method :currency_before_type_cast, :currency
  def currency_was
    return currency unless currency_changed?
    return nil unless (extended_currency = attribute_was(:currency))
    # logger.debug2  "extended_currency = #{extended_currency}"
    encrypt_remove_pre_and_postfix(extended_currency, 'currency', 32)
  end # currency_was

  # 6) price - only for agreement proposal - Float in model - encrypted text in db
  # todo: there is a minor problem with price validation.
  # price= accepts only float and model can not return invalid price errors
  def price
    return nil unless (temp_extended_price = read_attribute(:price))
    str_to_float_or_nil encrypt_remove_pre_and_postfix(temp_extended_price, 'price', 33)
  end # price
  def price=(new_price)
    if !new_record?
      nil
    elsif new_price.to_s != ''
      check_type('price', new_price, 'Float')
      write_attribute :price, encrypt_add_pre_and_postfix(new_price.to_s, 'price', 33)
    else
      write_attribute :price, nil
    end
  end # price=
  alias_method :price_before_type_cast, :price
  def price_was
    return price unless price_changed?
    return nil unless (temp_extended_price = attribute_was(:price))
    str_to_float_or_nil encrypt_remove_pre_and_postfix(temp_extended_price, 'price', 33)
  end # price_was

  # 7) new_deal_yn - y for agreement proposal - n for cancelled agreement - not encrypted string

  # 8) accepted_yn - y for accepted agreement - n for rejected agreement - not encrypted string

  # 9) status_update_at - integer - keep track of comments changed after user has loaded gifts/index page

  # 10) deleted_at - datetime - when was comment marked as deleted

  # 11) updated_by - string - comma seperated string with userids for update (delete comment, cancel/reject,/accept deal proposal)
  # ( used when sending notification - do not send notification to logged in users = users in updated_by field )
  validates_each :updated_by do |rec, attr, value|
    if rec.new_record?
      if value.to_s != ''
        logger.debug2 'updated_at must be blank after create'
        rec.errors.add attr, :present
      end
    elsif value.to_s == ''
      logger.debug2 'updated_at is required'
      rec.errors.add attr, :blank # updated_at is required after update
    else
      # check users
      user_ids = value.split(',')
      users = User.where('user_id in (?)', user_ids)
      if users.size != user_ids.size
        logger.debug2 'One or more invalid user ids in updated_at'
        rec.errors.add attr, :invalid
      else
        allowed_user_ids = rec.api_comments.collect { |ac| ac.user_id } +
            rec.gift.api_gifts.collect { |ag| ag.user_id_giver } +
            rec.gift.api_gifts.collect { |ag| ag.user_id_receiver }
        shared_user_ids = user_ids & allowed_user_ids
        if shared_user_ids.size == 0
          logger.debug2 "updated_by is invalid. updated_at = #{value}. Allowed userids #{allowed_user_ids.join(', ')}"
          rec.errors.add attr, :invalid
        elsif shared_user_ids.size < user_ids.size
          logger.warn "comment.updated_by was invalid and one or more userids has been removed"
          logger.warn "please set correct comment.updated_by when updating comment status"
          logger.warn "old value = #{value}"
          rec.updated_by = shared_user_ids.join(',')
          logger.warn "new value = #{rec.updated_by}"
        end
      end
    end
  end # validates_each :updated_by

  def table_row_id
    "gift-#{gift.id}-comment-#{id}"
  end # table_row_id


  def debug_notifications
    true
  end # debug_notifications

  # helpers used in comments/comment_status partial - show/hide comment links

  # display cancel new deal check box?
  # only for new not accepted/rejected agreement proposals
  def show_cancel_new_deal_link? (users)
    return false unless new_deal_yn == 'Y'
    return false if accepted_yn
    login_user_ids = users.find_all { |u| !u.deleted_at }.collect { |u| u.user_id }
    comment_user_ids = api_comments.collect { |ac| ac.user_id }
    user_ids = login_user_ids & comment_user_ids
    return false if user_ids.size == 0
    return false if gift.direction == 'both'
    true
  end # show_cancel_new_deal_link?

  def show_accept_new_deal_link? (users)
    return false unless new_deal_yn == 'Y'
    return false if accepted_yn
    login_user_ids = users.find_all { |u| !u.deleted_at }.collect { |u| u.user_id }
    return false if gift.direction == 'both'
    gift_user_ids = gift.api_gifts.collect { |ag| ag.user_id_giver || ag.user_id_receiver }
    user_ids = login_user_ids & gift_user_ids
    return false if user_ids.size == 0 # login user(s) are not creator(s) of gift
    # user(s) is creator of gift.
    # recheck friend relation with creator of new proposal
    # friends relation can have changed - or maybe not logged in with the correct users to accept deal proposal
    users2 = users.find_all { |u| user_ids.index(u.user_id)}
    special_case = false # special case - users friend but not users2 friend
    api_comments.each do |api_comment|
      return true if (api_comment.user.friend?(users2) <= 2) # login user is friend with creator of deal proposal
      special_case = true if users.size != users2.size and (api_comment.user.friend?(users) <= 2)
    end
    if special_case
      logger.info2 "special case. login user(s) are not friend with creator(s) of new deal proposal"
    else
      logger.debug2 "login user(s) are not friend with creator(s) of new deal proposal"
    end
    false
  end # show_accept_new_deal_link?

  def show_reject_new_deal_link? (users)
    show_accept_new_deal_link?(users)
  end # show_reject_new_deal_link?

  # ok to delete comment if login user(s) is giver, receiver or creator of comment
  def show_delete_comment_link?(users)
    return false unless [Array, ActiveRecord::Relation::ActiveRecord_Relation_User].index(users.class) and users.length > 0
    return false if users.size == 1 and users.first.dummy_user?
    return false if accepted_yn == 'Y' # delete accepted proposal is not allow - delete gift is allowed
    return false if deleted_at # comment has already been marked as deleted
    # ok to delete if login user(s) is giver/reciever
    gift.api_gifts.each do |api_gift|
      user = users.find { |user2| user2.provider == api_gift.provider }
      next unless user
      return true if [api_gift.user_id_receiver, api_gift.user_id_giver].index(user.user_id) # giver or receiver
    end
    # ok to delete if login user(s) has created the comment
    api_comments.each do |api_comment|
      user = users.find { |user2| user2.provider == api_comment.provider}
      next unless user
      return true if api_comment.user_id == user.user_id # creator of comment
    end
    # not giver/receiver - not creator of comment - delete if not allowed
    false
  end # show_delete_comment_link?

  def cancelled_proposal?
    noti_type = 3 if (new_deal_yn_was == 'Y' and !new_deal_yn and !accepted_yn)
    noti_type
  end # cancelled_proposal?
  def rejected_proposal?
    noti_type = 4 if (new_deal_yn == 'Y' and !accepted_yn_was and accepted_yn == 'N')
    noti_type
  end # rejected_proposal?
  def accepted_proposal?
    noti_type = 5 if (new_deal_yn == 'Y' and !accepted_yn_was and accepted_yn == 'Y')
    noti_type
  end # accepted_proposal?
  def deleted_comment?
    !deleted_at_was and deleted_at # deleted mark comment
  end # deleted_comment?

  def get_noti_key_prefix (noti_key_1, noti_key_2, noti_key_3)
    NOTI_KEY_1[noti_key_1] + '_' + NOTI_KEY_2[noti_key_2] + NOTI_KEY_3[noti_key_3]
  end # get_noti_key_prefix

  def init_noti_key_regexp (noti_key_1, noti_key_2, noti_key_3)
    noti_key_prefix = get_noti_key_prefix(noti_key_1, noti_key_2, noti_key_3)
    Regexp.new "^#{noti_key_prefix}_(1|2|3|n)_v#{NOTI_KEY_4}$"
  end # init_noti_key_regexp



  # Note: nnn different translations. See inbox/index/gift_comment*
  # noti_key_1: 1:new comment, 2:new proposal, 3:cancelled proposal, 4:rejected proposal, 5:accepted proposal
  # noti_key_2: 1:giver, 2:receiver, 3: giver and receiver
  # noti_key_3: 1: notification to owner of gift and followers of gift, 2: notification to other users that has commented the gift, 3: notification to followers
  # from_user is user that has commented the gift - added to noti_options hash
  # to_user is giver, receiver or an other user that also has commented the gift - receiver of notification
  # noti_key is concatenation of noti_key_1, noti_type_2, noti_key_3 and NOTI_KEY_4 (version)
  # total of 176 different translation keys                                   8
  # config/locales/language.yml/inbox/index/new_comment_* (48 translations)
  # config/locales/language.yml/inbox/index/new_proposal_* (32 translations)
  # config/locales/language.yml/inbox/index/cancelled_proposal_* (32 translations)
  # config/locales/language.yml/inbox/index/rejected_proposal_* (32 translations)
  # config/locales/language.yml/inbox/index/accepted_proposal_* (32 translations)
  def send_notification (noti_key_1, noti_key_2, noti_key_3, from_users, to_user)
    raise "invalid noti_key_3" if [true, false].index(noti_key_3)
    logger.debug2  "noti_key_1 = #{noti_key_1} (#{NOTI_KEY_1[noti_key_1]}), " +
             "noti_key_2 = #{noti_key_2} (#{NOTI_KEY_2[noti_key_2]}), " +
             "noti_key_3 = #{noti_key_3} (#{NOTI_KEY_3[noti_key_3]}), " +
             "from_users = #{User.debug_info(from_users)}, " +
             ", to_user = #{to_user.debug_info}" if debug_notifications
    if from_users.size > 1
      from_users.each { |from_user| send_notification(noti_key_1, noti_key_2, noti_key_3, [from_user], to_user) }
      return
    end
    from_user = from_users.first

    ## find from user. 3 user cases:
    ## a) one and only one from user - use this even if provider for from and to users does not match (cross provider notification)
    ## b) many from users shared provider exist - use from user with same provider as to user
    ## c) many from users and shared provider does not exist - todo: create test case
    #if from_users.size == 1
    #  # case a
    #  from_user = from_users.first
    #elsif (from_user = from_users.find { |u| u.provider == to_user.provider})
    #  # case b - ok
    #  nil
    #else
    #  # case c
    #  logger.debug2 "case c: found no shared providers between from_users and to_user"
    #  logger.debug2 "from_users = #{User.debug_info(from_users)}"
    #  logger.debug2 "to_user = #{to_user.debug_info}"
    #  raise "invalid from_users / to_user. No shared providers was found"
    #end
    #if from_user.provider != to_user.provider
    #  logger.debug2 "case a: found no shared providers between from_users and to_user"
    #  logger.debug2 "from_users = #{User.debug_info(from_users)}"
    #  logger.debug2 "to_user = #{to_user.debug_info}"
    #end

    if [1,2].index(noti_key_1)
      # new comment/proposal. api comment row has just been created for from_user
      api_comment = api_comments.find { |ac| ac.user_id == from_user.user_id }
    else
      api_comment = api_comments.find { |ac| ac.provider == from_user.provider }
    end

    # todo: test if we always can find a api comment when sending notifications
    # raise "todo: test if we always can find a api comment when sending notifications" unless api_comment
    logger.warn2 "warning: did not find api comment for #{to_user.provider}" unless api_comment
    logger.warn2 "warning: did not find api comment for #{to_user.provider}" unless api_comment
    logger.warn2 "warning: did not find api comment for #{to_user.provider}" unless api_comment



    if [3,4].index(noti_key_1)
      logger.debug2  "special handling of noti_key_1 = 3..5 ..." if debug_notifications
      # special handling of noti_type_1 = 3..5. noti_key_1 (noti_type):
      #   3 - cancelled proposal notification
      #       a) change unread new proposal notification to new_comment notification (remove+send+stop)
      #       b) read new proposal - send cancelled proposal notification to owner of gift - continue
      #       c) read new proposal - don't send any other notifications
      #   4 - rejected proposal
      #       a) change any unread new proposal notification to new comment notification (remove+send)
      #       b) send rejected proposal notification to owner of new proposal / comment
      #       c) don't send any other notifications
      #   5 - accepted proposal
      #       a) unread - change unread new proposal notification to accepted proposal notification (remove)
      #       b) read - send accepted proposal notification

      # logger.debug2  "comment id #{id} used in unread notifications " + notifications.where("noti_read = 'N'").collect { |n| "#{n.noti_key} to #{n.to_user.short_user_name}" }.join(', ')
      # comment id 3 used in
      #   a) unread notifications new_proposal_giver_3_v1 to Charlie S,
      #   b) new_proposal_giver_other_2_v1 to Sandra Q,
      #   c) new_proposal_giver_other_1_v1 to Karen S
      # do not a) change new_proposal_giver_3_v1 to Charlie S
      # change b) new_proposal_giver_other_2_v1 to Sandra Q to a new_proposal_giver_other_1_v1 (u2/karen) and a new_comment_giver_other_1_v1 (u3/david)
      # change c) new_proposal_giver_other_1_v1 to Karen S to a new_comment_giver_other_1_v1 (u3/david)

      # find any new_proposal_other notifications for this comment. used in 3a, 4a and 5a
      regexp1 = init_noti_key_regexp(2, noti_key_2, 1) # notification to gift giver/receiver
      regexp2 = init_noti_key_regexp(2, noti_key_2, 2) # notification to other users
      regexp3 = init_noti_key_regexp(2, noti_key_2, 3) # notification to followers
      new_proposal_notifications = api_comment.notifications.find_all do |n|
        ((noti_key_1 == 3 and regexp1.match(n.noti_key)) or regexp2.match(n.noti_key) or regexp3.match(n.noti_key))
      end
      if new_proposal_notifications.size == 0
        logger.debug2  "no new proposal notifications was found for comment id #{id}" if debug_notifications
      else
        logger.debug2  "comment id #{id} used in new proposal notifications:" if debug_notifications
        0.upto(new_proposal_notifications.size-1) do |i|
          n = new_proposal_notifications[i]
          logger.debug2  "#{i+1}: #{n.noti_read == 'N' ? 'un' : ''}read #{n.noti_key} to #{n.to_user.short_user_name}"
          logger.debug2  "#{i+1}: from user #{n.from_user.short_user_name}" if n.from_user
        end if debug_notifications
      end

      stop = false
      0.upto(new_proposal_notifications.size-1) do |i|
        new_proposal_notification = new_proposal_notifications[i]
        if new_proposal_notification.noti_read == 'N'
          logger.debug2  "#{i+1}: #{new_proposal_notification.noti_read == 'N' ? 'un' : ''}read #{new_proposal_notification.noti_key} to #{new_proposal_notification.to_user.short_user_name}" if debug_notifications
          # 3a, 4a, 5a - change unread new_proposal_other notification to new_comment notification
          logger.debug2  "#{i+1}: case 3a, 4a, 5a - change unread new_proposal_other notification to new_comment notification" if debug_notifications
          # change or delete new_proposal_notification
          logger.debug2  "#{i+1}: change or delete new_proposal_notification" if debug_notifications
          api_comment.remove_from_notification(new_proposal_notification)
          # add new comment notification corresponding to changed/deleted new proposal notification
          logger.debug2  "#{i+1}: add new comment notification corresponding to changed/deleted new proposal notification" if debug_notifications
          # initialize variables to be used in new comment notification that replaces removed new proposal notification
          logger.debug2  "#{i+1}: initialize variables to be used in new comment notification that replaces removed new proposal notification" if debug_notifications
          tmp_noti_key_3 = case
                             when regexp1.match(new_proposal_notification.noti_key) then 1
                             when regexp2.match(new_proposal_notification.noti_key) then 2
                             when regexp3.match(new_proposal_notification.noti_key) then 3
                           end
          if noti_key_1 == 3
            # cancelled - from_user = comment.user - ok
            tmp_from_user = from_user
          else
            # rejected/accepted - use from_user from new_proposal_notification
            tmp_from_user = new_proposal_notification.from_user || user
          end
          tmp_to_user = new_proposal_notification.to_user
          logger.debug2  "#{i+1}: noti_key_3 = #{noti_key_3}, tmp_noti_key_3 = #{tmp_noti_key_3}" if debug_notifications
          logger.debug2  "#{i+1}: from_user = #{from_user.short_user_name}, tmp_from_user = #{tmp_from_user ? tmp_from_user.short_user_name : nil}" if debug_notifications
          logger.debug2  "#{i+1}: to_user = #{to_user.short_user_name}, tmp_to_user = #{tmp_to_user.short_user_name}" if debug_notifications
          send_notification(1, noti_key_2, tmp_noti_key_3, [tmp_from_user], tmp_to_user)
          logger.debug2  "#{i+1}: stop check: noti_key_1 = #{noti_key_1}, new_proposal_notification.noti_key = #{new_proposal_notification.noti_key}" if debug_notifications
          if [3,4].index(noti_key_1) and regexp1.match(new_proposal_notification.noti_key)
            logger.debug2  "#{i+1}: signal stop" if debug_notifications
            stop = true
          end
        else
          # 3b, 3c, 4b, 4c, 5b - don't change read new proposal notification
          logger.debug2  "#{i+1}: 3b, 3c, 4b, 4c, 5b - don't change read new proposal notification" if debug_notifications
        end
      end # each new_proposal_notification
      if stop
        logger.debug2  "stopped" if debug_notifications
        return
      end

      #regexp = init_noti_key_regexp(2, noti_key_2, noti_key_3)
      #logger.debug2  "regexp = #{regexp}, comment.id = #{id}, to_userid = #{to_user.user_id} (#{to_user.short_user_name})"
      #new_proposal_notifications = notifications.where("to_user_id = ? and noti_read = 'N'", to_user.user_id).find_all { |n| regexp.match(n.noti_key)}
      #logger.debug2  "new_proposal_notifications.size = #{new_proposal_notifications.size}"
      #new_proposal_notification = new_proposal_notifications.first
      #logger.debug2  new_proposal_notification
      #if new_proposal_notification
      #  # 3a, 4a or 5a
      #  remove_from_notification(new_proposal_notification)
      #  if [3,4].index(noti_key_1)
      #    # 3a or 4a
      #    logger.debug2  "Comment.send_notification: case #{noti_key_1}a"
      #    logger.debug2  "new_proposal.from_user.short_user_name = #{new_proposal_notification.from_user.short_user_name}" if new_proposal_notification.from_user
      #    logger.debug2  "new_proposal.to_user.short_user_name = #{new_proposal_notification.to_user.short_user_name}"
      #    logger.debug2  "from_user.short_user_name = #{from_user.short_user_name}"
      #    logger.debug2  "to_user.short_user_name = #{to_user.short_user_name}"
      #    logger.debug2  "todo: can not use from_user in case 4a. is invalid for 4a"
      #    if noti_key_1 == 3
      #      # cancelled - from_user = comment.user - ok
      #      send_notification(1, noti_key_2, noti_key_3, from_user, to_user) # new comment notification
      #    else
      #      send_notification(1, noti_key_2, noti_key_3, new_proposal_notification.from_user, to_user) # new comment notification
      #    end
      #    return
      #  end
      #  # 5a => 5b
      #else
      #  # 3b, 3c, 4b, 4c, 5b
      #  return if noti_key_1 == 3 and ![gift.user_id_giver, gift.user_id_receiver].index(to_user.user_id) # 3c
      #  return if noti_key_1 == 4 and user_id != to_user.user_id # 4c
      #  # 3b, 4b, 5b
      #end

    end # if [3,4,5].index(noti_key_1)

    noti_key_prefix = get_noti_key_prefix(noti_key_1, noti_key_2, noti_key_3)
    regexp = init_noti_key_regexp(noti_key_1, noti_key_2, noti_key_3)
    # logger.debug2  "regexp = #{regexp}"
    match = nil
    n = Notification.where("to_user_id = ? and noti_read = 'N'", to_user.user_id)
    .find { |n| n.noti_options[:giftid] == gift.id and match = regexp.match(n.noti_key) }
    if !n
      # first unread comment for this gift
      logger.debug2  "first unread comment for this gift" if debug_notifications
      n = Notification.new
      n.to_user_id = to_user.user_id
      n.from_user_id = from_user.user_id # set to nil if no_users > 1
      n.internal = 'Y'
      n.noti_key = "#{noti_key_prefix}_1_v#{NOTI_KEY_4}" # no_users = 1
      if %w(giver both).index(gift.direction)
        givername = gift.api_gifts.shuffle.first.giver.short_user_name
      end
      if %w(receiver both).index(gift.direction)
        receivername = gift.api_gifts.shuffle.first.receiver.short_user_name
      end
      noti_options = {:giftid => gift.id, :gifttext => gift.description.first(30),
                      :no_users => 0, :no_other_users => -2,
                      :username1 => nil,
                      :username2 => nil,
                      :username3 => nil,
                      :givername => givername, # (gift.user_id_giver ? gift.giver.short_user_name : ""),
                      :receivername => receivername} # (gift.user_id_receiver ? gift.receiver.short_user_name : "")}
      logger.debug2  "noti_key_1 = #{noti_key_1}, noti_key_3 = #{noti_key_3}" if debug_notifications
      if [1,2,3].index(noti_key_1) or noti_key_3 == 2
        # user array not used for rejected and accepted notification to owner of comment
        noti_options[:username1] = from_user.short_user_name
        noti_options[:no_users] += 1
        noti_options[:no_other_users] += 1
      end
      if [4, 5].index(noti_key_1)
        # names of giver/receiver are used in reject/accept notifications
        # noti_type_1 = 5: giver/receiver is added to gift after the notifications are sent
        logger.debug2  "before: givername = #{noti_options[:givername]}, receivername = #{noti_options[:receivername]}" if debug_notifications
        noti_options[:givername] = user.short_user_name if noti_options[:givername] == ""
        noti_options[:receivername] = user.short_user_name if noti_options[:receivername] == ""
        logger.debug2  "after: givername = #{noti_options[:givername]}, receivername = #{noti_options[:receivername]}" if debug_notifications
      end
      n.noti_options = noti_options
      n.noti_read = 'N'
    elsif [4,5].index(noti_key_1) and noti_key_3 == 2
      raise "debug - this notification should only be sent once"
    elsif n.api_comments.find { |c| c.user_id == from_user.user_id }
      # user already in unread notification messages "user array"
      # logger.debug2  "user already in unread notification message"
      nil
    else
      # user not in unread notification messages "user array"
      # change noti_key / add user to unread notification message
      # logger.debug2  "change noti_key / add user to unread notification message"
      noti_options = n.noti_options # copy to/from local variable for encryption to work
      noti_options[:no_users] += 1
      noti_options[:no_other_users] += 1
      if noti_options[:no_users] > 3 then
        xno_users = 'n'
      else
        xno_users = noti_options[:no_users].to_s
        noti_options["username#{xno_users}".to_sym] = from_user.short_user_name
      end
      if n.from_user_id
        logger.debug2  "clear from_userid (#{n.from_user.short_user_name}) for notification #{n.id}. todo: Can cause problems for rule 4a" if debug_notifications
        n.from_user_id = nil # set to nil (no_users > 1)
      end
      n.noti_key = "#{noti_key_prefix}_#{xno_users}_v#{NOTI_KEY_4}"
      n.noti_options = noti_options
    end
    n.valid?
    # todo: error response from comment/create does not work
    logger.error2  "n.errors = " + n.errors.full_messages.join('. ') if not n.valid?
    n.save!
    # add comment id to ajax comments - used in new messages count where new comments is ajax inserted in gifts/index page
    # buffer is returned to gifts/index page and cleared in util_controller.new_messages_count
    # buffer is cleared in gifts_controller.index when user starts or reloads index page
    # buffer is emptied for messages older whan 6 minutes in AjaxComment.after_insert call back
    ac = AjaxComment.new
    ac.user_id = to_user.user_id
    ac.comment_id = comment_id
    ac.save!
    # add row to CommentNotification / keep track of number of users in notification message
    logger.debug2  "add CommentNotification for comment id #{id} and notification id #{n.id} #{n.noti_key}" if debug_notifications
    cn = ApiCommentNotification.where("api_comment_id = ? and notification_id = ?", api_comment.id, n.id).first
    if !cn
      cn = ApiCommentNotification.new
      cn.api_comment_id = api_comment.id
      cn.notification_id = n.id
      cn.save!
    end
  end # create_or_update_noti



  def before_create
    self.status_update_at = Sequence.next_status_update_at
  end
  def before_update
    # logger.debug2  "price = #{price} (#{price.class})"
    # logger.debug2  "currency = #{currency} (#{currency.class})"
    self.status_update_at = Sequence.next_status_update_at if accepted_proposal? or rejected_proposal? or cancelled_proposal?
    if deleted_comment?
      # delete marked comment - will be removed from gift/index pages within the next 5 minutes
      self.status_update_at = Sequence.next_status_update_at
      logger.debug2  "cleanup any unread notifications" if debug_notifications
      # change number of users for any unread notifications
      api_comments.each do |api_comment|
        api_comment.remove_from_notifications
      end # each api_comment
    end # if
  end # before_update

  # Note: 176 different translation keys                                   8
  # config/locales/language.yml/inbox/index/new_comment_* (48 translations)
  # config/locales/language.yml/inbox/index/new_proposal_* (32 translations)
  # config/locales/language.yml/inbox/index/cancelled_proposal_* (32 translations)
  # config/locales/language.yml/inbox/index/rejected_proposal_* (32 translations)
  # config/locales/language.yml/inbox/index/accepted_proposal_* (32 translations)
  # this method is also called from after_update for noti types 3 .. 5 (cancel, reject and accept). update = true
  def after_create (update = false)
    # find noti_key_1 and noti_userids. noti_key1 is part of translate key for notification
    # - noti_key_1: 1:new comment, 2:new proposal, 3:cancelled proposal, 4:rejected proposal, 5:accepted proposal
    # - from_userids: sender of notification
    if update
      # called from after_update callback
      case
        when accepted_proposal?
          noti_key_1 = 5 # accepted
          # from_userids = gift.api_gifts.collect { |ag| ag.user_id_giver || ag.user_id_receiver }
        when rejected_proposal?
          noti_key_1 = 4 # rejected
          # from_userids = gift.api_gifts.collect { |ag| ag.user_id_giver || ag.user_id_receiver }
        when cancelled_proposal?
          noti_key_1 = 3 # cancelled
          # from_userids = api_comments.collect { |ac| ac.user_id }
      end # case
      from_userids = updated_by.split(',')
      # after update
    else
      # after insert
      if new_deal_yn == 'Y'
        noti_key_1 = 2 # proposal
      else
        noti_key_1 = 1 # comment
      end
      from_userids = api_comments.collect { |ac| ac.user_id }
      # after insert
    end
    # from_users & from_providers - sender of notification
    from_users = User.where('user_id in (?)', from_userids)
    from_providers = from_userids.collect { |u| u.split('/').last }
    # direction - noti_key_2 - part of translate key for notification
    case
      when gift.direction == 'both' then
        noti_key_2 = 3
      when gift.direction == 'giver' then
        noti_key_2 = 1
      when gift.direction == 'receiver' then
        noti_key_2 = 2
      else
        raise "system error: gift without giver or receiver"
    end
    # noti_key prefix - part 1 & 2 in notification message translate key
    logger.debug2 "noti_key_1 = #{noti_key_1}, noti_key_2 = #{noti_key_2}"
    noti_key_prefix = NOTI_KEY_1[noti_key_1] + '_' + NOTI_KEY_2[noti_key_2]
    logger.debug2 "noti_key_prefix = #{noti_key_prefix}" if debug_notifications
    logger.debug2 "from_users = #{User.debug_info(from_users)}"
    logger.debug2 "from_providers = #{from_providers.join(', ')}"
    # initialise helpers - arrays with giver user_id's, receiver user_id's and both
    # todo: drop dummy_user? check - dummy users are added in after_update callback
    gift_givers = gift.api_gifts.
        find_all { |ag| ag.giver and !ag.giver.dummy_user? and from_providers.index(ag.provider) }.
        collect { |api_gift| api_gift.user_id_giver }
    gift_receivers = gift.api_gifts.
        find_all { |ag| ag.receiver and !ag.receiver.dummy_user? and from_providers.index(ag.provider) }.
        collect { |api_gift| api_gift.user_id_receiver }
    gift_giver_and_receivers = gift_givers + gift_receivers
    logger.debug2 "gift_givers = #{gift_givers.join(', ')}"
    logger.debug2 "gift_receivers = #{gift_receivers.join(', ')}"
    logger.debug2 "gifts_giver_and_receivers = #{gift_giver_and_receivers.join(', ')}"

    gift_givers_shared = gift_givers.find_all { |user_id| from_providers.index(user_id.split('/').last) }
    gift_receivers_shared = gift_receivers.find_all { |user_id| from_providers.index(user_id.split('/').last) }

    # send notifications
    case
      when [1,2,5].index(noti_key_1)
        # new comment, new proposal and accepted proposal

        # 1) notifications to giver and/or receiver
        #    do not send notification to logged in users (from_users)
        #    - that is api_comments.user's for 1/2 new comment/proposal
        #    - that is updated_by user's for 5 accept proposal
        logger.debug2  "1: send notifications to gifts giver and/or receiver" if debug_notifications
        users1_ids = gift_giver_and_receivers - from_userids
        if users1_ids.size == 0
          users1 = []
        else
          users1 = User.where('user_id in (?)', users1_ids)
          raise 'one or more invalid userids in giver and receivers' if users1.size != users1_ids.size
        end

        ## old: users1.push(gift.giver) if gift.user_id_giver and from_userid != gift.user_id_giver
        #logger.debug2 "1a: gift.direction = #{gift.direction}"
        #logger.debug2 "1a: gift_givers    = #{gift_givers.join(', ')}"
        #logger.debug2 "1a: from_userids   = #{User.debug_info(from_users)}"
        #shared_userids = gift_givers & from_userids
        #logger.debug2 "1a: shared_userids = #{shared_userids.join(', ')}"
        #if %w(giver both).index(gift.direction) and shared_userids.size == 0
        #  raise "did not find any shared providers" if gift_givers_shared.size == 0
        #  users1 += User.where('user_id in (?)', gift_givers_shared) if gift_givers_shared.size > 0
        #end
        #
        ## old: users1.push(gift.receiver) if gift.user_id_receiver and from_userid != gift.user_id_receiver
        #logger.debug2 "1b: gift.direction = #{gift.direction}"
        #logger.debug2 "1b: gift_receivers = #{gift_receivers.join(', ')}"
        #logger.debug2 "1b: from_userids   = #{User.debug_info(from_users)}"
        #shared_userids = gift_receivers & from_userids
        #logger.debug2 "1b: shared_userids = #{shared_userids.join(', ')}"
        #if %w(receiver both).index(gift.direction) and shared_userids.size == 0
        #  users1 += User.where("user_id in (?)", gift_receivers_shared) if gift_receivers_shared.size > 0
        #end

        if noti_key_1 == 5
          # special rejected/accepted notification to owner of comment
          to_userids = api_comments.collect { |ac| ac.user_id}
          api_comments.collect { |ac| users1.push(ac.user) }
          # users1.push(user)
        else
          to_userids = []
        end
        #users1_ids = users1.collect { |u| u.user_id }
        logger.debug2  "1: users1 = " + users1_ids.join(', ') if debug_notifications

        # 2) notifications to users that has commented the gift - "_other" is added to notification key!
        # users2 = gift.comments.includes(:user).collect { |c| c.user }.find_all { |user2| ![from_userid, to_user_id, gift.user_id_giver, gift.user_id_receiver].index(user2.user_id) }.uniq
        logger.error2 "2: from_userids is invalid. Expected Array. Found #{from_userids.class}" unless from_userids.class == Array
        logger.error2 "2: to_userids is invalid. Expected Array. Found #{to_userids.class}" unless to_userids.class == Array
        logger.error2 "2: gifts_giver_and_receivers is invalid. Expected Array. Found #{gift_giver_and_receivers.class}" unless gift_giver_and_receivers.class == Array
        exclude_user_ids = from_userids + to_userids + gift_giver_and_receivers
        logger.debug2 "2: exclude_user_ids = #{exclude_user_ids.join(', ')}"
        users2 = gift.api_comments.includes(:user).collect { |c| c.user }.find_all { |user2| !exclude_user_ids.index(user2.user_id) }.uniq
        users2_ids = users2.collect { |u| u.user_id }
        users_ids = (users1_ids + users2_ids).uniq
        logger.debug2  "2: users2 = " + users2_ids.join(', ') if debug_notifications
        # 3) check followers - users that have selected to follow gift comments - users that have selected NOT to follow gift comments
        users3 = []
        logger.debug2  "3: adding/removing followers" if debug_notifications
        GiftLike.where("gift_id = ? and follow is not null", gift.gift_id).each do |gl|
          next if
          if gl.follow == 'Y'
            # user has selected to follow gift
            users3 << gl.user if !from_userids.index(gl.user.user_id) and !users_ids.index(gl.user_id)
          else
            # user has deselected to follow gift
            users1 = users1.delete_if { |u| u.user_id == gl.user_id }
            users2 = users2.delete_if { |u| u.user_id == gl.user_id }
          end
        end # each
        #logger.debug2  "3: users1 = " + users1_ids.join(', ') if debug_notifications
        #logger.debug2  "3: users2 = " + users2_ids.join(', ') if debug_notifications
        #logger.debug2  "3: users3 = " + users3_ids.join(', ') if debug_notifications
        # send notifications
        logger.debug2  "start1: send notification from #{User.debug_info(from_users)}" if debug_notifications
        logger.debug2  "start1: send notifications to gifts giver and receiver: #{User.debug_info(users1)}"  if debug_notifications
        users1.each { |to_user| send_notification(noti_key_1, noti_key_2, 1, from_users, to_user) }
        logger.debug2  "end1: send notifications to gifts giver, receiver and followers: #{User.debug_info(users1)}"  if debug_notifications

        logger.debug2  "start2: send notification from #{User.debug_info(from_users)}"
        logger.debug2  "start2: send notifications to other users that also have commented the gift: #{User.debug_info(users2)}" if debug_notifications
        users2.each { |to_user| send_notification(noti_key_1, noti_key_2, 2, from_users, to_user) }
        logger.debug2  "end2: send notifications to other users that also have commented the gift: #{User.debug_info(users2)}" if debug_notifications

        logger.debug2  "start3: send notification from #{User.debug_info(from_users)}"
        logger.debug2  "start3: send notifications to users that follows the gift: #{User.debug_info(users3)}" if debug_notifications
        users3.each { |to_user| send_notification(noti_key_1, noti_key_2, 3, from_users, to_user) }
        logger.debug2  "end3: send notifications to users that follows the gift: #{User.debug_info(users3)}" if debug_notifications

        # new comment and new proposal - add user as follower of gift - user will receive notifications until user stops following the gift
        if noti_key_1 <= 2
          # check for new user_id's - ignore giver and receiver user_id's
          (api_comments.collect { |ac| ac.user_id} - gift_giver_and_receivers).each do |user_id|
            gl = GiftLike.where("user_id = ? and gift_id = ?", user_id, gift.gift_id).first
            if gl
              gl.follow = 'Y' unless gl.follow
            else
              gl = GiftLike.new
              gl.user_id = user_id
              gl.gift_id = gift.gift_id
              gl.like = 'N'
              gl.follow = 'Y'
              gl.show = 'Y'
            end
            if gl.new_record? or gl.changed?
              logger.debug2  "added #{user_id} as follower" if debug_notifications
              gl.save!
            end
          end # each user_id
        end # if
      when noti_key_1 == 3
        # cancelled proposal - send only notification to giver/receiver
        logger.debug2 "cancelled proposal - send only notification to giver/receiver"
        logger.debug2 "gift_givers    = #{ gift_givers.join(', ')}"
        logger.debug2 "gift_receivers = #{ gift_receivers.join(', ')}"
        logger.debug2 "from_userids   = #{from_userids.join(', ')}"
        # after_create: gift_givers    = 100006399422155/facebook, 109316109373670614208/google_oauth2, 2179784783/twitter
        # after_create: gift_receivers =
        # after_create: from_userids   = 117657151428689087350/google_oauth2, 100006351370003/facebook
        users1_ids_tmp = gift_giver_and_receivers - from_userids
        logger.debug2 "users1_ids_tmp/a = #{users1_ids_tmp.join(', ')}"
        users1_ids_tmp = users1_ids_tmp.find_all { |user_id| from_providers.index(user_id.split('/').last) }
        logger.debug2 "users1_ids_tmp/b = #{users1_ids_tmp.join(', ')}"
        if users1_ids_tmp.size > 0
          users1 = User.where('user_id in (?)', users1_ids_tmp)
          users1.each { |to_user| send_notification(noti_key_1, noti_key_2, 1, from_users, to_user) }
        end
        #users1 = []
        #users1.push(gift.giver) if gift.user_id_giver and from_userid != gift.user_id_giver
        #users1.push(gift.receiver) if gift.user_id_receiver and from_userid != gift.user_id_receiver
      when [4].index(noti_key_1)
        # rejected/accepted proposal - send notification to creator of proposal / comment
        api_comments.each do |ac|
          to_user = ac.user
          send_notification(noti_key_1, noti_key_2, 1, from_users, to_user)
        end
    end # case
  end # after_create

  def after_update
    logger.debug2  "Comment.after_update:" if debug_notifications
    logger.debug2  "Comment.after_update: new deal_yn: #{new_deal_yn_was} (#{new_deal_yn_was.class}) => #{new_deal_yn} (#{new_deal_yn.class})" if debug_notifications
    logger.debug2  "Comment.after_update: accepted_jn: #{accepted_yn_was} (#{accepted_yn_was.class}) => #{accepted_yn} (#{accepted_yn.class})" if debug_notifications
    # logger.debug2  "Comment.after_update: currency = #{currency}"
    # comment: after update: new deal: Y => Y, accepted:  => N
    # check for canceled, rejected or accepted deal proposal - notifications are sent from after_create method
    if  accepted_proposal? or # noti_type 5: accepted proposal
        rejected_proposal? or # noti type 4: rejected proposal
        cancelled_proposal? # noti type 3: cancelled proposal
      # send notifications
      after_create(true)
      if accepted_yn == 'Y'
        # accepted proposal - update gift (price, received_at etc) and api_gifts (giver or receivers)
        # copy users from api_comment to api_gifts. Insert dummy user for providers with no match
        # provider must by in from gift.updated_by (see validation in util.accept_deal)
        accepted_by_providers = updated_by.split(',').collect { |userid2| userid2.split('/').last }
        providers_hash = {}
        api_comments.each do |ac|
          providers_hash[ac.provider] = ac.user_id if accepted_by_providers.index(ac.provider)
        end
        gift.api_gifts.each do |ag|
          user_id_accept = providers_hash[ag.provider] || "gofreerev/#{ag.provider}"
          if ag.user_id_giver
            ag.user_id_receiver = user_id_accept
          else
            ag.user_id_giver = user_id_accept
          end
          ag.save!
        end
        if price
          gift.price = price
          gift.currency = currency
          # logger.debug2  "Comment.after_update: gift.currency = #{gift.currency}"
        end
        gift.received_at = updated_at # todo: move to gift callback
        gift.status_update_at = Sequence.next_status_update_at  # todo: move to gift callback
        gift.direction = 'both'
        gift.save!
        # mark users for balance recalculation - ensures that balance is recalculated even if accept new deal post processing should fail for some reason
        gift.api_gifts.each do |ag|
          [ ag.giver, ag.receiver].each do |u|
            next if u.dummy_user?
            u.reload
            u.balance_at = Date.yesterday
            u.save
          end # each u
        end # each ag
      end # if accepted
    end # if cancelled, rejected or accepted
  end # after_update

  #def before_destroy
  #  logger.debug2  "cleanup any unread notifications" if debug_notifications
  #  # change number of users for uny unread notifications
  #  notifications.find_all { |n| n.noti_read == 'N' }.each do |n|
  #    remove_from_notification(n)
  #  end # each n
  #end # before_destroy


  # check for partial deleted comments
  # this is api comment(s) marked as delete - test login with logged in users
  # used when ajax replacing deleted comments with empty rows in gifts/index page
  # see User.delete_user and UtilController.new_messages_count
  def partial_deleted?(login_users)
    return false unless [Array, ActiveRecord::Relation::ActiveRecord_Relation_User].index(login_users.class)
    return false unless login_users.size > 0
    return false if login_users.first.dummy_user?
    providers = login_users.collect { |u| u.provider }
    # test if comment has one or more delete marked api comments (normally none)
    ac = api_comments.find { |ag2| providers.index(ag2.provider) and ag2.deleted_at }
    return false unless ac
    # test if all api comments has been delete marked
    ac = api_comments.find { |ag2| providers.index(ag2.provider) and !ag2.deleted_at }
    (ac ? false : true)
  end # partial_deleted?



  ##############
  # encryption #
  ##############

  # https://github.com/jmazzi/crypt_keeper gem encrypts all attributes and all rows in db with the same key
  # this extension to use different encryption for each attribute and each row
  # overwrite non model specific methods defined in /config/initializers/active_record_extensions.rb
  protected
  def encrypt_pk
    self.comment_id
  end

  def encrypt_pk=(new_encrypt_pk_value)
    self.comment_id = new_encrypt_pk_value
  end

  def new_encrypt_pk
    loop do
      temp_comment_id = String.generate_random_string(20)
      return temp_comment_id unless Comment.find_by_comment_id(temp_comment_id)
    end
  end

end # Comment
