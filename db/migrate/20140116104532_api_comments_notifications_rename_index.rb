class ApiCommentsNotificationsRenameIndex < ActiveRecord::Migration
  def up
    remove_index "api_comments_notifications", name: "index_comment_notifications_on_notification_id"
    add_index "api_comments_notifications", ["notification_id"], name: "index_comm_noti_on_noti_id"
  end
  def down
    remove_index "api_comments_notifications", :name => 'index_comm_noti_on_noti_id'
    add_index "api_comments_notifications", ["notification_id"], name: "index_comment_notifications_on_notification_id"
  end
end
