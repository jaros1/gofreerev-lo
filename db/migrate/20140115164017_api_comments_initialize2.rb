class ApiCommentsInitialize2 < ActiveRecord::Migration
  def up
    Comment.all.each do |c|
      ac = ApiComment.new
      ac.gift_id    = c.gift_id
      ac.comment_id = c.comment_id
      ac.provider   = c.user_id.split('/').last
      ac.user_id    = c.user_id
      ac.save!
    end
  end
  def down
    ApiComment.delete_all
  end
end
