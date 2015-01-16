class Session < ActiveRecord::Base

  # create_table "sessions", force: true do |t|
  #   t.string   "session_id",              limit: 32
  #   t.integer  "last_row_id"
  #   t.float    "last_row_at"
  #   t.datetime "created_at"
  #   t.datetime "updated_at"
  # end
  
  # 1) session_id
  
  # 2) last_row_id
  
  # 3) last_row_at
  

  ##############
  # encryption #
  ##############

  # https://github.com/jmazzi/crypt_keeper gem encrypts all attributes and all rows in db with the same key
  # this extension to use different encryption for each attribute and each row
  # overwrites non model specific methods defined in /config/initializers/active_record_extensions.rb
  protected
  def encrypt_pk
    self.session_id
  end
  def encrypt_pk=(new_encrypt_pk_value)
    self.session_id = new_encrypt_pk_value
  end
  def new_encrypt_pk
    self.session_id
  end

end
