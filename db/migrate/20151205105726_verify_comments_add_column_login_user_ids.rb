class VerifyCommentsAddColumnLoginUserIds < ActiveRecord::Migration
  def up
    add_column :verify_comments, :login_user_ids, :string
  end
  def down
    remove_column :verify_comments, :login_user_ids
  end
end
