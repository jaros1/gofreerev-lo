# validate json request/response with json schemas
# server side: https://github.com/ruby-json-schema/json-schema
# client side: https://github.com/geraintluff/tv4

# helper expression for gid, sid, cid etc (20 decimal string). To big to be a JS integer. From 2015-01-01 and one year forward in time
uid_from = (Time.zone.parse '2015-01-01').to_i
uid_to = 1.year.from_now.to_i
uid_short_pattern = `rgxg range -Z #{uid_from} #{uid_to}`.strip
uid_pattern = "^#{uid_short_pattern}[0-9]{10}$"

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
users_type = {
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
            :friend => {:type => 'integer', :minimum => 1, :maximum => 8}
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
        :properties => {
            # client userid normally = 1. Allow up to 100 user accounts in localStorage
            :client_userid => client_userid_type,
            # client unix timestamp (10) with milliseconds (3) - total 13 decimals
            :client_timestamp => client_timestamp_type,
            # client secret - string with 10 decimals - used in device.sha256 signature
            :client_secret => {:type => 'string'},
            # did - unique device id - js unix timestamp (10) with milliseconds (3) and random numbers (7) - total 20 decimals
            :did => {:type => 'string', :pattern => uid_pattern},
            # pubkey key for unique device - used in encrypted client to client information replication
            :pubkey => {:type => 'string'},
            # array with oauth authorization for zero, one or more social networks (from localStorage)
            :oauths => oauths_type
        },
        :required => %w(client_userid client_timestamp client_secret did pubkey oauths),
        :additionalProperties => false
    },
    :login_response => {
        :type => 'object',
        :properties => {
            # array with login user and friends information (friends etc). from api friend lists
            :users => users_type,
            # optional array with providers with expired oauth authorization
            :expired_tokens => expired_tokens_type,
            # optional array with new oauth authorization - for now only used for google+
            :oauths => oauths_type,
            # optional error message from login
            :error => {:type => 'string'}
        },
        :required => %w(users),
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
            # Timezone offset in hours. todo: remove - all dates should be formatted with javascript, not rails
            :timezone => {:type => 'number', :minimum => -12, :maximum => 14},
            # client secret - string with 10 decimals - used in device.sha256 signature
            :client_secret => {:type => 'string'}
        },
        :required => %w(client_userid timezone client_secret),
        :additionalProperties => false
    },
    :do_tasks_response => {
        :type => 'object',
        :properties => {
            # optional array with new oauth authorization to client (temporary stored in server session after api omniauth login
            :oauths => oauths_type,
            # array with login user and friends information (friends etc). from api friend lists
            :users => users_type,
            # optional error message from do_tasks
            :error => {:type => 'string'}
        },
        :additionalProperties => false
    },

    # ping request/response is the central message used in synchronization of information between servers and clients
    # number of pings per time period are regulated after average server load
    # client pings are distributed equally over time
    :ping_request =>
        {:type => 'object',
         :properties =>
             {# client userid normally = 1. Allow up to 100 user accounts in localStorage
              :client_userid => client_userid_type,
              # client unix timestamp (10) with milliseconds (3) - total 13 decimals
              :client_timestamp => client_timestamp_type,
              # sid - unique session id - js unix timestamp (10) with milliseconds (3) and random numbers (7) - total 20 decimals
              :sid => {:type => 'string', :pattern => uid_pattern},
              # new_gifts - optional array with minimal meta-information for new gifts (gid, sha256 and user ids) -
              # login users and creators of gifts must be identical - gift is always created on this server
              :new_gifts => {
                  :type => 'array',
                  :items => {
                      :type => 'object',
                      :properties => {
                          # gid - unique gift id - js unix timestamp (10) with milliseconds (3) and random numbers (7) - total 20 decimals
                          :gid => {:type => 'string', :pattern => uid_pattern},
                          # sha256 digest of client side gift information (created at client + description + 4 open graph fields)
                          :sha256 => {:type => 'string', :maxLength => 32},
                          # internal user ids for either giver or receiver - todo: change to uid/provider format to support cross server replication?
                          :giver_user_ids => {:type => 'array', :items => {:type => 'integer'}},
                          :receiver_user_ids => {:type => 'array', :items => {:type => 'integer'}}
                      },
                      :required => %w(gid sha256),
                      :additionalProperties => false}
              },
              # new_comments - optional array with minimal meta-information for new comments (cid, sha256 and user ids)
              :new_comments => {
                  :type => 'array',
                  :items => {
                      :type => 'object',
                      :properties => {
                          # cid - unique comment id - js unix timestamp (10) with milliseconds (3) and random numbers (7) - total 20 decimals
                          :cid => {:type => 'string', :pattern => uid_pattern},
                          # sha256 digest of client side comment information (unique gift id, created at client unix timestamp, comment, price and currency)
                          :sha256 => {:type => 'string', :maxLength => 32},
                          # internal user ids for creator of comment (=login users) - todo: change to uid/provider format to support cross server replication?
                          :user_ids => {:type => 'array', :items => {:type => 'integer'}}
                      },
                      :required => %w(cid sha256 user_ids),
                      :additionalProperties => false}
              },
              # verify_gifts - optional array used when verifying gifts received from other device - check server sha256 signature created in a previous new_gifts request
              # gift must be from a friend - gift can be from an other gofreerev server
              :verify_gifts => {
                  :type => 'array',
                  :items => {
                      # unique seq returned in response (gid is not guaranteed to be unique when receiving gifts from other devices)
                      :seq => {:type => 'integer'},
                      # gid - unique gift id - js unix timestamp (10) with milliseconds (3) and random numbers (7) - total 20 decimals
                      :gid => {:type => 'string', :pattern => uid_pattern},
                      # sha256 digest of client side gift information (created at client + description + 4 open graph fields)
                      :sha256 => {:type => 'string', :maxLength => 32},
                      # internal user ids for either giver or receiver - todo: change to uid/provider format to support cross server replication?
                      :giver_user_ids => {:type => 'array', :items => {:type => 'integer'}},
                      :receiver_user_ids => {:type => 'array', :items => {:type => 'integer'}}
                  },
                  :required => %w(seq gid sha256),
                  :additionalProperties => false
              },
              # verify_comments - optional array used when verifying comments received from other devices. check server sha256 signature created in a previous new_comments request
              :verify_comments => {
                  :type => 'array',
                  :items => {
                      :type => 'object',
                      :properties => {
                          # unique seq returned in response (cid is not guaranteed to be unique when receiving comments from other devices)
                          :seq => {:type => 'integer'},
                          # cid - unique comment id - js unix timestamp (10) with milliseconds (3) and random numbers (7) - total 20 decimals
                          :cid => {:type => 'string', :pattern => uid_pattern},
                          # sha256 digest of client side comment information (unique gift id, created at client unix timestamp, comment, price and currency)
                          :sha256 => {:type => 'string', :maxLength => 32},
                          # internal user ids for creator of comment (=login users) - todo: change to uid/provider format to support cross server replication?
                          :user_ids => {:type => 'array', :items => {:type => 'integer'}}
                      },
                      :required => %w(seq cid sha256 user_ids),
                      :additionalProperties => false}
              },
              # pubkeys - optional array with did (unique device id) - request public key for other client before starting client to client communication
              :pubkeys => {:type => 'array',
                           :items => {:type => 'string', :pattern => uid_pattern}},
              # refresh_tokens - google+ only - optional array with refresh tokens to be used when refreshing expired access token
              :refresh_tokens => {
                  :type => 'array',
                  :items => {
                      :type => 'object',
                      :properties => {
                          :provider => {:type => 'string', :pattern => providers_pattern},
                          :access_token => {:type => 'string'}
                      }
                  }
              },
              # array with encrypted messages from client to other devices (users_sha256, todo: gifts_sha256, gifts etc)
              # temporary buffer on server until message is delivered or message is expired/too old
              :messages => {
                  :type => 'array',
                  :items => {
                      :type => 'object',
                      :properties => {
                          # receiver did - unique device id - js unix timestamp (10) with milliseconds (3) and random numbers (7) - total 20 decimals
                          :receiver_did => {:type => 'string', :pattern => uid_pattern},
                          # receiver sha256 signature for generated from client secret and login user ids. used in client to client communication
                          :receiver_sha256 => {:type => 'string'},
                          # public/private key encryption (rsa) or symmetric key encryption? start with rsa and continue with symmetric
                          :encryption => {:type => 'string', :pattern => '^(rsa|sym)$'},
                          # message for receiver device encrypted with device public key
                          :message => {:type => 'string'}
                      },
                      :required => %w(receiver_did receiver_sha256 encryption message),
                      :additionalProperties => false
                  }

              }
             },
         :required => %w(client_userid client_timestamp sid),
         :additionalProperties => false
        },
    :ping_response =>
        {:type => 'object',
         :properties =>
             {# client unix timestamp (10) with milliseconds (3) for previous ping request from same unique device (did or session_id + user_clientid)
              :old_client_timestamp => client_timestamp_type,
              # interval in milliseconds before next ping request from client. used when distribution client pings equal over time
              :interval => {:type => 'integer', :minimum => 1000},
              # array with online friends/devices - tells the client which devices are available for information synchronization
              :online => {
                  :type => 'array',
                  :items => {
                      :type => 'object',
                      :properties => {
                          # unique device id for other online device available for information synchronization
                          :did => {:type => 'string', :pattern => uid_pattern},
                          # sha256 signature for device generated from client secret and login user ids. used in client to client communication
                          :sha256 => {:type => 'string'},
                          # array with internal user ids for mutual friends - synchronize information for mutual friends between clients
                          :mutual_friends => {:type => 'array', :items => {:type => 'integer'}}
                      },
                      :required => %w(did sha256 mutual_friends),
                      :additionalProperties => false
                  }},
              # optional - return fatal errors to client (invalid json request)
              :error => {:type => 'string'},
              # optional array with created_at_server timestamps (or error messages) response for new_gifts request
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
                                  :gid => {:type => 'string', :pattern => uid_pattern},
                                  # error message if signature for gift could not be saved on server
                                  :error => {:type => 'string'},
                                  # ok - created at server unix timestamp - 10 decimals - gift signature was saved on server
                                  :created_at_server => {:type => 'integer', :minimum => uid_from, :maximum => uid_to}
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
              # object and array with created_at_server timestamps (or error messages) response for new_comments request
              :new_comments => {
                  :type => 'object',
                  :properties => {
                      # any generic error message when processing of new_comments request. see also error property in data array
                      :error => {:type => 'string'},
                      # array with created_at_server timestamps or error messages for each cid in new_comments request
                      :data => {
                          :type => 'array',
                          :items => {
                              :type => 'object',
                              :properties => {
                                  # required unique comment id from new_comments request
                                  :cid => {:type => 'string', :pattern => uid_pattern},
                                  # error message if signature for comment could not be saved on server
                                  :error => {:type => 'string'},
                                  # ok - created at server unix timestamp - 10 decimals - comment signature was saved on server
                                  :created_at_server => {:type => 'integer', :minimum => uid_from, :maximum => uid_to}
                              },
                              :required => %w(cid),
                              :additionalProperties => false
                          }
                      },
                      # optional number of errors returned in data array
                      :no_errors => {:type => 'integer'}
                  },
                  :additionalProperties => false
              },
              # optional array with created_at_server timestamps or null (error) response for verify_gifts request
              :verify_gifts => {
                  :type => 'object',
                  :properties => {
                      # array with created_at_server timestamps or null for row in verify_gifts request
                      :data => {
                          :type => 'array',
                          :items => {
                              :type => 'object',
                              :properties => {
                                  # unique seq from verify_gifts request (gid is not guaranteed to be unique when receiving gifts from other devices)
                                  :seq => {:type => 'integer'},
                                  # gid - unique gift id - from verify_gifts request
                                  :gid => {:type => 'string', :pattern => uid_pattern},
                                  # created_at_server unix timestamp or null (error)
                                  :created_at_server => {:type => 'integer', :minimum => uid_from, :maximum => uid_to}
                              },
                              :required => %w(seq gid),
                              :additionalProperties => false
                          }
                      }
                  },
                  :additionalProperties => false
              },
              # optional array with created_at_server timestamps or null (error) response for verify_comments request
              :verify_comments => {
                  :type => 'object',
                  :properties => {
                      # array with created_at_server timestamps or null for row in verify_comments request
                      :data => {
                          :type => 'array',
                          :items => {
                              :type => 'object',
                              :properties => {
                                  # unique seq from verify_comments request (cid is not guaranteed to be unique when receiving comments from other devices)
                                  :seq => {:type => 'integer'},
                                  # cid - unique comment id - from verify_comments request
                                  :cid => {:type => 'string', :pattern => uid_pattern},
                                  # created_at_server unix timestamp or null (error)
                                  :created_at_server => {:type => 'integer', :minimum => uid_from, :maximum => uid_to}
                              },
                              :required => %w(seq cid),
                              :additionalProperties => false
                          }
                      }
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
                          :did => {:type => 'string', :pattern => uid_pattern},
                          # public key or null if unknown did
                          :pubkey => {:type => 'string'}
                      },
                      :required => %w(did),
                      :additionalProperties => false
                  }
              },
              # optional array with providers with expired oauth authorization
              :expired_tokens => expired_tokens_type,
              # optional array with new oauth authorization - for now only used for google+
              :oauths => oauths_type,
              # array with encrypted messages to client from other devices (users_sha256, todo: gifts_sha256, gifts etc)
              # temporary buffered on server until message was delivered or message was expired/too old
              :messages => {
                  :type => 'array',
                  :items => {
                      :type => 'object',
                      :properties => {
                          # receiver did - unique device id - js unix timestamp (10) with milliseconds (3) and random numbers (7) - total 20 decimals
                          :sender_did => {:type => 'string', :pattern => uid_pattern},
                          # receiver sha256 signature for generated from client secret and login user ids. used in client to client communication
                          :sender_sha256 => {:type => 'string'},
                          # public/private key encryption (rsa) or symmetric key encryption? start with rsa and continue with symmetric
                          :encryption => {:type => 'string', :pattern => '^(rsa|sym)$'},
                          # when was message received from other device - unix timestamp
                          :created_at_server => {:type => 'integer', :minimum => 1.month.ago.to_i, :maximum => 1.year.from_now.to_i},
                          # message for receiver device encrypted with device public key
                          :message => {:type => 'string'}
                      },
                      :required => %w(sender_did sender_sha256 created_at_server message),
                      :additionalProperties => false
                  }

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
    }

    # device to device communication (server spec)

    # device to device communication (client spec)
}