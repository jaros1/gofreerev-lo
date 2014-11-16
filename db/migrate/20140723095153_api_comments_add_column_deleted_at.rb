class ApiCommentsAddColumnDeletedAt < ActiveRecord::Migration
  def change
    # used to delete marked api comments. used when user account is deleted for multi-provider comments
    add_column :api_comments, :deleted_at, :datetime
  end
end
