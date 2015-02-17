class CommentsRemoveCommentCurrencyAndPrice < ActiveRecord::Migration
  
  # old:
  # create_table "comments", force: true do |t|
  #   t.text     "comment",                     null: false
  #   t.datetime "created_at"
  #   t.datetime "updated_at"
  #   t.text     "currency"
  #   t.text     "price"
  #   t.string   "new_deal_yn",      limit: 1
  #   t.string   "accepted_yn",      limit: 1
  #   t.integer  "status_update_at",            null: false
  #   t.datetime "deleted_at"
  #   t.string   "updated_by"
  #   t.string   "cid",              limit: 20
  # end
  
  def up
    remove_column :comments, :comment
    remove_column :comments, :currency
    remove_column :comments, :price
  end
  def down
    add_column :comments, :comment, :text
    add_column :comments, :currency, :text
    add_column :comments, :price, :text
  end

end
