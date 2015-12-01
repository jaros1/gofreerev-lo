class VerifyCommentsChangeOriginalClientRequestColumnToText < ActiveRecord::Migration

  def up
    change_column :verify_comments, :original_client_request, :text, :null => false
    change_column :verify_comments, :request_mid, :integer, :null => false
  end
  def down
    change_column :verify_comments, :original_client_request, :string, :null => true
    change_column :verify_comments, :request_mid, :integer, :null => true
  end

end
