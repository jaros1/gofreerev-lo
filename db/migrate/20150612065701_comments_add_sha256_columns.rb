class CommentsAddSha256Columns < ActiveRecord::Migration
  def change
    add_column :comments, :sha256_action, :string, :limit => 45
    add_column :comments, :sha256_deleted, :string, :limit => 45
  end
end
