class CommentsNotificationsAddColumnApiCommentId < ActiveRecord::Migration
  def change
    add_column :comments_notifications, :api_comment_id, :integer
    # initialize new api_comment_id - there should be one and only one relevant api comment
    CommentNotification.all.each do |cn|
      provider = cn.notification.to_user.provider
      raise "no provider" unless provider
      api_comment = cn.comment.api_comments.find { |ac| ac.provider == provider }
      if api_comment
        cn.api_comment_id = api_comment.id
        CommentNotification.update_all "api_comment_id = #{cn.api_comment_id}",
                                       "comment_id = #{cn.comment_id} and notification_id = #{cn.notification_id}"
      else
        puts "warning: no api comment for comment #{cn.comment_id}"
        CommentNotification.delete_all "comment_id = #{cn.comment_id} and notification_id = #{cn.notification_id}"
      end
    end
    add_index "comments_notifications", ["api_comment_id", "notification_id"], name: "index_api_com_no_on_api_com_id", unique: true
  end
end
