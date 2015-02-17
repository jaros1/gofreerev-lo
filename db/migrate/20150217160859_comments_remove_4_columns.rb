class CommentsRemove4Columns < ActiveRecord::Migration

  # old:
  # create_table "comments", force: true do |t|
  #   t.datetime "created_at"
  #   t.datetime "updated_at"
  #   t.string   "new_deal_yn",      limit: 1
  #   t.string   "accepted_yn",      limit: 1
  #   t.integer  "status_update_at",            null: false
  #   t.string   "updated_by"
  #   t.string   "cid",              limit: 20
  # end
  # add_index "comments", ["cid"], name: "index_comments_on_cid", unique: true, using: :btree

  def up
    remove_column :comments, :new_deal_yn
    remove_column :comments, :accepted_yn
    remove_column :comments, :status_update_at
    remove_column :comments, :updated_by
  end
  def down
    add_column :comments, :new_deal_yn, :string, :limit => 1
    add_column :comments, :accepted_yn, :string, :limit => 1
    add_column :comments, :status_update_at, :integer, :null => false
    add_column :comments, :updated_by, :string
  end

end
