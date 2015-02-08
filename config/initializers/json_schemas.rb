# validate json request/response with json schemas
# server side: https://github.com/ruby-json-schema/json-schema
# client side: https://github.com/geraintluff/tv4

# helper expression for gid, sid, cid etc (20 decimal string). To big to be a JS integer. From 2015-01-01 and one year forward in time
uid_from = (Time.zone.parse '2015-01-01').to_i
uid_to = 1.year.from_now.to_i
uid_short_range = `rgxg range -Z #{uid_from} #{uid_to}`.strip
uid_full_range = "^#{uid_short_range}[0-9]{10}$"

JSON_SCHEMA = {
    # ping request/response is the central message used in synchronization of information between servers and clients
    # number of pings per time period are regulated after average server load
    # client pings are distributed equally over time
    :ping_request =>
        {:type => 'object',
         :properties =>
             {# client userid normally = 1. Allow up to 100 user accounts in localStorage
              :client_userid => {:type => 'integer', :minimum => 1, :maximum => 100},
              # client unix timestamp (10) with milliseconds (3) - total 13 decimals
              :client_timestamp => {:type => 'integer', :minimum => 1.day.ago.to_i*1000, :maximum => 1.year.from_now.to_i*1000},
              # sid - unique session id - js unix timestamp (10) with milliseconds (3) and random numbers (7) - total 20 decimals
              :sid => {:type => 'string', :pattern => uid_full_range},
              # new_gifts - optional array with minimal meta-information for new gifts (gid, sha256 and user ids)
              :new_gifts => {
                  :type => 'array',
                  :items => {
                      :type => 'object',
                      :properties => {
                          # gid - unique gift id - js unix timestamp (10) with milliseconds (3) and random numbers (7) - total 20 decimals
                          :gid => {:type => 'string', :pattern => uid_full_range},
                          # sha256 digest of client side gift information (created at client unix timestamp + description)
                          :sha256 => {:type => 'string', :maxLength => 32},
                          # internal user ids for either giver or receiver - todo: change to uid/provider format to support cross server replication?
                          :giver_user_ids => {:type => 'array', :items => {:type => 'integer'}},
                          :receiver_user_ids => {:type => 'array', :items => {:type => 'integer'}}
                      },
                      :required => %w(gid sha256),
                      :additionalProperties => %w(giver_user_ids receiver_user_ids)}},
              # pubkeys - optional array with did (unique device id) - request public key for other client before starting client to client communication
              :pubkeys => {:type => 'array',
                           :items => {:type => 'string', :pattern => uid_full_range}}},
         :required => %w(client_userid client_timestamp sid),
         :additionalProperties => false
        },
    :ping_response =>
        {:type => 'object',
         :properties =>
             {# client unix timestamp (10) with milliseconds (3) for previous ping request from same unique device (did or session_id + user_clientid)
              :old_client_timestamp => {:type => 'integer', :minimum => 1.day.ago.to_i*1000, :maximum => 1.year.from_now.to_i*1000},
              # interval in milliseconds before next ping request from client. used when distribution client pings equal over time
              :interval => {:type => 'integer', :minimum => 1000},
              # array with online friends/devices - tells the client which devices are available for information synchronization
              :online => {
                  :type => 'array',
                  :items => {
                      :type => 'object',
                      :properties => {
                          # unique device id for other online device available for information synchronization
                          :did => {:type => 'string', :pattern => uid_full_range},
                          # array with internal user ids for mutual friends - synchronize information for mutual friends between clients
                          :mutual_friends => {:type => 'array', :items => {:type => 'integer'}}
                      },
                      :required => %w(did mutual_friends),
                      :additionalProperties => false
                  }},
              # optional - return fatal errors to client (invalid json request)
              :error => {:type => 'string'},
              # object and array with created_at_server timestamps (or error messages) response for new_gifts request
              :new_gifts => {
                  :type => 'object',
                  :properties => {
                      # any generic error message when processing of new_gifts request. see also error property in data array
                      :error => {:type => 'string'},
                      # array with created_at_server timestamps or error messages for each gid in new_gifts request
                      :data => {
                          :type => 'array',
                          :items => {
                              :type => 'object',
                              :properties => {
                                  # required unique gift id from new_gifts request
                                  :gid => {:type => 'string', :pattern => uid_full_range},
                                  # error message if signature for gift could not be saved on server
                                  :error => {:type => 'string'},
                                  # ok - created at server unix timestamp - 10 decimals - gift signature was saved on server
                                  :created_at_server => {:type => 'integer', :minimum => Time.zone.now.to_i, :maximum => 1.year.from_now.to_i}
                              },
                              :required => %w(gid),
                              :additionalProperties => false
                          }
                      },
                      # optional number of errors returned in data array
                      :no_errors => {:type => 'integer'}
                  },
                  :additionalProperties => false
              },
              # array with did and public keys response for pubkeys request
              :pubkeys => {
                  :type => 'array',
                  :items => {
                      :type => 'object',
                      :properties => {
                          # unique device id from pubkeys request
                          :did => {:type => 'string', :pattern => uid_full_range},
                          # public key or null if unknown did
                          :pubkey => {:type => 'string'}
                      },
                      :required => %w(did),
                      :additionalProperties => false
                  }
              }
             },
         :required => %w(interval),
         :additionalProperties => false
        }
}