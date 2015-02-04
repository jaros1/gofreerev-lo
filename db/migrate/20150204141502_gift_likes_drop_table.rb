class GiftLikesDropTable < ActiveRecord::Migration
  def up
    drop_table :gift_likes
  end
  def down
    create_table "gift_likes", force: true do |t|
      t.string   "gift_like_id", limit: 20, null: false
      t.string   "gift_id",      limit: 20, null: false
      t.text     "like"
      t.text     "show"
      t.text     "follow"
      t.datetime "created_at"
      t.datetime "updated_at"
      t.string   "user_id",      limit: 40, null: false
    end
    add_index "gift_likes", ["gift_id", "user_id"], name: "index_gift_lines_on_gift_id", unique: true, using: :btree
    add_index "gift_likes", ["user_id"], name: "index_gift_lines_on_user_id", using: :btree
  end
end
