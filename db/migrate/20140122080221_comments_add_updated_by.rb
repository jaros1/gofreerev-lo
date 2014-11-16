class CommentsAddUpdatedBy < ActiveRecord::Migration
  def change
    add_column :comments, :updated_by, :string
  end
end
