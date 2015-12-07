class VerifyGift < ActiveRecord::Base

  # table with remote gift verification
  # client_sid, client_sha256, client_seq, server_id and gid from client verify_gifts request
  # server_seq from server sequence and used as seq in server to server verify gift message
  # verified_at_server is response from server to server verify gifts message to be returned to client in next ping request

  # create_table "verify_gifts", force: true do |t|
  #   t.string   "client_sid",         limit: 20, null: false
  #   t.string   "client_sha256",      limit: 45, null: false
  #   t.integer  "client_seq",                    null: false
  #   t.integer  "server_id",                     null: false
  #   t.string   "gid",                limit: 20, null: false
  #   t.integer  "server_seq",                    null: false
  #   t.boolean  "verified_at_server"
  #   t.string   "error"
  #   t.integer  "request_mid"
  #   t.integer  "response_mid"
  #   t.datetime "created_at"
  #   t.datetime "updated_at"
  # end
  # add_index "verify_gifts", ["client_sid", "client_sha256", "client_seq"], name: "index_verify_gift_pk", unique: true, using: :btree
  # add_index "verify_gifts", ["server_seq"], name: "index_verify_gift_uk", unique: true, using: :btree

  # 1) client_sid - unique session id from browser client ( = a browser tab ). null if verify gifts server to server message from verify comments

  # 2) client_sha256 - sha256 signature for unique device - changes if client login changes. null if verify gifts server to server message from verify comments

  # 3) client_seq - unique client seq from client verify_gifts request - always negative for remote gift verification
  validates_presence_of :client_seq
  validates_uniqueness_of :client_seq, :scope => %w(client_sid client_sha256), :allow_blank => true

  # 4) server_id - server id from client verify gifts request
  validates_presence_of :server_id

  # 5) gid - unique gift ud from client verify gifts request
  validates_presence_of :gid

  # 6) server_seq - unique - server sequence - used in server to server verify gifts message
  validates_presence_of :server_seq
  validates_uniqueness_of :server_seq, :allow_blank => true

  # 7) verified_at_server boolean - response from remote gift verification. Blank at create. true or false at update
  validates_each :verified_at_server do |record, attr, value|
    if record.new_record?
      # must be blank at create
      record.errors.add attr, :blank if value.to_s != ''
    else
      # must be true or false at update and cannot change
      if value == nil or value == ''
        record.errors.add attr, :present
      elsif ![true, false].index(value)
        record.errors.add attr, :invalid # invalid value
      elsif record.verified_at_server_was.to_s != '' and value != record.verified_at_server_was
        record.errors.add attr, :invalid # readonly
      end
    end
  end

  # 8) error. string - response from remote gift verification. blank or an english error message
  validates_absence_of :error, :on => :create
  validates_each :error, :on => :update do |record, attr, value|
    if record.verified_at_server == true
      record.errors.add attr, :present if value.class != NilClass
    elsif record.verified_at_server == false
      record.errors.add attr, :blank if value.to_s == ''
    elsif record.error_was and value != record.error_was
      record.errors.add attr, :invalid #readonly
    end
  end

  # 9) request_mid. unique server message id for request (sequence on this server)
  validates_presence_of :request_mid
  attr_readonly :request_mid

  # 10) response_mid. unique server message id for response (sequence on remote server)
  validates_absence_of :response_mid, :on => :create
  validates_presence_of :response_mid, :on => :update
  validates_each :response_mid, :on => :update do |record, attr, value|
    if record.response_mid_was and value != record.response_mid_was
      record.errors.add attr, :invalid #readonly
    end
  end

  # 11) original_client_request. client request. used in error message if invalid response from other server
  validates_presence_of :original_client_request
  attr_readonly :original_client_request

end
