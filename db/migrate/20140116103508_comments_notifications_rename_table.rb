class CommentsNotificationsRenameTable < ActiveRecord::Migration
  def change
    rename_table :comments_notifications, :api_comments_notifications
  end
end
