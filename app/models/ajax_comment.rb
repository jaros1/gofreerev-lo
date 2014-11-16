class AjaxComment < ActiveRecord::Base

  after_create :after_create

  # max interval for ajax check for new messages is 5 minutes.
  # see also my.js: calculate_new_messages_interval and insert_new_comments
  # see also util_controller.new_messages_count
  # delete all ajax commments more than 6 minutes old
  def after_create
    AjaxComment.where("created_at < ?", 6.minutes.ago).destroy_all ;
  end

end
