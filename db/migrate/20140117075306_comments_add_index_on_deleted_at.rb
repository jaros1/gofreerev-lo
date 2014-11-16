class CommentsAddIndexOnDeletedAt < ActiveRecord::Migration
  def change
    add_index "comments", ["deleted_at"], name: "index_comments_on_deleted_at"
  end
end
