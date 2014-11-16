class CommentsDropColumnUserId < ActiveRecord::Migration
  def up
    remove_index :comments, :name => "index_comments_on_user_id"
    remove_column :comments, :user_id
  end
  def down
    add_column :comments, :user_id, :string, :limit => 40
    ApiComment.all.each do |ac|
      c = Comment.find_by_comment_id(ac.comment_id)
      Comment.update_all "user_id = '#{ac.user_id}'", "id = #{c.id}"
    end
    add_index "comments", ["user_id"], name: "index_comments_on_user_id"
  end
end
