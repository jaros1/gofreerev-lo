# validate json request/response with json schemas
# server side: https://github.com/ruby-json-schema/json-schema
# client side: https://github.com/geraintluff/tv4

# max number of gofreerev servers
max_server_no = 10000

# helper expression for gid, sid, cid etc (20 decimal string). To big to be a JS integer. From 2014-01-01 and one year forward in time
# rgxg required - sudo apt-get install rgxg
uid_from = (Time.zone.parse '2014-01-01').to_i
uid_to = 1.year.from_now.to_i
cmd = "rgxg range -Z #{uid_from} #{uid_to}"
uid_short_pattern = `#{cmd}`
puts "OS commend \"#{cmd}\" failed. Please install rgxg. sudo apt-get install rgxg" unless uid_short_pattern
uid_short_pattern = uid_short_pattern.strip # 10 decimals
uid_pattern = "^#{uid_short_pattern}[0-9]{10}$" # 20 decimals

# pattern with valid providers
providers_pattern = '^(' + API_ID.keys.join('|') + ')$'

# array with omniauth authorizations. One item for each provider. Used in json schema definitions for login and ping response
oauths_type = {
    :type => 'array',
    :items => {
        :type => 'object',
        :properties => {
            # provider: facebook, foursquare etc
            :provider => {:type => 'string', :pattern => providers_pattern},
            # server side user id (uid + provider)
            :user_id => {:type => 'string'},
            # access token
            :token => {:type => 'string'},
            # unix expires at timestamp
            :expires_at => {:type => 'integer', :minimum => (Time.zone.parse '2015-01-01').to_i, :maximum => 15.months.from_now.to_i},
            # optional refresh token (google+ only)
            :refresh_token => {:type => 'string'}
        },
        :required => %w(provider user_id token expires_at),
        :additionalProperties => false
    }
}

# array with providers with expired access token. One item for each expired provider. Used in json schema definitions for login and ping response
expired_tokens_type = {
    :type => 'array',
    :items => {
        :type => 'string', :pattern => providers_pattern
    }
}

# client unix timestamp (10) with milliseconds (3) - total 13 decimals
# used when distribution pings equally over time (ping) and used when checking for expired access token on server (login and ping)
client_timestamp_type = {:type => 'integer', :minimum => 1.day.ago.to_i*1000, :maximum => 1.year.from_now.to_i*1000}

# client userid required in all requests. Normally 1. But up to 100 local user accounts are supported
# ( localStorage and server session are divided into a section for each user )
client_userid_type = {:type => 'integer', :minimum => 1, :maximum => 100}

# array with login user and friends information (friends etc). from api friend lists. used in login and do_tasks response
friends_array_type = {
    :type => 'array',
    :items => {
        :type => 'object',
        # fields in user record (login user, friend etc)
        :properties => {
            # internal user id (sequence) - used in internal arrays
            :user_id => {:type => 'integer', :minimum => 1},
            # provider unique user id - used in signatures and in communication between clients
            :uid => {:type => 'string'},
            # login provider - facebook, foursquare etc
            :provider => {:type => 'string', :pattern => providers_pattern},
            # full user name
            :user_name => {:type => 'string'},
            # url to profile picture
            :api_profile_picture_url => {:type => 'string'},
            # friend:
            # - 1: logged in user, 2: mutual friends, 3: follows, 4: stalked by,
            # - 5: deselected api friends, 6: friends of friends, 7: friends proposals, 8: others
            :friend => {:type => 'integer', :minimum => 1, :maximum => 8},
            # three sha256 signatures. included for friends that are using other Gofreerev servers
            # used as user_id when sending and receiving messages to/from other Gofreerev servers
            # sha256 signature on this Gofreerev server. used when receiving messages
            :sha256 => {:type => 'string'},
            # previous sha256 signature on this Gofreerev server. valid for 3 minutes after change of server secret
            :old_sha256 => {:type => 'string'},
            # array with sha256 signatures on other Gofreerev servers. used when sending messages
            :remote_sha256 => {
                :type => 'array',
                :items => {
                    :type => 'object',
                    :properties => {
                        :server_id => { :type => 'integer' },
                        :sha256 => { :type => 'string'}

                    },
                    :required => %w(server_id sha256),
                    :additionalProperties => false
                },
                :minItems => 1
            },
            # short list with remote friends from ping. Ask client to initialize a friend list update
            # ( after receiving server to server message with changed sha256 signature )
            :refresh => { :type => 'boolean' }
        },
        :required => %w(user_id uid provider user_name friend),
        :additionalProperties => false
    }
}


JSON_SCHEMA = {
    # login request/response is used after local device login. oauth information is send to server, validated and updated api friend lists are returned to client
    # oauth information is stored encrypted in localStorage in browser and only temporary in server session doing log in
    # oauth information is deleted from session cookie and from server session when login process is finished
    :login_request => {
        :type => 'object',
        :title => 'Login request from client with optional oauth authorization from localStorage',
        :properties => {
            # client userid normally = 1. Allow up to 100 user accounts in localStorage
            :client_userid => client_userid_type,
            # client unix timestamp (10) with milliseconds (3) - total 13 decimals - used together with server timestamp in check for expired tokens
            :client_timestamp => client_timestamp_type,
            # client secret - 10 characters string
            # client communication: used in device.sha256 signature - unique mailbox address - 10 digits
            # server communication: used in user.sha256 signature - used when comparing user information - 10 random characters
            :client_secret => {:type => 'string'},
            # did - unique device id - js unix timestamp (10) with milliseconds (3) and random numbers (7) - total 20 decimals
            :did => {:type => 'string', :pattern => uid_pattern},
            # pubkey key for unique device - used in encrypted client to client information replication
            :pubkey => {:type => 'string'},
            # array with oauth authorization for one or more social networks (from localStorage)
            :oauths => oauths_type,
            # server site url for calling server - not used in client server communication - only used in server to server communication
            :site_url => {:type => 'string', :pattern => '^https?:\/\/' }
        },
        :required => %w(client_userid client_timestamp client_secret did pubkey),
        :additionalProperties => false
    },
    :login_response => {
        :type => 'object',
        :properties => {
            # array with login user and friends information (friends etc). from api friend lists
            :friends => friends_array_type,
            # optional unix timestamp for last friends.sha256 update. old_sha256 is valid 3 minutes after friends_sha256_updated_at
            :friends_sha256_update_at => {:type => 'integer', :minimum => uid_from, :maximum => uid_to},
            # optional array with providers with expired oauth authorization
            :expired_tokens => expired_tokens_type,
            # optional array with new oauth authorization - for now only used for google+
            :oauths => oauths_type,
            # server public key - only returned after server login request
            :pubkey => {:type => 'string' },
            # server did - unique device id - only returned after server login request
            :did => {:type => 'string', :pattern => uid_pattern},
            # client secret - only returned after server login request - used when comparing user information - 10 random characters
            :client_secret => {:type => 'string'},
            # optional error message from login
            :error => {:type => 'string'}
        },
        :required => %w(friends),
        :additionalProperties => false
    },

    # log out request/response is used for device log out (without provider) or log out for a social network (with provider)
    :logout_request => {
        :type => 'object',
        :properties => {
            # client userid normally = 1. Old client userid at device logout (provider=null). Allow up to 100 user accounts in localStorage
            :client_userid => client_userid_type,
            # optional log out provider. null=device: device log out. <>null: social network log out
            :provider => {:type => 'string', :pattern => providers_pattern}
        },
        :required => %w(client_userid),
        :additionalProperties => false
    },
    :logout_response => {
        :type => 'object',
        # optional error message is the only property in log out response
        :properties => {:error => {:type => 'string'}},
        :additionalProperties => false
    },

    # do tasks is used to do some post page startup ajax tasks on server
    # ( set server timezone, move oauth from sessions table to localStorage, get friend list from login provider etc )
    :do_tasks_request => {
        :type => 'object',
        :properties => {
            # client userid normally = 1. Old client userid at device logout (provider=null). Allow up to 100 user accounts in localStorage
            :client_userid => client_userid_type,
            # did - unique device id - js unix timestamp (10) with milliseconds (3) and random numbers (7) - total 20 decimals
            :did => {:type => 'string', :pattern => uid_pattern}
        },
        :required => %w(client_userid),
        :additionalProperties => false
    },
    :do_tasks_response => {
        :type => 'object',
        :properties => {
            # optional array with new oauth authorization to client (temporary stored in server session after api omniauth login
            :oauths => oauths_type,
            # array with login user and friends information (friends etc). from api friend lists
            :friends => friends_array_type,
            # optional unix timestamp for last friends.sha256 update. old_sha256 is valid 3 minutes after friends_sha256_update_at
            :friends_sha256_update_at => {:type => 'integer', :minimum => uid_from, :maximum => uid_to},
            # optional error message from do_tasks
            :error => {:type => 'string'}
        },
        :additionalProperties => false
    },

    # ping request/response is the central message used in synchronization of information between servers and clients
    # number of pings per time period are regulated after average server load
    # client pings (clients and other Gofreerev servers) are distributed equally over time
    :ping_request =>
        {:type => 'object',
         :title => 'Send requests to server and send messages to other clients',
         :description => 'Ping request from client to server once every <interval> milliseconds. All gifts and comments must have a server side sha256 signature. Public keys and messages are used in encrypted client to client communication',
         :properties =>
             {# client userid normally = 1. Allow up to 100 user accounts in localStorage
              :client_userid => client_userid_type,
              # client unix timestamp (10) with milliseconds (3) - total 13 decimals
              :client_timestamp => client_timestamp_type,
              # sid - unique session id - js unix timestamp (10) with milliseconds (3) and random numbers (7) - total 20 decimals
              :sid => {:type => 'string', :pattern => uid_pattern},

              # new_servers - array with sha256 signatures - request internal server id for new "unknown" Gofreerev servers
              # ( known servers are downloaded from /assets/ruby_to.js page at page load - Gofreerev.rails['SERVERS'] )
              :new_servers => {
                  :type => 'array',
                  :title => 'Array with sha256 signatures for unknown servers',
                  :items => { :type => 'string'} # server sha256 signatures
              },

              # verify_gifts - optional array used when verifying gifts received from other clients - check server sha256 signature created in a previous new_gifts request
              # gift must be from a friend - gift can be from an other gofreerev server
              :verify_gifts => {
                  :type => 'array',
                  :title => 'Array with gifts verifications requests (gifts received from other clients)',
                  :description => 'Array with meta-data for gifts received from other clients. Server checks if server side sha256 value is valid (gift information is unchanged)',
                  :items => {
                      :type => 'object',
                      :properties => {
                          # optional server id for other Gofreerev server
                          :server_id => {:type => %w(integer undefined), :minimum => 1},
                          # unique seq returned in response (gid is not guaranteed to be unique when receiving gifts from other devices)
                          # use positive seq for local gifts without server id - use negative seq for remote gifts with server id
                          :seq => {:type => 'integer'},
                          # gid - unique gift id - js unix timestamp (10) with milliseconds (3) and random numbers (7) - total 20 decimals
                          :gid => {:type => 'string', :pattern => uid_pattern},
                          # required sha256 digest of client side gift information (created at client + description + 4 open graph fields)
                          :sha256 => {:type => 'string', :maxLength => 32},
                          # gift action: create, verify, accept or delete. create: new signature, verify: check signature(s), accept and delete: check old signatures and add new signature for action
                          :action => {:type => 'string', :pattern => '^(create|verify|accept|delete)$'},
                          # only used in accepted_gifts request - sha256 digest of client side gift information (created at client + description + 4 open graph fields + accepted_at_client)
                          :sha256_accepted => {:type => 'string', :maxLength => 32},
                          # only used in delete_gifts request - sha256 digest of client side gift information (created at client + description + 4 open graph fields + deleted_at_client)
                          :sha256_deleted => {:type => 'string', :maxLength => 32},
                          # internal user ids for either giver or receiver
                          :giver_user_ids => {:type => %w(NilClass array), :items => {:type => 'integer'}},
                          :receiver_user_ids => {:type => %w(NilClass array), :items => {:type => 'integer'}}
                      },
                      :required => %w(seq gid sha256 action),
                      :additionalProperties => false
                  },
                  :minItems => 1
              },

              # verify_comments - optional array with comment actions (create, verify, cancel, accept, reject and delete). add / check server sha256 signatures sha256, sha256_action and sha256_deleted
              :verify_comments => {
                  :type => 'array',
                  :items => {
                      :type => 'object',
                      :properties => {
                          # unique seq returned in response (cid is not guaranteed to be unique when receiving comments from other devices)
                          :seq => {:type => 'integer'},
                          # optional server id for other Gofreerev server if comment was created on an other Gofreerev server
                          :server_id => {:type => %w(undefined integer), :minimum => 1},
                          # cid - unique comment id - js unix timestamp (10) with milliseconds (3) and random numbers (7) - total 20 decimals
                          :cid => {:type => 'string', :pattern => uid_pattern},
                          # sha256 digest of client side comment information (unique gift id, created at client unix timestamp, comment, price, currency and new_deal)
                          :sha256 => {:type => 'string', :maxLength => 32},
                          # comment action: create, verify, cancel, accept or reject new deal proposal or delete comment.
                          # create: new signature, verify: check signatures, other: check old signatures and add new signature for new deal action or delete
                          :action => {:type => 'string', :pattern => '^(create|verify|cancel|accept|reject|delete)$'},
                          # internal user ids for creator of comment (=login users)
                          :user_ids => {:type => 'array', :items => {:type => 'integer'}},
                          # sha256 client digest if new deal proposal (new_deal=true) has been cancelled, accepted or rejected (unique gift id, created at client unix timestamp, comment, price, currency, new_deal, new_deal_action and new_deal_action_at_client)
                          :sha256_action => {:type => 'string', :maxLength => 32},
                          # optional internal user ids for any new_deal_action (cancel, accept or reject) for new deal proposal.
                          :new_deal_action_by_user_ids => {:type => 'array', :items => {:type => 'integer'}},
                          # sha256 client digest if comment has been deleted (unique gift id, created at client unix timestamp, comment, price, currency, new_deal, new_deal_action, new_deal_action_at_client and deleted_at_client)
                          :sha256_deleted => {:type => 'string', :maxLength => 32},
                          # optional gift hash. gift authorization information used for some comment actions (accept, reject and delete comment - comment deleted by giver or receiver of gift)
                          :gift => {
                              :type => 'object',
                              :properties => {
                                  # optional server id for other Gofreerev server if comment was created on an other Gofreerev server
                                  :server_id => {:type => 'integer', :minimum => 1},
                                  # gid - unique gift id - js unix timestamp (10) with milliseconds (3) and random numbers (7) - total 20 decimals
                                  :gid => {},
                                  # required sha256 digest of client side gift information (created at client + description + 4 open graph fields)
                                  :sha256 => {},
                                  # internal user ids for either giver or receiver. gift must have a giver or a receiver.
                                  :giver_user_ids => {},
                                  :receiver_user_ids => {}
                              },
                              :required => %w(gid sha256),
                              :additionalProperties => false
                          }
                      },
                      :required => %w(seq cid sha256 action user_ids),
                      :additionalProperties => false
                  },
                  :minItems => 1
              },

              # pubkeys - optional array with did (unique device id) - request public key for other client before starting client to client communication
              :pubkeys => {
                  :type => 'array',
                  :items => {:type => 'string', :pattern => uid_pattern},
                  :minItems => 1
              },

              # refresh_tokens - google+ only - optional array with refresh tokens to be used when refreshing expired access token
              :refresh_tokens => {
                  :type => 'array',
                  :items => {
                      :type => 'object',
                      :properties => {
                          :provider => {:type => 'string', :pattern => providers_pattern},
                          :refresh_token => {:type => 'string'}
                      },
                      :required => %w(provider refresh_token),
                      :additionalProperties => false
                  },
                  :minItems => 1,
                  :maxItems => 1
              },

              # optional array with oauth authorization for one or more social networks (from localStorage)
              # used for friend list update after detecting changed sha256 user signature in server to server communication
              # see :refresh => true in short friends list in util_controller.ping
              # see also server.from_sha256s_to_user_ids where changed sha256 signature in incoming server to server messages is detected
              :oauths => oauths_type,
              # optional array with encrypted messages from client to other devices (users_sha256, todo: gifts_sha256, gifts etc)
              # temporary buffer on server until message is delivered or message is expired/too old
              :messages => {
                  :type => 'array',
                  :title => 'Request with messages from child client or server',
                  :description => 'Array with messages from child client (server=false) or child server (server=true). Sender_did is only used in server to server communication. Receiver_sha256 is only used in client to client communication. Encryption is rsa, sym or mix. key is only used for mix encrypted messages',
                  :items => {
                      :type => 'object',
                      :properties => {
                          # sender did - unique device id - js unix timestamp (10) with milliseconds (3) and random numbers (7) - total 20 decimals
                          :sender_did => {:type => 'string', :pattern => uid_pattern},
                          # receiver did - unique device id - js unix timestamp (10) with milliseconds (3) and random numbers (7) - total 20 decimals
                          :receiver_did => {:type => 'string', :pattern => uid_pattern},
                          # (sender sha256 is not used neither in client to client communication nor in server to server communication)
                          # receiver sha256 signature for generated from client secret and login user ids. used in client to client communication
                          :receiver_sha256 => {:type => 'string'},
                          # server - true for server to server communication. false for client to client communication
                          :server => {:type => 'boolean'},
                          # encryption. rsa encrypted key and symmetric encrypted message
                          :key => {:type => 'string'},
                          :message => {:type => 'string'}
                      },
                      :required => %w(receiver_did server key message),
                      :additionalProperties => false
                  },
                  :minItems => 1
              }
             },
         :required => %w(client_userid client_timestamp sid),
         :additionalProperties => false
        },

    :ping_response =>
        {:type => 'object',
         :title => 'Receive response from server and receive messages from other clients',
         :properties =>
             {# client unix timestamp (10) with milliseconds (3) for previous ping request from same unique device (did or session_id + user_clientid)
              :old_client_timestamp => client_timestamp_type,
              # interval in milliseconds before next ping request from client. used when distribution client pings equal over time
              :interval => {:type => 'integer', :minimum => 1000},
              # array with online friends/devices - tells the client which devices are available for gift synchronization
              :online => {
                  :type => 'array',
                  :title => 'Array with online friends',
                  :description => 'Did is unique device id. sha256 is signature with client secret and current logged in users. sha256 changes when api provider login changes for a device. Did+sha256 is used as unique mailbox address. Mutual_friends is an array with mutual friends between did and friend did. Synchronize only information for mutual friends. Server id used for communication with friends on other gofreerev servers',
                  :items => {
                      :type => 'object',
                      :properties => {
                          # unique device id for other online device available for information synchronization
                          :did => {:type => 'string', :pattern => uid_pattern},
                          # sha256 signature for device generated from client secret and login user ids. used in client to client communication mailbox
                          :sha256 => {:type => 'string'},
                          # array with internal user ids for mutual friends - synchronize information for mutual friends between clients
                          :mutual_friends => {:type => 'array', :items => {:type => 'integer'}},
                          # optional server id if online unique device on an other gofreerev server (server to server communication)
                          :server_id => {:type => 'integer', :minimum => 1}
                      },
                      :required => %w(did sha256 mutual_friends),
                      :additionalProperties => false
                  },
                  :minItems => 1
              },

              # optional array with sha256 signatures for friends on other Gofreerev servers.
              # returned to client after change in server secret and updated sha256 signatures
              :friends => friends_array_type,

              # optional unix timestamp for server secret update / friends.sha256 updates. old_sha256 values are valid for 3 minutes after friends_sha256_update_at
              :friends_sha256_update_at => {:type => 'integer', :minimum => uid_from, :maximum => uid_to},

              # optional - return fatal errors to client (invalid json request)
              :error => {:type => 'string'},

              # new_servers response - array with sha256 signature and internal server id - response to new_servers request
              # blank server id = unknown server
              :new_servers => {
                  :type => 'array',
                  :title => 'New servers response with internal server id and sha256 signature. Blank server_id for unknown servers',
                  :items => {
                      :type => 'object',
                      :properties => {
                          :sha256 => { :type => 'string'},
                          :server_id => { :type => 'integer', :minimum => 0 }
                      },
                      :required => %w(sha256),
                      :additionalProperties => false
                  }
              },

              # optional array with verified_at_server (boolean) response for verify_gifts request (create, verify, accept or delete gift)
              :verify_gifts => {
                  :type => 'object',
                  :title => 'Server verify gifts response with verified_at_server true or false for each gifts in verify gifts request',
                  :properties => {
                      # optional fatal system error - string - english only error message - used for cross server error messages
                      # or object with :key and :options - multi-language support - used for within server error messages
                      :error => {
                          :type => %w(string object),
                          :properties => {
                              :key => { :type => 'string'},
                              :options => { :type => 'object'}
                          },
                          :required => %w(key),
                          :additionalProperties => false
                      },
                      # array with created_at_server boolean for rows in verify_gifts request
                      :gifts => {
                          :type => 'array',
                          :items => {
                              :type => 'object',
                              :properties => {
                                  # unique seq from verify_gifts request (gid is not guaranteed to be unique when receiving gifts from other clients)
                                  :seq => {:type => 'integer'},
                                  # gid - unique gift id - from verify_gifts request
                                  :gid => {:type => 'string', :pattern => uid_pattern},
                                  # verified_at_server - boolean - true if gift action (create, verify, accept or delete) succeeded
                                  :verified_at_server => {:type => 'boolean'},
                                  # error message if gift action (create, verify, accept, delete) failed. verified_at_server = false
                                  # either a string - english only error message - used for cross server error messages
                                  # or an object with :key and :options - multi-language support - used for within server error messages
                                  :error => {
                                      :type => %w(string object),
                                      :properties => {
                                          :key => { :type => 'string'},
                                          :options => { :type => 'object'}
                                      },
                                      :required => %w(key),
                                      :additionalProperties => false
                                  }
                              },
                              :required => %w(seq gid verified_at_server),
                              :additionalProperties => false
                          },
                          :minItems => 1
                      }
                  },
                  :additionalProperties => false
              },

              # optional array with verified_at_server boolean response for verify_comments request (create, verify, cancel, accept, reject or delete)
              :verify_comments => {
                  :type => 'object',
                  :properties => {
                      # optional fatal system error - string - english only error message - used for cross server error messages
                      # or object with :key and :options - multi-language support - used for within server error messages
                      :error => {
                          :type => %w(string object),
                          :properties => {
                              :key => { :type => 'string'},
                              :options => { :type => 'object'}
                          },
                          :required => %w(key),
                          :additionalProperties => false
                      },
                      # array with created_at_server boolean for rows in verify_comments request
                      :comments => {
                          :type => 'array',
                          :items => {
                              :type => 'object',
                              :properties => {
                                  # unique seq from verify_comments request (cid is not guaranteed to be unique when receiving comments from other devices)
                                  # use negative seq for remote comment actions. use positive seq for local comment actions
                                  :seq => {:type => 'integer'},
                                  # cid - unique comment id - from verify_comments request
                                  :cid => {:type => 'string', :pattern => uid_pattern},
                                  # verified_at_server - boolean - true if comment action (create, verify, cancel, accept, reject or delete) succeeded
                                  :verified_at_server => {:type => 'boolean'},
                                  # error message if comment action (create, verify, cancel, accept, reject or delete) failed. verified_at_server = false
                                  # either a string - english only error message - used for cross server error messages
                                  # or an object with :key and :options - multi-language support - used for within server error messages
                                  :error => {
                                      :type => %w(string object),
                                      :properties => {
                                          :key => { :type => 'string'},
                                          :options => { :type => 'object'}
                                      },
                                      :required => %w(key),
                                      :additionalProperties => false
                                  }
                              },
                              :required => %w(seq cid verified_at_server),
                              :additionalProperties => false
                          },
                          :minItems => 1
                      }
                  },
                  :additionalProperties => false
              },
              # array with did and public keys response for pubkeys request
              :pubkeys => {
                  :type => 'array',
                  :title => 'Array with requested public keys to client',
                  :description => 'Response for a remote device will be returned in a later pubkeys request. Blank pubkey is returned for unknown device',
                  :items => {
                      :type => 'object',
                      :properties => {
                          # unique device id from pubkeys request
                          :did => {:type => 'string', :pattern => uid_pattern},
                          # public key or null if unknown did
                          :pubkey => {:type => %w(NilClass null string)}
                      },
                      :required => %w(did),
                      :additionalProperties => false
                  },
                  :minItems => 1
              },

              # optional array with providers with expired oauth authorization
              :expired_tokens => expired_tokens_type,

              # optional array with new oauth authorization - for now only used for google+
              :oauths => oauths_type,

              # array with encrypted messages to client from other devices (users_sha256, todo: gifts_sha256, gifts etc)
              # temporary buffered on server until message was delivered or message was expired/too old
              :messages => {
                  :type => 'object',
                  :title => 'Response with messages from other clients to client',
                  :properties => {
                      :messages => {
                          :type => 'array',
                          :title => 'Array with messages from other clients to client',
                          :items => {
                              :type => 'object',
                              :properties => {
                                  # receiver did - unique device id - js unix timestamp (10) with milliseconds (3) and random numbers (7) - total 20 decimals
                                  # only used in server to server messages (server=true).
                                  :receiver_did => {:type => 'string', :pattern => uid_pattern},
                                  # sender did - unique device id - js unix timestamp (10) with milliseconds (3) and random numbers (7) - total 20 decimals
                                  :sender_did => {:type => 'string', :pattern => uid_pattern},
                                  # sender sha256 signature for generated from client secret and login user ids. used in client to client communication
                                  :sender_sha256 => {:type => 'string'},
                                  # server - true for server to server communication. false for client to client communication
                                  :server => {:type => 'boolean'},
                                  # encryption. rsa encrypted key and symmetric encrypted message
                                  :key => {:type => 'string'},
                                  :message => {:type => 'string'}
                              },
                              :required => %w(sender_did server key message),
                              :additionalProperties => false
                          },
                          :minItems => 1
                      },
                      # optional error message (fatal server errors)
                      :error => {:type => 'string'}
                  },
                  :additionalProperties => false
              }

             },
         :required => %w(interval),
         :additionalProperties => false
        },

    # new gift - preview open graph link. server is using either Embedly::API or opengraph_parser gems to fetch OG tags for url
    :open_graph_request => {
        :type => 'object',
        :properties => {
            # client userid normally = 1. Allow up to 100 user accounts in localStorage
            :client_userid => client_userid_type,
            # client unix timestamp (10) with milliseconds (3) - total 13 decimals
            :client_timestamp => client_timestamp_type,
            # lookup url
            :url => {:type => 'string'}
        },
        :required => %w(client_userid client_timestamp url),
        :additionalProperties => false
    },
    :open_graph_response => {
        :type => 'object',
        :properties => {
            # open graph meta-tags - blank if url does not exist
            :url => {:type => 'string'},
            :title => {:type => 'string'},
            :description => {:type => 'string'},
            :image => {:type => 'string'},
            # optional error message (server errors)
            :error => {:type => 'string'}
        },
        :additionalProperties => false
    },

    ##################################
    # server to server communication #
    ##################################

    # server login: see client :login_request and :login_response

    # server ping: see client :ping_request and :ping_response

    # todo: changed user sha256 server to server message

    # verify_gifts server to server message
    :verify_gifts_request => {
        :type => 'object',
        :properties => {
            :msgtype  => { :type => 'string', :pattern => '^verify_gifts$' },
            # mid - unique server to server message id
            :mid => { :type => 'integer', :minimum => 1},
            # array with logged in users - must be a hash with sha256, pseudo_user_id and sha256_updated_at
            # (verified server user) or a negative integer (unknown user)
            :login_users => {
                :type => 'array',
                :items => {
                    :type => %w(object integer),
                    :properties => { # if object - verified server user
                        :sha256 => { :type => 'string'},
                        :pseudo_user_id => { :type => 'integer', :minimum => 1},
                        :sha256_updated_at => { :type => 'integer'},
                        :required => %w(sha256 pseudo_user_id sha256_updated_at),
                        :additionalProperties => false
                    },
                    :maximum => -1, # if integer - unknown user
                },
                :minItems => 1
            },
            # array with verify gifts request from clients to other Gofreerev server
            :verify_gifts => {
                :type => 'array',
                :items => {
                    :type => 'object',
                    :properties => {
                        # unique seq (Sequence.next_verify_gift_seq) returned in response (gid is not guaranteed to be unique when receiving gifts for verification).
                        :seq => {:type => 'integer'},
                        # gid - unique gift id - js unix timestamp (10) with milliseconds (3) and random numbers (7) - total 20 decimals
                        :gid => {:type => 'string', :pattern => uid_pattern},
                        # required sha256 digest of client side gift information (created at client + description + 4 open graph fields)
                        :sha256 => {:type => 'string', :maxLength => 32},
                        # gift action: create, verify, accept or delete. create: new signature, verify: check signature(s), accept and delete: check old signatures and add new signature for action
                        :action => {:type => 'string', :pattern => '^(verify|accept|delete)$'},
                        # only used in accepted_gifts request - sha256 digest of client side gift information (created at client + description + 4 open graph fields + accepted_at_client)
                        :sha256_accepted => {:type => 'string', :maxLength => 32},
                        # only used in delete_gifts request - sha256 digest of client side gift information (created at client + description + 4 open graph fields + deleted_at_client)
                        :sha256_deleted => {:type => 'string', :maxLength => 32},
                        # internal user ids for either giver or receiver
                        :giver_user_ids => {
                            :type => %w(NilClass array),
                            :items => {
                                :type => %w(object integer),
                                :properties => { # if object - verified server user
                                                 :sha256 => { :type => 'string'},
                                                 :pseudo_user_id => { :type => 'integer', :minimum => 1},
                                                 :sha256_updated_at => { :type => 'integer'}
                                },
                                :required => %w(sha256 pseudo_user_id sha256_updated_at),
                                :additionalProperties => false,
                                :maximum => -1, # if integer - unknown user with negative user id
                            }
                        },
                        :receiver_user_ids => {
                            :type => %w(NilClass array),
                            :items => {
                                :type => %w(object integer),
                                :properties => { # if object - verified server user
                                                 :sha256 => { :type => 'string'},
                                                 :pseudo_user_id => { :type => 'integer', :minimum => 1},
                                                 :sha256_updated_at => { :type => 'integer'}
                                },
                                :required => %w(sha256 pseudo_user_id sha256_updated_at),
                                :additionalProperties => false,
                                :maximum => -1, # if integer - unknown user with negative user id
                            }
                        }
                    },
                    :required => %w(seq gid sha256 action),
                    :additionalProperties => false
                },
                :minItems => 1
            }
        },
        :required => %w(msgtype mid login_users verify_gifts),
        :additionalProperties => false
    },

    :verify_gifts_response => {
        :type => 'object',
        :properties => {
            :msgtype => {:type => 'string', :pattern => '^verify_gifts$'},
            # mid - unique server to server message id
            :mid => { :type => 'integer', :minimum => 1},
            # request mid - unique server to server message id - from verify gifts request
            :request_mid => { :type => 'integer', :minimum => 1},
            # array with verify gifts response to clients on other gofreerev server
            :verify_gifts => {
                :type => 'array',
                :items => {
                    :type => 'object',
                    :properties => {
                        # unique seq (Sequence.next_verify_gift_seq) returned in response (gid is not guaranteed to be unique when receiving gifts for verification).
                        :seq => { :type => 'integer'},
                        # gid - unique gift id - js unix timestamp (10) with milliseconds (3) and random numbers (7) - total 20 decimals
                        :gid => {:type => 'string', :pattern => uid_pattern},
                        # verify gift request rejected due to changed user sha256 signatures. Server must process incoming sha256 changed signature message, update user info and resend verify gift request with up-to-date sha256 signatures
                        :sha256_changed => { :type => 'boolean'},
                        # true if verify gift request was ok. false if not. See more info in error field
                        :verified_at_server => { :type => 'boolean'},
                        # optional additional error info. Only "system" errors (english only - not using translations)
                        :error => { :type => 'string'},
                        # optional gift direction in response. used in server to server verify comments message authorization check
                        :direction => { :type => 'string', :pattern => '^(giver|receiver)$'}
                    },
                    :required => %w(seq),
                    :additionalProperties => false
                }
            },
            # optional error message.
            :error => { :type => 'string' }
        },
        :required => %w(msgtype mid request_mid),
        :additionalProperties => false
    },


    # verify_comments server to server message. from client on one Gofreerev server to other Gofreerev server where comment was created
    :verify_comments_request => {
        :type => 'object',
        :properties => {
            :msgtype  => { :type => 'string', :pattern => '^verify_comments$' },
            # mid - unique server to server message id
            :mid => { :type => 'integer', :minimum => 1},
            # array with logged in users - must be a hash with sha256, pseudo_user_id and sha256_updated_at
            # (verified server user) or a negative integer (unknown user)
            :login_users => {
                :type => 'array',
                :items => {
                    :type => %w(object integer),
                    :properties => { # if object - verified server user
                                     :sha256 => { :type => 'string'},
                                     :pseudo_user_id => { :type => 'integer', :minimum => 1},
                                     :sha256_updated_at => { :type => 'integer'},
                                     :required => %w(sha256 pseudo_user_id sha256_updated_at),
                                     :additionalProperties => false
                    },
                    :maximum => -1, # if integer - unknown user
                },
                :minItems => 1
            },
            # array with verify comments request from client to other gofreerev server
            :verify_comments => {
                :type => 'array',
                :items => {
                    :type => 'object',
                    :properties => {
                        # unique seq (Sequence.next_verify_seq) returned in response (cid is not guaranteed to be unique when receiving comments for verification).
                        :seq => {:type => 'integer'},
                        # cid - unique comment id - js unix timestamp (10) with milliseconds (3) and random numbers (7) - total 20 decimals
                        :cid => {:type => 'string', :pattern => uid_pattern},
                        # required sha256 digest of client side comment information (unique gift id + created at client + comment + price + currency + new_deal)
                        :sha256 => {:type => 'string', :maxLength => 32},
                        # verify: check signature, other: check old signatures and add new signature for new deal action (cancel, accept or reject) or delete comment
                        :action => {:type => 'string', :pattern => '^(verify|cancel|accept|reject|delete)$'},
                        # only used in new deal proposal actions (cancel, accept and reject) - sha256 digest of client side comment information (sha256 fields + new_deal_action + new_deal_action_at_client)
                        :sha256_action => {:type => 'string', :maxLength => 32},
                        # optional user signatures for any new_deal_action (cancel, accept or reject) for new deal proposal.
                        :new_deal_action_by_user_ids => {
                            :type => %w(NilClass array),
                            :items => {
                                :type => %w(object integer),
                                :properties => { # if object - verified server user
                                                 :sha256 => { :type => 'string'},
                                                 :pseudo_user_id => { :type => 'integer', :minimum => 1},
                                                 :sha256_updated_at => { :type => 'integer'}
                                },
                                :required => %w(sha256 pseudo_user_id sha256_updated_at),
                                :additionalProperties => false,
                                :maximum => -1, # if integer - unknown user with negative user id
                            }
                        },
                        # only used in delete_comments request - sha256 digest of client side comment information (sha256_action fields + deleted_at_client)
                        :sha256_deleted => {:type => 'string', :maxLength => 32},
                        # internal user ids for creator of comment
                        :user_ids => {
                            :type => %w(NilClass array),
                            :items => {
                                :type => %w(object integer),
                                :properties => { # if object - verified server user
                                                 :sha256 => { :type => 'string'},
                                                 :pseudo_user_id => { :type => 'integer', :minimum => 1},
                                                 :sha256_updated_at => { :type => 'integer'}
                                },
                                :required => %w(sha256 pseudo_user_id sha256_updated_at),
                                :additionalProperties => false,
                                :maximum => -1, # if integer - unknown user with negative user id
                            }
                        },
                        # optional gift hash. used in authorization check. required for reject and accept new deal proposal and delete comment requests if comment is deleted by giver or receiver of gift
                        :gift => {
                            :type => :object,
                            :properties => {
                                # gid - unique gift id - js unix timestamp (10) with milliseconds (3) and random numbers (7) - total 20 decimals
                                :gid => {:type => 'string', :pattern => uid_pattern},
                                # required sha256 digest of client side gift information (created at client + description + 4 open graph fields)
                                :sha256 => {:type => 'string', :maxLength => 32},
                                # array with user signatures for giver of gift if any. must have giver and/or receiver array
                                :giver_user_ids => {
                                    :type => %w(NilClass array),
                                    :items => {
                                        :type => %w(object integer),
                                        :properties => { # if object - verified server user
                                                         :sha256 => { :type => 'string'},
                                                         :pseudo_user_id => { :type => 'integer', :minimum => 1},
                                                         :sha256_updated_at => { :type => 'integer'}
                                        },
                                        :required => %w(sha256 pseudo_user_id sha256_updated_at),
                                        :additionalProperties => false,
                                        :maximum => -1, # if integer - unknown user with negative user id
                                    }
                                },
                                # array with user signatures for receiver of gift if any. must have giver and/or receiver array
                                :receiver_user_ids => {
                                    :type => %w(NilClass array),
                                    :items => {
                                        :type => %w(object integer),
                                        :properties => { # if object - verified server user
                                                         :sha256 => { :type => 'string'},
                                                         :pseudo_user_id => { :type => 'integer', :minimum => 1},
                                                         :sha256_updated_at => { :type => 'integer'}
                                        },
                                        :required => %w(sha256 pseudo_user_id sha256_updated_at),
                                        :additionalProperties => false,
                                        :maximum => -1, # if integer - unknown user with negative user id
                                    }
                                },
                                # optional sha256 signature for server (site_url) if gift and comment is on different Gofreerev servers
                                :server_id => { :type => 'string'}
                            },
                            # gift hash options
                            :required => %w(gid sha256),
                            :additionalProperties => false
                        }
                    },
                    # verify comment options
                    :required => %w(seq cid sha256 user_ids),
                    :additionalProperties => false
                }
            }
        },
        :required => %w(msgtype mid login_users verify_comments),
        :additionalProperties => false
    },

    :verify_comments_response => {
        :type => 'object',
        :properties => {
            :msgtype => {:type => 'string', :pattern => '^verify_comments$'},
            # mid - unique server to server message id
            :mid => { :type => 'integer', :minimum => 1},
            # request mid - unique server to server message id - from verify comments request
            :request_mid => { :type => 'integer', :minimum => 1},
            # array with verify comments response to clients on other gofreerev server
            :verify_comments => {
                :type => 'array',
                :items => {
                    :type => 'object',
                    :properties => {
                        # unique seq (Sequence.next_verify_seq) returned in response (cid is not guaranteed to be unique when receiving comments for verification).
                        :seq => { :type => 'integer'},
                        # cid - unique comment id - js unix timestamp (10) with milliseconds (3) and random numbers (7) - total 20 decimals
                        :cid => {:type => 'string', :pattern => uid_pattern},
                        # verify comment request rejected due to changed user sha256 signatures. Server must process incoming sha256 changed signature message, update user info and resend verify comment request with up-to-date sha256 signatures
                        :sha256_changed => { :type => 'boolean'},
                        # true if verify comment request was ok. false if not. See more info in error field
                        :verified_at_server => { :type => 'boolean'},
                        # optional additional error info. Only "system" errors
                        :error => { :type => 'string'}
                    },
                    :required => %w(seq),
                    :additionalProperties => false
                }
            },
            # optional error message.
            :error => { :type => 'string' }
        },
        :required => %w(msgtype mid request_mid),
        :additionalProperties => false
    },

    # todo: client to client communication step 1 - symmetric password handshake

    # client to client communication step 2
    # send a list of users sha256 values to other client for a list of mutual friends from ping (online devices)
    :users_sha256 => {
        :type => 'object',
        :title => 'Communication step 2 with user sha256 values to other client',
        :properties => {
            # mid - unique message id - js unix timestamp (10) with milliseconds (3) and random numbers (7) - total 20 decimals
            :mid => {:type => 'string', :pattern => uid_pattern},
            # msgtype = users_sha256
            :msgtype => {:type => 'string', :pattern => '^users_sha256$'},
            # array with internal user id and sha256 calculation for a list of users (mutual friends) - use empty sha256 if no gifts was found for a user
            :users => {
                :type => 'array',
                :items => {
                    :type => 'object',
                    :properties => {
                        # internal user id (within server communication) or user sha256 signature (cross server communication)
                        :user_id => { :type => %w(integer string) },
                        # sha256 calc for user gifts
                        :sha256 => { :type => 'string', :maxLength => 32}
                    },
                    :required => %w(user_id),
                    :additionalProperties => false
                },
                :minItems => 1
            }
        },
        :required => %w(mid msgtype users),
        :additionalProperties => false
    },

    # client to client communication step 3
    # send list with gifts sha256 values to other client after having compared sha256 values for mutual friends:
    :gifts_sha256 => {
        :type => 'object',
        :title => 'Communication step 3 with gift sha256 values to other client',
        :properties => {
            # mid - unique message id - js unix timestamp (10) with milliseconds (3) and random numbers (7) - total 20 decimals
            :mid => {:type => 'string', :pattern => uid_pattern},
            # request_mid - unique message id - reference to previous users_sha256 message - see client to client communication step 2
            :request_mid => {:type => 'string', :pattern => uid_pattern},
            # msgtype = gifts_sha256
            :msgtype => {:type => 'string', :pattern => '^gifts_sha256$'},
            # optional timestamp for oldest gift in sha256 compare - ignore gifts before this timestamp - todo: replace 0 with null
            :oldest_gift_at => {:type => 'integer', :minimum => uid_from, :maximum => uid_to},
            # optional array with gifts to be ignored in sha256 compare - for example gifts rejected due to invalid server sha256 signature
            :ignore_invalid_gifts => {
                :type => 'array',
                :items => {:type => 'string', :pattern => uid_pattern}
            },
            # array with internal user ids - must be a sublist of mutual friends - from previous users_sha256 message
            # use internal user ids for within server messages. use sha256 signatures for message between two gofreerev servers
            :users => {
                :type => 'array',
                :items => {:type => %w(integer string) },
                :minItems => 1
            },
            # array with sha256 values for gifts for users - empty array if no gifts were found for requested users (mutual friends)
            :gifts => {
                :type => 'array',
                :items => {
                    :type => 'object',
                    :properties => {
                        # gid - unique gift id - js unix timestamp (10) with milliseconds (3) and random numbers (7) - total 20 decimals
                        :gid => {:type => 'string', :pattern => uid_pattern},
                        # sha256 calculation for gift and comments
                        :sha256 => {:type => 'string', :maxLength => 32}
                    },
                    :required => %w(gid sha256),
                    :additionalProperties => false
                }
            }
        },
        :required => %w(mid request_mid msgtype users gifts),
        :additionalProperties => false
    },

    # client to client communication step 4
    # send 3 sub messages to other client after having compared sha256 values for gifts for mutual friends
    # 1) send_gifts: send missing gifts to other client
    # 2) request_gifts: request missing gifts from other client
    # 3) check_gifts: send sub sha256 values (seperate sha256 for gift and comments) for changed gifts to other client
    :sync_gifts => {
        :type => 'object',
        :title => 'Communication step 3 with send_gifts, request_gifts and check_gifts sub messages to other client',
        :properties => {
            # mid - unique message id - js unix timestamp (10) with milliseconds (3) and random numbers (7) - total 20 decimals
            :mid => {:type => 'string', :pattern => uid_pattern},
            # request_mid - unique message id - reference to previous gifts_sha256 message - see client to client communication step 3
            :request_mid => {:type => 'string', :pattern => uid_pattern},
            # msgtype = sync_gifts
            :msgtype => {:type => 'string', :pattern => '^sync_gifts$'},

            # array with internal user ids - must be a subset of mailbox.mutual_friends - from previous gifts_sha256 message
            # use internal user id for within server messages. use sha256 signatures for messages to other gofreerev servers
            :mutual_friends => {:type => 'array', :items => {:type => %w(integer string) }, :minItems => 1},

            # syn_gifts optional sub message 1 - send_gifts - send missing gifts to other client
            :send_gifts => {
                :type => 'object',
                :title => 'send_gifts sub message. Send missing gifts to other client',
                :properties => {
                    # mid - unique message id for sub message - js unix timestamp (10) with milliseconds (3) and random numbers (7) - total 20 decimals
                    :mid => {:type => 'string', :pattern => uid_pattern},
                    # msgtype = send_gifts
                    :msgtype => {:type => 'string', :pattern => '^send_gifts$'},
                    # array with missing gifts to other client
                    :gifts => {
                        :type => 'array',
                        :items => {
                            :type => 'object', # = gift
                            :properties => {
                                # gid - unique gift id - js unix timestamp (10) with milliseconds (3) and random numbers (7) - total 20 decimals
                                :gid => {:type => 'string', :pattern => uid_pattern},
                                # internal user ids for either giver or receiver - todo: change to uid/provider format to support cross server replication?
                                :giver_user_ids => {:type => 'array', :items => {:type => %w(integer string) } },
                                :receiver_user_ids => {:type => 'array', :items => {:type => %w(integer string) } },
                                # created at client unix timestamp - 10 decimals - used in gift signature on server
                                :created_at_client => {:type => 'integer', :minimum => uid_from, :maximum => uid_to},
                                # created at server - server number - 0 for this server - see also servers array for cross server messages
                                :created_at_server => {:type => 'integer', :minimum => 0, :maximum => max_server_no},
                                # optional price - set when gift is created or when gift is accepted by a friend
                                :price => {:type => %w(undefined null number), :minimum => 0, :multipleOf => 0.01 },
                                # optional currency - set when gift is created or when gift is accepted by a friend - iso4217 with restrictions
                                :currency => {:type => 'string', :pattern => '^[a-zA-Z]{3}$'},
                                # direction. giver: was created by giver_user_ids as an offer. receiver: was created by receiver_user_ids as seeks
                                :direction => {:type => 'string', :pattern => '^(giver|receiver)$'},
                                # description of gift
                                :description => {:type => 'string'},
                                # 4 optional open graph attributes if gift was created with an open graph link
                                :open_graph_url => {:type => %w(undefined string) },
                                :open_graph_title => {:type => %w(undefined string) },
                                :open_graph_description => {:type => %w(undefined string) },
                                :open_graph_image => {:type => %w(undefined string) },
                                # todo: add optional image url (file upload has not been implemented yet)
                                # like - now a boolean - todo: must be changed to an array with user ids and like/unlike timestamps
                                :like => {:type => %w(undefined boolean)},
                                # optional deleted at timestamp if gift has been deleted by giver or receiver
                                :deleted_at_client => {:type => %w(undefined integer), :minimum => uid_from, :maximum => uid_to},
                                # optional accepted cid - from accepted new deal proposal (comment) - unique comment id - js unix timestamp (10) with milliseconds (3) and random numbers (7) - total 20 decimals
                                :accepted_cid => {:type => %w(undefined string), :pattern => uid_pattern},
                                # optional accepted at client unix timestamp for accepted new deal proposal.
                                :accepted_at_client => {:type => %w(undefined integer), :minimum => uid_from, :maximum => uid_to},
                                # optional array with gift comments
                                :comments => {
                                    :type => 'array',
                                    :items => {
                                        :type => 'object', # = comment
                                        :properties => {
                                            # cid - unique comment id - js unix timestamp (10) with milliseconds (3) and random numbers (7) - total 20 decimals
                                            :cid => {:type => 'string', :pattern => uid_pattern},
                                            # internal user ids for creator of comment - todo: change to uid/provider format to support cross server replication?
                                            :user_ids => {:type => 'array', :items => {:type => %w(integer string) } },
                                            # optional price - can be set when creation a proposal (special comment) for gift/offer
                                            :price => {:type => %w(undefined null number), :minimum => 0, :multipleOf => 0.01},
                                            # optional currency - can be set when creation a proposal (special comment) for gift/offer - iso4217 with restrictions
                                            :currency => {:type => %w(undefined string), :pattern => '^[a-zA-Z]{3}$'},
                                            # comment
                                            :comment => {:type => 'string'},
                                            # created at client unix timestamp - 10 decimals - used in comment signature on server
                                            :created_at_client => {:type => 'integer', :minimum => uid_from, :maximum => uid_to},
                                            # created at server - server number - 0 for current server - see also servers array for cross server messages
                                            :created_at_server => {:type => 'integer', :minimum => 0, :maximum => max_server_no},
                                            # optional new_deal boolean - true if commemt was created as a new deal proposal - false if comment
                                            :new_deal => {:type => %w(undefined boolean) },
                                            # optional new_deal_action. Only used for new deal proposals.
                                            :new_deal_action => {:type => %w(undefined string), :pattern => '^(cancel|accept|reject)$'},
                                            # optional new_deal_action user id, log in users for cancel, accept or reject action, subset of gift creator (accept, reject) or subset of comment creator (cancel)
                                            :new_deal_action_by_user_ids => {:type => %w(undefined array), :items => {:type => 'integer'}},
                                            # optional new_deal_action_at_client unix timestamp
                                            :new_deal_action_at_client => {:type => %w(undefined integer), :minimum => uid_from, :maximum => uid_to},
                                            # optional deleted at timestamp if comment has been deleted by giver, receiver or commenter
                                            :deleted_at_client => {:type => %w(undefined integer), :minimum => uid_from, :maximum => uid_to}
                                        }, # comment properties
                                        :required => %w(cid user_ids comment created_at_client created_at_server),
                                        :additionalProperties => false
                                    },
                                    :minItems => 1
                                }
                            }, # gift properties
                            :required => %w(gid giver_user_ids receiver_user_ids created_at_client created_at_server direction description),
                            :additionalProperties => false
                        },
                        :minItems => 1
                    },
                    # array with users used in gifts array without mutual users - used as fallback information in case of unknown users error on other client
                    :users => {
                        :type => 'array',
                        :items => {
                            :type => 'object',
                            # fields in user record (login user, friend etc)
                            :properties => {
                                # internal user id (sequence) - used in internal arrays
                                :user_id => {:type => %w(integer string) },
                                # provider unique user id - used in signatures and in communication between clients
                                :uid => {:type => 'string'},
                                # login provider - facebook, foursquare etc
                                :provider => {:type => 'string', :pattern => providers_pattern},
                                # full user name
                                :user_name => {:type => 'string'},
                                # url to profile picture
                                :api_profile_picture_url => {:type => 'string'}
                            },
                            :required => %w(user_id uid provider user_name),
                            :additionalProperties => false
                        }
                    },
                    # array with server sha256 signatures. Used when sending gifts to client on an other gofreerev server
                    # sha256 signatures added by sender - receiver must translate sha256 signatures to new internal server ids
                    :servers => {
                        :type => 'array',
                        :title => 'Array with sha256 signatures for internal server ids in send_gifts message',
                        :properties => {
                            # internal server ids used in send_gifts message
                            :server_id => { :type => 'integer', :minimum => 0},
                            # sha256 signature for server site_url.
                            :sha256 => { :type => 'string'}
                        },
                        :required => %w(server_id sha256),
                        :additionalProperties => false

                    }
                },
                :required => %w(mid msgtype gifts),
                :additionalProperties => false
            },

            # syn_gifts optional sub message 2 - request_gifts - request missing gifts from other client
            :request_gifts => {
                :type => 'object',
                :title => 'request_gifts sub message. Request missing gifts from other client',
                :properties => {
                    # mid - unique message id for sub message - js unix timestamp (10) with milliseconds (3) and random numbers (7) - total 20 decimals
                    :mid => {:type => 'string', :pattern => uid_pattern},
                    # msgtype = request_gifts
                    :msgtype => {:type => 'string', :pattern => '^request_gifts$'},
                    # array with gid's for missing gifts
                    :gifts => {
                        :type => 'array',
                        :items => {:type => 'string', :pattern => uid_pattern},
                        :minItems => 1
                    },
                    :required => %w(mid msgtype gifts),
                    :additionalProperties => false
                }
            },

            # syn_gifts optional sub message 3 - check_gifts - merge gifts - send array with gifts sub sha2546 values to other client
            :check_gifts => {
                :type => 'object',
                :title => 'check_gifts sub message. Send sha256 values for gift and comments to other client',
                :properties => {
                    # mid - unique message id for sub message - js unix timestamp (10) with milliseconds (3) and random numbers (7) - total 20 decimals
                    :mid => {:type => 'string', :pattern => uid_pattern},
                    # msgtype = check_gifts
                    :msgtype => {:type => 'string', :pattern => '^check_gifts$'},
                    # array with sub sha256 values for gifts - one sha256 for gift and an other sha256 value for comments
                    :gifts => {
                        :type => 'array',
                        :items => {
                            :type => 'object',
                            :properties => {
                                # gid - unique gift id - js unix timestamp (10) with milliseconds (3) and random numbers (7) - total 20 decimals
                                :gid => {:type => 'string', :pattern => uid_pattern},
                                # sha256 calculation for gift and comments
                                :sha256 => {:type => 'string', :maxLength => 32},
                                # sha256 calculation for gift only
                                :sha256_gift => {:type => 'string', :maxLength => 32},
                                # sha256 calculation for comments only
                                :sha256_comments => {:type => 'string', :maxLength => 32},
                                # optional array with sha256 signatures for comments. Used in check_gifts return message after receiving gift with changed sha256_comments signature
                                :comments => {
                                    :type => 'array',
                                    :properties => {
                                        # cid - unique comment id - js unix timestamp (10) with milliseconds (3) and random numbers (7) - total 20 decimals
                                        :cid => { :type => 'string', :pattern => uid_pattern},
                                        # sha256 calculation for comment
                                        :sha256 => {:type => 'string', :maxLength => 32}
                                    },
                                    :required => %w(cid sha256),
                                    :additionalProperties => false
                                }
                            },
                            :required => %w(gid sha256 sha256_gift sha256_comments),
                            :additionalProperties => false
                        },
                        :minItems => 1
                    },
                    :required => %w(mid msgtype gifts),
                    :additionalProperties => false
                }
            },

            # sync_gifts optional sub message 4 - request_comments - request missing comments from other client
            :request_comments => {
                :type => 'object',
                :title => 'request_comments sub message. Request missing comments from other client',
                :properties => {
                    # mid - unique message id for sub message - js unix timestamp (10) with milliseconds (3) and random numbers (7) - total 20 decimals
                    :mid => {:type => 'string', :pattern => uid_pattern},
                    # msgtype = request_gifts
                    :msgtype => {:type => 'string', :pattern => '^request_comments$'},
                    # array with cid's for missing comments
                    :comments => {
                        :type => 'array',
                        :items => {:type => 'string', :pattern => uid_pattern},
                        :minItems => 1
                    },
                    :required => %w(mid msgtype comments),
                    :additionalProperties => false
                }
            },

            # syn_gifts optional sub message 5 - gifts with errors - received one or more new gifts in incoming send_gifts message with errors
            # other client should verify gift signatures (sha256, sha256_action and sha256_deleted), report any error (log & notification) and optional uncreate, unaccept or undelete gift
            :invalid_gifts => {
                :type => 'object',
                :title => 'invalid_gifts sub message. Return errors from gifts in send_gifts message to other client',
                :properties => {
                    # mid - unique message id for sub message - js unix timestamp (10) with milliseconds (3) and random numbers (7) - total 20 decimals
                    :mid => {:type => 'string', :pattern => uid_pattern},
                    # msgtype = check_gifts
                    :msgtype => {:type => 'string', :pattern => '^invalid_gifts$'},
                    # array with invalid gift errors
                    :gifts => {
                        :type => 'array',
                        :title => 'invalid_gifts sub message. Return send_gift processing errors to other client',
                        :items => {
                            :type => 'object',
                            :properties => {
                                :gid => { :type => 'string', :pattern => uid_pattern },
                                # gift processing error message
                                # either a string - english only error message - used for cross server error messages
                                # or an object with :key and :options - multi-language support - used for within server error messages
                                :error => {
                                    :type => %w(string object),
                                    :properties => {
                                        :key => { :type => 'string'},
                                        :options => { :type => 'object'}
                                    },
                                    :required => %w(key),
                                    :additionalProperties => false
                                }
                            },
                            :required => %w(gid error),
                            :additionalProperties => false
                        },
                        :minItems => 1
                    },
                }
            },

            # syn_gifts optional sub message 6 - comments with invalid signature - received one or more new comments in incoming send_gifts message with invalid sha256 signatures
            # other client should recheck comment signatures (sha256, sha256_action and sha256_deleted), report any error (log & notification) and optional uncreate, unaction or undelete comment
            # todo: add object with mid, msgtype etc?
            :invalid_comments => {
                :type => 'array',
                :title => 'invalid_gifts sub message. Return send_gift processing errors to other client',
                :items => {
                    :type => 'object',
                    :properties => {
                        :cid => { :type => 'string', :pattern => uid_pattern },
                        # comment processing error message
                        # either a string - english only error message - used for cross server error messages
                        # or an object with :key and :options - multi-language support - used for within server error messages
                        :error => {
                            :type => %w(string object),
                            :properties => {
                                :key => { :type => 'string'},
                                :options => { :type => 'object'}
                            },
                            :required => %w(key),
                            :additionalProperties => false
                        }
                    },
                    :required => %w(gid error),
                    :additionalProperties => false
                },
                :minItems => 1
            }
        },
        :required => %w(mid request_mid msgtype mutual_friends),
        :additionalProperties => false
    },

}