class Ping < ActiveRecord::Base

  # user_ids - Array in model - text in db - array with currently logged in oauth users
  # stored encrypted in sessions table - stored in clear in pings
  # using in util/ping to return a list with online devices/friends
  def user_ids
    return nil unless (temp_user_ids = read_attribute(:user_ids))
    # logger.debug2  "temp_user_ids = #{temp_user_ids}"
    YAML::load temp_user_ids
  end

  # user_ids
  def user_ids=(new_user_ids)
    if new_user_ids
      check_type('user_ids', new_user_ids, 'Array')
      write_attribute :user_ids, new_user_ids.to_yaml
    else
      write_attribute :user_ids, nil
    end
  end

  # user_ids=
  alias_method :user_ids_before_type_cast, :user_ids

  def user_ids_was
    return user_ids unless user_ids_changed?
    return nil unless (temp_user_ids = attribute_was(:user_ids))
    YAML::load temp_user_ids
  end

  # user_ids_was

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
