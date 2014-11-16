class CommentsNotificationsDropColumnCommentId < ActiveRecord::Migration
  def up
    remove_index "comments_notifications", name: "index_comment_notifications_on_comment_id"
    remove_column "comments_notifications", :comment_id
  end
  def down
    add_column :comments_notifications, :comment_id, :integer
    CommentNotification.all.each do |cn|
      api_comment = ApiComment.find(cn.api_comment_id)
      comment = api_comment.comment
      CommentNotification.update_all "comment_id = #{comment.id}",
                                     "api_comment_id = #{cn.api_comment_id} and notification_id = #{cn.notification_id}"
    end
    add_index "comments_notifications", ["comment_id", "notification_id"], name: "index_comment_notifications_on_comment_id", unique: true
  end
end
