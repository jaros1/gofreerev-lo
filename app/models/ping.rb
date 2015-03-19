class Ping < ActiveRecord::Base

  # create_table "pings", force: true do |t|
  # 1:  t.string   "session_id",    limit: 32
  # 2:  t.integer  "client_userid"
  # 3:  t.string   "client_sid",    limit: 20
  # 4:  t.datetime "last_ping_at"
  # 5:  t.datetime "next_ping_at"
  # 6:  t.string   "did"
  # 7:  t.text     "user_ids"
  # 8:  t.string   "sha256",        limit: 45
  # end
  # add_index "pings", ["session_id", "client_userid", "client_sid"], name: "index_ping_pk", unique: true, using: :btree

  # 1: rails sessionid

  # 2: client_userid. sequence with local user accounts in a browser starting with 1

  # 3: client_sid: one unique session id for each browser tab

  # 4: last_ping_at - datetime with milliseconds - stored as decimal(13,3) in database
  # timestamp for last ping request from browser or other gofreerev server
  def last_ping_at
    return nil unless (temp_last_ping_at = read_attribute(:last_ping_at))
    logger.debug2  "temp_user_ids = #{temp_last_ping_at}"
    Time.at temp_last_ping_at
  end
  def last_ping_at=(new_last_ping_at)
    if new_last_ping_at
      check_type('last_ping_at', new_last_ping_at, 'ActiveSupport::TimeWithZone')
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
    logger.debug2  "temp_user_ids = #{temp_next_ping_at}"
    Time.at temp_next_ping_at
  end
  def next_ping_at=(new_next_ping_at)
    if new_next_ping_at
      check_type('next_ping_at', new_next_ping_at, 'ActiveSupport::TimeWithZone')
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
    YAML::load temp_user_ids
  end # user_ids_was

  # 8: sha256 - generated from client secret and user_ids.
  # stored encrypted sessions table and stored in clear text in pings


  # array with internal user ids - used in ping response (online devices)
  # replicate gifts for mutual friends between online devices
  attr_accessor :mutual_friends

  # attr_accessor :internal_user_ids

  # pubkeys request from ping. Return pubkeys for list of unique device ids. Used in client communication
  # json validated with pubkeys part of JSON_SCHEMA[:ping_request] / JSON_SCHEMA[:ping_response]
  # returns null is did does not exists.
  public
  def self.pubkeys (pubkeys_request)
    return nil unless pubkeys_request.class == Array and pubkeys_request.size > 0
    pubkeys_request.uniq!
    pubkeys_response = Pubkey.where(:did => pubkeys_request).collect { |p| {:did => p.did, :pubkey => p.pubkey} }
    if pubkeys_request.size != pubkeys_response.size
      # client request with invalid pid! add null response
      (pubkeys_request - pubkeys_response.collect { |p| p[:did] }).each do |did|
        pubkeys_response.push({:did => did, :pubkey => null})
      end
    end
    pubkeys_response
  end # self.pubkeys

end
