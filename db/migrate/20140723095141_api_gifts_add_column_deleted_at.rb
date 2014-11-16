class ApiGiftsAddColumnDeletedAt < ActiveRecord::Migration
  def change
    # used to delete marked api gifts. used when user account is deleted for multi-provider gifts
    add_column :api_gifts, :deleted_at, :datetime
  end
end
