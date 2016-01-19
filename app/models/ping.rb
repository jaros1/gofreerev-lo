class Ping < ActiveRecord::Base

  # create_table "pings", force: true do |t|
  #  1:  t.string   "session_id",    limit: 32
  #  2:  t.integer  "client_userid"
  #  3:  t.string   "client_sid",    limit: 20
  #  4:  t.datetime "last_ping_at"
  #  5:  t.datetime "next_ping_at"
  #  6:  t.string   "did"
  #  7:  t.text     "user_ids"
  #  8:  t.string   "sha256",        limit: 45
  #  9:  t.integer  "server_id"
  # 10:  t.string   "micro_interval_adjustments"
  # 11:  t.integer  "request_interval"
  # 12:  t.string   "request_interval_stat"
  # end
  # add_index "pings", ["session_id", "client_userid", "client_sid"], name: "index_ping_pk", unique: true, using: :btree

  belongs_to :server

  # 1: rails sessionid

  # 2: client_userid. sequence with local user accounts in a browser starting with 1

  # 3: client_sid: one unique session id for each browser tab

  # 4: last_ping_at - datetime with milliseconds - stored as decimal(13,3) in database
  # timestamp for last ping request from browser or other gofreerev server
  def last_ping_at
    return nil unless (temp_last_ping_at = read_attribute(:last_ping_at))
    # logger.debug2  "temp_last_ping_at = #{temp_last_ping_at}"
    Time.at temp_last_ping_at
  end
  def last_ping_at=(new_last_ping_at)
    if new_last_ping_at
      check_type('last_ping_at', new_last_ping_at, 'Time')
      write_attribute :last_ping_at, new_last_ping_at.to_f
    else
      write_attribute :last_ping_at, nil
    end
  end # last_ping_at=
  alias_method :last_ping_at_before_type_cast, :last_ping_at
  def last_ping_at_was
    return last_ping_at unless last_ping_at_changed?
    return nil unless (temp_last_ping_at = attribute_was(:last_ping_at))
    Time.at temp_last_ping_at
  end # last_ping_at_was

  # 5: next_ping_at - datetime with milliseconds - stored as decimal in database
  # timestamp for next allowed ping request from browser or other gofreerev server
  def next_ping_at
    return nil unless (temp_next_ping_at = read_attribute(:next_ping_at))
    # logger.debug2  "temp_next_ping_at = #{temp_next_ping_at}"
    Time.at temp_next_ping_at
  end
  def next_ping_at=(new_next_ping_at)
    if new_next_ping_at
      check_type('next_ping_at', new_next_ping_at, 'Time')
      write_attribute :next_ping_at, new_next_ping_at.to_f
    else
      write_attribute :next_ping_at, nil
    end
  end # next_ping_at=
  alias_method :next_ping_at_before_type_cast, :next_ping_at
  def next_ping_at_was
    return next_ping_at unless next_ping_at_changed?
    return nil unless (temp_next_ping_at = attribute_was(:next_ping_at))
    Time.at temp_next_ping_at
  end # next_ping_at_was

  # 6: did - client unique device id - stored encrypted in sessions table - stored in clear text in pings table

  # 7: user_ids - Array in model - text in db - array with currently logged in oauth users
  # stored encrypted in sessions table - stored in clear in pings
  # using in util/ping to return a list with online devices/friends
  def user_ids
    return nil unless (temp_user_ids = read_attribute(:user_ids))
    # logger.debug2  "temp_user_ids = #{temp_user_ids}"
    YAML::load temp_user_ids
  end # user_ids
  def user_ids=(new_user_ids)
    if new_user_ids
      check_type('user_ids', new_user_ids, 'Array')
      write_attribute :user_ids, new_user_ids.to_yaml
    else
      write_attribute :user_ids, nil
    end
  end # user_ids=
  alias_method :user_ids_before_type_cast, :user_ids
  def user_ids_was
    return user_ids unless user_ids_changed?
    return nil unless (temp_user_ids = attribute_was(:user_ids))
    temp_user_ids
  end # user_ids_was

  # 8: sha256 - generated from client secret and user_ids.
  # stored encrypted sessions table and stored in clear text in pings

  # 9: server_id - used for pings received in server to server online users message
  # blank: session on this gofreerev server. not blank: session on other gofreerev server

  # 10: micro_interval_adjustments - client server communication overhead - subtract a few milliseconds to the :interval returned to client
  # yaml array - micro adjustment for the last 11 pings (milliseconds)

  # 11: request_interval from client ping request. client request for a longer interval. primary used in server to server communication
  # clear request_interval_stat when request_interval changes

  # 12: request_interval_stat. yaml array with interval stat for the last <n> pings
  # avg(request_interval_stat) should be as close to request_interval as possible
  # see util_controller.ping for implememtation

  # array with internal user ids - used in ping response (online devices)
  # replicate gifts for mutual friends between online devices
  attr_accessor :mutual_friends


  # pubkeys request from ping. Return pubkeys for list of unique device ids. Used in client communication
  # json validated with pubkeys part of JSON_SCHEMA[:ping_request] / JSON_SCHEMA[:ping_response]
  # returns null is did does not exists.
  public
  def self.pubkeys (pubkeys_request)
    return nil unless pubkeys_request.class == Array and pubkeys_request.size > 0
    pubkeys_request.uniq!
    pubkeys_response = Pubkey.where(:did => pubkeys_request)
    # check for missing public keys for remote devices on other Gofreerev servers
    # ignore did in request but set client_request_at timestamp
    # public key will be requested in next server to server ping
    # client will continue to request missing public key
    pubkeys_response.delete_if do |p|
      pubkeys_request.delete_if { |did| did == p.did }
      if p.server_id and !p.pubkey
        # remote dids
        if !p.client_request_at
          p.client_request_at = Time.zone.now
          p.save!
        end
        true
      else
        # local dids
        false
      end
    end
    pubkeys_response = pubkeys_response.collect { |p| {:did => p.did, :pubkey => p.pubkey} }
    pubkeys_response += pubkeys_request.collect { |did| {:did => did, :pubkey => nil} } # unknown dids
    pubkeys_response.size == 0 ? nil : pubkeys_response
  end # self.pubkeys

end
