class SessionsNewTableStructure < ActiveRecord::Migration

  # splitting session storage in one section for each client_userid - will also solve problem with 4kb limit for cookie storage
  # move fields from session cookie storage to sessions table
  # cookie storage: :client_userid, :timezone and :secret
  # table storage: :created, :expires_at, :flash_id, :language, :last_row_at, :last_row_id, :refresh_tokens, :state, :tokens and :user_ids

  # old:
  # create_table "sessions", force: true do |t|
  #   t.string   "session_id",  limit: 32
  #   t.integer  "last_row_id"
  #   t.float    "last_row_at"
  #   t.datetime "created_at"
  #   t.datetime "updated_at"
  # end
  # add_index "sessions", ["session_id"], name: "index_session_session_id", unique: true, using: :btree

  # new:
  # create_table "sessions", force: true do |t|
  #   t.string   "session_id",     limit: 32
  #   t.integer  "client_userid",             default: 0
  #   t.text     "created"
  #   t.text     "expires_at"
  #   t.text     "flash_id"
  #   t.text     "language"
  #   t.text     "last_row_at"
  #   t.text     "last_row_id"
  #   t.text     "refresh_tokens"
  #   t.text     "state"
  #   t.text     "tokens"
  #   t.text     "user_ids"
  #   t.datetime "created_at"
  #   t.datetime "updated_at"
  # end

def up
    remove_index :sessions, :name => "index_session_session_id"
    remove_column :sessions, :last_row_id
    remove_column :sessions, :last_row_at
    remove_column :sessions, :created_at
    remove_column :sessions, :updated_at
    add_column :sessions, :client_userid, :integer, :default => 0
    add_index "sessions", ["session_id", "client_userid"], name: "index_session_session_id", unique: true, using: :btree

    add_column :sessions, :created, :text # encrypted Time
    add_column :sessions, :expires_at, :text # encrypted Hash with provider and unix timestamps
    add_column :sessions, :flash_id, :text # encrypted Integer
    add_column :sessions, :language, :text # encrypted String
    add_column :sessions, :last_row_at, :text # encrypted Float (seconds with milliseconds since midnight)
    add_column :sessions, :last_row_id, :text # encrypted Integer (status_update_at_seq sequence)
    add_column :sessions, :refresh_tokens, :text # encrypted Hash with providers and refresh tokens (google+ only)
    add_column :sessions, :state, :text # encrypted String
    add_column :sessions, :tokens, :text # encrypted Hash with providers and oauth tokens
    add_column :sessions, :user_ids, :text # encrypted Array with user_id's for logged in users

    add_column :sessions, :created_at, :datetime
    add_column :sessions, :updated_at, :datetime

  end




  def down
    remove_column :sessions, :created_at
    remove_column :sessions, :updated_at

    remove_column :sessions, :created
    remove_column :sessions, :expires_at
    remove_column :sessions, :flash_id
    remove_column :sessions, :language
    remove_column :sessions, :last_row_at
    remove_column :sessions, :last_row_id
    remove_column :sessions, :refresh_tokens
    remove_column :sessions, :state
    remove_column :sessions, :tokens
    remove_column :sessions, :user_ids

    remove_index :sessions, :name => "index_session_session_id"
    remove_column :sessions, :client_userid
    add_column :sessions, :last_row_id, :integer
    add_column :sessions, :last_row_at, :float
    add_column :sessions, :created_at, :datetime
    add_column :sessions, :updated_at, :datetime
    add_index "sessions", ["session_id"], name: "index_session_session_id", unique: true, using: :btree
  end
end
