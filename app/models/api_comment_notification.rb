class ApiCommentNotification < ActiveRecord::Base

  self.table_name = 'api_comments_notifications'

  belongs_to :comment
  belongs_to :notification
end
