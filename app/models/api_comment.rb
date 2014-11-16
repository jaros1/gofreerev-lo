class ApiComment < ActiveRecord::Base

  #create_table "api_comments", force: true do |t|
  #  t.string   "gift_id",    limit: 20
  #  t.string   "comment_id", limit: 20
  #  t.string   "provider",   limit: 20
  #  t.string   "user_id",    limit: 40
  #  t.datetime "created_at"
  #  t.datetime "updated_at"
  #end

  belongs_to :gift, :class_name => 'Gift', :primary_key => :gift_id, :foreign_key => :gift_id
  belongs_to :user, :class_name => 'User', :primary_key => :user_id, :foreign_key => :user_id
  belongs_to :comment, :class_name => 'Comment', :primary_key => :comment_id, :foreign_key => :comment_id
  has_and_belongs_to_many :notifications
  has_many :friends, :through => :user

  before_update :before_update



  # 4) user_id - required - not encrypted - readonly
  validates_presence_of :user_id
  attr_readonly :user_id


  # number of older comments for gift
  # used in gifts/index page to display "show <n> more comments"
  attr_accessor :no_older_comments


  def debug_notifications
    true
  end # debug_notifications



  # comment no longer relevant for unread notification n
  # used when comments are deleted, deal proposal is cancelled, rejected or accepted
  def remove_from_notification (n)
    logger.debug2  "comment id #{id}. Notification id #{n.id}. notification key #{n.noti_key}" if debug_notifications
    # only modify unread notifications
    return unless n.noti_read == 'N'
    cn = notifications.where("notification_id = ?", n.id).first
    logger.debug2  "cn.class = #{cn.class}" if debug_notifications
    logger.debug2  "cn.id = #{cn.id}" if cn and debug_notifications
    logger.debug2  "cn.noti_key = #{cn.noti_key}" if cn and debug_notifications
    logger.debug2  "cn.from_user.short_user_name = #{cn.from_user.short_user_name}" if cn and cn.from_user and debug_notifications
    logger.debug2  "cn.to_user.short_user_name = #{cn.to_user.short_user_name}" if cn and cn.to_user and debug_notifications
    # find no users before and after removing this comment from notification
    old_no_users = n.api_comments.collect { |c| c.user_id }.uniq.size
    new_users = n.api_comments.find_all { |ac| ac.id != id }.collect { |ac| ac.user }.uniq
    new_no_users = new_users.size
    if new_no_users == 0
      # last user for this unread notification has been removed
      logger.debug2  "last user for this unread notification has been removed" if debug_notifications
      n.destroy!
      return
    end
    return if old_no_users == new_no_users # unchanged number of users => unchanged notification
    if new_no_users > 3
      # unchanged noti_key and username array. Just change number of users
      logger.debug2  "unchanged noti_key and username array. Just change number of users" if debug_notifications
      notifications.delete(cn) if cn
      noti_options = n.noti_options
      noti_options[:no_users] = new_no_users
      noti_options[:no_other_users] = new_no_users - 2
      n.noti_options = noti_options
      n.save!
      return
    end
    # change noti_key, username array and number of users
    if n.noti_key !~ /^([a-z_]+)_(\d)_v(\d+)$/
      logger.debug2  "invalid noti key format. noti key = #{noti_key}"
      return
    end
    logger.debug2  "change noti_key, username array and number of users" if debug_notifications
    noti_key_prefix, noti_key_no_users, noti_key_version = $1, $2, $3
    noti_options = n.noti_options
    (1..3).each { |i| noti_options["username#{i}".to_sym] = nil }
    usernames = new_users.collect { |u| u.short_user_name }
    0.upto(usernames.size-1).each do |i|
      noti_options["username#{i+1}".to_sym] = usernames[i]
    end
    noti_options[:no_users] = new_no_users
    noti_options[:no_other_users] = new_no_users - 2
    n.noti_key = "#{noti_key_prefix}_#{new_no_users}_v#{noti_key_version}"
    logger.debug2  "noti_key: old = #{n.noti_key_was}, new = #{n.noti_key}" if debug_notifications
    n.noti_options = noti_options
    notifications.delete(cn) if cn
    n.save!
  end # remove_from_notification

  # remove api comment from unread notifications - for example after delete comment
  def remove_from_notifications
    notifications.find_all { |n| n.noti_read == 'N' }.each do |n|
      remove_from_notification(n)
    end # each n
  end

  def before_update
    if !deleted_at_was and deleted_at
      # api comment has been delete marked in User.delete_user (partial delete comment when deleting user account)
      # update comment.status_update_at so that comment will be ajax updated or deleted in other browser sessions
      comment.status_update_at = Sequence.next_status_update_at
      comment.updated_by = user_id
      comment.save!
    end # if
  end # before_update

end
