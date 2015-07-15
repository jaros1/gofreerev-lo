class VerifyCommentsAddColumnOriginalClientRequest < ActiveRecord::Migration
  def change
    add_column :verify_comments, :original_client_request, :string
  end
end
