class CreateApiComments < ActiveRecord::Migration
  def change
    create_table :api_comments do |t|
      t.string :gift_id, :limit => 20
      t.string :comment_id, :limit => 20
      t.string :provider, :limit => 20
      t.string :user_id, :limit => 40
      t.timestamps
    end
    add_index "api_comments", ["gift_id"], name: "index_api_comments_on_gift_id"
    add_index "api_comments", ["user_id"], name: "index_api_comments_on_user_id"
    add_index "api_comments", ["comment_id"], name: "index_api_comments_on_comm_id"
  end
end
