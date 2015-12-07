class VerifyCommentsAddColumnOriginalClientRequestSha256 < ActiveRecord::Migration
  def up
    add_column :verify_comments, :original_client_request_sha256, :string, :limit => 45
    add_index :verify_comments, [:original_client_request_sha256], :name => 'index_verify_comment_ix1'
  end
  def down
    remove_index :verify_comments, :name => 'index_verify_comment_ix1'
    remove_column :verify_comments, :original_client_request_sha256
  end
end
