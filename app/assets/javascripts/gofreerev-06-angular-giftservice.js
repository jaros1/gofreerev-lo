// Gofreerev angularJS code

angular.module('gifts')
    .factory('GiftService', ['TextService', 'NotiService', 'UserService', function(textService, notiService, userService) {
        var self = this;
        var service = 'GiftService';
        console.log(service + ' loaded');

        // cache nid for repeating errors without an object (gift, comment, user etc). for example nid for system errors.
        // nid is used as message folder in notifications
        var cache_nid = {} ;

        // todo: add comment validations.
        // - invalid_comment is called from create_new_comment, when receiving new comments from other clients and before sending comments to other clients
        // - invalid_comment_change is called in any local updates and when merging comment information from other clients into local comment
        // new_users is an optional array with new users (used when validating new gifts received from other clients)
        // context - validating context - create, receive, send - not all validations are relevant in all contexts
        // server_id - mailbox.server_id - null for within server messages - >0 for messages to/from clients on other gofreerev servers
        var invalid_comment = function (comment, new_users, context, server_id) {
            var pgm = service + '.invalid_comment: ' ;
            var errors = [] ;
            // fields to validate:
            // -  1) cid - unique comment id - js unix timestamp (10) with milliseconds (3) and random numbers (7) - total 20 decimals
            // -  2) user_ids - internal user ids for creator of comment - todo: change to uid/provider format to support cross server replication?
            // -  3) price - optional price - can be set when creation a proposal (new_deal = true) comment) for gift/offer
            // -  4) currency - optional currency - can be set when creation a proposal (new_deal = true) for gift/offer - iso4217 with restrictions
            // -  5) comment
            // -  6) created_at_client - created at client unix timestamp - 10 decimals - used in comment signature on server
            // -  7) created_at_server - server number - 0 for current server - see also servers array for cross server messages
            // -  8) likes - array with likes from friends. boolean in message. array in localStorage / JS
            // -  9) new_deal- optional new_deal boolean - true if commemt was created as a new deal proposal - false if comment
            // - 10) new_deal_action - optional new_deal_action. Only used for new deal proposals.
            // - 11) new_deal_action_by_user_ids - optional new_deal_action user id, log in users for cancel, accept or reject action, subset of gift creator (accept, reject) or subset of comment creator (cancel)
            // - 12) new_deal_action_at_client - optional new_deal_action_at_client unix timestamp
            // - 13) deleted_at_client - optional deleted at timestamp if comment has been deleted by giver, receiver or commenter

            // new_users from send_gifts sub message (sync_gifts) - fallback information used in case of unknown user
            var new_users_index = {} ;
            for (var i=0 ; i<new_users.length ; i++) new_users_index[new_users[i].user_id] = new_users[i] ;
            console.log(pgm + 'new_users_index = ' + JSON.stringify(new_users_index)) ;
            if (new_users.length > 0) {
                if (['send','receive'].indexOf(context) == -1) errors.push('System error. Invalid "invalid_comment" call. new_users parameter should only be used when sending to and receiving gifts from other clients') ;
            };
            // context: create, send or receive
            if (['load', 'create', 'send', 'receive'].indexOf(context) == -1) errors.push('System error. Invalid "invalid_comment" call. context was ' + context + '. context must be load, create, send or receive') ;
            // server_id - mailbox.server_id - must be undefined, null or an integer > 0
            if ((typeof server_id == 'undefined') || (server_id == null) || ((typeof server_id == 'number') && (server_id >= 1) && (server_id == Math.round(server_id)))) ; // empty
            else errors.push('System error. Invalid "invalid_comment" call. server_id (mailbox.server_id) must be null or an integer >= 1') ;
            
            // -  1) cid - unique comment id - js unix timestamp (10) with milliseconds (3) and random numbers (7) - total 20 decimals
            var from_unix_timestamp = Math.floor((new Date('2014-01-01')).getTime()/1000) ;
            var to_unix_timestamp =  Math.floor((new Date).getTime()/1000) + 24*60*60;
            if (!comment.hasOwnProperty('cid')) errors.push('Required cid (unique comment id) is missing') ;
            else if (typeof comment.cid != 'string') errors.push('Invalid cid (unique comment id). Cid must be a string with 20 digits') ;
            else if (!comment.cid.match(/^[0-9]{20}$/)) errors.push('Invalid cid (unique comment id). Cid must be a string with 20 digits') ;
            else if (parseInt(comment.cid.substr(0,10)) < from_unix_timestamp) errors.push('Invalid cid (unique comment id). The first 10 digits must be a valid unix timestamp') ;
            else if (parseInt(comment.cid.substr(0,10)) > to_unix_timestamp) errors.push('Invalid cid (unique comment id). The first 10 digits must be a valid unix timestamp') ;
            
            // -  2) user_ids - internal user ids for creator of comment
            // - normally from a friend or from a friend of other part in a closed deal
            // - can also be from "unknown" users from other api providers (friend with other api provider logins)

            var user_ids, providers, user_id, user ;
            var logged_in_user = false ;
            var friend = false ;
            if (!comment.hasOwnProperty(('user_ids') || comment.user_ids.length == 0)) errors.push('Comment without user ids is not allowed') ;
            else {
                user_ids = [] ;
                providers = [] ;
                for (i=0 ; i<comment.user_ids.length ; i++) {
                    user_id = comment.user_ids[i] ;
                    if (user_ids.indexOf(user_id) != -1) {
                        errors.push('User ids is invalid. Doublet user ids in ' + comment.user_ids.join(', ')) ;
                        break ;
                    }
                    // lookup user: 1) friends array, 2) users array, 3) new_users array
                    user = userService.get_friend(user_id) ;
                    if (!user) user = userService.get_user(user_id) ;
                    if (!user) user = new_users_index[user_id] ;
                    if (!user) {
                        errors.push('User is invalid. Unknown user id ' + user_id + ' in user_ids ' + comment.user_ids.join(', ')) ;
                        break ;
                    }
                    if (providers.indexOf(user.provider) != -1) {
                        errors.push('User ids is invalid. Doublet provider in user_ids' + comment.user_ids.join(', ')) ;
                        break ;
                    }
                    providers.push(user.provider) ;
                    if (user.hasOwnProperty('friend')) {
                        if (user.friend == 1) logged_in_user = true ;
                        if (user.friend <= 2) friend = true ;
                    }
                } // for i
            } // if

            // -  3) price - optional price - can be set when creation a proposal (special comment) for gift/offer
            //  {:type => %w(undefined number), :minimum => 0, :multipleOf => 0.01 },
            // console.log(pgm + 'price = ' + comment.price + ', typeof price = ' + typeof comment.price) ;
            if (typeof comment.price == null) delete comment.price ;
            if ((typeof comment.price != 'undefined') && (comment.price != null)) {
                if (typeof comment.price != 'number') errors.push('Price is invalid. Must be an number >= 0') ;
                else if (comment.price < 0) errors.push('Price is invalid. Must be an number >= 0') ;
                else if (comment.price != Math.round(comment.price, 2)) errors.push('Price is invalid. Max 2 decimals are allowed in prices') ;
            }
            
            // -  4) currency - optional currency - can be set when creation a proposal (new_deal = true) for gift/offer - iso4217 with restrictions
            // Gofreerev.rails['VALID_CURRENCIES'] is a list with currencies from country to currency hash (from money gem)
            // not all currencies in list is active and not all currencies have exchange rates from default money bank
            // validate currency iso4217 only when creating comment.
            // dont validate when sending/receiving comments. Is readonly. Use verify_comment when receiving comments
            // (list with valid iso4217 can change over time and can be different on different Gofreerev servers)
            if ((typeof comment.price == 'number') && (!comment.hasOwnProperty('currency'))) errors.push('Required currency is missing') ;
            if (comment.hasOwnProperty('currency')) {
                if (typeof comment.currency != 'string') errors.push('Currency is invalid. Must be a 3 letters string with valid iso4217 currency code') ;
                else if (!comment.currency.match(/^[a-z]{3}$/)) errors.push('Currency is invalid. Must be a 3 letters string with valid iso4217 currency code') ;
                else if ((context == 'create') && (Gofreerev.rails['VALID_CURRENCIES'].indexOf(comment.currency) == -1)) errors.push('Unknown currency ' + comment.currency) ;
            }
            
            // -  5) comment - required
            if ((typeof comment.comment != 'string') || (comment.comment == '')) errors.push('Required comment is missing') ;

            // -  6) created_at_client - created at client unix timestamp - 10 decimals - used in comment signature on server
            if (!comment.created_at_client) errors.push('Required created_at_client unix timestamp is missing') ;
            else if (comment.created_at_client < from_unix_timestamp) errors.push('Invalid created_at_client unix timestamp') ;
            else if (comment.created_at_client > to_unix_timestamp) errors.push('Invalid created_at_client unix timestamp') ;

            // -  7) created_at_server - server number - 0 for current server -  >0 for comments from other Gofreerev servers
            // blank when creating comment, 0 when server signature for comment has been created
            if (!comment.hasOwnProperty('created_at_server') || (comment.created_at_server == null)) {
                // must be a newly created comment waiting for server signature
                if (['load','create'].indexOf(context) == -1) errors.push('Created_at_server is missing') ;
            }
            else if ((typeof comment.created_at_server != 'number') && (comment.created_at_server < 0) && (Math.round(comment.created_at_server) != comment.created_at_server)) {
                errors.push('Created_at_server is invalid. Must be null or an integer >= 0') ;
            }
            else {
                if (context == 'create') errors.push('Created_at_server is invalid. Must be null when creating a new comment') ;
            }

            // -  8) todo: likes - array with likes from friends. boolean in message. array in localStorage / JS

            // -  9) new_deal- optional new_deal boolean - true if commemt was created as a new deal proposal - null or false if comment
            if ((typeof comment.new_deal != 'undefined') && (comment.new_deal != null) && (typeof comment.new_deal != 'boolean')) {
                errors.push('new_deal is invalid. Must be null or a boolean') ;
            }

            // 10), 11) and 12). validate three additional new_deal fields (new_deal_action, new_deal_action_by_user_ids and deal_action_at_client)
            if (comment.new_deal == true) {
                // new deal proposal.

                // the three new_deal fields must all be null or must all have valid values
                if (((typeof comment.new_deal_action == 'undefined') || (comment.new_deal_action == null)) &&
                    ((typeof comment.new_deal_action_by_user_ids == 'undefined') || (comment.new_deal_action_by_user_ids == null)) &&
                    ((typeof comment.new_deal_action_at_client == 'undefined') || (comment.new_deal_action_at_client == null))) {
                    // no new_deal_action
                    ; // empty
                }
                else {
                    // new_deal_action
                    // - 10) new_deal_action - optional new_deal_action. Only used for new deal proposals (new_deal = true)
                    if ((typeof comment.new_deal_action == 'undefined') || (comment.new_deal_action == null)) errors.push('new_deal_action is missing') ;
                    else if ((typeof comment.new_deal_action != 'string') || (['cancel','accept','reject'].indexOf(comment.new_deal_action) == -1)) {
                        errors.push('new_deal_action is invalid. Allowed values are cancel, accept or reject') ;
                    }
                    // - 11) new_deal_action_by_user_ids - optional new_deal_action user id, log in users for cancel, accept or reject action, subset of gift creator (accept, reject) or subset of comment creator (cancel)
                    if ((typeof comment.new_deal_action_by_user_ids == 'undefined') || (comment.new_deal_action_by_user_ids == null)) errors.push('new_deal_action_by_user_ids is missing') ;
                    else if ((!$.isArray(comment.new_deal_action_by_user_ids)) || (comment.new_deal_action_by_user_ids.length == 0)) errors.push('new_deal_action_by_user_ids is invalid. Must be null or an not empty array');
                    // - 12) new_deal_action_at_client - optional new_deal_action_at_client unix timestamp
                    if ((typeof comment.new_deal_action_at_client == 'undefined') || (comment.new_deal_action_at_client == null)) errors.push('new_deal_action_at_client is missing') ;
                    else if (comment.new_deal_action_at_client < from_unix_timestamp) errors.push('Invalid new_deal_action_at_client unix timestamp') ;
                    else if (comment.new_deal_action_at_client > to_unix_timestamp) errors.push('Invalid new_deal_action_at_client unix timestamp') ;
                }

            }
            else {
                // comment.

                // - 10) new_deal_action must be null
                if ((typeof comment.new_deal_action != 'undefined') && (comment.new_deal_action != null)) {
                    errors.push('new_deal_action is invalid. Must be null for comments') ;
                }
                // - 11) new_deal_action_by_user_ids must be null
                if ((typeof comment.new_deal_action_by_user_ids != 'undefined') && (comment.new_deal_action_by_user_ids != null)) {
                    errors.push('new_deal_action_by_user_ids is invalid. Must be null for comments') ;
                }
                // - 12) new_deal_action_at_client must be null
                if ((typeof comment.new_deal_action_at_client != 'undefined') && (comment.new_deal_action_at_client != null)) {
                    errors.push('new_deal_action_at_client is invalid. Must be null for comments') ;
                }
            }

            if (errors.length > 0) {
                console.log(pgm + 'Error for comment ' + JSON.stringify(comment)) ;
                console.log(pgm + 'Error: ' + errors.join('. ')) ;
                return errors.join('. ') ;
            }
            else return null ;

        };
        var invalid_comment_change = function (old_comment, new_comment) {
            var pgm = service + '.invalid_changed_comment: ' ;
            console.log(pgm + 'Not implemented') ;
            return null ;
        };

        // todo: add gift validations.
        // - invalid_gift is called from create_new_gift, when receiving new gifts from other clients and before sending gifts to other clients
        // - invalid_gift_change is called in any local updates and when merging gift information from other clients into local gift
        // new_users is an optional array with new users (used when validating new gifts received from other clients)
        // context: "load" : loaded from localStorage, "create" : create gift on this client, "receive" : receive gift from other client or "send" : send gift to other client
        // mailbox: used when sending/receiving messages.
        // - mailbox.server_id. null for within server messages. >0 for messages to/from other Gofreerev servers
        // - mailbox.mutual_friends. gift must be from mailbox.mutual_friends when sending and receiving messages to/from other clients
        var invalid_gift = function (gift, new_users, context, mailbox) {
            var pgm = service + '.invalid_gift: ' ;
            var errors = [] ;
            // fields to validate:
            //  1) gid - unique gift id - js unix timestamp (10) with milliseconds (3) and random numbers (7) - total 20 decimals
            //  2) giver_user_ids and/or receiver_user_ids
            //  3) created_at_client unix timestamp - 10 decimals - used in gift signature on server
            //  4) created_at_server - null or an integer - 0 for current server - >0 for gifts from other Gofreerev servers
            //  5) price => {:type => %w(undefined number), :minimum => 0, :multipleOf => 0.01 },
            //  6) currency: optional currency - set when gift is created or when gift is accepted by a friend - iso4217 with restrictions
            //  7) direction: giver or receiver (creator of gift)
            //  8) description   :description => {:type => 'string'},
            //  9) open_graph_url => {:type => %w(undefined string) },
            // 10) open_graph_title => {:type => %w(undefined string) },
            // 11) open_graph_description => {:type => %w(undefined string) },
            // 12) open_graph_image => {:type => %w(undefined string) },
            // 13) like - todo: must be changed to an array with user ids and like/unlike timestamps
            // 14) deleted_at_client => {:type => %w(undefined integer), :minimum => uid_from, :maximum => uid_to},
            // 15) accepted_cid => {:type => %w(undefined string), :pattern => uid_pattern},
            // 16) accepted_at_client => {:type => %w(undefined integer), :minimum => uid_from, :maximum => uid_to},
            // 17) comments array
            
            // new_users from send_gifts sub message (sync_gifts) - fallback information used in case of unknown user
            var new_users_index = {} ;
            for (var i=0 ; i<new_users.length ; i++) new_users_index[new_users[i].user_id] = new_users[i] ;
            console.log(pgm + 'new_users_index = ' + JSON.stringify(new_users_index)) ;

            if (['load', 'create', 'send', 'receive'].indexOf(context) == -1) {
                return 'System error when calling invalid_gifts. Invalid context parameter. Must be load, create, send or receive. Was ' + context ;
            };
            if ((['load','create'].indexOf(context) != -1) && mailbox) {
                return 'System error when calling invalid_gifts. Mailbox parameter must be null for context load and create' ;
            };
            if ((['send', 'receive'].indexOf(context) != -1) && !mailbox) {
                return 'System error when calling invalid_gifts. Mailbox parameter is missing for context send or receive' ;
            };

            // mailbox & server_id
            var server_id ;
            if (mailbox) server_id = mailbox.server_id ;
            else server_id = null ;

            //  1) gid - unique gift id - js unix timestamp (10) with milliseconds (3) and random numbers (7) - total 20 decimals
            var from_unix_timestamp = Math.floor((new Date('2014-01-01')).getTime()/1000) ;
            var to_unix_timestamp =  Math.floor((new Date).getTime()/1000) + 24*60*60;
            if (!gift.gid) errors.push('Required gid (unique gift id) is missing') ;
            else if (typeof gift.gid != 'string') errors.push('Invalid gid (unique gift id). Gid must be a string with 20 digits') ;
            else if (!gift.gid.match(/^[0-9]{20}$/)) errors.push('Invalid gid (unique gift id). Gid must be a string with 20 digits') ;
            else if (parseInt(gift.gid.substr(0,10)) < from_unix_timestamp) errors.push('Invalid gid (unique gift id). The first 10 digits must be a valid unix timestamp') ;
            else if (parseInt(gift.gid.substr(0,10)) > to_unix_timestamp) errors.push('Invalid gid (unique gift id). The first 10 digits must be a valid unix timestamp') ;

            //  2) giver_user_ids and/or receiver_user_ids
            // must be in friends, in users or in new_users JS arrays
            // gift must be from a mutual friend
            var giver_user_ids = gift.giver_user_ids || [] ;
            var receiver_user_ids = gift.receiver_user_ids || [] ;
            if ((giver_user_ids.length == 0) && (receiver_user_ids.length ==0)) errors.push('Gift without giver or receiver is not allowed') ;
            var user_ids, providers, user_id, user ;
            user_ids = [] ;
            providers = [] ;
            var logged_in_user = false ;
            var friend = false ;
            var in_mutual_friends = false ;
            for (i=0 ; i<giver_user_ids.length ; i++) {
                user_id = giver_user_ids[i] ;
                if (user_ids.indexOf(user_id) != -1) {
                    errors.push('Giver is invalid. Doublet user ids in giver_user_ids' + giver_user_ids.join(', ')) ;
                    break ;
                }
                user_ids.push(user_id) ;
                // lookup user: 1) friends array, 2) users array, 3) new_users array
                user = userService.get_friend(user_id) ;
                if (!user) user = userService.get_user(user_id) ;
                if (!user) user = new_users_index[user_id] ;
                if (!user) {
                    errors.push('Giver is invalid. Unknown user id ' + user_id + ' in giver_user_ids ' + giver_user_ids.join(', ')) ;
                    break ;
                }
                if (providers.indexOf(user.provider) != -1) {
                    errors.push('Giver is invalid. Doublet provider in giver_user_ids' + giver_user_ids.join(', ')) ;
                    break ;
                }
                providers.push(user.provider) ;
                if (user.hasOwnProperty('friend')) {
                    if (user.friend == 1) logged_in_user = true ;
                    if (user.friend <= 2) friend = true ;
                };
                if ((['send','receive'].indexOf(context) != -1) && (mailbox.mutual_friends.indexOf(user_id) != -1)) in_mutual_friends = true ;
            } // for i
            user_ids = [] ;
            providers = [] ;
            for (i=0 ; i<receiver_user_ids.length ; i++) {
                user_id = receiver_user_ids[i] ;
                if (user_ids.indexOf(user_id) != -1) {
                    errors.push('Receiver is invalid. Doublet user ids in receiver_user_ids' + receiver_user_ids.join(', ')) ;
                    break ;
                }
                // lookup user: 1) friends array, 2) users array, 3) new_users array
                user = userService.get_friend(user_id) ;
                if (!user) user = userService.get_user(user_id) ;
                if (!user) user = new_users_index[user_id] ;
                if (!user) {
                    errors.push('Receiver is invalid. Unknown user id ' + user_id + 'in receiver_user_ids' + receiver_user_ids.join(', ')) ;
                    break ;
                }
                if (providers.indexOf(user.provider) != -1) {
                    errors.push('Receiver is invalid. Doublet provider in receiver_user_ids' + receiver_user_ids.join(', ')) ;
                    break ;
                }
                providers.push(user.provider) ;
                if (user.hasOwnProperty('friend')) {
                    if (user.friend == 1) logged_in_user = true ;
                    if (user.friend <= 2) friend = true ;
                };
                if ((['send','receive'].indexOf(context) != -1) && (mailbox.mutual_friends.indexOf(user_id) != -1)) in_mutual_friends = true ;
            } // for i
            if ($(giver_user_ids).filter(receiver_user_ids).length > 0) {
                errors.push('Giver/receiver is invalid. Found identical user id in giver and receiver user ids. A user cannot be both giver and receiver of a gift') ;
            };
            if ((giver_user_ids.length == 0) && (gift.direction == 'giver')) {
                errors.push('Giver is invalid. Cannot be empty for direction=giver') ;
            }
            else if (gift.accepted_cid || gift.accepted_at_client) {
                errors.push('Giver is invalid. Cannot be empty for an accepted deal') ;
            };
            if ((receiver_user_ids.length == 0) && (gift.direction == 'receiver')) {
                errors.push('Receiver is invalid. Cannot be empty for direction=receiver') ;
            }
            else if (gift.accepted_cid || gift.accepted_at_client) {
                errors.push('Receiver is invalid. Cannot be empty for an accepted deal') ;
            };
            if ((context != 'load') && !friend) errors.push('Giver/receiver is invalid. No mutual friends were found. context = ' + context); // no friend info at load / page startup time. Friend list is downloaded in post page task do_tasks
            if ((['send','receive'].indexOf(context) != -1) && !in_mutual_friends) {
                errors.push('Gift not valid for ' + context + '. Giver/receiver not in mailbox.mutual_friends') ;
            };

            //  3) created_at_client unix timestamp - 10 decimals - used in gift signature on server
            if (!gift.created_at_client) errors.push('Required created_at_client unix timestamp is missing') ;
            else if (gift.created_at_client < from_unix_timestamp) errors.push('Invalid created_at_client unix timestamp') ;
            else if (gift.created_at_client > to_unix_timestamp) errors.push('Invalid created_at_client unix timestamp') ;

            //  4) created_at_server - null or an integer - 0 for current server - >0 for gifts from other Gofreerev servers
            // blank when creating gift, 0 when server signature for gift has been created
            if (!gift.hasOwnProperty('created_at_server') || (gift.created_at_server == null)) {
                // must be a newly created gift waiting for server signature
                if (['create', 'load'].indexOf(context) == -1) errors.push('Created_at_server is missing') ;
            }
            else if ((typeof gift.created_at_server != 'number') && (gift.created_at_server < 0) && (Math.round(gift.created_at_server) != gift.created_at_server)) {
                errors.push('Created_at_server is invalid. Must be null or an integer >= 0') ;
            }
            else {
                if (context == 'create') errors.push('Created_at_server is invalid. Must be null when creating a new gift') ;
            }

            //  5) price => {:type => %w(undefined number), :minimum => 0, :multipleOf => 0.01 },
            // console.log(pgm + 'price = ' + gift.price + ', typeof price = ' + typeof gift.price) ;
            if ((typeof gift.price != 'undefined') && (gift.price != null)) {
                if (typeof gift.price != 'number') errors.push('Price is invalid. Must be an number >= 0') ;
                else if (gift.price < 0) errors.push('Price is invalid. Must be an number >= 0') ;
                else if (gift.price != Math.round(gift.price, 2)) errors.push('Price is invalid. Max 2 decimals are allowed in prices') ;
            }

            //  6) currency: optional currency - set when gift is created or when gift is accepted by a friend - iso4217 with some restrictions
            // Gofreerev.rails['VALID_CURRENCIES'] is a list with currencies from country to currency hash (from money gem)
            // not all currencies in list is active and not all currencies have exchange rates from default money bank
            if ((typeof gift.price == 'number') && (!gift.currency)) errors.push('Required currency is missing') ;
            if (gift.currency) {
                if (typeof gift.currency != 'string') errors.push('Currency is invalid. Must be a 3 letters string with valid iso4217 currency code') ;
                else if (!gift.currency.match(/^[a-z]{3}$/)) errors.push('Currency is invalid. Must be a 3 letters string with valid iso4217 currency code') ;
                else if (Gofreerev.rails['VALID_CURRENCIES'].indexOf(gift.currency) == -1) errors.push('Unknown currency ' + gift.currency) ;
            }
            else {
                if (typeof gift.price == 'number') errors.push('Required currency is missing') ;
            }

            //  7) direction: giver or receiver (creator of gift)
            if (!gift.direction) errors.push('Required direction is missing') ;
            else if (typeof gift.direction != 'string') errors.push('Direction is invalid. Must be giver or receiver') ;
            else if (['giver', 'receiver'].indexOf(gift.direction) == -1) errors.push('Direction is invalid. Must be giver or receiver') ;
            else if ((gift.direction == 'giver') && (giver_user_ids.length == 0)) errors.push('Direction is giver but no giver user ids was found') ;
            else if ((gift.direction == 'receiver') && (receiver_user_ids.length == 0)) errors.push('Direction is receiver but no receiver user ids was found') ;

            //  8) description   :description => {:type => 'string'},
            if ((typeof gift.description != 'string') || (gift.description == '')) errors.push('Required description is missing') ;

            //  9) open_graph_url => {:type => %w(undefined string) },
            if (gift.open_graph_url) {
                if (typeof gift.open_graph_url != 'string') errors.push('Open graph link is invalid. Must be an http url') ;
                else if (!gift.open_graph_url.match(/^https?:\/\//)) errors.push('Open graph link is invalid. Must be an http url') ;
                else if (!gift.open_graph_title && !gift.open_graph_description && !gift.open_graph_image) errors.push('Open graph link is invalid. Open graph must have a title, a description and/or an image') ;
            }

            // 10) open_graph_title => {:type => %w(undefined string) },
            if (gift.open_graph_title && (typeof gift.open_graph_title != 'string')) errors.push('Invalid open graph title. Must be blank or a string') ;

            // 11) open_graph_description => {:type => %w(undefined string) },
            if (gift.open_graph_description && (typeof gift.open_graph_description != 'string')) errors.push('Invalid open graph description. Must be blank or a string') ;

            // 12) open_graph_image => {:type => %w(undefined string) },
            if (gift.open_graph_image) {
                if (typeof gift.open_graph_image != 'string') errors.push('Open graph image is invalid. Must be an http url') ;
                else if (!gift.open_graph_image.match(/^https?:\/\//)) errors.push('Open graph image is invalid. Must be an http url') ;
            }
            
            // 13) like - todo: must be changed to an array with user ids and like/unlike timestamps
            // likes are not server validated and should only be replicated direct from client to client

            // 14) deleted_at_client => {:type => %w(undefined integer), :minimum => uid_from, :maximum => uid_to},
            if (gift.deleted_at_client) {
                if (gift.deleted_at_client < from_unix_timestamp) errors.push('Invalid deleted_at_client unix timestamp') ;
                else if (gift.deleted_at_client > to_unix_timestamp) errors.push('Invalid deleted_at_client unix timestamp') ;
            }
            
            // 15) accepted_cid => {:type => %w(undefined string), :pattern => uid_pattern},
            if (gift.accepted_cid) {
                if (typeof gift.accepted_cid != 'string') errors.push('Invalid accepted cid (unique comment id). Cid must be a string with 20 digits') ;
                else if (!gift.accepted_cid.match(/^[0-9]{20}$/)) errors.push('Invalid accepted cid (unique comment id). Cid must be a string with 20 digits') ;
                else if (parseInt(gift.accepted_cid.substr(0,10)) < from_unix_timestamp) errors.push('Invalid accepted cid (unique comment id). The first 10 digits must be a valid unix timestamp') ;
                else if (parseInt(gift.accepted_cid.substr(0,10)) > to_unix_timestamp) errors.push('Invalid accepted cid (unique comment id). The first 10 digits must be a valid unix timestamp') ;
                else if (!gift.comments || (gift.comments.length == 0)) errors.push('Unknown accepted cid (unique comment id). Accepted deal proposal was not found') ;
                else {
                    var accepted_comment = null, comment ;
                    for (i=0 ; i<gift.comments.length ; i++) {
                        if (gift.comments[i].cid == gift.accepted_cid) accepted_comment = gift.comments[i] ;
                    }
                    if (!accepted_comment) errors.push('Unknown accepted cid (unique comment id). Accepted deal proposal was not found') ;
                    else if (accepted_comment.new_deal_action != 'accepted') errors.push('Invalid accepted cid (unique comment id). Comment is not an accepted deal proposal') ;
                    else if (!accepted_comment.new_deal_action_by_user_ids) errors.push('Invalid accepted cid (unique comment id). Accepted by for accepted deal proposal was not found') ;
                    else {
                        // todo: compare comment.new_deal_action_by_user_ids and gift.giver_user_ids / gift.receiver_user_ids

                    }

                }
            }

            // 16) accepted_at_client => {:type => %w(undefined integer), :minimum => uid_from, :maximum => uid_to},
            if (gift.accepted_at_client) {
                if (gift.accepted_at_client < from_unix_timestamp) errors.push('Invalid accepted_at_client unix timestamp') ;
                else if (gift.accepted_at_client > to_unix_timestamp) errors.push('Invalid accepted_at_client unix timestamp') ;
                else if (accepted_comment && (gift.accepted_at_client != accepted_comment.new_deal_action_at_client)) {
                    errors.push('Invalid accepted_at_client unix timestamp') ;
                    accepted_comment = null ;
                }
            }

            if (accepted_comment) {

            }

            // 17) comments array
            var comments = gift.comments ;
            var no_comments_errors = 0 ;
            var cid, cids = [], doublet_cids = [] ;
            if (comments) {
                for (i=0 ; i<comments.length ; i++) {
                    cid = comments[i].cid ;
                    if (cids.indexOf(cid) == -1) cids.push(cid) ;
                    else if (doublet_cids.indexOf(cid) == -1) doublet_cids.push(cid) ;
                    if (invalid_comment(comments[i], new_users, context, server_id)) no_comments_errors += 1 ;
                }
                if (no_comments_errors > 0) errors.push(no_comments_errors + ' invalid comments') ;
            };
            if (doublet_cids.length > 0) errors.push('Doublet comments cid ' + doublet_cids.join(', ') + ' found for gift') ;

            if (errors.length > 0) {
                console.log(pgm + 'Error for gift ' + JSON.stringify(gift)) ;
                console.log(pgm + 'Error: ' + errors.join('. ')) ;
                return errors.join('. ') ;
            }
            else return null ;
        };
        var invalid_gift_change = function (old_gift, new_gift) {
            var pgm = service + '.invalid_changed_gift: ' ;
            console.log(pgm + 'Not implemented') ;
            return null ;
        };

        // calculate sha256 value for comment. used when comparing gift and comments between clients. replicate gifts with changed sha256 value between clients
        // readonly fields used in server side sha256 signature - update is NOT allowed - not included in comment_sha256_for_client
        // - created_at_client    - readonly - used in client part of server side sha256 signature - not included in comment_sha256_for_client
        // - comment              - readonly - used in client part of server side sha256 signature - not included in comment_sha256_for_client
        // - price                - readonly - used in client part of server side sha256 signature - not included in comment_sha256_for_client
        // - currency             - readonly - used in client part of server side sha256 signature - not included in comment_sha256_for_client
        // - new_deal             - readonly - used in client part of server side sha256 signature - not included in comment_sha256_for_client
        // - user_ids             - readonly - used in server side sha256 signature - not included in comment_sha256_for_client
        // - created_at_server    - server number - returned from new comments request and not included in comment_sha256_for_client
        // - new_deal_action      - blank, cancelled, accepted or rejected - only used for new deal proposals (new_deal=true), include in comment_sha256_for_client
        // - new_deal_action_by_user_ids - relevant login user ids for new_deal_action (cancel, accept, reject) - subset of comment or gift creators - include in comment_sha256_for_client
        // - new_deal_action_at_client - new deal action client unix timestamp - cancel, accept or reject - include in comment_sha256_for_client
        // - deleted_at_client    - deleted at client unix timestamp - include in comment_sha256_for_client
        var comment_sha256_for_client = function (comment, in_gifts) {
            var pgm = service + '.comment_sha256_for_client: ';
            if (!comment.hasOwnProperty('created_at_server')) return null; // wait for server side create
            // optional new deal action (cancel, accept or reject)
            var new_deal_action ;
            var new_deal_action_at_client ;
            var new_deal_action_by_user_ids = [];
            if ((in_gifts && comment.hasOwnProperty('new_deal_action_at_server')) || (!in_gifts && comment.new_deal_action_at_client)) {
                // new_deal_action completed (cancel, accept or reject new deal proposal)
                // todo: use internal user ids. comment_sha256_for_client is only used within client.
                new_deal_action = comment.new_deal_action ;
                new_deal_action_at_client = comment.new_deal_action_at_client ;
                new_deal_action_by_user_ids = userService.get_external_user_ids(comment.new_deal_action_by_user_ids);
                if (!new_deal_action_by_user_ids) new_deal_action_by_user_ids = [];
                new_deal_action_by_user_ids = new_deal_action_by_user_ids.sort() ;
            } ;
            new_deal_action_by_user_ids.unshift(new_deal_action_by_user_ids.length);
            new_deal_action_by_user_ids = new_deal_action_by_user_ids.join(',');
            // optional delete comment
            var deleted_at_client ;
            if ((in_gifts && comment.hasOwnProperty('deleted_at_server')) || (!in_gifts && comment.deleted_at_client)) deleted_at_client = comment.deleted_at_client ; // delete completed
            return Gofreerev.sha256(comment.cid, new_deal_action, new_deal_action_by_user_ids, new_deal_action_at_client, deleted_at_client);
        }; // comment_sha256_for_client

        // calculate client side sha256 value for gift. used when comparing gift lists between clients. replicate gifts with changed sha256 value to/from other clients
        // - readonly fields used in server side sha256 signature - update is not allowed - not included in gift_sha256_for_client:
        //   created_at_client, description, open_graph_url, open_graph_title, open_graph_description and open_graph_image,
        //   direction, giver_user_ids or receiver_user_ids
        //   direction=giver: giver_user_ids can not be changed, receiver_user_ids are added later, use receiver_user_ids in gift_sha256_for_client
        //   direction=receiver: receiver_user_ids can not be changed, giver_uds_ids are added latter, use receiver user ids in gift_sha256_for_client
        // - created_at_server timestamp is readonly and is returned from ping/new_gifts response - not included in gift_sha256_for_client
        // - price and currency - should not change, but include in gift_sha256_for_client
        // - todo: likes - array with likes - must be server validated - see solution for gift comments
        // - follow - change to array and keep last follow/unfollow for each logged in users - not included in gift_sha256_for_client
        //   find some way to replicate follow/unfollow to clients with identical logged in users - not shared with friends
        // - show - device only field or logged in user only field - replicate hide to other devices with identical logged in users? - not included in gift_sha256_for_client
        // - deleted_at_client - included in gift_sha256_for_client
        // - comments - array with comments - included comment_sha256_for_client array in gift gift_sha256_for_client
        // todo: gift from gifts array. check for operation in progress (accept, delete)
        // todo: gift from send_gifts message.
        var gift_sha256_for_client = function (gift) {
            var pgm = service + '.gift_sha256_for_client: ';
            if ((typeof gift.created_at_server == 'undefined') || (gift.created_at_server == null)) return [null,null,null]; // no server side sha256 signature
            // accepted or deleted. gift is from gifts array (check for operation in progress) or from an incoming send_gifts message (don't check for operation in progress)
            var in_gifts = (gifts.indexOf(gift) != -1) ;
            // todo 1: use internal user ids. gift_sha256_for_client is only used within client.
            // todo 2: only initialize other participant if accepted_at_server. empty array if accept operation is in progress
            // other participant in gift. null until closed/given/received
            var accepted = ((in_gifts && gift.hasOwnProperty('accepted_at_server')) || (!in_gifts && gift.accepted_at_client)) ;
            var deleted = ((in_gifts && gift.hasOwnProperty('deleted_at_server')) || (!in_gifts && gift.deleted_at_client)) ;
            var other_participant_internal_ids = gift.direction == 'giver' ? gift.receiver_user_ids : gift.giver_user_ids;
            if ((typeof other_participant_internal_ids == 'undefined') || (other_participant_internal_ids == null) || !accepted) other_participant_internal_ids = [];
            var other_participant_external_ids = [];
            var user;
            for (var i = 0; i < other_participant_internal_ids.length; i++) {
                user = userService.get_friend(other_participant_internal_ids[i]);
                if (!user) {
                    console.log(pgm + 'Cannot calculate sha256 for gift ' + gift.gid + '. Unknown internal user id ' + other_participant_internal_ids[i]);
                    return [null,null,null];
                }
                other_participant_external_ids.push(user.uid + '/' + user.provider);
            }
            other_participant_external_ids = other_participant_external_ids.sort();
            other_participant_external_ids.unshift(other_participant_external_ids.length.toString());
            var other_participant_str = other_participant_external_ids.join(',');
            // price and currency
            // likes - todo: change like from boolean to an array of like and unlike with user id and timestamp
            var likes_str = '';
            // optional accepted action
            var accepted_cid, accepted_at_client ;
            if (accepted) {
                accepted_cid = gift.accepted_cid ;
                accepted_at_client = gift.accepted_at_client ;
            }; // if
            // optional delete gift
            var deleted_at_client ;
            if (deleted) deleted_at_client = gift.deleted_at_client ; // delete completed
            // comments. string with sha256 value for each comment
            var comments, comment_sha256_temp;
            if ((typeof gift.comments == 'undefined') || (gift.comments == null)) comments = [];
            else comments = gift.comments;
            var comments_sha256 = [], s;
            for (i = 0; i < comments.length; i++) {
                s = comment_sha256_for_client(comments[i], in_gifts);
                if (!s) return [null,null,null]; // error in sha256 calc. error has been written to log
                comments_sha256.push(s);
            };
            comments_sha256.unshift(comments.length.toString());
            var comments_str = comments_sha256.join(',');
            // return an array with 3 sha256 values. sha256 is the real/full sha256 value for gift. sha256_gift and sha256_comments are sub sha256 values used in gifts sync between devices
            var sha256 = Gofreerev.sha256(gift.gid, other_participant_str, gift.price, gift.currency, likes_str, accepted_cid, accepted_at_client, deleted_at_client, comments_str);
            var sha256_gift = Gofreerev.sha256(gift.gid, other_participant_str, gift.price, gift.currency, likes_str, accepted_cid, accepted_at_client, deleted_at_client);
            var sha256_comments = Gofreerev.sha256(comments_str);
            console.log(pgm + 'gid = ' + gift.gid + ', in_gifts = ' + in_gifts + ', comments_str = ' + comments_str + ', sha256 = ' + sha256 + ', sha256_gift = ' + sha256_gift + ', sha256_comments = ' + sha256_comments) ;
            return [sha256, sha256_gift, sha256_comments];
        }; // gift_sha256_for_client

        var sort_by_gid = function (a, b) {
            if (a.gid < b.gid) return -1;
            if (a.gid > b.gid) return 1;
            return 0;
        }; // sort_by_gid


        // new gift default values - used in new gift form
        var new_gift = {} ;
        var appname = Gofreerev.rails['APP_NAME'];
        var init_new_gift = function () {
            new_gift = {
                direction: 'giver',
                currency: userService.get_currency(),
                errors: null,
                file_upload_title: function () {
                    if (userService.is_logged_in()) return I18n.t('js.new_gift.file_title_true', {appname: appname}) ;
                    else return I18n.t('js.new_gift.file_title_false', {appname: appname}) ;
                },
                show: function () {
                    var user_ids = userService.get_login_userids() ;
                    return (user_ids.length > 0) ; // logged in with one or more login providers?
                }
            };
            // todo: resize gift description
            // Gofreerev.autoresize_text_field(this)
            // add id to new gift description? or add this as parameter and call onfocus event for description
        };
        init_new_gift() ;

        var gifts = []; // gifts array used in main/gifts page - todo: add gift.updated_at_timestamp and sort gifts by updated_at_client timestamp - last changed in top of page
        var gid_to_gifts_index = {}; // from gid to index in gifts array
        var user_id_to_gifts = {}; // from internal user id to array of gifts - for fast user.sha256 calculation

        var seq_to_gid = {} ; // localStorage: from gift_<seq> in localStorage to gid
        var gid_to_seq = {} ; // localStorage: from gid to gift_<seq> in localStorage

        var init_gifts_index = function () {
            var pgm = service + '.init_gifts_index: ' ;
            gid_to_gifts_index = {};
            user_id_to_gifts = {};
            var user_ids, user_id, i, j, gift, sha256_values;
            for (i = 0; i < gifts.length; i++) {
                gift = gifts[i];
                // sha256 calc is done in load_gifts
                //sha256_values = gift_sha256_for_client(gift);
                //gift.sha256 = sha256_values[0];
                //gift.sha256_gift = sha256_values[1]; // sub sha256 values used in gifts sync between devices
                //gift.sha256_comments = sha256_values[2]; // sub sha256 values used in gifts sync between devices
                // simple gid to index
                gid_to_gifts_index[gift.gid] = i;
                // user_id to array of gifts
                user_ids = [];
                for (j = 0; j < gift.giver_user_ids.length; j++) {
                    user_id = gift.giver_user_ids[j];
                    if (user_ids.indexOf(user_id) == -1) {
                        if (!user_id_to_gifts[user_id]) user_id_to_gifts[user_id] = [];
                        user_id_to_gifts[user_id].push(gift);
                        user_ids.push(user_id);
                    }
                } // for j
                for (j = 0; j < gift.receiver_user_ids.length; j++) {
                    user_id = gift.receiver_user_ids[j];
                    if (user_ids.indexOf(user_id) == -1) {
                        if (!user_id_to_gifts[user_id]) user_id_to_gifts[user_id] = [];
                        user_id_to_gifts[user_id].push(gift);
                        user_ids.push(user_id);
                    }
                } // for j
            } // for i
            // sort gift arrays in user_id_gifts_index for fast users sha256 calc
            for (user_id in user_id_to_gifts) {
                user_id_to_gifts[user_id].sort(sort_by_gid);
            }
            // console.log(pgm + 'user_id_to_gifts = ' + JSON.stringify(user_id_to_gifts)) ;
        }; // init_gifts_index


        //if (gift.giver_user_ids != new_gift.giver_user_ids) gift.giver_user_ids = new_gift.giver_user_ids;
        //if (gift.receiver_user_ids != new_gift.receiver_user_ids) gift.receiver_user_ids = new_gift.receiver_user_ids;
        //if (gift.created_at_client != new_gift.created_at_client) gift.created_at_client = new_gift.created_at_client;
        //if (gift.created_at_server != new_gift.created_at_server) gift.created_at_server = new_gift.created_at_server;
        //if (gift.price != new_gift.price) gift.price = new_gift.price;
        //if (gift.currency != new_gift.currency) gift.currency = new_gift.currency;
        //if (gift.direction != new_gift.direction) gift.direction = new_gift.direction;
        //if (gift.description != new_gift.description) gift.description = new_gift.description;
        //if (gift.open_graph_url != new_gift.open_graph_url) gift.open_graph_url = new_gift.open_graph_url;
        //if (gift.open_graph_title != new_gift.open_graph_title) gift.open_graph_title = new_gift.open_graph_title;
        //if (gift.open_graph_description != new_gift.open_graph_description) gift.open_graph_description = new_gift.open_graph_description;
        //if (gift.open_graph_image != new_gift.open_graph_image) gift.open_graph_image = new_gift.open_graph_image;
        //if (gift.like != new_gift.like) gift.like = new_gift.like;
        //if (gift.follow != new_gift.follow) gift.follow = new_gift.follow;
        //if (gift.show != new_gift.show) gift.show = new_gift.show;
        //// todo: add gift.deleted_at_server (integer)
        //if (gift.deleted_at_client != new_gift.deleted_at_client) gift.deleted_at_client = new_gift.deleted_at_client;
        //if (gift.accepted_cid != new_gift.accepted_cid) gift.accepted_cid = new_gift.accepted_cid;
        //if (gift.accepted_at_client != new_gift.accepted_at_client) gift.accepted_at_client = new_gift.accepted_at_client;
        //// todo: should merge comments and keep sequence - not overwrite arrays
        //if (!gift.hasOwnProperty('comments')) gift.comments = [];
        //if (!new_gift.hasOwnProperty('comments')) new_gift.comments = [];
        //if (gift.comments != new_gift.comments) refresh_comments(gift.comments, new_gift.comments);


        // remove session specific attributes from gift and comments before save
        function prepare_gift_for_save(gift) {
            var pgm = service + '.prepare_gift_for_save: ';
            gift = JSON.parse(JSON.stringify(gift));
            // remove temp gift properties before save
            var keep_gift_property = {
                gid: true, giver_user_ids: true, receiver_user_ids: true, created_at_client: true,
                created_at_server: true, price: true, currency: true, direction: true, description: true,
                open_graph_url: true, open_graph_title: true, open_graph_description: true, open_graph_image: true,
                comments: true, like: true, follow: true, show: true,
                accepted_cid: true, accepted_at_client: true, accepted_at_server: true,
                deleted_at_client: true, deleted_at_server: true
            };
            for (var key in gift) {
                if (gift.hasOwnProperty(key) && !keep_gift_property[key]) delete gift[key];
            }
            // remove temp comment properties before save
            if (!gift.hasOwnProperty('comments')) gift.comments = [];
            var comment;
            var keep_comment_property = {
                cid: true, user_ids: true, price: true, currency: true, comment: true, new_deal: true,
                created_at_client: true, created_at_server: true,
                new_deal_action: true, new_deal_action_at_client: true,new_deal_action_by_user_ids: true,  new_deal_action_at_server: true,
                deleted_at_client: true, deleted_at_server: true
            } ;
            for (var i = 0; i < gift.comments.length; i++) {
                comment = gift.comments[i] ;
                for (key in comment) {
                    if (comment.hasOwnProperty(key) && !keep_comment_property[key]) delete comment[key];
                }
            }
            return gift;
        }

        // add new gift to 1) js array and to 2) localStorage. new gift has already been validated in GiftsCtrl.create_new_gift
        // params:
        // - gift to be added to gifts array in localStorage
        // - send_gifts_users - only used when receiving gift from an other client - users array from send_gifts message
        var save_new_gift = function (gift, send_gifts_users) {
            var pgm = service + '.save_new_gift: ';

            // calc sha256 values for new gift
            var sha256_values = gift_sha256_for_client(gift) ;
            gift.sha256 = sha256_values[0];
            gift.sha256_gift = sha256_values[1]; // sub sha256 values used in gifts sync between devices
            gift.sha256_comments = sha256_values[2]; // sub sha256 values used in gifts sync between devices

            // 1: add new gift to js array
            if (gid_to_gifts_index.hasOwnProperty(gift.gid)) {
                console.log(pgm + 'error. gift with gid ' + gift.gid + ' is already in gifts array');
                return;
            }
            gifts.unshift(gift);
            init_gifts_index();

            // 2: add any new givers/receivers to localStorage.
            // todo: remove if else? send_gifts_users array with be empty for local gifts and non empty for remote gifts
            if (!gift.hasOwnProperty('created_at_server')) {
                // gift created on this client. givers/receives are always in friends array as login users (user.friend == 1)
                userService.add_new_users(gift.giver_user_ids, []) ;
                userService.add_new_users(gift.receiver_user_ids, []) ;
            }
            else {
                // gift created on other client. givers/receivers are normally friends but can also be unknown users from other client
                userService.add_new_users(gift.giver_user_ids, send_gifts_users) ;
                userService.add_new_users(gift.receiver_user_ids, send_gifts_users) ;
            };

            // 3: add new gift to localStorage
            gift = prepare_gift_for_save(gift) ;
            var seq = Gofreerev.get_next_seq().toString();
            Gofreerev.setItem('gift_' + seq, JSON.stringify(gift)) ;
            gid_to_seq[gift.gid] = seq ;
            seq_to_gid[seq] = gift.gid ;
            init_gifts_index() ;
        }; // save_new_gift

        // save_gift are called after any changes in a gift (like, follow, hide, delete etc)
        var save_gift = function (gift) {
            var pgm = service + '.save_gift: ' ;
            var seq = gid_to_seq[gift.gid] ;
            var error ;
            if (!seq) {
                error = 'Gift with gid ' + gift.gid + ' was not found in localStorage gid_to_seq index' ;
                console.log(pgm + 'Error. Save gift failed. ' + error);
                return error ;
            }
            var key = 'gift_' + seq ;
            var old_gift = Gofreerev.getItem(key) ;
            if (!old_gift) {
                error = 'Gift with gid ' + gift.gid + ' was not found in localStorage. Key = ' + key ;
                console.log(pgm + 'Error. Save gift failed. ' + error);
                return error ;
            }
            old_gift = JSON.parse(old_gift) ;
            error = invalid_gift_change(old_gift, gift) ;
            if (error) return error ; // invalid update
            var new_gift = prepare_gift_for_save(gift) ;
            Gofreerev.setItem(key, JSON.stringify(new_gift)) ;
            // recalc sha256 values for changed gift
            var sha256_values = gift_sha256_for_client(gift) ;
            gift.sha256 = sha256_values[0];
            gift.sha256_gift = sha256_values[1]; // sub sha256 values used in gifts sync between devices
            gift.sha256_comments = sha256_values[2]; // sub sha256 values used in gifts sync between devices
            return null ;
        } ;

        // find all gift_<seq> keys in localStorage for actual user
        function get_gift_keys () {
            var pgm = service + '.get_gift_keys: ' ;
            var userid = userService.client_userid() ;
            if (userid == 0) return [] ;
            var regexp = new RegExp('^' + userid + '_gift_[0-9]+$') ; // format <userid>_gift_<seq>
            var keys = [] ;
            var lng = localStorage.length ;
            var key, key_a ;
            for (var i=0 ; i < lng ; i++ ) {
                key = localStorage.key(i);
                if (key.match(regexp)) {
                    // remove userid from key
                    key_a = key.split('_') ;
                    key_a.splice(0,1) ;
                    key = key_a.join('_') ;
                    keys.push(key) ;
                }
            }
            // sort gift_<seq> keys. highest seq first
            keys = keys.sort(function(a,b) {
                var a9 = parseInt(a.split('_')[1]) ;
                var b9 = parseInt(b.split('_')[1]) ;
                return b9-a9 ;
            }) ;
            return keys ;
        } // get_gift_keys

        // helper function. collect user ids used in gifts and comments and append to array
        // should normally be a list of (positive) integers
        // send in load_gifts, validate_send_gifts_message etc
        // params:
        // - user_ids                 : user ids to add to array
        // - array                    : buffer with user ids
        // - ignore_negative_user_ids : ignore negative user ids for remote gift when called from add_friends_to_users
        function add_user_ids_to_array (user_ids, array, ignore_negative_user_ids) {
            if (!user_ids) return ;
            if (user_ids.length == 0) return ;
            if ((typeof ignore_negative_user_ids == 'undefined') || (ignore_negative_user_ids == null)) ignore_negative_user_ids = false ;
            var i, user_id ;
            for (i=0 ; i<user_ids.length ; i++) {
                user_id = user_ids[i] ;
                if (ignore_negative_user_ids && (typeof user_id == 'number') && (user_id < 0) && (Math.round(user_id) == user_id)) continue ;
                if (array.indexOf(user_id) == -1) array.push(user_id) ;
            }
        } // add_user_ids_to_array


        // post load_gifts / post login - copy friends used in gifts and comments to users (localStorage and JS)
        // users array should normally be up-to-date
        var add_friends_to_users = function () {
            var pgm = service + '.add_friends_to_users: ' ;
            var migration_user_ids = [] ;
            var i, gift, comment ;
            var ignore_negative_user_ids ; // negative user id is used for unknown users in gifts and comments from clients on other Gofreerev servers

            // find relevant user ids
            for (i=0 ; i<gifts.length ; i++) {
                gift = gifts[i] ;
                // ignore negative user ids for remote gifts from client on other gofreerev servers (never in friends array)
                ignore_negative_user_ids = (gift.created_at_server > 0) ;
                // migration_user_ids - friends used in gifts and comments must be in users
                add_user_ids_to_array(gift.giver_user_ids, migration_user_ids, ignore_negative_user_ids) ;
                add_user_ids_to_array(gift.receiver_user_ids, migration_user_ids, ignore_negative_user_ids) ;
                if (gift.comments) for (j=0 ; j<gift.comments.length ; j++) {
                    comment = gift.comments[j] ;
                    add_user_ids_to_array(comment.user_ids, migration_user_ids, ignore_negative_user_ids) ;
                    add_user_ids_to_array(comment.new_deal_action_by_user_ids, migration_user_ids, ignore_negative_user_ids) ;
                }
            }; // for i

            // remove any invalid user ids (must be integer >= 1)
            var user_id ;
            for (i=migration_user_ids.length-1 ; i>= 0 ; i--) {
                user_id = migration_user_ids[i];
                if ((typeof user_id != 'number') || (Math.round(user_id) != user_id) || (user_id < 1)) {
                    console.log(pgm + 'Error. Ignoring invalid user id ' + user_id + ' in copy friends to users operation') ;
                    migration_user_ids.splice(i,1) ;
                    continue ;
                }
            }; // for i

            if (migration_user_ids.length > 0) userService.add_friends_to_users(migration_user_ids) ;
        }; // add_friends_to_users


        // check sha256 server signature for gifts received from other clients before adding or merging gift on this client
        // input is gifts in verify_gifts from send_gifts message pass 1 (receive_message_send_gifts)
        // gifts in verify_gifts array are moved to verify gifts buffer
        // unique sequence seq is used in verify gifts requests and is returned in verify gifts response
        // positive seq is used for local gifts where response in immediate
        // negative seq (from sequence) is used for remote gifts where response will come in a later verify_gifts_response
        // server verifies if gift sha256 server signature is valid and returns a created_at_server timestamp if ok or null if not ok
        // output is created_at_server timestamp received in verify_gifts_response (added as gift.verified_at_server)
        // output is used in send_gifts message pass 2 (receive_message_send_gifts)
        var verify_gifts = []; // array with gifts for next verify_gifts request - there can be doublets in array if a gift is received from multiple clients
        // verify gifts buffer - index by seq and key
        var verify_gifts_key_to_seq = {} ; // helper: hash key=>seq, key = gid+sha256+userids
        var verify_gifts_seq_to_gifts = {} ; // helper: from seq to one or more gifts
        var verify_gifts_online = true ; // todo: set to false if ping does not respond - set to true if ping respond
        var verify_gifts_old_remote_seq = Gofreerev.getItem('seq') ; // ignore old remote gift verifications

        // add gift to verify_gifts array. actions: create, verify, accept or delete gift.
        // create gift action is always local (current Gofreerev server)
        // verify, accept and delete gift actions can be local or remote (other Gofreerev servers)
        var verify_gifts_add = function (gift, action) {
            var pgm = service + '.verify_gifts_add: ' ;
            var error, property_at_server ;
            switch (action) {
                case 'create':
                    property_at_server = 'created_at_server' ;
                    break ;
                case 'verify':
                    property_at_server = 'verified_at_server' ;
                    break ;
                case 'accept':
                    property_at_server = 'accepted_at_server' ;
                    break ;
                case 'delete':
                    property_at_server = 'deleted_at_server' ;
                    break ;
                default:
                    error = 'Invalid verify_gifts_add call. Expected action create, verify, accept or delete. Action was ' + action ;
                    console.log(pgm + error) ;
                    return error ;
            } ; // switch
            if ((action != 'verify') && (gifts.indexOf(gift) == -1)) {
                // gift action: create, accept or delete. gift must be in gifts array.
                error = 'Invalid verify_gifts_add call. Gift must be in gifts array. Action was ' + action ;
                console.log(pgm + error) ;
                console.log(pgm + 'gift = ' + JSON.stringify(gift)) ;
                return error ;
            }; // if
            if (!gift.hasOwnProperty('created_at_client') || (typeof gift.created_at_client == 'undefined') || (gift.created_at_client == null)) {
                error = 'Invalid verify_gifts_add call. gift.created_at_client is missing for action ' + action ;
                console.log(pgm + error) ;
                return error ;
            };
            if ((action != 'create') && ((!gift.hasOwnProperty('created_at_server')) || (gift.created_at_server == null))) {
                // accept or delete old existing gift
                error = 'Invalid verify_gifts_add call. gift.created_at_server is missing or waiting for create gift operation to complete. Action was ' + action ;
                console.log(pgm + error) ;
                return error ;
            };

            if (action == 'accept') {
                if (!gift.hasOwnProperty('accepted_cid') || (typeof gift.accepted_cid == 'undefined') || (gift.accepted_cid == null)) {
                    error = 'Invalid verify_gifts_add call. gift.accepted_cid is missing for action accept' ;
                    console.log(pgm + error) ;
                    return error ;
                };
                if (!gift.hasOwnProperty('accepted_at_client') || (typeof gift.accepted_at_client == 'undefined') || (gift.accepted_at_client == null)) {
                    error = 'Invalid verify_gifts_add call. gift.accepted_at_client is missing for action accept' ;
                    console.log(pgm + error) ;
                    return error ;
                };
            };
            if (action == 'delete' && (!gift.hasOwnProperty('deleted_at_client') || (typeof gift.deleted_at_client == 'undefined') || (gift.deleted_at_client == null))) {
                error = 'Invalid verify_gifts_add call. gift.deleted_at_client is missing for action delete' ;
                console.log(pgm + error) ;
                return error ;
            };
            if ((gift.hasOwnProperty(property_at_server))) {
                // already created, verified, accepted or deleted
                error = 'Invalid verify_gifts_add call. gift.' + property_at_server + ' is not null. Action was ' + action ;
                console.log(pgm + error) ;
                return error ;
            };
            if (gift.verify_gift_at) {
                // gift already in verify gift buffer. check action
                if (gift.verify_gift_action == action) return null;
                error = 'Invalid verify_gifts_add call. Gift ' + gift.gid + ' already in verify gifts buffer with action ' + gift.verify_gift_action +
                    '. Old ' + gift.verify_gift_action + ' gift action must complete before continuing with new ' + action + ' gift action' ;
                console.log(pgm + error) ;
                return error ;
            };
            gift.verify_gift_at = Gofreerev.unix_timestamp() ;
            gift.verify_gift_action = action ; // verify, accept or delete
            verify_gifts.push(gift) ;
            console.log(pgm + 'added gid ' + gift.gid + ' to verify gifts buffer with action=' + action) ;
            return null;
        }; // verify_gifts_add


        // check sha256 server signature for comments received from other clients before adding or merging gift on this client
        // input is comments in verify_comments from send_gifts message pass 1 (receive_message_send_gifts)
        // unique sequence seq is used in verify comments requests.
        // positive seq is used for local comments where response in immediate
        // negative seq (from sequence) is used for remote comments where response will come in a later verify_comments_response
        // server verifies if comment sha256 server signature is valid and returns a created_at_server timestamp if ok or null if not ok
        // output is created_at_server timestamp received in verify_comments_response (added as comment.verified_at_server)
        // output is used in send_gifts message pass 2 (receive_message_send_gifts)
        var verify_comments = []; // array with commentss for next verify_comments request - there can be doublets in array if a gift is received from multiple clients
        // verify comments buffer - index by seq and key
        var verify_comments_key_to_seq = {} ; // helper: array with keys, key = gid+sha256+userids
        var verify_comments_seq_to_comms = {} ; // helper: from seq to one or more comments
        var verify_comments_online = true ; // todo: set to false if ping does not respond - set to true if ping respond
        var verify_comments_old_remote_seq = Gofreerev.getItem('seq') ; // ignore old remote comment verifications todo: identical with verify_gifts_old_remote_seq

        // add comment to verify_comments array. actions create, verify, new deal action (cancel, accept, reject) or delete
        var verify_comments_add = function (gift, comment, action) {
            var pgm = service + '.verify_comments_add: ' ;
            var error, property_at_server ;
            switch (action) {
                case 'create':
                    property_at_server = 'created_at_server' ;
                    break ;
                case 'verify':
                    property_at_server = 'verified_at_server' ;
                    break ;
                case 'delete':
                    property_at_server = 'deleted_at_server' ;
                    break ;
                case 'cancel':
                case 'accept':
                case 'reject':
                    // cancel, accept or reject new deal proposal
                    property_at_server = 'new_deal_action_at_server';
                    break ;
                default:
                    error = 'Invalid verify_comments_add call. Expected action create, verify, cancel, accept, reject or delete. Action was ' + action ;
                    console.log(pgm + error) ;
                    return error ;
            } ; // switch
            if (!comment.hasOwnProperty('created_at_client') || (typeof comment.created_at_client == 'undefined') || (comment.created_at_client == null)) {
                error = 'Invalid verify_comments_add call. comment.created_at_client is missing or waiting for create comment operation to complete. Action was ' + action ;
                console.log(pgm + error) ;
                return error ;
            };
            if ((action != 'create') && ((!comment.hasOwnProperty('created_at_server')) || (comment.created_at_server == null))) {
                // accept or delete old existing gift
                error = 'Invalid verify_comments_add call. comment.created_at_server is missing or waiting for create comment operation to complete. Action was ' + action ;
                console.log(pgm + error) ;
                return error ;
            };
            if (['cancel', 'accept', 'reject'].indexOf(action) != -1) {
                // new deal action (cancel, accept or reject new deal proposal). new_deal_action and new_new_action_at_client are required
                if (!comment.hasOwnProperty('new_deal_action') || (typeof comment.new_deal_action == 'undefined') || (comment.new_deal_action == null)) {
                    error = 'Invalid verify_comments_add call. gift.new_deal_action is missing for action ' + action ;
                    console.log(pgm + error) ;
                    return error ;
                } ;
                if (comment.new_deal_action != action) {
                    error = 'Invalid verify_comments_add call. Invalid action. Comment.new_deal_action is ' + comment.new_deal_action + '. verify_comments_add was called with action ' + action ;
                    console.log(pgm + error) ;
                    return error ;
                };
                if (!comment.hasOwnProperty('new_deal_action_at_client') || (typeof comment.new_deal_action_at_client == 'undefined') || (comment.new_deal_action_at_client == null)) {
                    error = 'Invalid verify_comments_add call. gift.new_deal_action_at_client is missing for action ' + action ;
                    console.log(pgm + error) ;
                    return error ;
                } ;
            };
            if ((action == 'delete') && (!comment.hasOwnProperty('deleted_at_client') || (typeof comment.deleted_at_client == 'undefined') || (comment.deleted_at_client == null))) {
                error = 'Invalid verify_comments_add call. comment.deleted_at_client is missing for action delete' ;
                console.log(pgm + error) ;
                return error ;
            };
            if ((comment.hasOwnProperty(property_at_server))) {
                // already verified, cancelled, accepted, rejected or deleted
                error = 'Invalid verify_comments_add call. comment.' + property_at_server + ' is not null. Action was ' + action ;
                console.log(pgm + error) ;
                return error ;
            };
            if (comment.verify_comment_at) {
                // comment already in verify comment buffer. check action
                if (comment.verify_comment_action == action) return null;
                error = 'Invalid verify_comments_add call. Comment ' + comment.cid + ' already in verify comments buffer with action ' + comment.verify_comment_action +
                    '. Old ' + comment.verify_comment_action + ' comment action must complete before continuing with new ' + action + ' comment action' ;
                console.log(pgm + error) ;
                return error ;
            };
            comment.verify_comment_at = Gofreerev.unix_timestamp() ;
            comment.verify_comment_action = action ; // verify, accept or delete
            verify_comments.push({gift: gift, comment: comment});
            console.log(pgm + 'added cid ' + comment.cid + ' to verify comments buffer with action ' + action) ;
        }; // verify_comments_add


        // load/reload gifts and comments from localStorage - used at startup and after login/logout
        //var seq_to_gid = {} ; // localStorage: from gift_<seq> in localStorage to gid
        //var gid_to_seq = {} ; // localStorage: from gid to gift_<seq> in localStorage
        var load_gifts = function () {
            var pgm = service + '.load_gifts: ';
            var new_gifts = [];

            // find all gift_<seq> keys in localStorage for actual user
            var keys = get_gift_keys() ;

            // ready to initialize gifts array including 4 helper hashes
            gifts.length = 0 ;
            gid_to_gifts_index = {};
            user_id_to_gifts = {};
            seq_to_gid = {} ;
            gid_to_seq = {} ;

            // loop for all gifts
            var gift, j, comment, migration, seq, k, errors, sha256_values ;
            for (var i=0 ; i<keys.length ; i++) {

                seq = keys[i].split('_')[1] ;
                gift = JSON.parse(Gofreerev.getItem(keys[i])) ;
                if (gid_to_seq.hasOwnProperty(gift.gid)) {
                    console.log(pgm + 'Error: Doublet gift in localStorage. Gift with gid ' + gift.gid + ' was found in key gift_' + gid_to_seq[gift.gid] + ' and in key ' + keys[i]) ;
                    continue ;
                }
                migration = false ;

                // data migration. rename comment.created_at to created_at_client
                //if ((gift.hasOwnProperty('comments')) && (typeof gift.comments == 'object') && (gift.comments.length > 0)) {
                //    for (j=0 ; j<gift.comments.length ; j++) {
                //        comment = gift.comments[j] ;
                //        if (comment.hasOwnProperty('created_at')) {
                //            comment.created_at_client = comment.created_at ;
                //            delete comment.created_at ;
                //            migration = true ;
                //        }
                //    }
                //}
                // calc sha256 signatures from gift and comments
                //gift.sha256 = calc_sha256_for_gift(gift) ;
                //if (!gift.sha256) console.log(pgm + ' could not calculate sha256 for gift ' + gift.gid) ;
                //gifts_index[gift.gid] = gifts.length ;

                // fix json error - js data migration. change gift deleted_at timestamp from milliseconds to seconds -- todo: remove
                //if (gift.deleted_at) {
                //    if (gift.deleted_at.toString().length == 13) {
                //        gift.deleted_at = Math.floor(gift.deleted_at / 1000) ;
                //        migration = true ;
                //    }
                //}

                // gift data migration. rename gift.deleted_at to gift.deleted_at_client
                //if (gift.hasOwnProperty('deleted_at')) {
                //    gift.deleted_at_client = gift.deleted_at ;
                //    delete gift.deleted_at ;
                //    migration = true ;
                //}
                // comment data migration - rename comment.deleted_at to comment.deleted_at_client
                //if ((gift.hasOwnProperty('comments')) && (typeof gift.comments == 'object') && (gift.comments.length > 0)) {
                //    for (j=0 ; j<gift.comments.length ; j++) {
                //        comment = gift.comments[j] ;
                //        if (comment.hasOwnProperty('deleted_at')) {
                //            comment.deleted_at_client = comment.deleted_at ;
                //            delete comment.deleted_at ;
                //            migration = true ;
                //        }
                //    }
                //}
                // gifts data migration. empty fields (fx open graph) removed from end of all sha256 signatures. recreate all server side gift signatures
                //if (gift.created_at_server) {
                //    delete gift.created_at_server ;
                //    migration = true ;
                //}

                // datamigration - check two invalid gifts
                //"GiftService.new_gifts_response: gift + 14252357688958255016 signature was not created on server. Could not create gift signature on server. giver_user_ids or receiver_user_ids property was missing" gofreerev.js:2745:20
                //"GiftService.new_gifts_response: gift + 14252357466622052986 signature was not created on server. Could not create gift signature on server. giver_user_ids or receiver_user_ids property was missing" gofreerev.js:2745:20
                //var errors ;
                //if (errors=invalid_gift(gift)) console.log(pgm + 'Gift ' + gift.gid + ', errors = ' + errors) ;
                //if (['14252357688958255016', '14252357466622052986'].indexOf(gift.gid) != -1) {
                //    migration = true ;
                //    continue ;
                //}

                // datamigration - testcase data cleanup. delete new gift with invalid owner
                //if (gift.gid == '14259160985531302471') {
                //    Gofreerev.removeItem(keys[i]) ;
                //    continue ;
                //}

                //if (gift.gid == '14315931137417750564') {
                //    // cleanup after testrun-23
                //    console.log(pgm + 'delete remote gift ' + gift.gid) ;
                //    Gofreerev.removeItem(keys[i]) ;
                //    continue ;
                //}

                //if (gift.gid == '14323048627287885889') {
                //    // cleanup gift replication error (doublet cids/comments).
                //    console.log(pgm + 'delete gift ' + gift.gid + ' with doublet comments') ;
                //    Gofreerev.removeItem(keys[i]) ;
                //    continue ;
                //}

                // migrate old comment accepted/rejected fields
                //if (gift.comments) for (j = 0; j < gift.comments.length; j++) {
                //    comment = gift.comments[j];
                //    if (comment.hasOwnProperty('accepted_at_client')) {
                //        comment.new_deal_action = 'accepted' ;
                //        comment.new_deal_action_by_user_ids = comment.accepted_by_user_ids ;
                //        comment.new_deal_action_at_client = comment.accepted_at_client ;
                //        delete comment.accepted ;
                //        delete comment.accepted_by_user_ids ;
                //        delete comment.accepted_at_client ;
                //        migration = true ;
                //    }
                //    if (comment.hasOwnProperty('rejected_at_client')) {
                //        comment.new_deal_action = 'rejected' ;
                //        comment.new_deal_action_by_user_ids = comment.rejected_by_user_ids ;
                //        comment.new_deal_action_at_client = comment.rejected_at_client ;
                //        delete comment.rejected ;
                //        delete comment.rejected_by_user_ids ;
                //        delete comment.rejected_at_client ;
                //        migration = true ;
                //    }
                //}; // if

                // testrun-x. remove remote gift with negative giver user id -4 (replicated from laptop2 to laptop)
                //if ((gift.gid == '14481197074000741072')&&(gift.giver_user_ids.indexOf(-4) != -1)) {
                //    console.log(pgm + 'delete gift ' + gift.gid + ' with negative user id -4') ;
                //    Gofreerev.removeItem(keys[i]) ;
                //    continue ;
                //} ;

                // changed sha256_deleted server side signature. resend delete gifts request to server
                if (gift.hasOwnProperty('deleted_at_server')) {
                    delete gift.deleted_at_server ;
                    migration = true ;
                }

                // save migrated gift
                if (migration) Gofreerev.setItem(keys[i], JSON.stringify(gift)) ;

                if (errors=invalid_gift(gift, [], 'load', null)) {
                    console.log(pgm + 'System error. Gift ' + gift.gid + ' is invalid. ' + errors) ;
                    console.log(pgm + 'gift = ' + JSON.stringify(gift)) ;
                };

                gifts.push(gift);
                gid_to_seq[gift.gid] = seq ;
                seq_to_gid[seq] = gift.gid ;

                // add client side sha256 signatures for gift (not saved in localStorage)
                sha256_values = gift_sha256_for_client(gift) ;
                gift.sha256 = sha256_values[0];
                gift.sha256_gift = sha256_values[1]; // sub sha256 values used in gifts sync between devices
                gift.sha256_comments = sha256_values[2]; // sub sha256 values used in gifts sync between devices
                if (!gift.hasOwnProperty('created_at_server')) verify_gifts_add(gift, 'create') ; // resend create gift request
                if ((gift.created_at_server == 0) && gift.deleted_at_client && !gift.hasOwnProperty('deleted_at_server')) verify_gifts_add(gift, 'delete') ; // resend delete gift request

                // add client side sha256 signature for comments (not saved in localStorage)
                if (gift.comments) for (j = 0; j < gift.comments.length; j++) {
                    comment = gift.comments[j];
                    comment.sha256 = comment_sha256_for_client(comment, true) ;
                    // resend old not processed comment actions
                    if (!comment.hasOwnProperty('created_at_server')) verify_comments_add(gift, comment, 'create') ; // resend create comment request
                    if (comment.new_deal_action_at_client && !comment.hasOwnProperty('new_deal_action_at_server')) verify_comments_add(gift, comment, comment.new_deal_action) ; // resend cancel, accept or reject new deal proposal request
                    if (comment.deleted_at_client && !comment.hasOwnProperty('deleted_at_server')) verify_comments_add(gift, comment, 'delete') ; // resend delete comment request
                } ;
                console.log(pgm + 'gift = ' + JSON.stringify(gift)) ;

            } // for i
            console.log(pgm + 'gifts.length = ' + gifts.length);
            init_gifts_index();

            // data migration. add missing users from friends to users array.
            add_friends_to_users() ;
        };
        load_gifts();

        // add missing gid (unique gift id)
        //for (i=0 ; i<gifts.length ; i++) if (!gifts[i].gid) {
        //    gifts[i].gid = Gofreerev.get_new_uid() ;
        //    init_gifts_index() ;
        //}
        // add missing cid (unique comment id)
        //for (i=0 ; i<gifts.length ; i++) {
        //    if (gifts[i].hasOwnProperty('comments')) {
        //        var comments = gifts[i].comments ;
        //        for (var j=0 ; j<comments.length ; j++) if (!comments[j].cid) comments[j].cid = Gofreerev.get_new_uid() ;
        //    }
        //}

        var comments_debug_info = function (comments) {
            var text = 'length = ' + comments.length;
            for (var i = 0; i < comments.length; i++) text += ', ' + comments[i].comment + ' (' + comments[i].cid + ')';
            return text;
        }; // comments_debug_info

        // todo: ok always to add new comments to end of comments array?
        // refresh gift comments from localStorage before update (changed in an other browser tab)
        var refresh_comments = function (comments, new_comments) {
            var pgm = service + '.refresh_comments: ';
            // console.log(pgm + 'input: comments.length = ' + comments.length + ', new_comments.length = ' + new_comments.length) ;
            // console.log(pgm + 'old comments: ' + comments_debug_info(comments)) ;
            // console.log(pgm + 'new comments: ' + comments_debug_info(new_comments)) ;
            // insert and update comments
            var comments_index;
            var init_comments_index = function () {
                comments_index = {};
                for (var j = 0; j < comments.length; j++) comments_index[comments[j].cid] = j;
            };
            init_comments_index();
            var cid, comment_index;
            for (var i = 0; i < new_comments.length; i++) {
                cid = new_comments[i].cid;
                if (comments_index.hasOwnProperty(cid)) {
                    // update comment
                    comment_index = comments_index[cid];
                    // todo: add server side comment.sha256_deleted and comment.sha256_action. almost as gifts, but a comment cannot be both accepted and deleted
                    // todo: it should be enough with one client side deleted_at_server=accepted_at_server field
                    if (comments[comment_index].user_ids != new_comments[i].user_ids) comments[comment_index].user_ids = new_comments[i].user_ids;
                    if (comments[comment_index].price != new_comments[i].price) comments[comment_index].price = new_comments[i].price;
                    if (comments[comment_index].currency != new_comments[i].currency) comments[comment_index].currency = new_comments[i].currency;
                    if (comments[comment_index].comment != new_comments[i].comment) comments[comment_index].comment = new_comments[i].comment;
                    if (comments[comment_index].created_at_client != new_comments[i].created_at_client) comments[comment_index].created_at_client = new_comments[i].created_at_client;
                    if (comments[comment_index].created_at_server != new_comments[i].created_at_server) comments[comment_index].created_at_server = new_comments[i].created_at_server;
                    if (comments[comment_index].new_deal != new_comments[i].new_deal) comments[comment_index].new_deal = new_comments[i].new_deal;
                    if (comments[comment_index].deleted_at_client != new_comments[i].deleted_at_client) comments[comment_index].deleted_at_client = new_comments[i].deleted_at_client;
                    // todo: add deleted_at_server (integer) ?
                    if (comments[comment_index].accepted != new_comments[i].accepted) comments[comment_index].accepted = new_comments[i].accepted;
                    if (comments[comment_index].accepted_at_client != new_comments[i].accepted_at_client) comments[comment_index].accepted_at_client = new_comments[i].accepted_at_client;
                    if (comments[comment_index].accepted_by_user_ids != new_comments[i].accepted_by_user_ids) comments[comment_index].accepted_by_user_ids = new_comments[i].accepted_by_user_ids;
                    if (comments[comment_index].rejected_at_client != new_comments[i].rejected_at_client) comments[comment_index].rejected_at_client = new_comments[i].rejected_at_client;
                    if (comments[comment_index].rejected_by_user_ids != new_comments[i].rejected_by_user_ids) comments[comment_index].rejected_by_user_ids = new_comments[i].rejected_by_user_ids;
                }
                else {
                    // insert comment.
                    // console.log(pgm + 'insert new comment ' + new_comments[i].comment) ;
                    comments.push(new_comments[i]);
                    init_comments_index();
                }
            } // for i
            // delete comments - todo: not implemented
            // console.log(pgm + 'output: comments.length = ' + comments.length + ', new_comments.length = ' + new_comments.length) ;
        }; // refresh_comments

        // refresh gift from localStorage before update (changed in an other browser tab)
        // called before adding change to js object in this browser tab
        var refresh_gift = function (gift) {
            var pgm = service + '.refresh_gift: ';
            var seq = gid_to_seq[gift.gid] ;
            if (!seq) {
                console.log(pgm + 'error. refresh failed. gift with gid ' + gift.gid + ' was not found in localStorage');
                return ;
            }
            var new_gift = JSON.parse(Gofreerev.getItem('gift_' + seq)) ;
            if (!new_gift) {
                console.log(pgm + 'error. refresh failed. gift with gid ' + gift.gid + ' was not found in localStorage');
                return;
            }
            if (gift.giver_user_ids != new_gift.giver_user_ids) gift.giver_user_ids = new_gift.giver_user_ids;
            if (gift.receiver_user_ids != new_gift.receiver_user_ids) gift.receiver_user_ids = new_gift.receiver_user_ids;
            if (gift.created_at_client != new_gift.created_at_client) gift.created_at_client = new_gift.created_at_client;
            if (gift.created_at_server != new_gift.created_at_server) gift.created_at_server = new_gift.created_at_server;
            if (gift.price != new_gift.price) gift.price = new_gift.price;
            if (gift.currency != new_gift.currency) gift.currency = new_gift.currency;
            if (gift.direction != new_gift.direction) gift.direction = new_gift.direction;
            if (gift.description != new_gift.description) gift.description = new_gift.description;
            if (gift.open_graph_url != new_gift.open_graph_url) gift.open_graph_url = new_gift.open_graph_url;
            if (gift.open_graph_title != new_gift.open_graph_title) gift.open_graph_title = new_gift.open_graph_title;
            if (gift.open_graph_description != new_gift.open_graph_description) gift.open_graph_description = new_gift.open_graph_description;
            if (gift.open_graph_image != new_gift.open_graph_image) gift.open_graph_image = new_gift.open_graph_image;
            if (gift.like != new_gift.like) gift.like = new_gift.like;
            if (gift.follow != new_gift.follow) gift.follow = new_gift.follow;
            if (gift.show != new_gift.show) gift.show = new_gift.show;
            // todo: add gift.deleted_at_server (integer)
            if (gift.deleted_at_client != new_gift.deleted_at_client) gift.deleted_at_client = new_gift.deleted_at_client;
            if (gift.accepted_cid != new_gift.accepted_cid) gift.accepted_cid = new_gift.accepted_cid;
            if (gift.accepted_at_client != new_gift.accepted_at_client) gift.accepted_at_client = new_gift.accepted_at_client;
            // todo: should merge comments and keep sequence - not overwrite arrays
            if (!gift.hasOwnProperty('comments')) gift.comments = [];
            if (!new_gift.hasOwnProperty('comments')) new_gift.comments = [];
            if (gift.comments != new_gift.comments) refresh_comments(gift.comments, new_gift.comments);
        }; // refresh_gift

        // fresh gift and comment before update (changed in an other browser tab)
        var refresh_gift_and_comment = function (gift, comment) {
            var pgm = service + '.refresh_gift_and_comment: ';
            var cid = comment.cid;
            var old_comments_length = (gift.comments || []).length;
            refresh_gift(gift);
            var comments = gift.comments || [];
            var new_comments_length = comments.length;
            var index = -1;
            for (var i = 0; i < comments.length; i++) if (cid == comments[i].cid) index = i;
            if (index == -1) {
                // comment has been physically deleted - return empty comment {}
                for (var key in comment) if (comment.hasOwnProperty(key)) delete comment[key];
                return;
            }
            // refresh comment
            // todo: add server side comment.sha256_deleted and comment.sha256_action. almost as gifts, but a comment cannot be both accepted and deleted
            // todo: it should be enough with one client side deleted_at_server=accepted_at_server field
            if (comment.user_ids != comments[index].user_ids) comment.user_ids = comments[index].user_ids;
            if (comment.price != comments[index].price) comment.price = comments[index].price;
            if (comment.currency != comments[index].currency) comment.currency = comments[index].currency;
            if (comment.comment != comments[index].comment) comment.comment = comments[index].comment;
            if (comment.created_at_client != comments[index].created_at_client) comment.created_at_client = comments[index].created_at_client;
            if (comment.created_at_server != comments[index].created_at_server) comment.created_at_server = comments[index].created_at_server;
            if (comment.new_deal != comments[index].new_deal) comment.new_deal = comments[index].new_deal;
            if (comment.new_deal_action != comments[index].new_deal_action) comment.new_deal_action = comments[index].new_deal_action;
            if (comment.new_deal_action_by_user_ids != comments[index].new_deal_action_by_user_ids) comment.new_deal_action_by_user_ids = comments[index].new_deal_action_by_user_ids;
            if (comment.new_deal_action_at_client != comments[index].new_deal_action_at_client) comment.new_deal_action_at_client = comments[index].new_deal_action_at_client;
            if (comment.deleted_at_client != comments[index].deleted_at_client) comment.deleted_at_client = comments[index].deleted_at_client;
        }; // refresh_gift_and_comment

        // less that <ping_interval> milliseconds (see ping) between util/ping for client_userid
        // there must be more than one browser tab open with identical client login
        // js array gifts could be out of sync
        // sync changes in gifts array in local storage with js gifts array
        var sync_gifts = function () {
            var pgm = service + '. sync_gift: ';
            // console.log(pgm + 'start');

            // read "new" gifts from localStorage
            var new_gifts = [] ;
            var keys = get_gift_keys() ;
            for (var i=0 ; i < keys.length ; i++) new_gifts.push(JSON.parse(Gofreerev.getItem(keys[i]))) ;
            console.log();

            // todo: remove - index should normally always be up-to-date
            init_gifts_index();

            // insert and update gifts (keep sequence)
            var gid;
            var insert_point = new_gifts.length;
            for (i = new_gifts.length - 1; i >= 0; i--) {
                gid = new_gifts[i].gid;
                if (gid_to_gifts_index.hasOwnProperty(gid)) {
                    // update gift
                    // match between gift id in localStorage and gift in js array gifts. insert new gift before this gift
                    insert_point = gid_to_gifts_index[gid];
                    // copy any changed values from new_gifts into gifts
                    if (gifts[insert_point].giver_user_ids != new_gifts[i].giver_user_ids) gifts[insert_point].giver_user_ids = new_gifts[i].giver_user_ids;
                    if (gifts[insert_point].receiver_user_ids != new_gifts[i].receiver_user_ids) gifts[insert_point].receiver_user_ids = new_gifts[i].receiver_user_ids;
                    if (gifts[insert_point].created_at_client != new_gifts[i].created_at_client) gifts[insert_point].created_at_client = new_gifts[i].created_at_client;
                    if (gifts[insert_point].created_at_server != new_gifts[i].created_at_server) gifts[insert_point].created_at_server = new_gifts[i].created_at_server;
                    if (gifts[insert_point].price != new_gifts[i].price) gifts[insert_point].price = new_gifts[i].price;
                    if (gifts[insert_point].currency != new_gifts[i].currency) gifts[insert_point].currency = new_gifts[i].currency;
                    if (gifts[insert_point].direction != new_gifts[i].direction) gifts[insert_point].direction = new_gifts[i].direction;
                    if (gifts[insert_point].description != new_gifts[i].description) gifts[insert_point].description = new_gifts[i].description;
                    if (gifts[insert_point].open_graph_url != new_gifts[i].open_graph_url) gifts[insert_point].open_graph_url = new_gifts[i].open_graph_url;
                    if (gifts[insert_point].open_graph_title != new_gifts[i].open_graph_title) gifts[insert_point].open_graph_title = new_gifts[i].open_graph_title;
                    if (gifts[insert_point].open_graph_description != new_gifts[i].open_graph_description) gifts[insert_point].open_graph_description = new_gifts[i].open_graph_description;
                    if (gifts[insert_point].open_graph_image != new_gifts[i].open_graph_image) gifts[insert_point].open_graph_image = new_gifts[i].open_graph_image;
                    if (gifts[insert_point].like != new_gifts[i].like) gifts[insert_point].like = new_gifts[i].like;
                    if (gifts[insert_point].follow != new_gifts[i].follow) gifts[insert_point].follow = new_gifts[i].follow;
                    if (gifts[insert_point].show != new_gifts[i].show) gifts[insert_point].show = new_gifts[i].show;
                    if (gifts[insert_point].deleted_at_client != new_gifts[i].deleted_at_client) gifts[insert_point].deleted_at_client = new_gifts[i].deleted_at_client;
                    // todo: add gift.deleted_at_server (integer)
                    if (gifts[insert_point].accepted_cid != new_gifts[i].accepted_cid) gifts[insert_point].accepted_cid = new_gifts[i].accepted_cid;
                    if (gifts[insert_point].accepted_at_client != new_gifts[i].accepted_at_client) gifts[insert_point].accepted_at_client = new_gifts[i].accepted_at_client;
                    if (!gifts[insert_point].hasOwnProperty('comments')) gifts[insert_point].comments = [];
                    if (!new_gifts[i].hasOwnProperty('comments')) new_gifts[i].comments = [];
                    if (gifts[insert_point].comments != new_gifts[i].comments) refresh_comments(gifts[insert_point].comments, new_gifts[i].comments);
                }
                else {
                    // insert gift
                    console.log(pgm + 'insert gid ' + gid + ' from localStorage into js gifts array at index ' + insert_point);
                    if (new_gifts[i].hasOwnProperty('gift.show_no_comments')) delete new_gifts[i]['gift.show_no_comments'];
                    new_gifts[i].new_comment = {comment: ""};
                    gifts.splice(insert_point, 0, new_gifts[i]);
                    init_gifts_index();
                }
            }
            // remove deleted gifts
            var new_gifts_index = {};
            for (i = 0; i < new_gifts.length; i++) new_gifts_index[new_gifts[i].gid] = i;
            for (i = gifts.length - 1; i >= 0; i--) {
                gid = gifts[i].gid;
                if (!new_gifts_index.hasOwnProperty(gid)) gifts.splice(i, 1);
            }
        }; // sync_gifts


        // remove "old" error messages from gifts
        // 1) errors from veriify gifts response. delete failed. gift was "undeleted"
        // 2) errors from verify comments response. create comment failed. comment was "uncreated"
        var remove_old_errors = function () {
            var pgm = service + '.remove_old_errors: ' ;
            var now = Gofreerev.unix_timestamp() ;
            var i, gift ;
            for (i=0 ; i<gifts.length ; i++) {
                gift = gifts[i] ;
                if (gift.hasOwnProperty('link_error_at') && (now - gift.link_error_at > 60)) {
                    delete gift.link_error ;
                    delete gift.link_error_at ;
                } ;
                if (gift.hasOwnProperty('new_comment') && gift.new_comment.hasOwnProperty('error_at') && (now - gift.new_comment.error_at > 60)) {
                    delete gift.new_comment.error ;
                    delete gift.new_comment.error_at ;
                } ;
            }
        }; // remove_old_errors


        // return hash with 1-3 sha256 gift signatures used when communicating with server and other clients
        // used in new_gifts_request, accept_gifts_request and delete_gifts_request
        // also used in verify_gifts used in client to client communication
        // readonly fields in all signatures: created_at_client + description + open graph fields
        // 1) sha256: required in all requests
        //    generated from created_at_client + description + open graph fields
        //    updateable fields: price, currency, deleted_at_client, accepted_cid, accepted_at_client and user ids for "other" (not creator) user
        // 2) sha256_accepted: only used when accepting or when verifying accepted gifts
        //    generated from created_at_client + description + open graph fields + price + currency + accepted_cid + accepted_at_client
        //    updateable fields: deleted_at_client
        // 3) sha256_deleted: only used when deleting or when verifying deleted gifts
        //    generated from created_at_client + description + open graph fields + price + currency + accepted_cid + accepted_at_client + deleted_at_client
        //    updateable fields; none
        // server adds extra information to signatures from client and checks server side sha256 signatures in all requests
        // that should ensure that gift information on client is not changed
        var gift_signature_for_server = function (gift) {
            var pgm = service + '.gift_signature_for_server: ' ;
            var signature = {
                sha256: Gofreerev.sha256(gift.created_at_client, gift.description, gift.open_graph_url,
                                         gift.open_graph_title, gift.open_graph_description, gift.open_graph_image)
            };
            if (gift.accepted_at_client) signature.sha256_accepted = Gofreerev.sha256(
                gift.created_at_client, gift.description, gift.open_graph_url,
                gift.open_graph_title, gift.open_graph_description, gift.open_graph_image,
                gift.price, gift.currency, gift.accepted_cid, gift.accepted_at_client);
            if (gift.deleted_at_client) signature.sha256_deleted = Gofreerev.sha256(
                gift.created_at_client, gift.description, gift.open_graph_url,
                gift.open_graph_title, gift.open_graph_description, gift.open_graph_image,
                gift.price, gift.currency, gift.accepted_cid, gift.accepted_at_client, gift.deleted_at_client);
            // todo: testrun-46. debugging invalid gift sha256 signature in reject new deal proposal request
            console.log(pgm + 'gid = ' + gift.gid + ', signature = ' + JSON.stringify(signature)) ;
            return signature;
        }; // gift_signature_for_server


        // send meta-data for newly created gifts to server and get gift.created_at_server response (boolean) from server.
        // called from UserService.ping
        // todo: delete. now using verify_gifts_add(gift, 'create') to send create new gift request to server
        var new_gifts_request = function () {
            return null ;
            var pgm = service + '.new_gifts_request: ' ;
            var request = [];
            var gift, hash, text_client, sha256_client, signature;
            for (var i = 0; i < gifts.length; i++) {
                gift = gifts[i];
                if (!gift.hasOwnProperty('created_at_server')) {
                    signature = gift_signature_for_server(gift) ;
                    hash = {gid: gift.gid, sha256: signature.sha256};
                    if (gift.giver_user_ids && (gift.giver_user_ids.length > 0)) hash.giver_user_ids = gift.giver_user_ids;
                    if (gift.receiver_user_ids && (gift.receiver_user_ids.length > 0)) hash.receiver_user_ids = gift.receiver_user_ids;
                    request.push(hash);
                } // if
            } // for i
            return (request.length == 0 ? null : request);
        }; // created_at_server_request
        // todo: delete - now using verify_gifts with action = create
        var new_gifts_response = function (response) {
            return ;
            var pgm = service + '.new_gifts_response: ';
            // console.log(pgm + 'response = ' + JSON.stringify(response)) ;
            if (response.hasOwnProperty('error')) console.log(pgm + response.error);
            if (response.hasOwnProperty('no_errors') && (response.no_errors > 0)) console.log(pgm + response.no_errors + ' gifts was not created');
            if (!response.hasOwnProperty('gifts')) return;
            var new_gifts = response.gifts;
            var new_gift, gid, index, gift, created_at_server;
            for (var i = 0; i < new_gifts.length; i++) {
                new_gift = new_gifts[i];
                gid = new_gift.gid;
                // check response. must be an ok response without error message or error response with an error message.
                if (new_gift.hasOwnProperty('error') && new_gift.created_at_server) {
                    console.log(pgm + 'System error. Invalid new gifts response. Gift ' + gid + ' signature created on server WITH an error message. error = ' + new_gift.error) ;
                    continue ;
                }
                if (!new_gift.hasOwnProperty('error') && !new_gift.created_at_server) {
                    console.log(pgm + 'System error. Invalid new gifts response. Gift ' + gid + ' signature was not created on server and no error message was returned.') ;
                    continue ;
                }
                if (!new_gift.created_at_server) {
                    // gift signature was not created
                    console.log(pgm + 'gift ' + gid + ' signature was not created on server. ' + new_gift.error);
                    // todo: delete gift and display error message in page header
                    continue;
                }
                // gift signature was created
                if (!gid_to_gifts_index.hasOwnProperty(gid)) {
                    console.log(pgm + 'System error. Invalid gift ' + gid + ' in new gifts response (1).');
                    continue;
                }
                index = gid_to_gifts_index[gid];
                if ((index < 0) || (index >= gifts.length)) {
                    console.log(pgm + 'System error. Invalid gift ' + gid + ' in new gifts response (2).');
                    continue;
                }
                gift = gifts[index];
                if (!gift) {
                    console.log(pgm + 'System error. Invalid gift ' + gid + ' in new gifts response (3).');
                    continue;
                }

                if (gift.hasOwnProperty('created_at_server')) {
                    console.log(pgm + 'System error. Gift ' + gid + ' signature was created on server but created_at_server property was setted between new gifts request and new gifts response.') ;
                    continue ;
                }
                refresh_gift(gift);
                if (gift.hasOwnProperty('created_at_server')) {
                    // thats is ok if multiple browser sessions with identical login / identical client user id
                    if (gift.created_at_server == 0) ; // empty - ok - received in an other browser session
                    else console.log(pgm + 'System error. Gift ' + gid + ' signature was created on server but created_at_server property for gift was set to an invalid value between new gifts request and new gifts response. Expected created_at_server = 0. Found created_at_server = ' + gift.created_at_server + '.');
                    continue;
                }

                gift.created_at_server = 0; // always 0 for current server - remote gifts are received in client to client communication
                save_gift(gift) ;
            } // for i
        }; // new_gifts_response



        // internal server id <=> server sha256 signature hashes
        // server sha256 signature is used in cross server communication (send_gifts message)
        // translated to sha256 before sending message and translated back to server id after receiving message
        // loaded from /assets/ruby_to.js page at page start.
        // new servers after page start are added in /util/ping new_servers request and response
        var server_id_to_sha256_hash = {}, sha256_to_server_id_hash = {} ;
        (function () {
            server_id_to_sha256_hash = Gofreerev.rails['SERVERS'] ;
            var server_id, sha256 ;
            for (server_id in server_id_to_sha256_hash) {
                if (!server_id_to_sha256_hash.hasOwnProperty(server_id)) continue ;
                sha256 = server_id_to_sha256_hash[server_id] ;
                sha256_to_server_id_hash[sha256] = parseInt(server_id) ;
            }
        })();

        // hash with unknown server sha256 signatures:
        // - null (new request)
        // < 0 : unix timestamp for last request - waiting for response
        // > 0 : unix timestamp for last response - also unknown by serber
        var unknown_servers = {} ;

        var new_servers_request = function () {
            var now = Gofreerev.unix_timestamp() ;
            var request = [], sha256, last_request_at ;
            for (sha256 in unknown_servers) {
                if (!unknown_servers.hasOwnProperty(sha256)) continue ;
                if (typeof unknown_servers[sha256] == 'number') {
                    // unknown server. timestamp for last request / last response
                    last_request_at = unknown_servers[sha256] ;
                    if (last_request_at < 0) {
                        // waiting for response. resend request once every minute
                        if (now + last_request_at < 60) continue ;
                    }
                    else {
                        // unknown server response from server. resend request once every 10 minutes
                        if (now - last_request_at < 600) continue ;
                    }
                }
                request.push(sha256) ;
                unknown_servers[sha256] = -now ; // timestamp for request
            } // for sha256
            return (request.length == 0 ? null : request) ;
        }; // new_servers_request

        var new_servers_response = function (response) {
            var pgm = service + '.new_servers_response: ' ;
            var i, sha256, server_id ;
            for (i=0 ; i<response.length ; i++) {
                sha256 = response[i].sha256 ;
                if ((typeof response[i].server_id == 'undefined') || (response[i].server_id == null)) {
                    // unknown server response.
                    if (!unknown_servers[sha256]) {
                        console.log(pgm + 'System error. Unexpected unknown server response. server sha256 signature ' + sha256 + ' was not found in unknown_servers hash') ;
                        continue ;
                    }
                    unknown_servers[sha256] = Gofreerev.unix_timestamp() ; // timestamp for response
                    continue ;
                } // if
                // new known server
                server_id = response[i].server_id.toString ;
                if (server_id_to_sha256_hash[server_id] && (server_id_to_sha256_hash[server_id] != sha256)) {
                    // server sha256 signature never changes!
                    console.log(pgm + 'System error. Received changed sha256 signature for server id ' + server_id + '. old sha256 = ' + server_id_to_sha256_hash[server_id] + '. new sha256 = ' + sha256) ;
                    unknown_servers[sha256] = Gofreerev.unix_timestamp() ;
                    continue ;
                }
                server_id_to_sha256_hash[server_id] = sha256 ;
                sha256_to_server_id_hash[sha256] = response[i].server_id ;
                if (unknown_servers.hasOwnProperty(sha256)) delete unknown_servers[sha256] ;
            } // for i
        }; // new_servers_response

        // before send - translate internal server ids to sha256 signatures
        var server_id_to_sha256 = function (server_id) {
            var pgm = service + '.server_id_to_sha256: ' ;
            var server_idx = server_id.toString() ;
            if (server_id_to_sha256_hash.hasOwnProperty(server_idx)) return server_id_to_sha256_hash[server_idx] ;
            console.log(pgm + 'Cannot translate unknown server id ' + server_id) ;
            return null ;
        }; // server_id_to_sha256

        // after receive - translate server sha256 signatures to internal server ids
        var sha256_to_server_id = function (sha256) {
            if (!sha256_to_server_id_hash.hasOwnProperty(sha256)) return null ;
            return sha256_to_server_id_hash[sha256] ;
        }; // sha256_to_server_id



        // make verify_gift request for one gift. Used in verify_gifts_request and verify_gifts_response (control)
        var verify_gift_to_hash = function (verify_gift) {
            // prepare request - using same client sha256 calculations as in new_gifts_request
            //sha256_client = Gofreerev.sha256(
            //    verify_gift.created_at_client.toString(), verify_gift.description, verify_gift.open_graph_url,
            //    verify_gift.open_graph_title, verify_gift.open_graph_description, verify_gift.open_graph_image);
            //hash = {
            //    gid: verify_gift.gid,
            //    sha256: signatures.sha256_client
            //};
            // calculate 1-3 client side signatures (sha256, sha256_accepted and/or sha256_deleted)
            var signatures = gift_signature_for_server(verify_gift) ;
            var hash = { gid: verify_gift.gid, sha256: signatures.sha256, action: verify_gift.verify_gift_action };
            if (signatures.sha256_accepted) hash.sha256_accepted = signatures.sha256_accepted ;
            if (signatures.sha256_deleted) hash.sha256_deleted = signatures.sha256_deleted ;
            // add user ids
            if (verify_gift.giver_user_ids.length > 0) hash.giver_user_ids = verify_gift.giver_user_ids ;
            if (verify_gift.receiver_user_ids.length > 0) hash.receiver_user_ids = verify_gift.receiver_user_ids ;
            // add server id (only for remote gifts)
            if (verify_gift.created_at_server != 0) hash.server_id = verify_gift.created_at_server ;
            return hash ;
        }; // verify_gift_to_hash

        var verify_gifts_request = function () {
            var pgm = service + '.verify_gifts_request: ';
            // check buffer for "old gifts". should normally be empty except for gifts with negative seq (remote gifts - remote actions)
            // local gifts are allowed if device is offline or if server does not respond
            var local_seq = 0 ;
            var seq ;
            var no_gifts = { local: 0, remote: 0, create: 0, verify: 0, accept: 0, delete: 0 } ;
            var request = [] ;
            for (seq in verify_gifts_seq_to_gifts) {
                // count old actions
                if (['create', 'verify', 'accept', 'delete'].indexOf(verify_gifts_seq_to_gifts[seq].action) != -1) {
                    no_gifts[verify_gifts_seq_to_gifts[seq].action] += 1 ;
                }
                else {
                    console.log(pgm + 'System error. Found invalid action ' + verify_gifts_seq_to_gifts[seq].action + ' in verify gifts buffer.');
                    console.log(pgm + 'verify_gifts_seq_to_gifts[' + seq + '] = ' + verify_gifts_seq_to_gifts[seq]) ;
                    continue ;
                };
                // count local/remote
                if (parseInt(seq) >= 0) {
                    // found "old" local gifts action in buffer. device must be offline or server is not responding. resend previous request
                    no_gifts.local += 1;
                    if (parseInt(seq) > local_seq) local_seq = parseInt(seq) ;
                    request.push(verify_gifts_seq_to_gifts[seq].request) ;
                }
                else no_gifts.remote += 1 ; // ok - remote gift actions can take some time (verify, accept or delete)
            }; // for seq
            
            if (verify_gifts_online && (no_gifts.local + no_gifts.remote > 0)) {
                // warning. Old requests found in gifts action buffer
                console.log(pgm + 'Found ' + no_gifts.local + ' local and ' + no_gifts.remote + ' remote gifts in gifts action buffer. ' +
                    no_gifts.create + ' create, '  + no_gifts.verify + ' verify, ' + no_gifts.accept + ' accept and ' + no_gifts.delete + ' delete gift requests') ;
            };
            if (verify_gifts.length == 0) return (request.length == 0 ? null : request) ; // no new gifts for verification

            // loop for new gifts in verify_gifts array
            var no_new_gifts = verify_gifts.length ;
            var already_verified = 0 ;
            var waiting_for_verification = 0 ;
            var old_request = request.length ; // resend old requests
            var new_request = 0 ;
            var verify_gift, sha256_client, hash, key ;

            // loop for gift actions in verify gifts buffer
            while (verify_gifts.length > 0) {
                verify_gift = verify_gifts.shift();
                if (verify_gift.hasOwnProperty('verified_at_server')) {
                    // ignore gift. gift has already been verified. can maybe happen if same gift object has been received from more than one client
                    already_verified += 1;
                    continue;
                }
                if (verify_gift.hasOwnProperty('verify_seq')) {
                    // must be a remote gift waiting for validation on an other gofreerev server
                    waiting_for_verification += 1;
                    continue;
                } // if
                // make request (create, verify, accept or delete gift)
                hash = verify_gift_to_hash(verify_gift);
                key = JSON.stringify(hash);
                // check verify gifts buffer
                seq = verify_gifts_key_to_seq[key];
                if (seq) {
                    // key/request already in verify gifts buffer (must be identical gift received in multiple incoming messages - verify gift requests)
                    verify_gift.verify_seq = seq ;
                    verify_gifts_seq_to_gifts[seq].gifts.push(verify_gift);
                    if (verify_gifts_seq_to_gifts[seq].action != 'verify') {
                        console.log(pgm + 'Warning. Multiple ' + verify_gifts_seq_to_gifts[seq].action + ' gift requests for ' +  verify_gifts_seq_to_gifts[seq].gid) ;
                    };
                }
                else {
                    // new request. add to verify gifts buffer and request array
                    if ((verify_gift.verify_gift_action == 'create') || (verify_gift.created_at_server == 0)) {
                        // local verification. positive seq. gift on this gofreerev server
                        local_seq += 1;
                        hash.seq = local_seq ;
                    }
                    else hash.seq = -Gofreerev.get_next_seq() ; // remote verification. negative seq. gift created in an other Gofreerev server
                    verify_gift.verify_seq = hash.seq ;
                    verify_gifts_key_to_seq[key] = hash.seq ;
                    verify_gifts_seq_to_gifts[hash.seq] = {
                        gid: verify_gift.gid,
                        action: verify_gift.verify_gift_action,
                        key: key,
                        gifts: [verify_gift],
                        request: hash
                    };
                    request.push(hash);
                    new_request += 1 ;
                }
            } // verify_gifts while loop

            if (already_verified > 0) console.log(pgm + 'Warning. Found ' + already_verified + ' already verified gifts in verify_gifts buffer.');
            if (waiting_for_verification > 0) console.log(pgm + 'Warning. Found ' + waiting_for_verification + ' gifts waiting for verification in verify_gifts buffer.');
            if (old_request > 0) console.log(pgm + 'Warning. Found ' + old_request + ' old requests in verify gifts buffer.') ;
            if (new_request > 0) console.log(pgm + new_request + ' new gift verification requests sent to server.');
            return (request.length == 0 ? null : request);
        }; // verify_gifts_request

        var verify_gifts_response = function (response) {
            var pgm = service + '.verify_gifts_response: ';
            var error ;

            if (response.error) {
                // fatal error
                if (typeof response.error == 'object') error =  I18n.t('js.gift_actions.' + response.error.key, response.error.options);
                else error = response.error ;
                console.log(pgm + 'Fatal verify gifts error: ' + error) ;
                // todo: notification
                return ;
            };

            // check seq. seq must be unique i response and all positive seq must be in verify gifts buffer
            var seqs = [], i, not_unique_seq = 0, seq, invalid_local_seq = 0, old_remote_seq = [], invalid_remote_seq = 0, invalid_gid = 0, gift, hash  ;
            for (i=0 ; i<response.gifts.length ; i++) {
                gift = response.gifts[i] ;
                seq = gift.seq;
                if (seqs.indexOf(seq) == -1) {
                    seqs.push(seq) ;
                    if (!verify_gifts_seq_to_gifts[seq]) {
                        // unknown seq!
                        if (seq >= 0) invalid_local_seq += 1 ;
                        else {
                            // ok if remote verification was started in a previous session / before page reload
                            // todo: there is a problem with multiple client sessions with same client_userid. remote verification can be started by one client and response received by an other client!
                            // todo: is there a mailbox per device or a mailbox per client?
                            if (verify_gifts_old_remote_seq == null) verify_gifts_old_remote_seq = 0 ;
                            else if (typeof verify_gifts_old_remote_seq == 'string') verify_gifts_old_remote_seq = parseInt(verify_gifts_old_remote_seq) ;
                            if (-seq <= verify_gifts_old_remote_seq) old_remote_seq.push(seq) ; // ignore old remote verifications (js variables have been resetted)
                            else invalid_remote_seq += 1 ;
                        }
                    }
                    else if (verify_gifts_seq_to_gifts[seq].gid != gift.gid) invalid_gid += 1 ;
                }
                else not_unique_seq += 1 ;
            } ; // for i
            seqs = null ;

            // receipt - abort if errors in verify gifts response
            if (not_unique_seq > 0) console.log(pgm + 'Error. ' + not_unique_seq + ' not unique seq in verify gifts response.') ;
            if (invalid_local_seq > 0) console.log(pgm + 'Error. ' + invalid_local_seq + ' invalid local seq in verify gifts response.') ;
            if (invalid_remote_seq > 0) console.log(pgm + 'Error. ' + invalid_remote_seq + ' invalid remote seq in verify gifts response.') ;
            if (invalid_gid > 0) console.log(pgm + invalid_gid + ' invalid gift id (gid) in verify gifts response.') ;
            if (old_remote_seq.length > 0) console.log(pgm + 'Warning. ' + old_remote_seq + ' old unknown remote seq in verify gifts response') ;
            if (not_unique_seq + invalid_local_seq + invalid_remote_seq + invalid_gid > 0) return ; // abort after fatal system errors. todo: add notification

            // loop for each row in verify gifts response (create, verify, accept or delete)
            // one row in response can be answer to multiple verify gifts requests (verify_gifts_seq_to_gifts[seq].gifts)
            // ( identical gift received in multiple send_gifts messages from other clients )
            var gift_verification, gid, new_gifts, key, verify_gift_action ;
            var no_gifts = { all: 0, create: 0, verify: 0, accept: 0, delete: 0, local: 0, remote: 0, syserr1: 0, syserr2: 0, syserr3: 0, resend: 0, true: 0, false: 0} ;
            var empty_new_gift_form ;
            while (response.gifts.length > 0) {
                gift_verification = response.gifts.shift();
                // ignore response from old remote gift actions (from before page reload)
                seq = gift_verification.seq ;
                if (old_remote_seq.indexOf(seq) != -1) continue ;
                // seq is ok - checked in previous loop
                gid = verify_gifts_seq_to_gifts[seq].gid ;
                verify_gift_action = verify_gifts_seq_to_gifts[seq].action ;
                // logical validate verify gift response. must be an ok response (verified_at_server=true) without error message (error=key=options=null) or must be
                // an error response (verified_at_server=false) with either error (cross server error message) or key+options (within server error message)
                if (gift_verification.verified_at_server && (gift_verification.hasOwnProperty('error') || gift_verification.hasOwnProperty('key') ||gift_verification.hasOwnProperty('options'))) {
                    console.log(pgm + 'System error in ' + verify_gift_action + ' response from server for gift ' + gid + '. OK response but error information was also returned');
                    console.log(pgm + 'request  = ' + JSON.stringify(verify_gifts_seq_to_gifts[seq].request)) ;
                    console.log(pgm + 'response = ' + JSON.stringify(gift_verification)) ;
                    // todo: system error count + notification
                    continue ;
                }; // if
                if (!gift_verification.verified_at_server) {
                    // gift action rejected by server. check error format. error format must be :error or :key+:options
                    if (!gift_verification.hasOwnProperty('error') && !gift_verification.hasOwnProperty('key') && !gift_verification.hasOwnProperty('options')) {
                        console.log(pgm + 'System error in ' + verify_gift_action + ' response from server for gift ' + gid + '. Inconsistent error response without any error information');
                        console.log(pgm + 'request  = ' + JSON.stringify(verify_gifts_seq_to_gifts[seq].request)) ;
                        console.log(pgm + 'response = ' + JSON.stringify(gift_verification)) ;
                        // todo: system error count + notification
                        continue ;
                    };
                    if (gift_verification.hasOwnProperty('error') && (gift_verification.hasOwnProperty('key') || gift_verification.hasOwnProperty('options'))) {
                        console.log(pgm + 'System error in ' + verify_gift_action + ' response from server for gift ' + gid + '. Inconsistent error response with :error and :key+:options');
                        console.log(pgm + 'request  = ' + JSON.stringify(verify_gifts_seq_to_gifts[seq].request)) ;
                        console.log(pgm + 'response = ' + JSON.stringify(gift_verification)) ;
                        // todo: system error count + notification
                        continue ;
                    };
                    if (gift_verification.hasOwnProperty('options') && !gift_verification.hasOwnProperty('key')) {
                        console.log(pgm + 'System error in ' + verify_gift_action + ' response from server for gift ' + gid + '. Inconsistent error response with :options without :key');
                        console.log(pgm + 'request  = ' + JSON.stringify(verify_gifts_seq_to_gifts[seq].request)) ;
                        console.log(pgm + 'response = ' + JSON.stringify(gift_verification)) ;
                        // todo: system error count + notification
                        continue ;
                    };
                }; // if
                new_gifts = verify_gifts_seq_to_gifts[seq].gifts;
                // one or more gifts in verify gifts buffer with this seq/key
                while (new_gifts.length > 0) {
                    no_gifts.all += 1 ;
                    gift = new_gifts.shift() ;
                    no_gifts[gift.verify_gift_action] += 1 ; // action: create, verify, accept and delete
                    if (seq > 0) no_gifts.local += 1 ;
                    else no_gifts.remote += 1 ;
                    // check gifts array. new_gift is either from gifts array (!verify) or from an incoming send_gifts message (verify)
                    if ((gift.verify_gift_action != 'verify') && (gifts.indexOf(gift) == -1)) {
                        // actions create, accept and delete. gift is no longer in gifts array!
                        console.log(pgm + 'System error. Received ' + gift.verify_gift_action + ' gift response from server for gift ' + gift.gid + ' but gift is no longer in gifts array') ;
                        no_gifts.syserr2 += 1 ;
                        continue ;
                    }; // if

                    // recheck key. check if gift has changed between verify gifts request and response (remote verification can take some time)
                    hash = verify_gift_to_hash(gift);
                    key = JSON.stringify(hash);
                    if (key != verify_gifts_seq_to_gifts[seq].key) {
                        // gift changed between verify gifts request and verify gifts response.
                        if (verify_gifts_seq_to_gifts[seq].action != gift.verify_gift_action) {
                            console.log(pgm + 'System error. gift.verify_gift_action for gift ' + gift.gid +
                                ' was changed between verify gifts request (' + verify_gifts_seq_to_gifts[seq].action +
                                ') and verify gifts response (' + gift.verify_gift_action + ')') ;
                            no_gifts.syserr1 += 1 ;
                            continue ;
                        };
                        // write warning in log and and send a new verify gifts request with changed gift
                        // todo: check verify_gift_action. ok to resend verify. Maybe not ok to resend create, accept or delete gift.
                        console.log(pgm + 'Warning. Gift ' + gift.gid + ' was changed between verify gifts request and verify gifts response.') ;
                        console.log(pgm + 'old key = ' + verify_gifts_seq_to_gifts[seq].key) ;
                        console.log(pgm + 'new key = ' + key) ;
                        console.log(pgm + 'Resending gift ' + gift.gid + ' to server for verification') ;
                        delete gift.verify_gift_at ;
                        verify_gift_action = gift.verify_gift_action ;
                        delete gift.verify_gift_action ;
                        delete gift.verify_seq ;
                        verify_gifts_add(gift, verify_gift_action) ;
                        no_gifts.resend += 1 ;
                        continue ;
                    }; // if

                    // do or rollback actions: create, verify, accept or delete
                    no_gifts[gift_verification.verified_at_server] += 1 ; // true or false
                    switch(gift.verify_gift_action) {

                        case 'create':
                            // create new gift operation. new_gift object should by in gifts array (already checked)
                            if (gift_verification.verified_at_server) {
                                // gift create ok. add created_at_server = 0 (gift is already in gifts array with created_at_server = 0 - created on this Gofreerev server)
                                if (gift.hasOwnProperty('created_at_server')) {
                                    // not possible. new_gift object changed between verify gifts request and verify gifts response
                                    console.log(pgm + 'System error. Gift ' + gid + ' signature was created on server but created_at_server property was set between verify gifts request and verify gifts response.') ;
                                    no_gifts.syserr3 += 1 ;
                                    // todo: send notification
                                    continue ;
                                };
                                // recheck gift in localStorage
                                refresh_gift(gift);
                                if (gift.hasOwnProperty('created_at_server')) {
                                    // thats is ok if multiple browser sessions (windows or tabs) with identical login / identical client user id
                                    if (gift.created_at_server == 0) continue; // ok - received in an other browser session
                                    console.log(pgm + 'System error. Gift ' + gid + ' signature was created on server but created_at_server property for gift was set to an invalid value between verify gifts request and verify gifts response. Expected created_at_server = 0. Found created_at_server = ' + gift.created_at_server + '.');
                                    no_gifts.syserr3 += 1 ;
                                    // todo: send notification
                                    continue;
                                };
                                // create gift ok
                                gift.created_at_server = 0; // always 0 for current server for create
                                // ready for next gift action - clear info used in verify comment request & response
                                delete gift.verify_seq ;
                                delete gift.verify_gift_at ;
                                delete gift.verify_gift_action ;
                                save_gift(gift) ;
                            }
                            else {
                                // gift create failed
                                if (typeof gift_verification.error == 'object') error =  I18n.t('js.gift_actions.' + gift_verification.error.key, gift_verification.error.options);
                                else error = gift_verification.error ;
                                console.log(pgm + 'create new gift failed for gid ' + gid + ' with error message: ' + error) ;
                                // remove gift from gifts array.
                                i = gifts.indexOf(gift) ;
                                gifts.splice(i,1) ;
                                init_gifts_index() ;
                                // empty new gift form?
                                empty_new_gift_form = ( (gift.direction == 'giver') &&
                                                        ((gift.price == null) || (gift.price == '')) &&
                                                        ((gift.description == null) || (gift.description == '')) &&
                                                        ((gift.open_graph_url == null) || (gift.open_graph_url == '')) );
                                if (empty_new_gift_form) {
                                    // blank new gift form. Move failed new gift back to new gift form and display error message and send notification
                                    console.log(pgm + 'uncreate gid ' + gid + '. failed create gift is moved (back) to new_gift form.') ;
                                    new_gift.direction = gift.direction ;
                                    new_gift.price = gift.price ;
                                    new_gift.description = gift.description ;
                                    new_gift.open_graph_url = gift.open_graph_url ;
                                    new_gift.error =  error ;
                                    new_gift.error_at = Gofreerev.unix_timestamp() ;
                                }
                                else {
                                    // new gift form in use. Write error message in log + send notification
                                    console.log(pgm + 'new_gift form already in use. display error message only in log and notification') ;
                                    console.log(pgm + 'uncreated gift was ' + JSON.stringify(gift)) ;
                                }; // if
                                // todo: send notification just in case new gift form was outside windows or new gift form was already in use

                            }; // if
                            break;

                        case 'verify':
                            // used in receive_message_send_gifts
                            gift.verified_at_server = gift_verification.verified_at_server ;
                            if (!gift_verification.verified_at_server) {
                                // gift verification failed. copy error object. is used in receive_message_send_gifts
                                gift.verified_error = gift_verification.error ;
                                if (typeof gift_verification.error == 'object') error =  I18n.t('js.gift_actions.' + gift_verification.error.key, gift_verification.error.options);
                                else error = gift_verification.error ;
                                // write error message to log. no notification here. Any notifications are sent from receive_message_send_gifts
                                console.log(pgm + 'verify gift failed for gid ' + gid + ' with error message: ' + error) ;
                            }
                            break;

                        case 'accept':
                            if (gift_verification.verified_at_server) {
                                // gift accept ok. add accepted_at_server = created_at_server
                            }
                            else {
                                // gift accept failed.
                                // todo: must rollback accept gift action (gift and comment)
                                // todo: should display error message (from server)
                            };
                            break;

                        case 'delete':
                            if (!gift.hasOwnProperty('deleted_at_client')) {
                                console.log(pgm + 'System error. Received delete gift response from server but gift ' + gift.gid + ' has not been deleted by client') ;
                                console.log(pgm + 'response = ' + JSON.stringify(gift_verification)) ;
                                // todo: no_gifts.syserr<n> += 1 + notification
                                continue ;
                            };
                            if (gift_verification.verified_at_server) {
                                // delete gift ok. add deleted_at_server = created_at_server
                                if (gift.hasOwnProperty('deleted_at_server')) {
                                    console.log(pgm + 'System error. Gift ' + gift.cid + ' deleted marked on server but deleted_at_server property was set between verify gifts request and verify gifts response.') ;
                                    // todo: no_gifts.syserr<n> += 1 + notification
                                    continue ;
                                };
                                refresh_gift(gift);
                                if (gift.hasOwnProperty('deleted_at_server')) {
                                    // that is ok if multiple browser sessions (windows or tabs) with identical login / identical client user id
                                    if (gift.deleted_at_server == gift.created_at_server) continue ; // ok - gift delete response received in an other browser session
                                    console.log(pgm + 'System error. Gift ' + gift.cid + ' signature was deleted on server but deleted_at_server property for gift was set to an invalid value between verify comments request and verify comments response. Expected deleted_at_server = ' + gift.created_at_server + '. Found deleted_at_server = ' + gift.deleted_at_server);
                                    no_gifts.syserr3 += 1 ;
                                    continue;
                                } // if
                                // delete gift ok
                                gift.deleted_at_server = gift.created_at_server ;
                            }
                            else {
                                // delete gift failed.
                                if (gift.hasOwnProperty('deleted_at_server')) {
                                    console.log(pgm + 'System error. Gift ' + gift.cid + ' delete was reject by server but has already been deleted in client') ;
                                    console.log(pgm + 'Server response was ' + JSON.stringify(gift_verification)) ;
                                    console.log(pgm + 'gift.created_at_server = ' + gift.created_at_server) ;
                                    console.log(pgm + 'gift.deleted_at_server = ' + gift.deleted_at_server) ;
                                    // todo: no_gifts.syserr<n> count + notification
                                    continue ;
                                } ;
                                // undelete gift
                                delete gift.deleted_at_client;
                                // display error message
                                // todo: handle missing translations
                                // todo: seq > 0. should have key and translation. seq < 0. should have english error message only
                                gift.link_error_at = Gofreerev.unix_timestamp();
                                if (gift_verification.hasOwnProperty('key')) gift.link_error = I18n.t('js.gift_actions.' + gift_verification.key, gift_verification.options);
                                else gift.link_error = gift_verification.error ;
                            }; // if
                            // save gift - deleted (success) or undeleted (failure)
                            save_gift(gift) ;
                            // cleanup info used in verify comment request & response
                            delete gift.verify_seq ;
                            delete gift.verify_comment_at ;
                            delete gift.verify_comment_action ;
                            break;

                    }; // switch

                    // todo: remove new_gift.verify_gift_action, new_gift.verify_gift_at and new_gift.verify_seq

                }; // while
                // remove from verify gifts buffer
                key = verify_gifts_seq_to_gifts[seq].key ;
                delete verify_gifts_seq_to_gifts[seq] ;
                delete verify_gifts_key_to_seq[key] ;
            } // while response.length > 0

            // receipt
            // todo: add number create, verify, accept, delete, local, remote, syserr1, resend, true and false in receipt
            console.log(pgm + 'Received response for ' + no_gifts.all + ' gift actions (' + no_gifts.true + ' valid and ' + no_gifts.false + ' invalid).') ;

        }; // verify_gifts_response


        // todo: remember delete request for remote gifts? this is gifts with created_at_server != 0. verification of remote gifts can take some time

        // send meta-data for deleted gifts to server and get gift.deleted_at_server response (boolean) from server.
        // called from UserService.ping
        // todo: delete - moved to verify gifts request with action = delete
        var delete_gifts_request = function () {
            return ;
            var pgm = service + '.delete_gifts_request: ' ;
            var request = [];
            var gift, hash, signatures ;
            for (var i = 0; i < gifts.length; i++) {
                gift = gifts[i];
                if (!gift.hasOwnProperty('created_at_server')) continue ; // wait for create gifts request to finish
                if (!gift.deleted_at_client) continue ;
                if (!gift.deleted_at_server) {
                    signatures = gift_signature_for_server(gift);
                    hash = {gid: gift.gid, sha256: signatures.sha256, sha256_deleted: signatures.sha256_deleted};
                    if (signatures.sha256_accepted) hash.sha256_accepted = signatures.sha256_accepted ;
                    if (gift.giver_user_ids && (gift.giver_user_ids.length > 0)) hash.giver_user_ids = gift.giver_user_ids;
                    if (gift.receiver_user_ids && (gift.receiver_user_ids.length > 0)) hash.receiver_user_ids = gift.receiver_user_ids;
                    if (gift.created_at_server != 0) hash.server_id = gift.created_at_server ; // remote gift
                    request.push(hash);
                } // if
            } // for i
            return (request.length == 0 ? null : request);
        }; // delete_gifts_request

        // todo: delete - moved to verify gifts request with action = delete
        var delete_gifts_response = function (response) {
            return ;
            var pgm = service + '.delete_gifts_response: ';
            // console.log(pgm + 'response = ' + JSON.stringify(response)) ;
            if (response.hasOwnProperty('error')) console.log(pgm + response.error);
            if (response.hasOwnProperty('no_errors') && (response.no_errors > 0)) console.log(pgm + response.no_errors + ' gifts was not deleted. See following error message.');
            if (!response.hasOwnProperty('gifts')) return;
            var new_gifts = response.gifts;
            var new_gift, gid, index, gift, created_at_server, noti;
            function add_index_error (gid, ref) {
                // system error in gid/gift lookup
                cache_nid.delete_gift_syserr123_nid = notiService.add_notification({
                    notitype: 'delete_gift', key: 'syserr' + ref, options: {gid: gid, ref: ref},
                    extra: {gid: gid, ref: ref}, nid: cache_nid.delete_gift_syserr123_nid}) ;
            }
            function add_response_error (new_gift, ref) {
                // system error in delete gifts response
                cache_nid.delete_gift_syserr456_nid = notiService.add_notification({
                    notitype: 'delete_gift', key: 'syserr' + ref, options: { gid: new_gift.gid, error: new_gift.error, key: new_gift.key, options: JSON.stringify(new_gift.options)},
                    extra: {gid: gift.gid, ref: ref}, nid: cache_nid.delete_gift_syserr456_nid}) ;
            }
            for (var i = 0; i < new_gifts.length; i++) {
                new_gift = new_gifts[i];
                // lookup gift
                gid = new_gift.gid;
                if (!gid_to_gifts_index.hasOwnProperty(gid)) { add_index_error(gid, 1) ; continue; }
                index = gid_to_gifts_index[gid];
                if ((index < 0) || (index >= gifts.length)) { add_index_error(gid, 2) ; continue; }
                gift = gifts[index];
                if (!gift) { add_index_error(gid, 3); continue; }
                // check response. must be an ok response without error message (error=key=options=null) or an error
                // response with either an error message (cross server error) or with key+options (within server error)
                if (new_gift.deleted_at_server && (new_gift.hasOwnProperty('error') || new_gift.hasOwnProperty('key') || new_gift.hasOwnProperty('options'))) {
                    // unexpected error information
                    add_response_error (new_gift,4) ;
                    continue ;
                }
                if (!new_gift.deleted_at_server) {
                    // gift delete rejected by server
                    if (!new_gift.hasOwnProperty('error') && !new_gift.hasOwnProperty('key') && !new_gift.hasOwnProperty('options')) {
                        add_response_error (new_gift,5) ; // no error information
                        continue ;
                    }
                    if (new_gift.hasOwnProperty('error') && (new_gift.hasOwnProperty('key') || new_gift.hasOwnProperty('options'))) {
                        add_response_error (new_gift,6) ; // inconsistent error information
                        continue ;
                    }
                    if (new_gift.hasOwnProperty('options') && !new_gift.hasOwnProperty('key')) {
                        add_response_error (new_gift,6) ; // inconsistent error information
                        continue ;
                    }

                }
                if (!new_gift.deleted_at_server) {
                    // delete gift request failed. see error message from server
                    console.log(pgm + 'Gift ' + gid + '. Delete gift request failed. ' + new_gift.error);
                    gift.link_error = new_gift.error ;
                    gift.link_error_at = Gofreerev.unix_timestamp() ;
                    gift.link_error_delete_nid = notiService.add_notification({
                        notitype: 'delete_gift', key: 'error', options: {error: new_gift.error},
                        nid: gift.link_error_delete_nid,
                        url:'todo: add show gift url',
                        extra: {gid: gid}}) ;
                    // undelete gift
                    refresh_gift(gift) ;
                    delete gift.deleted_at_client ;
                    save_gift(gift) ;
                    continue;
                }
                // todo: how to handle "remote delete". created by user A on server A, replicated to user A on server B. deleted by under A on server B.
                // gift delete signature was created
                if (gift.hasOwnProperty('deleted_at_server')) {
                    console.log(pgm + 'System error. Gift ' + gid + ' deleted marked on server but deleted_at_server property was set between delete gifts request and delete gifts response.') ;
                    continue ;
                }
                refresh_gift(gift);
                if (gift.hasOwnProperty('deleted_at_server')) {
                    // that is ok if multiple browser sessions with identical login / identical client user id
                    if (gift.deleted_at_server == 1) ; // empty - ok - response received in an other browser session
                    else console.log(pgm + 'System error. Gift ' + gid + ' deleted signature was created on server but deleted_at_server property for gift was setted to an invalid value between delete gifts request and delete gifts response. Expected deleted_at_server = 1. Found deleted_at_server = ' + gift.deleted_at_server + '.');
                    continue;
                }
                gift.deleted_at_server = 1;
                save_gift(gift) ;
                save = true;
            } // for i
        }; // delete_gifts_response

        // return hash with <n> sha256 comment signatures used when communicating with server and other clients
        // used in new_comments_request, verify_comments_request and delete_comments_request
        // readonly fields in all signatures: gid, created_at_client + comment + price and currency
        // 1) sha256: required in all requests
        //    generated from gid + created_at_client + comment + price + currency + new_deal
        //    updateable fields: new_deal_action, new_deal_action_by_user_ids, new_deal_action_at_client and deleted_at_client
        // 2) sha256_action: only used when cancelling, accepting or rejecting new deal proposal (new_deal=true)
        //    generated from gid + created_at_client + comment + price + currency + new_deal + new_deal_action + new_deal_action_at_client
        //    updateable fields: deleted_at_client
        // 3) sha256_deleted: only used when deleting or when verifying deleted gifts
        //    generated from gid + created_at_client + comment + price + currency + new_deal + new_deal_action + new_deal_action_at_client + deleted_at_client
        //    updateable fields; none
        // server adds extra information to signatures from client and checks server side sha256 signatures in all requests
        // that should ensure that gift information on client is not changed

        var comment_signature_for_server = function (gid, comment) {
            var signature = {
                sha256: Gofreerev.sha256(gid, comment.created_at_client.toString(), comment.comment, comment.price, comment.currency, comment.new_deal)
            };
            if (comment.new_deal_action) signature.sha256_action = Gofreerev.sha256(gid, comment.created_at_client.toString(), comment.comment, comment.price, comment.currency, comment.new_deal, comment.new_deal_action, comment.new_deal_action_at_client) ;
            if (comment.deleted_at_client) signature.sha256_deleted = Gofreerev.sha256(gid, comment.created_at_client.toString(), comment.comment, comment.price, comment.currency, comment.new_deal, comment.new_deal_action, comment.new_deal_action_at_client, comment.deleted_at_client) ;
            return signature;
        };

        
        // send meta-data for new comments to server and get comment.created_at_server boolean.
        // called from UserService.ping
        // todo: delete. now using verify_comments_add(gift, comment, 'create') to send create new comment request to server
        var new_comments_request_index = {}; // from cid to [gift,comment] - used in new_comments_response for quick comment lookup
        var new_comments_request = function () {
            return null ;
            var pgm = service + '.new_comments_request: ';
            var request = [], signature ;
            new_comments_request_index = {};
            var gift, comments, comment, hash, sha256_client, cid;
            for (var i = 0; i < gifts.length; i++) {
                if (!gifts[i].comments) continue;
                gift = gifts[i];
                comments = gifts[i].comments;
                for (var j = 0; j < comments.length; j++) {
                    if (comments[j].hasOwnProperty('created_at_server')) continue;
                    comment = comments[j];
                    cid = comment.cid;
                    // send meta-data for new comment to server and generate a sha256 signature for comment on server
                    signature = comment_signature_for_server(gift.gid, comment) ;
                    hash = {cid: cid, user_ids: comment.user_ids, sha256: signature.sha256};
                    request.push(hash);
                    // cid to gift+comment helper - used in new_comments_response for quick gift and comment lookup
                    new_comments_request_index[cid] = [gift, comment];
                } // for j
            } // for i
            return (request.length == 0 ? null : request);
        }; // new_comments_request
        var new_comments_response = function (response) {
            return ;
            var pgm = service + '.new_comments_response: ';
            // console.log(pgm + 'response = ' + JSON.stringify(response)) ;
            if (response.hasOwnProperty('error')) console.log(pgm + response.error);
            if (response.hasOwnProperty('no_errors') && (response.no_errors > 0)) console.log(pgm + response.no_errors + ' comments was not created');
            if (!response.hasOwnProperty('comments')) return;
            var new_comments = response.comments;
            var new_comment, cid, comment, created_at_server;
            var gift_and_comment, gift ;
            for (var i = 0; i < new_comments.length; i++) {
                new_comment = new_comments[i];
                cid = new_comment.cid;
                // check response. must be an ok response without error message or error response with an error message.
                // created_at_server: boolean in server response. integer 0 in javascript (current server)
                if (new_comment.hasOwnProperty('error') && new_comment.created_at_server) {
                    console.log(pgm + 'System error. Invalid new comments response. Comment ' + cid + ' signature created on server WITH an error message. error = ' + new_comment.error) ;
                    continue ;
                }
                if (!new_comment.hasOwnProperty('error') && !new_comment.created_at_server) {
                    console.log(pgm + 'System error. Invalid new comments response. Comment ' + cid + ' signature was not created on server and no error message was returned.') ;
                    continue ;
                }
                if (!new_comment.created_at_server) {
                    // comment signature was not created
                    console.log(pgm + 'Comment ' + cid + ' signature was not created on server. ' + new_comment.error);
                    // todo: delete comment and display error message in page header or insert as an user notification
                    continue;
                }
                // comment signature was created
                if (!new_comments_request_index.hasOwnProperty(cid)) {
                    console.log(pgm + 'System error. Unknown comment ' + cid + ' in new comments response (1)');
                    continue;
                }
                gift_and_comment = new_comments_request_index[cid] ;
                gift = gift_and_comment[0] ;
                comment = gift_and_comment[1] ;
                if (!comment) {
                    console.log(pgm + 'System error. Unknown comment ' + cid + ' in new comments response (2)');
                    continue;
                };
                if (comment.hasOwnProperty('created_at_server')) {
                    console.log(pgm + 'System error. Comment ' + cid + ' signature was created on server but created_at_server property was setted between new comments request and new comments response.') ;
                    continue ;
                };
                // todo: add refresh_comment method
                // refresh_comment(comment) ;
                if (comment.hasOwnProperty('created_at_server')) {
                    // thats is ok if multiple browser sessions with identical login / identical client user id
                    if (comment.created_at_server == 0) ; // empty - ok - received in an other browser session
                    else console.log(pgm + 'System error. Comment ' + cid + ' signature was created on server but created_at_server property for comment was set to an invalid value between new comments request and new comments response. Expected created_at_server = 0. Found created_at_server = ' + comment.created_at_server + '.');
                    continue;
                }
                comment.created_at_server = 0;
                save_gift(gift) ;
            } // for i
            new_comments_request_index = {};
        }; // new_comments_response




        // make verify_comment request for one comment. Used in verify_comments_request and verify_comments_response (control)
        var verify_comment_to_hash_and_key = function (gift, verify_comment) {
            // prepare request - using same client sha256 calculations as in new_comments_request
            // calculate 1-3 client side signatures (sha256, sha256_action and/or sha256_deleted)
            var signatures = comment_signature_for_server(gift.gid, verify_comment) ;
            var comment_hash = { cid: verify_comment.cid, sha256: signatures.sha256, action: verify_comment.verify_comment_action, user_ids: verify_comment.user_ids };
            if (signatures.sha256_action) {
                comment_hash.sha256_action = signatures.sha256_action ;
                comment_hash.new_deal_action_by_user_ids = verify_comment.new_deal_action_by_user_ids ;
            }
            if (signatures.sha256_deleted) comment_hash.sha256_deleted = signatures.sha256_deleted ;
            // add server id (only comments for remote verification)
            if (verify_comment.created_at_server != 0) comment_hash.server_id = verify_comment.created_at_server ;
            // server side authorization check:
            // - verify. not relevant. comment is in most cases from a friend of giver or receiver but there are some exceptions (friend lists out of sync, not connected login provider)
            // - cancel new deal proposal. login users must also be creator of comment. info is already available in comment hash
            // - accept new deal proposal. login users must also be creator of gift. add gift hash to comment hash (subset of verify gift request)
            // - reject new deal proposal. login users must also be creator of gift. add gift hash to comment hash (subset of verify gift request)
            // - delete comment. add gift hash to comment has if comment is deleted by giver or receiver of gift
            var add_gift_info, login_user_ids, gift_hash ;
            switch (verify_comment.verify_comment_action) {
                case 'verify':
                case 'cancel':
                    add_gift_info = false ;
                    break ;
                case 'accept':
                case 'reject':
                    add_gift_info = true ;
                    break ;
                case 'delete':
                    login_user_ids = userService.get_login_userids() ;
                    add_gift_info = ($(login_user_ids).filter(verify_comment.user_ids).length == 0) ;
            }; // switch
            var comment_key = JSON.stringify(comment_hash) ;
            if (add_gift_info) {
                // additional authorization information is required for comment action (accept, reject or delete)
                // (subset of verify gift request)
                var signatures = gift_signature_for_server(gift) ;
                var gift_hash = { gid: gift.gid, sha256: signatures.sha256 };
                // add user ids
                if (gift.giver_user_ids.length > 0) gift_hash.giver_user_ids = gift.giver_user_ids ;
                if (gift.receiver_user_ids.length > 0) gift_hash.receiver_user_ids = gift.receiver_user_ids ;
                // add server id (only for remote gifts).
                if (gift.created_at_server != 0) gift_hash.server_id = gift.created_at_server ;
                comment_hash.gift = gift_hash ;
            }
            return {hash: comment_hash, key: comment_key} ;
        } ; // verify_comment_to_hash_and_key

        var verify_comments_request = function () {
            var pgm = service + '.verify_comments_request: ';
            // check buffer for "old comments". should normally be empty except for comments with negative seq (remote comments - remote actions)
            // local comments are allowed if device is offline or if server does not respond
            var local_seq = 0 ;
            var seq ;
            var no_comments = { local: 0, remote: 0, create: 0, verify: 0, cancel: 0, accept: 0, reject: 0, delete: 0 } ;
            var request = [] ;
            for (seq in verify_comments_seq_to_comms) {
                // count old actions
                if (['create', 'verify', 'cancel', 'accept', 'reject', 'delete'].indexOf(verify_comments_seq_to_comms[seq].action) != -1) {
                    no_comments[verify_comments_seq_to_comms[seq].action] += 1 ;
                }
                else {
                    console.log(pgm + 'System error. Found invalid action ' + verify_comments_seq_to_comms[seq].action + ' in verify comments buffer.');
                    console.log(pgm + 'verify_comments_seq_to_comms[' + seq + '] = ' + verify_comments_seq_to_comms[seq]) ;
                    continue ;
                };
                // count local/remote
                if (parseInt(seq) >= 0) {
                    // found "old" local comment action in buffer. device must be offline or server is not responding. resend previous request
                    no_comments.local += 1;
                    if (parseInt(seq) > local_seq) local_seq = parseInt(seq) ;
                    request.push(verify_comments_seq_to_comms[seq].request) ; 
                }
                else no_comments.remote += 1 ; // ok - remote comment actions can take some time (verify, cancel, accept, reject or delete)
            }; // for seq
            
            if (verify_comments_online && (no_comments.local + no_comments.remote > 0)) {
                // warning. Old requests found in comments action buffer
                console.log(pgm + 'Warning. Found ' + no_comments.local + ' local and ' + no_comments.remote + ' remote comments in comments actions buffer. ' +
                    no_comments.create + ' create, ' + no_comments.verify + ' verify, ' + no_comments.cancel + ' cancel, ' + no_comments.accept + ' accept, ',  + no_comments.reject + ' reject and ' + no_comments.delete + ' delete comment requests' ) ;
            };
            if (verify_comments.length == 0) return (request.length == 0 ? null : request) ; // no new comments for verification

            // loop for new comments in verify_comments array
            var no_new_comments = verify_comments.length ;
            var already_verified = 0 ;
            var waiting_for_verification = 0 ;
            var old_request = request.length ; // resend old requests
            var new_request = 0 ;
            var verify_comment_hash, verify_comment, gift, sha256_client, hash_and_key, hash, key ;
            var signatures, local ;

            // loop for comment actions in verify comments buffer
            while (verify_comments.length > 0) {
                verify_comment_hash = verify_comments.shift();
                gift = verify_comment_hash.gift ;
                verify_comment = verify_comment_hash.comment;
                // todo: change. not only used for verify. also used for create, cancel, accept, reject and delete comment requests
                if (verify_comment.hasOwnProperty('verified_at_server')) {
                    // ignore comment. comment has already been verified. can maybe happen if same comment has been received from more than one client
                    already_verified += 1;
                    continue;
                }
                if (verify_comment.hasOwnProperty('verify_seq')) {
                    // must be a remote comment waiting for validation on an other gofreerev server
                    waiting_for_verification += 1;
                    continue;
                } // if
                // make request (create, verify, cancel, accept, reject or delete comment)
                hash_and_key = verify_comment_to_hash_and_key(gift,verify_comment);
                hash = hash_and_key.hash ;
                key = hash_and_key.key ;
                // check verify comments buffer
                seq = verify_comments_key_to_seq[key];
                if (seq) {
                    // key/request already in verify comments buffer (must be identical comment received in multiple incoming messages - verify comment requests)
                    verify_comment.verify_seq = seq ;
                    verify_comments_seq_to_comms[seq].comments.push(verify_comment);
                    if (verify_comments_seq_to_comms[seq].action != 'verify') {
                        console.log(pgm + 'Warning. Multiple ' + vverify_comments_seq_to_comms[seq].action + ' comment requests for ' +  verify_comments_seq_to_comms[seq].cid) ;
                    };
                }
                else {
                    // new request. add to verify comments buffer and request array
                    // local (within server) or remote (cross Gofreerev server request)?
                    // use positive seq for local (response now) and negative seq for remote requests (response in a later ping response)
                    if (verify_comment.verify_comment_action == 'create') local = true ;
                    else if (hash.hasOwnProperty('server_id')) local = false ; // comment on an other Gofreerev server
                    else if (!hash.hasOwnProperty('gift')) local = true ; // no gift hash
                    else local = !hash.gift.hasOwnProperty('server_id') ; // gift on an other Gofreerev server
                    if (local) {
                        // local verification. positive seq. comment on this gofreerev server. response now
                        local_seq += 1;
                        hash.seq = local_seq ;
                    }
                    else hash.seq = -Gofreerev.get_next_seq() ; // remote verification. negative seq. comment or gift on an other Gofreerev server. response in a later ping response
                    verify_comment.verify_seq = hash.seq ;
                    verify_comments_key_to_seq[key] = hash.seq ;
                    verify_comments_seq_to_comms[hash.seq] = {
                        cid: verify_comment.cid,
                        action: verify_comment.verify_comment_action,
                        key: key,
                        gift: gift,
                        comments: [verify_comment],
                        request: hash
                    };
                    request.push(hash);
                    // todo: testrun-46. debugging invalid gift sha256 signature in reject new deal proposal request
                    console.log(pgm + 'hash = ' + JSON.stringify(hash)) ;
                    new_request += 1 ;
                }
            } // verify_comments while loop

            if (already_verified > 0) console.log(pgm + 'Warning. Found ' + already_verified + ' already verified comments in verify_comments buffer.');
            if (waiting_for_verification > 0) console.log(pgm + 'Warning. Found ' + waiting_for_verification + ' comments waiting for verification in verify_comments buffer.');
            if (old_request > 0) console.log(pgm + 'Warning. Found ' + old_request + ' old requests in verify comments buffer.') ;
            if (new_request > 0) console.log(pgm + new_request + ' new comment verification requests sent to server.');
            return (request.length == 0 ? null : request);
        }; // verify_comments_request

        var verify_comments_response = function (response) {
            var pgm = service + '.verify_comments_response: ';
            var error ;

            if (response.error) {
                // fatal error
                if (typeof response.error == 'object') error =  I18n.t('js.comment_actions.' + response.error.key, response.error.options);
                else error = response.error ;
                console.log(pgm + 'Fatal verify comments error: ' + error) ;
                // todo: notification
                return ;
            };

            // seq must be unique i response and all positive seq must be in verify comments buffer
            var seqs = [], i, j, not_unique_seq = 0, seq, invalid_local_seq = 0, old_remote_seq = [], invalid_remote_seq = 0, invalid_cid = 0, comment, hash_and_key, hash  ;
            for (i=0 ; i<response.comments.length ; i++) {
                comment = response.comments[i] ;
                seq = comment.seq;
                if (seqs.indexOf(seq) == -1) {
                    seqs.push(seq) ;
                    if (!verify_comments_seq_to_comms[seq]) {
                        // unknown seq!
                        if (seq >= 0) invalid_local_seq += 1 ;
                        else {
                            // ok if remote verification was started in a previous session / before page reload
                            // todo: there is a problem with multiple client sessions with same client_userid. remote verification can be started by one client and response received by an other client!
                            // todo: is there a mailbox per device or a mailbox per client?
                            if (verify_comments_old_remote_seq == null) verify_comments_old_remote_seq = 0 ;
                            else if (typeof verify_comments_old_remote_seq == 'string') verify_comments_old_remote_seq = parseInt(verify_comments_old_remote_seq) ;
                            if (-seq <= verify_comments_old_remote_seq) old_remote_seq.push(seq) ; // ignore old remote verifications (js variables have been reset)
                            else invalid_remote_seq += 1 ;
                        }
                    }
                    else if (verify_comments_seq_to_comms[seq].cid != comment.cid) invalid_cid += 1 ;
                }
                else not_unique_seq += 1 ;
            }; // for
            seqs = null ;

            // receipt - abort if errors in verify comments response
            if (not_unique_seq > 0) console.log(pgm + 'Error. ' + not_unique_seq + ' not unique seq in verify comments response.') ;
            if (invalid_local_seq > 0) console.log(pgm + 'Error. ' + invalid_local_seq + ' invalid local seq in verify comments response.') ;
            if (invalid_remote_seq > 0) console.log(pgm + 'Error. ' + invalid_remote_seq + ' invalid remote seq in verify comments response.') ;
            if (invalid_cid > 0) console.log(pgm + invalid_cid + ' invalid unique comment id (cid) in verify comments response.') ;
            if (old_remote_seq.length > 0) console.log(pgm + 'Warning. ' + old_remote_seq + ' old unknown remote seq in verify comments response') ;
            if (not_unique_seq + invalid_local_seq + invalid_remote_seq + invalid_cid > 0) return ; // abort

            // loop for each row in verify comments response (create, verify, cancel, accept, reject or delete)
            // one row in response can be answer to multiple verify comments requests (verify_comments_seq_to_comms[seq].comments)
            // ( identical gift received in multiple send_gifts messages from other clients )
            var comment_verification, cid, new_comments, key, verify_comment_action, gift, comment_found ;
            var no_comments = { all: 0, create: 0, verify: 0, cancel: 0, accept: 0, reject: 0, delete: 0, local: 0, remote: 0, syserr1: 0, syserr2: 0, syserr3: 0, resend: 0, true: 0, false: 0} ;
            var empty_new_comment_form ;
            while (response.comments.length > 0) {
                comment_verification = response.comments.shift();
                // ignore response from old remote comment actions (from before page reload)
                seq = comment_verification.seq ;
                if (old_remote_seq.indexOf(seq) != -1) continue ;
                // seq is ok - checked in previous loop
                cid = verify_comments_seq_to_comms[seq].cid ;
                verify_comment_action = verify_comments_seq_to_comms[seq].action ;
                // logical validate verify comment response. must be an ok response (verified_at_server=true) without error message (error=key=options=null) or must be
                // an error response (verified_at_server=false) with either error (cross server error message) or key+options (within server error message)
                if (comment_verification.verified_at_server && (comment_verification.hasOwnProperty('error') || comment_verification.hasOwnProperty('key') ||comment_verification.hasOwnProperty('options'))) {
                    console.log(pgm + 'System error in ' + verify_comment_action + ' response from server for comment ' + cid + '. OK response but error information was also returned');
                    console.log(pgm + 'request  = ' + JSON.stringify(verify_comments_seq_to_comms[seq].request)) ;
                    console.log(pgm + 'response = ' + JSON.stringify(comment_verification)) ;
                    // todo: system error count + notification
                    continue ;
                }; // if
                if (!comment_verification.verified_at_server) {
                    // comment action rejected by server. check error format. error format must be :error or :key+:options
                    if (!comment_verification.hasOwnProperty('error') && !comment_verification.hasOwnProperty('key') && !comment_verification.hasOwnProperty('options')) {
                        console.log(pgm + 'System error in ' + verify_comment_action + ' response from server for comment ' + cid + '. Inconsistent error response without any error information');
                        console.log(pgm + 'request  = ' + JSON.stringify(verify_comments_seq_to_comms[seq].request)) ;
                        console.log(pgm + 'response = ' + JSON.stringify(comment_verification)) ;
                        // todo: system error count + notification
                        continue ;
                    };
                    if (comment_verification.hasOwnProperty('error') && (comment_verification.hasOwnProperty('key') || comment_verification.hasOwnProperty('options'))) {
                        console.log(pgm + 'System error in ' + verify_comment_action + ' response from server for comment ' + cid + '. Inconsistent error response with :error and :key+:options');
                        console.log(pgm + 'request  = ' + JSON.stringify(verify_comments_seq_to_comms[seq].request)) ;
                        console.log(pgm + 'response = ' + JSON.stringify(comment_verification)) ;
                        // todo: system error count + notification
                        continue ;
                    };
                    if (comment_verification.hasOwnProperty('options') && !comment_verification.hasOwnProperty('key')) {
                        console.log(pgm + 'System error in ' + verify_comment_action + ' response from server for comment ' + cid + '. Inconsistent error response with :options without :key');
                        console.log(pgm + 'request  = ' + JSON.stringify(verify_comments_seq_to_comms[seq].request)) ;
                        console.log(pgm + 'response = ' + JSON.stringify(comment_verification)) ;
                        // todo: system error count + notification
                        continue ;
                    };
                }; // if
                gift = verify_comments_seq_to_comms[seq].gift ;
                new_comments = verify_comments_seq_to_comms[seq].comments;
                // one or more comments in verify comments buffer with this seq/key
                while (new_comments.length > 0) {
                    no_comments.all += 1 ;
                    comment = new_comments.shift() ;
                    no_comments[comment.verify_comment_action] += 1 ; // action: create, verify, cancel, accept, reject and delete
                    if (seq > 0) no_comments.local += 1 ;
                    else no_comments.remote += 1 ;

                    // check comment in gifts array. new_comment is either from gifts array (!verify) or from an incoming send_gifts message (verify)
                    if (comment.verify_comment_action != 'verify') {
                        // client action: create, cancel, accept, reject or delete. comment must be in gifts array
                        comment_found = false ;
                        for (i=0 ; (!comment_found && (i<gifts.length)) ; i++) {
                            if (!gifts[i].hasOwnProperty('comments')) continue ;
                            for (j=0 ; (!comment_found && (j<gifts[i].comments.length)) ; j++) if (comment === gifts[i].comments[j]) comment_found = true ;
                        }; // for j
                        if (!comment_found) {
                            // action action: create, cancel, accept, reject or delete. Comment is no longer in gifts array!
                            console.log(pgm + 'System error. Received ' + comment.verify_comment_action + ' comment response from server for comment ' + comment.cid + ' but comment is no longer in gifts array') ;
                            no_comments.syserr2 += 1 ;
                            continue ;
                        }; // if
                    }; // if

                    // recheck key. check if comment has changed between verify comments request and response (remote verification can take some time)
                    hash_and_key = verify_comment_to_hash_and_key(gift, comment);
                    hash = hash_and_key.hash ;
                    key = hash_and_key.key ;
                    if (key != verify_comments_seq_to_comms[seq].key) {
                        // comment changed between verify comments request and verify comments response.
                        // write warning in log and and a send new verify comments request with changed comment
                        // todo: check verify_comment_action. ok to resend verify. Maybe not ok to resend cancel, accept, reject or delete.
                        console.log(pgm + 'Warning. Comment ' + comment.cid + ' was changed between verify comments request and verify comments response.') ;
                        console.log(pgm + 'old key = ' + verify_comments_seq_to_comms[seq].key) ;
                        console.log(pgm + 'new key = ' + key) ;
                        console.log(pgm + 'Resending comment ' + comment.cid + ' to server for verification') ;
                        delete comment.verify_comment_at ;
                        verify_comment_action = comment.verify_comment_action ;
                        delete comment.verify_comment_action ;
                        delete comment.verify_seq ;
                        verify_comments_add(gift, comment, verify_comment_action) ;
                        continue ;
                    }; // if

                    // do or rollback actions: create, verify, cancel, accept, reject or delete. see verify_gifts_response
                    no_comments[comment_verification.verified_at_server] += 1 ; // true or false
                    switch(comment.verify_comment_action) {

                        case 'create':
                            // create new comment operation. new_comment should be in gifts array (already checked)
                            if (comment_verification.verified_at_server) {
                                // comment create ok. add created_at_server = 0 (comment is already in gifts array with created_at_server = 0 - created on this Gofreerev server)
                                if (comment.hasOwnProperty('created_at_server')) {
                                    // not possible. new_comment object changed between verify comments request and verify comments response
                                    console.log(pgm + 'System error. Comment ' + cid + ' signature was created on server but created_at_server property was set between verify comments request and verify comments response.') ;
                                    no_comments.syserr3 += 1 ;
                                    // todo: send notification
                                    continue ;
                                };
                                // recheck comment in localStorage
                                refresh_gift_and_comment(gift, comment);
                                if (comment.hasOwnProperty('created_at_server')) {
                                    // thats is ok if multiple browser sessions (windows or tabs) with identical login / identical client user id
                                    if (comment.created_at_server == 0) continue; // ok - received in an other browser session
                                    console.log(pgm + 'System error. Comment ' + cid + ' signature was created on server but created_at_server property for comment was set to an invalid value between verify comments request and verify comments response. Expected created_at_server = 0. Found created_at_server = ' + comment.created_at_server + '.');
                                    no_comments.syserr3 += 1 ;
                                    // todo: send notification
                                    continue;
                                };
                                // create comment ok
                                comment.created_at_server = 0; // always 0 for current server for create
                                // ready for next comment action - clear info used in verify comment request & response
                                delete comment.verify_seq ;
                                delete comment.verify_comment_at ;
                                delete comment.verify_comment_action ;
                            }
                            else {
                                // comment created failed
                                if (typeof comment_verification.error == 'object') error =  I18n.t('js.comment_actions.' + comment_verification.error.key, comment_verification.error.options);
                                else error = comment_verification.error ;
                                console.log(pgm + 'create new comment failed for cid ' + cid + ' with error message: ' + error) ;
                                // remove comment from gift.comments array
                                i = gift.comments.indexOf(comment) ;
                                gift.comments.splice(i,1) ;
                                if (typeof gift.show_no_comments != 'undefined') gift.show_no_comments = gift.show_no_comments - 1 ;
                                if (gift.hasOwnProperty('new_comment')) {
                                    empty_new_gift_form = ( ((gift.new_comment.comment == null) || (gift.new_comment.comment == '')) &&
                                                               ((gift.new_comment.price == null) || (gift.new_comment.price == '')) &&
                                                               !gift.new_comment.new_deal );
                                }
                                else empty_new_gift_form = true;
                                if (empty_new_gift_form) {
                                    // blank new comment form for gift. Move failed new comment back to new_comment form and display error message and send notification
                                    console.log(pgm + 'uncreate cid ' + cid + '. failed create comment is moved (back) to new_comment form for gid ' + gift.gid) ;
                                    if (!gift.hasOwnProperty('new_comment')) gift.new_comment = {} ;
                                    gift.new_comment.comment = comment.comment ;
                                    gift.new_comment.price = comment.price ;
                                    gift.new_comment.new_deal = comment.new_deal ;
                                    gift.new_comment.error =  error ;
                                    gift.new_comment.error_at = Gofreerev.unix_timestamp() ;
                                }
                                else {
                                    // new comment form for gift in use. Write error message in log + send notification
                                    console.log(pgm + 'new_comment form already in use for gid ' + gift.gid + '. display error message only in log and notification') ;
                                    console.log(pgm + 'uncreated comment was ' + JSON.stringify(comment)) ;
                                }; // if
                                // todo: send notification just in case new comment form was outside windows or new comment form for gift was already in use
                            }; // if
                            save_gift(gift) ;
                            break ;

                        case 'verify':
                            // used in receive_message_send_gifts
                            comment.verified_at_server = comment_verification.verified_at_server ;
                            if (!comment_verification.verified_at_server) {
                                // comment verification failed. copy error object. is used in receive_message_send_gifts
                                comment.verified_error = gift_verification.error ;
                                if (typeof comment_verification.error == 'object') error =  I18n.t('js.comment_actions.' + comment_verification.error.key, comment_verification.error.options);
                                else error = comment_verification.error ;
                                // write error message to log. no notification here. Any notifications are sent from receive_message_send_gifts
                                console.log(pgm + 'verify comment failed for cid ' + cid + ' with error message: ' + error) ;
                            }
                            break ;

                        case 'cancel':
                            if (!comment.hasOwnProperty('new_deal_action_at_client')) {
                                console.log(pgm + 'System error. Received cancel new deal proposal comment response from server but new deal proposal ' + comment.cid + ' has not been cancelled by client') ;
                                console.log(pgm + 'response = ' + JSON.stringify(comment_verification)) ;
                                // todo: no_comments.syserr<n> += 1 + notification
                                continue ;
                            };
                            if (comment_verification.verified_at_server) {
                                // cancel new deal proposal ok. add new_deal_action_at_server = created_at_server
                                if (comment.hasOwnProperty('new_deal_action_at_server')) {
                                    console.log(pgm + 'System error. New deal proposal ' + comment.cid + ' cancelled marked on server but new_deal_action_at_server property was set between verify comments request and verify comments response.') ;
                                    // todo: no_comments.syserr<n> += 1 + notification
                                    continue ;
                                };
                                refresh_gift_and_comment(gift, comment);
                                if (comment.hasOwnProperty('new_deal_action_at_server')) {
                                    // that is ok if multiple browser sessions (windows or tabs) with identical login / identical client user id
                                    if (comment.new_deal_action_at_server == comment.created_at_server) continue ; // ok - cancel new deal proposal response received in an other browser session
                                    console.log(pgm + 'System error. New deal proposal ' + comment.cid + ' was cancelled on server but new_deal_action_at_server property for new deal proposal was set to an invalid value between verify comments request and verify comments response. Expected new_deal_action_at_server = ' + comment.created_at_server + '. Found new_deal_action_at_server = ' + comment.new_deal_action_at_server);
                                    no_comments.syserr3 += 1 ;
                                    continue;
                                } // if
                                // cancel new deal proposal ok
                                comment.new_deal_action_at_server = comment.created_at_server ;
                            }
                            else {
                                // cancel new deal proposal failed.
                                if (comment.hasOwnProperty('new_deal_action_at_server')) {
                                    console.log(pgm + 'System error. Cancel new deal proposal ' + comment.cid + ' was reject by server but has already been cancelled in client') ;
                                    console.log(pgm + 'Server response was ' + JSON.stringify(comment_verification)) ;
                                    console.log(pgm + 'comment.created_at_server = ' + comment.created_at_server) ;
                                    console.log(pgm + 'comment.new_deal_action_at_server = ' + comment.new_deal_action_at_server) ;
                                    // todo: no_comments.syserr<n> count + notification
                                    continue ;
                                } ;
                                // remove cancel new deal proposal from comment
                                delete comment.new_deal_action  ;
                                delete comment.new_deal_action_by_user_ids ;
                                delete comment.new_deal_action_at_client ;
                                // display error message
                                // todo: handle missing translations
                                // todo: seq > 0. should have key and translation. seq < 0. should have english error message only
                                comment.link_error_at = Gofreerev.unix_timestamp();
                                if (typeof comment_verification.error == 'object') comment.link_error = I18n.t('js.comment_actions.' + comment_verification.error.key, comment_verification.error.options);
                                else comment.link_error = comment_verification.error ;
                                console.log(pgm + 'cancel new deal proposal failed. error message was ' + comment.link_error) ;
                            }; // if
                            // save gift - cancelled (success) or uncancel (failure)
                            // cleanup info used in verify comment request & response
                            save_gift(gift) ;
                            delete comment.verify_seq ;
                            delete comment.verify_comment_at ;
                            delete comment.verify_comment_action ;
                            break;

                        case 'accept':
                            if (comment_verification.verified_at_server) {
                                // accept new deal proposal ok. add comment.action_at_server = comment.created_at_server and gift.accepted_at_server = gift.created_at_server
                            }
                            else {
                                // accept new deal proposal failed. Chance back to a not accepted new deal proposal and display error message from server
                            }; // if
                            break ;

                        case 'reject':
                            if (!comment.hasOwnProperty('new_deal_action_at_client')) {
                                console.log(pgm + 'System error. Received reject new deal proposal response from server but new deal proposal ' + comment.cid + ' has not been rejected by client') ;
                                console.log(pgm + 'response = ' + JSON.stringify(comment_verification)) ;
                                // todo: no_comments.syserr<n> += 1 + notification
                                continue ;
                            };
                            if (comment_verification.verified_at_server) {
                                // reject new deal proposal ok. add new_deal_action_at_server = created_at_server
                                if (comment.hasOwnProperty('new_deal_action_at_server')) {
                                    console.log(pgm + 'System error. New deal proposal ' + comment.cid + ' reject marked on server but new_deal_action_at_server property was set between verify comments request and verify comments response.') ;
                                    // todo: no_comments.syserr<n> += 1 + notification
                                    continue ;
                                };
                                refresh_gift_and_comment(gift, comment);
                                if (comment.hasOwnProperty('new_deal_action_at_server')) {
                                    // that is ok if multiple browser sessions (windows or tabs) with identical login / identical client user id
                                    if (comment.new_deal_action_at_server == comment.created_at_server) continue ; // ok - reject new deal proposal response received in an other browser session
                                    console.log(pgm + 'System error. New deal proposal ' + comment.cid + ' was rejected on server but new_deal_action_at_server property for new deal proposal was set to an invalid value between verify comments request and verify comments response. Expected new_deal_action_at_server = ' + comment.created_at_server + '. Found new_deal_action_at_server = ' + comment.new_deal_action_at_server);
                                    no_comments.syserr3 += 1 ;
                                    continue;
                                } // if
                                // reject new deal proposal ok
                                comment.new_deal_action_at_server = comment.created_at_server ;
                            }
                            else {
                                // reject new deal proposal failed.
                                if (comment.hasOwnProperty('new_deal_action_at_server')) {
                                    console.log(pgm + 'System error. Reject new deal proposal ' + comment.cid + ' was reject by server but has already been rejected in client') ;
                                    console.log(pgm + 'Server response was ' + JSON.stringify(comment_verification)) ;
                                    console.log(pgm + 'comment.created_at_server = ' + comment.created_at_server) ;
                                    console.log(pgm + 'comment.new_deal_action_at_server = ' + comment.new_deal_action_at_server) ;
                                    // todo: no_comments.syserr<n> count + notification
                                    continue ;
                                } ;
                                // remove reject new deal proposal from comment
                                delete comment.new_deal_action  ;
                                delete comment.new_deal_action_by_user_ids ;
                                delete comment.new_deal_action_at_client ;
                                // display error message
                                // todo: handle missing translations
                                // todo: seq > 0. should have key and translation. seq < 0. should have english error message only
                                comment.link_error_at = Gofreerev.unix_timestamp();
                                if (typeof comment_verification.error == 'object') comment.link_error = I18n.t('js.comment_actions.' + comment_verification.error.key, comment_verification.error.options);
                                else comment.link_error = comment_verification.error ;
                                console.log(pgm + 'reject new deal proposal failed. error message was ' + comment.link_error) ;
                            }; // if
                            // save gift - rejected (success) or unrejected (failure)
                            // cleanup info used in verify comment request & response
                            save_gift(gift) ;
                            delete comment.verify_seq ;
                            delete comment.verify_comment_at ;
                            delete comment.verify_comment_action ;
                            break;

                        case 'delete':
                            if (!comment.hasOwnProperty('deleted_at_client')) {
                                console.log(pgm + 'System error. Received delete comment response from server but comment ' + comment.cid + ' has not been deleted by client') ;
                                console.log(pgm + 'response = ' + JSON.stringify(comment_verification)) ;
                                // todo: no_comments.syserr<n> += 1 + notification
                                continue ;
                            };
                            if (comment_verification.verified_at_server) {
                                // delete comment ok. add deleted_at_server = created_at_server
                                if (comment.hasOwnProperty('deleted_at_server')) {
                                    console.log(pgm + 'System error. Comment ' + comment.cid + ' deleted marked on server but deleted_at_server property was set between verify comments request and verify comments response.') ;
                                    // todo: no_comments.syserr<n> += 1 + notification
                                    continue ;
                                };
                                refresh_gift_and_comment(gift, comment);
                                if (comment.hasOwnProperty('deleted_at_server')) {
                                    // that is ok if multiple browser sessions (windows or tabs) with identical login / identical client user id
                                    if (comment.deleted_at_server == comment.created_at_server) continue ; // ok - comment delete response received in an other browser session
                                    console.log(pgm + 'System error. Comment ' + comment.cid + ' signature was deleted on server but deleted_at_server property for comment was set to an invalid value between verify comments request and verify comments response. Expected deleted_at_server = ' + comment.created_at_server + '. Found deleted_at_server = ' + comment.deleted_at_server);
                                    no_comments.syserr3 += 1 ;
                                    continue;
                                } // if
                                // delete comment ok
                                comment.deleted_at_server = comment.created_at_server ;
                            }
                            else {
                                // delete comment failed.
                                if (comment.hasOwnProperty('deleted_at_server')) {
                                    console.log(pgm + 'System error. Comment ' + comment.cid + ' delete was reject by server but has already been deleted in client') ;
                                    console.log(pgm + 'Server response was ' + JSON.stringify(comment_verification)) ;
                                    console.log(pgm + 'comment.created_at_server = ' + comment.created_at_server) ;
                                    console.log(pgm + 'comment.deleted_at_server = ' + comment.deleted_at_server) ;
                                    // todo: no_comments.syserr<n> count + notification
                                    continue ;
                                } ;
                                // undelete comment
                                delete comment.deleted_at_client;
                                // display error message
                                // todo: handle missing translations
                                // todo: seq > 0. should have key and translation. seq < 0. should have english error message only
                                comment.link_error_at = Gofreerev.unix_timestamp();
                                if (comment_verification.hasOwnProperty('key')) comment.link_error = I18n.t('js.comment_actions.' + comment_verification.key, comment_verification.options);
                                else comment.link_error = comment_verification.error ;
                            }; // if
                            // save gift - deleted (success) or undeleted (failure)
                            save_gift(gift) ;
                            // cleanup info used in verify comment request & response
                            delete comment.verify_seq ;
                            delete comment.verify_comment_at ;
                            delete comment.verify_comment_action ;
                            break;

                    } ; // switch

                    // todo: remove new_comment.verify_comment_action, new_comment.verify_comment_at and new_comment.verify_seq

                }; // while
                // remove from verify comments buffer
                key = verify_comments_seq_to_comms[seq].key ;
                delete verify_comments_seq_to_comms[seq] ;
                delete verify_comments_key_to_seq[key] ;
            } // while response.length > 0

            // receipt
            console.log(pgm + 'Received response for ' + no_comments.all + ' comment actions (' + no_comments.true + ' valid and ' + no_comments.false + ' invalid).') ;

        }; // verify_comments_response


        // send meta-data for deleted comments to server and get comment.deleted_at_server response (boolean) from server.
        // called from UserService.ping
        // todo: add array with just deleted comments to prevent a full gifts/comments search for deleted comments
        // todo: delete. use verify_comments_add(comment, 'delete')
        var delete_comments_request = function () {
            return null ;
            var pgm = service + '.delete_comments_request: ' ;
            var request = [];
            var i, gift, j, comment, hash, signatures ;
            var login_user_ids = userService.get_login_userids() ;
            if (login_user_ids.length == 0) return null ; // not logged in
            for (i = 0; i < gifts.length; i++) {
                gift = gifts[i];
                if (!gift.hasOwnProperty('comments')) continue ;
                if (gift.comments.length == 0) continue ;
                for (j=0 ; j<gift.comments.length ; j++) {
                    comment = gift.comments[j] ;
                    if (!comment.deleted_at_client) continue ;
                    if (!comment.deleted_at_server) {
                        signatures = comment_signature_for_server(gift.gid, comment);
                        hash = {cid: comment.cid, user_ids: comment.user_ids, sha256: signatures.sha256, sha256_deleted: signatures.sha256_deleted};
                        if (signatures.sha256_action) {
                            hash.sha256_action = signatures.sha256_action ;
                            hash.new_deal_action_by_user_ids = comment.new_deal_action_by_user_ids ;
                        };
                        // todo: add gift fields if comment was deleted by giver or receiver of gift (not owner of comment)
                        if ($(login_user_ids).filter(comment.user_ids).length == 0) {
                            // comment was NOT deleted by creator of comment. login user must be giver or receiver of gift.
                            continue ;
                        };
                        // that is gid, gift.sha256, gift.giver_user_ids and gift.receiver_user_ids
                        request.push(hash);
                    } // if
                } ;
            } // for i
            return (request.length == 0 ? null : request);
        }; // delete_comments_request
        // todo: delete - now using verify_comments with action = delete
        var delete_comments_response = function (response) {
            return ;
            var pgm = service + '.delete_comments_response: ';
            // console.log(pgm + 'response = ' + JSON.stringify(response)) ;
            if (response.hasOwnProperty('error')) console.log(pgm + response.error);
            if (response.hasOwnProperty('no_errors') && (response.no_errors > 0)) console.log(pgm + response.no_errors + ' comments was not deleted. See following error message.');
            if (!response.hasOwnProperty('gifts')) return;
            var new_comments = response.comments;
            var new_comment, gid, index, comment, created_at_server, noti;
            function add_index_error (gid, ref) {
                // system error in gid/gift lookup
                cache_nid.delete_gift_syserr123_nid = notiService.add_notification({
                    notitype: 'delete_gift', key: 'syserr' + ref, options: {gid: gid, ref: ref},
                    extra: {gid: gid, ref: ref}, nid: cache_nid.delete_gift_syserr123_nid}) ;
            }
            function add_response_error (new_gift, ref) {
                // system error in delete gifts response
                cache_nid.delete_gift_syserr456_nid = notiService.add_notification({
                    notitype: 'delete_gift', key: 'syserr' + ref, options: { gid: new_gift.gid, error: new_gift.error, key: new_gift.key, options: JSON.stringify(new_gift.options)},
                    extra: {gid: comment.gid, ref: ref}, nid: cache_nid.delete_gift_syserr456_nid}) ;
            }
            for (var i = 0; i < new_comments.length; i++) {
                new_comment = new_comments[i];
                // lookup comment
                // todo: error. No gid in new_comment!
                gid = new_comment.gid;
                if (!gid_to_gifts_index.hasOwnProperty(gid)) { add_index_error(gid, 1) ; continue; }
                index = gid_to_gifts_index[gid];
                if ((index < 0) || (index >= gifts.length)) { add_index_error(gid, 2) ; continue; }
                comment = gifts[index];
                if (!comment) { add_index_error(gid, 3); continue; }
                // check response. must be an ok response without error message (error=key=options=null) or an error
                // response with either an error message (cross server error) or with key+options (within server error)
                if (new_comment.deleted_at_server && (new_comment.hasOwnProperty('error') || new_comment.hasOwnProperty('key') || new_comment.hasOwnProperty('options'))) {
                    // unexpected error information
                    add_response_error (new_comment,4) ;
                    continue ;
                }
                if (!new_comment.deleted_at_server) {
                    // gift delete rejected by server
                    if (!new_comment.hasOwnProperty('error') && !new_comment.hasOwnProperty('key') && !new_comment.hasOwnProperty('options')) {
                        add_response_error (new_comment,5) ; // no error information
                        continue ;
                    }
                    if (new_comment.hasOwnProperty('error') && (new_comment.hasOwnProperty('key') || new_comment.hasOwnProperty('options'))) {
                        add_response_error (new_comment,6) ; // inconsistent error information
                        continue ;
                    }
                    if (new_comment.hasOwnProperty('options') && !new_comment.hasOwnProperty('key')) {
                        add_response_error (new_comment,6) ; // inconsistent error information
                        continue ;
                    }

                }
                if (!new_comment.deleted_at_server) {
                    // delete gift request failed. see error message from server
                    console.log(pgm + 'Gift ' + gid + '. Delete gift request failed. ' + new_comment.error);
                    comment.link_error = new_comment.error ;
                    comment.link_error_at = Gofreerev.unix_timestamp() ;
                    comment.link_error_delete_nid = notiService.add_notification({
                        notitype: 'delete_gift', key: 'error', options: {error: new_comment.error},
                        nid: comment.link_error_delete_nid,
                        url:'todo: add show gift url',
                        extra: {gid: gid}}) ;
                    // undelete gift
                    refresh_gift(comment) ;
                    delete comment.deleted_at_client ;
                    save_gift(comment) ;
                    continue;
                }
                // todo: how to handle "remote delete". created by user A on server A, replicated to user A on server B. deleted by under A on server B.
                // gift delete signature was created
                if (comment.hasOwnProperty('deleted_at_server')) {
                    console.log(pgm + 'System error. Comment ' + gid + ' deleted marked on server but deleted_at_server property was set between delete gifts request and delete gifts response.') ;
                    continue ;
                }
                refresh_gift(comment);
                if (comment.hasOwnProperty('deleted_at_server')) {
                    // that is ok if multiple browser sessions with identical login / identical client user id
                    if (comment.deleted_at_server == 1) ; // empty - ok - response received in an other browser session
                    else console.log(pgm + 'System error. Gift ' + gid + ' deleted signature was created on server but deleted_at_server property for gift was setted to an invalid value between delete gifts request and delete gifts response. Expected deleted_at_server = 1. Found deleted_at_server = ' + comment.deleted_at_server + '.');
                    continue;
                }
                comment.deleted_at_server = 1;
                save_gift(comment) ;
                save = true;
            } // for i
        }; // delete_comments_response
        
        
        


        // list of mailboxes for other devices (online and offline)
        // key = did+sha256 is used as mailbox index.
        var mailboxes = []; // list with online and offline devices
        var key_mailbox_index = {}; // from key (did+sha256) to index
        var devices = {}; // hash with public key and symmetric password for each unique device (did)
        var user_mailboxes = {}; // list with relevant mailboxes for each user id (mutual friend) - how to notify about changes in gifts
        var unencrypted_messages = [] ; // temporary buffer symmetric encrypted messages (waiting for public key / symmetric password )

        var update_key_mailbox_index = function () {
            var pgm = service + '.update_key_mailbox_index: ';
            key_mailbox_index = {}; // one index for each device
            user_mailboxes = {}; // one index for each userid
            var mailbox, i, j, mutual_friend_userid;
            for (i = 0; i < mailboxes.length; i++) {
                mailbox = mailboxes[i];
                key_mailbox_index[mailbox.key] = i;
                // list with relevant mailboxes for mutual friend
                // a kind of listeners - mailbox (device) get notifications for relevant gift
                for (j = 0; j < mailbox.mutual_friends.length; j++) {
                    mutual_friend_userid = mailbox.mutual_friends[j];
                    if (!user_mailboxes[mutual_friend_userid]) user_mailboxes[mutual_friend_userid] = [];
                    user_mailboxes[mutual_friend_userid].push(i); // index to mailboxes array
                } // for j
            } // for j
            // console.log(pgm + 'user_mailboxes = ' + JSON.stringify(user_mailboxes)) ;
        };
        update_key_mailbox_index();


        // mailbox actions:
        // - online => offline - continue to buffer messages in javascript arrays
        // - old offline => online - deliver old messages in next ping
        // - new device online - exchange symmetric key and request gift info for mutual friends
        // - new mutual friend for online device - request gift info for new mutual friend
        // - removed mutual friend for online device - continue to buffer messages, but don't deliver in next  ping
        var update_mailboxes = function (new_mailboxes) {
            var pgm = service + '.update_mailboxes: ';
            // console.log(pgm + 'new_mailboxes = ' + JSON.stringify(new_mailboxes)) ;
            // add index
            var i;
            var new_mailboxes_index = {}, new_mailbox;
            for (i = 0; i < new_mailboxes.length; i++) {
                new_mailbox = new_mailboxes[i];
                new_mailbox.key = new_mailbox.did + new_mailbox.sha256; // unique mailbox index
                if (new_mailboxes_index.hasOwnProperty(new_mailbox.key)) {
                    console.log(pgm + 'System error. Doublet rows in ping[:online] response. new_mailboxes = ' + JSON.stringify(new_mailboxes)) ;
                    return ;
                }
                new_mailboxes_index[new_mailbox.key] = i;
            }
            // update old mailboxes
            var j, new_mutual_friends, mailbox, hash, k, friend ;
            for (i = 0; i < mailboxes.length; i++) {
                mailbox = mailboxes[i];
                mailbox.online = new_mailboxes_index.hasOwnProperty(mailbox.key);
                if (!mailbox.online) continue;
                j = new_mailboxes_index[mailbox.key];
                // check for changes in mutual friends
                new_mutual_friends = $(new_mailboxes[j].mutual_friends).not(mailbox.mutual_friends).get();
                mailbox.mutual_friends = new_mailboxes[j].mutual_friends;
                if (new_mutual_friends.length > 0) {
                    // communication step 2 - compare sha256 checksum for mutual friends
                    hash = {
                        mid: Gofreerev.get_new_uid(),
                        msgtype: 'users_sha256',
                        users: Gofreerev.clone_array(new_mutual_friends)
                    };
                    // todo: debug why client is sending doublet users_sha256 to other client after page reload
                    console.log(pgm + 'Found new mutual friends ' + new_mutual_friends.join(', ') + ' in old mailbox ' + JSON.stringify(mailbox) + '. Added message = ' + JSON.stringify(hash) + ' to outbox') ;
                    mailbox.outbox.push(hash);
                }
            } // for i
            // add new mailboxes
            for (i = 0; i < new_mailboxes.length; i++) {
                mailbox = new_mailboxes[i];
                mailbox.online = true;
                if (!key_mailbox_index.hasOwnProperty(mailbox.key)) {
                    // setup new mailbox
                    // folders used for ingoming messages
                    mailbox.inbox = []; // new messages from server / other devices
                    mailbox.read = []; // temporary parked new messages (send_gifts)
                    // folders used for outgoing messages
                    mailbox.outbox = []; // message to send in next ping
                    mailbox.sending = []; // ping request in process
                    mailbox.sent = []; // messages sent - response not yet received
                    mailbox.done = []; // messages sent - response ok received (request_mid)
                    mailbox.error = []; // messages sent - response error  received (request_mid)
                    // first outgoing message
                    // communication step 2 - compare sha256 checksum for mutual friends
                    hash = {
                        mid: Gofreerev.get_new_uid(),
                        msgtype: 'users_sha256',
                        users: Gofreerev.clone_array(mailbox.mutual_friends)
                    } ;
                    // todo: debug why client is sending doublet users_sha256 to other client after page reload
                    console.log(pgm + 'New online mailbox ' + JSON.stringify(mailbox) + ' with mutual friends ' + mailbox.mutual_friends.join(', ') + '. Added message = ' + JSON.stringify(hash) + ' to outbox') ;
                    mailbox.outbox.push(hash);
                    mailboxes.push(mailbox);
                }
            }
            update_key_mailbox_index();
            // console.log(pgm + 'mailboxes = ' + JSON.stringify(mailboxes)) ;
            // console.log(pgm + 'device_pubkey = ' + JSON.stringify(device_pubkey)) ;
        }; // update_mailboxes

        // get/set pubkey for unique device - called in ping - used in client to client communication
        // note that public keys for remote devices sometimes are returned in a later pubkeys_response
        // number of rows in response < number of rows in request
        // public key has to be requested in a server to server pubkeys request
        // client continues to request remote public key until it is returned
        var pubkeys_request = function () {
            var pgm = service + '.pubkeys_request: ' ;
            var request = [];
            var mailbox, did;
            for (var i = 0; i < mailboxes.length; i++) {
                mailbox = mailboxes[i];
                did = mailbox.did;
                if ((!devices.hasOwnProperty(did) || !devices[did].pubkey) && (request.indexOf(did) == -1)) {
                    request.push(did);
                    devices[did] = {};
                }
            }
            if (request.length > 0) console.log(pgm + 'request = ' + JSON.stringify(request)) ;
            return request.length == 0 ? null : request;
        };
        var pubkeys_response = function (response) {
            var pgm = service + '.pubkeys_response: ';
            console.log(pgm + 'pubkeys = ' + JSON.stringify(response));
            var did;
            for (var i = 0; i < response.length; i++) {
                did = response[i].did;
                if (!response[i].pubkey) {
                    console.log(pgm + 'Error. No public key was returned for unknown device ' + did) ;
                    continue ;
                }
                if (devices[did] && devices[did].pubkey) console.log(pgm + 'invalid pubkeys response from ping. pubkey for device ' + did + ' has already been received from server');
                else devices[did].pubkey = response[i].pubkey;
            } // for
        }; // pubkeys_response


        // sha256 calculation for a user
        // params:
        // - user_id - interval user id - required
        // - oldest_gift_id - optional unix timestamp - ignore gifts created or updated before this unix timestamp - used in localStorage space management
        // - ignore_invalid_gifts - optional array with gid's to ignore in user sha256 calculation - for example gift marked as spam or gift with invalid server sha256 signature
        var calc_sha256_for_user = function (user_id, oldest_gift_at, ignore_invalid_gifts) {
            var pgm = service + '.calc_sha256_for_user: ';
            var sha256_input = [], i, gift;
            if (!oldest_gift_at) oldest_gift_at = 0;
            if (!ignore_invalid_gifts) ignore_invalid_gifts = [];
            if (!user_id_to_gifts[user_id]) {
                console.log(pgm + 'No gifts was found for user_id ' + user_id);
                return null;
            }
            // console.log(pgm + 'user_id_gifts_index[' + user_id + '].length = ' + user_id_gifts_index[user_id].length) ;
            for (i = 0; i < user_id_to_gifts[user_id].length; i++) {
                gift = user_id_to_gifts[user_id][i];
                if (!gift.sha256) continue; // no server gift signature or sha256 gift calculation error
                // todo: add gift.updated_at_client property - apply oldest_gift_at filter
                if (ignore_invalid_gifts.indexOf(gift.gid) != -1) {
                    console.log(pgm + 'Ignoring gift ' + gift.gid + ' in sha256 calc for user_id ' + user_id);
                    continue;
                }
                sha256_input.push(gift.gid);
                sha256_input.push(gift.sha256);
            } // for i
            // console.log(pgm + 'sha256_input.length = ' + sha256_input.length) ;
            if (sha256_input.length == 0) return null;
            return Gofreerev.sha256(sha256_input.join(','));
        }; // calc_sha256_for_user

        // calculate sha256 for a list of user ids - used in gift sync / users_sha256 message
        // params:
        // - user_ids - array with interval user id - required
        // - oldest_gift_id - optional unix timestamp - ignore gifts created or updated before this unix timestamp - used in localStorage space management
        // - ignore_invalid_gifts - optional array with gid's to ignore in user sha256 calculation - for example gift marked as spam or gift with invalid server sha256 signature
        var calc_sha256_for_users = function (user_ids, oldest_gift_at, ignore_invalid_gifts) {
            if (!oldest_gift_at) oldest_gift_at = 0;
            if (!ignore_invalid_gifts) ignore_invalid_gifts = [];
            var response = [], i, hash, sha256;
            for (i = 0; i < user_ids.length; i++) {
                hash = {user_id: user_ids[i]} ;
                sha256 = calc_sha256_for_user(user_ids[i], oldest_gift_at, ignore_invalid_gifts) ;
                if (sha256) hash.sha256 = sha256 ;
                response.push(hash) ;
            }
            return response;
        }; // calc_sha256_for_users

        // communication step 2 - send array with sha256 calculation for mutual users to other device
        // input msg is a small user_sha256 message without sha256 calculation
        // send_message_users_sha256 adds sha256 values for each mutual friend
        // send "users_sha256" message to mailbox/other device. one sha256 signature for each mutual friend
        var send_message_users_sha256 = function (mailbox, msg) {
            var pgm = service + '.send_message_users_sha256: ';
            var error ;
            // console.log(pgm + 'msg = ' + JSON.stringify(msg));
            var oldest_gift_at = 0; // todo: set oldest_gift_at as max oldest_gift_at for this and other client
            var ignore_invalid_gifts = []; // todo: add gid ignore lists. Glocal list and/or a list for each device
            
            // add sha256 calc for each mutual friend - see calc_sha256_for_users
            var users_sha256_message = {
                msgtype: msg.msgtype,
                mid: msg.mid,
                users: calc_sha256_for_users(msg.users, oldest_gift_at, ignore_invalid_gifts)
            };
            // console.log(pgm + 'users_sha256_message (1) = ' + JSON.stringify(users_sha256_message)) ;

            if (mailbox.hasOwnProperty('server_id')) {
                // users_sha256 message to user on other Gofreerev server
                // replace internal user ids with remote sha256 signatures
                var i, user_ids = [] ;
                // todo: use clone_array
                for (i=0 ; i<users_sha256_message.users.length ; i++) user_ids.push(users_sha256_message.users[i].user_id) ;
                if (error=userService.user_ids_to_remote_sha256(user_ids, 'mutual_friends', mailbox.server_id, msg, false)) {
                    // write error in log - first message in communication - don't send error message to other client
                    error = 'Could not send users_sha256 message. ' + error ;
                    console.log(pgm + error + ' msg = ' + JSON.stringify(msg)) ;
                    return ;
                }
                // no errors. replace user ids
                for (i=0 ; i<users_sha256_message.users.length ; i++) users_sha256_message.users[i].user_id = user_ids[i] ;
            } // if
            console.log(pgm + 'users_sha256_message = ' + JSON.stringify(users_sha256_message)) ;
            
            // validate users_sha256 message before sending to other device
            if (Gofreerev.is_json_message_invalid(pgm,users_sha256_message,'users_sha256','')) return  ;

            return users_sha256_message ;
        }; // send_message_users_sha256

        // communication step 3 - send list of gifts sha256 values to other device
        var send_message_gifts_sha256 = function (msg) {
            var pgm = service + '.send_message_gifts_sha256: ';
            console.log(pgm + 'msg = ' + JSON.stringify(msg));

            // find sha256 values for relevant gifts / mutual friends
            var gifts_sha256_hash = {}, user_id, i, j, gift;
            for (i = 0; i < msg.mutual_friends.length; i++) {
                user_id = user_ids[i];
                console.log(pgm + 'user_id_gifts_index[' + user_id + '].length = ' + user_id_to_gifts[user_id].length);
                for (j = 0; j < user_id_to_gifts[user_id].length; j++) {
                    gift = user_id_to_gifts[user_id][j];
                    if (!gift.sha256) continue; // no server gift signature or sha256 gift calculation error
                    // todo: add gift.updated_at_client property - apply oldest_gift_at filter
                    if (!gifts_sha256_hash[gift.gid]) gifts_sha256_hash[gift.gid] = gift.sha256;
                } // for j
            } // for i
            console.log(pgm + 'gifts_sha256_hash = ' + JSON.stringify(gifts_sha256_hash));
            //gifts_sha256_hash =
            //    {"14239781692770120364":"ä Ùh¿G×Ñâô9ÔÀ4ÀXèk\u0010N~,\nB]M",
            //     "14239781692770348983":",F¯Ø\"Lo\u0004ö5é_Ï%p\\T¡(j{ï³o",
            //        ...
            //     "14244941900636888171":"¨Yr¤ï9ÉÀðn\u0000K JýôNèÅMêÛûCô"}

            return {
                msgtype: msg.msgtype,
                mid: msg.mid,
                mutual_friends: msg.mutual_friends
            };

        }; // send_message_gifts_sha256

        // send/receive messages to/from other devices
        var send_messages = function () {
            var pgm = service + '.send_messages: ';
            var response = [];
            var mailbox, did, device, messages, msg, message, message_csv, message_json_com, message_csv_rsa_enc, message_with_envelope;
            var encrypt = new JSEncrypt();
            var random_password, key;
            for (var i = 0; i < mailboxes.length; i++) {
                mailbox = mailboxes[i];
                did = mailbox.did;
                device = devices[did];
                if (!device || !device.pubkey) {
                    console.log(pgm + 'Wait. Public key has not yet been received for device ' + did);
                    continue;
                }
                encrypt.setPublicKey(devices[did].pubkey);
                if (mailbox.outbox.length == 0) continue; // no new messages for this mailbox

                // send continue with symmetric key communication
                // console.log(pgm + 'send messages in outbox for device ' + mailbox.did + ' with key ' + mailbox.key);
                // initialise an array with messages for device
                messages = [];
                if (mailbox.sending.length > 0) {
                    console.log(pgm + 'found ' + mailbox.sending.length + ' old messages in sending for device ' + mailbox.did + ' with key ' + mailbox.key);
                }
                mailbox.sending.length = 0;
                // move messages from outbox to sending
                while (mailbox.outbox.length > 0) {
                    msg = mailbox.outbox.shift();
                    console.log(pgm + 'msg = ' + JSON.stringify(msg));
                    // outbox[0] = {"msgtype":"users_sha256","mutual_friends":[1126,920]}"
                    switch (msg.msgtype) {
                        case 'users_sha256':
                            // communication step 2 - send users sha256 signatures to other device
                            msg = send_message_users_sha256(mailbox, msg) ;
                            if (!msg) continue ; // errors - skip message
                            messages.push(msg);
                            break;
                        case 'gifts_sha256':
                            // communication step 3 - send gifts sha256 signatures to other device
                            messages.push(msg);
                            break;
                        case 'sync_gifts':
                            // communication step 4 - send 1-3 sub messages to other device (send_gifts, request_gifts and/or check_gifts)
                            // send_gifts: send missing gifts to other device
                            // request:gifts: request missing gifts from other device
                            // check_gifts: send gifts sub sha256 signatures to other device (separate sha256 signatures for gift and comments)
                            messages.push(msg);
                            break;
                        case 'error':
                            // error notification to other device about errors in input message, processing errors or error in response x
                            messages.push(msg);
                            break;
                        default:
                            // error. unknown msgtype!
                            mailbox.error.push(msg) ;
                            if (mailbox.error.length > 5) mailbox.error.shift();
                            console.log(pgm + 'Not implemented msgtype ' + msg.msgtype + ' moved to error. mailbox ' + JSON.stringify(mailbox));
                    } // end msgtype switch
                    mailbox.sending.push(msg);
                } // for j (mailbox.outbox)
                if (messages.length == 0) {
                    console.log(pgm + 'Error in all messages to did ' + mailbox.did) ;
                    continue ;
                }
                // todo: add more header fields in message?
                message = {
                    sent_at_client: (new Date).getTime(),
                    messages: messages // array with messages
                };
                console.log(pgm + 'unencrypted message = ' + JSON.stringify(message));

                // encrypt message in mailbox using mix encryption
                random_password = Gofreerev.generate_random_password(200);
                key = encrypt.encrypt(random_password);
                message_with_envelope = {
                    receiver_did: mailbox.did,
                    receiver_sha256: mailbox.sha256,
                    server: false,
                    key: key,
                    message: Gofreerev.encrypt(JSON.stringify(message), random_password)
                };

                // todo: server_id for remote gofreerev server added to ping :online response. Not tested!
                // server_id not needed in client request. server knowns server id for each receiver_did
                // if (mailbox.hasOwnProperty('server_id')) message_with_envelope.receiver_server_id = mailbox.server_id ;
                console.log(pgm + 'message_with_envelope = ' + JSON.stringify(message_with_envelope)) ;
                // send encrypted message
                response.push(message_with_envelope);
                // console.log(pgm + 'encrypted message = ' + JSON.stringify(message_with_envelope));
            } // for i (mailboxes)
            return (response.length == 0 ? null : response);
        }; // send_messages

        // ping ok response. move messages from mailbox.sending to mailbox.sent
        var messages_sent = function () {
            var mailbox, i, msg;
            for (i = 0; i < mailboxes.length; i++) {
                mailbox = mailboxes[i];
                while (mailbox.sending.length > 0) {
                    msg = mailbox.sending.shift() ;
                    if (msg.msgtype == 'sync_gifts') {
                        // 1-4 responses for one sync_gifts message. add sub messages (send_gifts, request_gifts, check_gifts and request_comments) to sent folder
                        if (msg.send_gifts) mailbox.sent.push(msg.send_gifts);
                        if (msg.request_gifts) mailbox.sent.push(msg.request_gifts);
                        if (msg.check_gifts) mailbox.sent.push(msg.check_gifts);
                        if (msg.request_comments) mailbox.sent.push(msg.request_comments);
                    }
                    else mailbox.sent.push(msg);
                    if (mailbox.sent.length > 5) mailbox.sent.shift(); // keep last 5 sent messages
                }
            } // for i
        }; // messages_sent

        // ping error response. move messages from mailbox.sending to mailbox.outbox. redo send operation in next ping
        var messages_not_sent = function () {
            var mailbox, i, msg;
            for (i = 0; i < mailboxes.length; i++) {
                mailbox = mailboxes[i];
                while (mailbox.sending.length > 0) {
                    msg = mailbox.sending.shift() ;
                    mailbox.outbox.push(msg);
                }
            } // for i
        }; // messages_sent

        // manage device.ignore_invalid_gifts list - filter messages with invalid gifts
        var is_gift_on_ignore_list = function (device, gid) {
            if (!device.hasOwnProperty('ignore_invalid_gifts')) device.ignore_invalid_gifts = [] ;
            if (device.ignore_invalid_gifts.indexOf(gid) == -1) return false;
            console.log(pgm + 'Error. Gift ' + gid + ' is in ignore list. See previous error message in log.');
            return true;
        };
        var add_gift_to_ignore_list = function (device, gid) {
            if (!device.hasOwnProperty('ignore_invalid_gifts')) device.ignore_invalid_gifts = [] ;
            if (device.ignore_invalid_gifts.indexOf(gid) != -1) return ;
            device.ignore_invalid_gifts.push(gid);
        };


        // move previous message from sent to done or error
        // done: true - move to done folder, false - move to error folder
        // todo: return nil (ok) or text string (fatal error)
        var move_previous_message = function (pgm, mailbox, request_mid, response_msgtype, done) {
            var pgm = service + '.move_previous_message: ' ;
            if (!request_mid) {
                console.log(pgm + 'no previous message');
                return false ;
            }
            // request/response matrix. request message should be in sent folder
            var request_msgtypes ;
            switch (response_msgtype) {
                case 'gifts_sha256':
                    request_msgtypes = ['users_sha256'];
                    break;
                case 'sync_gifts' :
                    request_msgtypes = ['gifts_sha256', 'send_gifts', 'check_gifts', 'request_gifts', 'request_comments'];
                    break;
                case 'error':
                    request_msgtypes = ['users_sha256', 'gifts_sha256', 'send_gifts', 'check_gifts', 'request_gifts',  'request_comments'];
                    break ;
                default:
                    request_msgtypes = [];
            }; // switch
            if (request_msgtypes.length == 0) {
                console.log(pgm + 'Unknown response_msgtype ' + response_msgtype) ;
                return false ;
            }
            if ((typeof done == 'undefined') || (done == null)) done = true ;
            var folder = done ? mailbox.done : mailbox.error ;
            var folder_name = done ? 'done' : 'error' ;
            var msg;
            var index ;
            // check sent folder
            for (var i = 0; i < mailbox.sent.length; i++) {
                if ((mailbox.sent[i].mid == request_mid) && ((index=request_msgtypes.indexOf(mailbox.sent[i].msgtype)) != -1)) {
                    console.log(pgm + 'Moving old ' + request_msgtypes[index] + ' message ' + request_mid + ' from sent to ' + folder_name + ' folder.');
                    msg = mailbox.sent.splice(i, 1);
                    folder.push(msg[0]);
                    return true ;
                }
            }
            // check outbox folder - normally not the case - sent messages should be in sent folder
            for (i = 0; i < mailbox.outbox.length; i++) {
                if ((mailbox.outbox[i].mid == request_mid) && ((index=request_msgtypes.indexOf(mailbox.outbox[i].msgtype)) != -1)) {
                    console.log(pgm + 'Warning. Moving old ' + request_msgtypes[index] + ' message ' + request_mid + ' from outbox to ' + folder_name + ' folder.');
                    msg = mailbox.outbox.splice(i, 1);
                    folder.push(msg[0]);
                    return true ;
                }
            }
            console.log(pgm + 'Error. Old message with mid ' + request_mid + ' with response ' + response_msgtype + ' was not found in mailbox.');
            return false ;
        }; // move_previous_message


        // communication step 2 - receive "users_sha256" message from other device. one user.sha256 signature for each mutual friend
        var receive_message_users_sha256 = function (device, mailbox, msg) {
            var pgm = service + '.receive_message_users_sha256: ';
            var error, json_error;

            // try catch block. send error message to other client in case of hard javascript errors
            try {

                console.log(pgm + 'mailbox = ' + JSON.stringify(mailbox));
                console.log(pgm + 'msg     = ' + JSON.stringify(msg));

                // validate users_sha256 message before processing message
                if (Gofreerev.is_json_message_invalid(pgm, msg, 'users_sha256', '')) {
                    // return JSON error to other device
                    json_error = JSON.parse(JSON.stringify(tv4.error));
                    delete json_error.stack;
                    json_errors = JSON.stringify(json_error);
                    error = 'users_sha256 message rejected by receiver. JSON schema validation errors: ' + json_errors;
                    console.log(pgm + error + ' msg = ' + JSON.stringify(msg));
                    mailbox.outbox.push({
                        mid: Gofreerev.get_new_uid(),
                        request_mid: msg.mid,
                        msgtype: 'error',
                        request_mid: msg.mid,
                        error: error
                    });
                    return;
                }
                ;

                // abort if response to request msg.mid is already in mailbox
                // todo: refactor and add this check to other receive_message_xxxx
                for (i = 0; i < mailbox.outbox.length; i++) {
                    if (mailbox.outbox[i].request_mid == msg.mid) {
                        console.log(pgm + 'Error. Response to users_sha256 message ' + msg.mid + ' is already in outbox.');
                        return;
                    }
                }
                ; // for i
                for (i = 0; i < mailbox.done.length; i++) {
                    if (mailbox.done[i].request_mid == msg.mid) {
                        console.log(pgm + 'Error. Response to users_sha256 message ' + msg.mid + ' is already in done.');
                        return;
                    }
                }
                ; // for i
                for (i = 0; i < mailbox.error.length; i++) {
                    if (mailbox.error[i].request_mid == msg.mid) {
                        console.log(pgm + 'Error. Response to users_sha256 message ' + msg.mid + ' is already in error.');
                        return;
                    }
                }
                ; // for i

                // check for users_sha256 message from client on other Gofreerev server (using sha256 signature as user_id)
                var unknown_sha256_user_ids = [], i, user_id, index, friend, msg_users_old;
                if (mailbox.hasOwnProperty('server_id')) {
                    console.log(pgm + 'users_sha256 message from client on an other Gofreerev server. Translate sha256 signatures in msg.users to internal user ids');
                    console.log(pgm + 'msg.users (1) = ' + JSON.stringify(msg.users));

                    // keep a copy of old sha256 user ids before translation (for debug and error messages)
                    var msg_users_sha256 = [];
                    for (i = 0; i < msg.users.length; i++) {
                        user_id = msg.users[i].user_id;
                        msg_users_sha256.push(user_id);
                    } // for i

                    //// print debug information for user id 2, 3, 920, 1126. todo: remove
                    //var debug_users = [2, 3, 920, 1126], debug_user ;
                    //for (i=0 ; i<debug_users.length ; i++) {
                    //    debug_user = userService.get_friend(debug_users[i]) ;
                    //    if (debug_user) console.log(pgm + 'debug_users[' + debug_users[i] + '] = ' + JSON.stringify(debug_user)) ;
                    //    else console.log(pgm + 'debug_users[' + debug_users[i] + '] was not found');
                    //} // for i

                    // todo: user.sha256 signatures changes when server secret changes
                    // todo: a message received after secret change can be with old sha256 signature.
                    // todo: keep old sha256 signature as a fallback for one or two minutes for old messages
                    // todo: see more todos in userService.get_friend_by_sha256
                    for (i = msg.users.length - 1; i >= 0; i--) {
                        user_id = msg.users[i].user_id;
                        friend = userService.get_friend_by_sha256(user_id);
                        if (friend) {
                            console.log(pgm + 'translating sha256 user_id ' + user_id + ' to internal user_id ' + friend.user_id);
                            msg.users[i].user_id = friend.user_id;
                        }
                        else {
                            console.log(pgm + 'unknown sha256 user_id ' + user_id);
                            unknown_sha256_user_ids.push(msg.users[i].user_id);
                            msg.users.splice(i, 1);
                        }
                    }
                    console.log(pgm + 'msg.users (2) = ' + JSON.stringify(msg.users));
                    if (unknown_sha256_user_ids.length > 0) console.log(pgm + 'unknown_sha256_user_ids = ' + JSON.stringify(unknown_sha256_user_ids));
                }
                ; // if

                // compare mailbox.mutual_friends and msg.users. list of users in msg must be a sublist of mutual friends
                var my_mutual_friends = mailbox.mutual_friends;
                var msg_users = [];
                for (i = 0; i < msg.users.length; i++) {
                    user_id = msg.users[i].user_id;
                    msg_users.push(user_id);
                }
                ; // for i
                var invalid_user_ids = $(msg_users).not(my_mutual_friends).get();
                console.log(pgm + 'msg_users = ' + JSON.stringify(msg_users) + ', my_mutual_friends = ' + JSON.stringify(my_mutual_friends) + ', invalid_user_ids = ' + JSON.stringify(invalid_user_ids));
                // msg_users = [2,3], my_mutual_friends = [920], invalid_user_ids  = [2,3]" gofreerev.js:4220:0
                if (invalid_user_ids.length + unknown_sha256_user_ids.length > 0) {
                    // unknown or invalid user in users_sha256 message:
                    error = (invalid_user_ids.length + unknown_sha256_user_ids.length) + ' rejected users(s) in users_sha256 message';
                    if (msg_users_sha256) error += '. Received sha256 user signatures: ' + msg_users_sha256.join(', ');
                    if (unknown_sha256_user_ids.length > 0) error += '. Unknown sha256 user signatures: ' + unknown_sha256_user_ids.join(', ');
                    error += '. Received internal user ids: ' + msg_users.join(', ');
                    if (invalid_user_ids.length > 0) {
                        error += '. Expected user ids: ' + my_mutual_friends.join(', ');
                        error += '. Unknown mutual friends: ' + invalid_user_ids.join(', ');
                    }
                    console.log(pgm + error);
                    // continue with users_sha256 message if possible
                    msg_users = $(msg_users).not(invalid_user_ids).get();
                    console.log(pgm + 'msg_users.length = ' + msg_users.length);
                    if (msg_users.length == 0) {
                        console.log(pgm + 'Could not receive users_sha256 message. User ids in message and mutual users in mailbox does not match');
                        mailbox.outbox.push({
                            mid: Gofreerev.get_new_uid(),
                            request_mid: msg.mid,
                            msgtype: 'error',
                            error: error
                        });
                        return;
                    } // if
                } // if
                //var missing_user_ids = $(my_mutual_friends).not(msg_users).get() ;
                //if (missing_user_ids.length > 0) {
                //    console.log(pgm + 'User id ' + missing_user_ids.join(', ') + ' was missing in message. ' +
                //                'Expected user ids ' + mailbox.mutual_friends.join(', ') + '. Found user ids ' + msg_users.join(', ') + '.') ;
                //    my_mutual_friends = $(my_mutual_friends).not(missing_user_ids).get() ;
                //    if (my_mutual_friends.length == 0) return ;
                //}
                //var mutual_friends = my_mutual_friends ;
                //console.log(pgm + 'mutual_friends = ' + mutual_friends.join(', ')) ;

                // exclude some gifts from user sha256 calculation.
                var oldest_gift_at = 0; // todo: max oldest_gift_at on this device and msg.oldest_gift_at
                var ignore_invalid_gifts = []; // todo: merge msg.ignore_invalid_gifts and device.ignore_invalid_gifts gids

                // compare sha256 values for msg.users - continue gift sync until sha256 values are identical todo: or endless loop is detected
                var sha256_array = calc_sha256_for_users(msg_users, oldest_gift_at, ignore_invalid_gifts);
                var sha256_hash = {};
                for (i = 0; i < sha256_array.length; i++) {
                    user_id = sha256_array[i].user_id;
                    sha256_hash[user_id] = {my_sha256: sha256_array[i].sha256};
                } // for i
                for (i = 0; i < msg.users.length; i++) {
                    user_id = msg.users[i].user_id;
                    if (invalid_user_ids.indexOf(user_id) != -1) continue; // skip "invalid" users (devices on two different Gofreerev servers dont have to agree 100% about mutual friends)
                    // if (mutual_friends.indexOf(user_id) == -1) continue ;
                    sha256_hash[user_id].msg_sha256 = msg.users[i].sha256;
                } // for i
                console.log(pgm + 'sha256_hash = ' + JSON.stringify(sha256_hash));
                //sha256_hash = {"1126":{"my_sha256":null,
                //                       "msg_sha256":null},
                //               "920": {"my_sha256":"\u0011½ åìÊ~\u000b\u0007Y\u000bá\\>é\u0013ìÞOì\\ÏwÆJ+K\nª\n",
                //                       "msg_sha256":"aÕÛPîÂ\t¬B!\u001cíÌÁ2\"ò®\u000fvEUO\u000fåuÙ"}}

                // find users with sha256 difference
                var user_ids = [];
                for (user_id in sha256_hash) {
                    if ((sha256_hash[user_id].my_sha256 == null) && (sha256_hash[user_id].msg_sha256 == null)) continue;
                    if (sha256_hash[user_id].my_sha256 != sha256_hash[user_id].msg_sha256) user_ids.push(parseInt(user_id));
                }
                if (user_ids.length == 0) {
                    console.log(pgm + 'mutual gifts for this device are up-to-date.');
                    return;
                }
                user_ids.sort();
                console.log(pgm + 'user_ids = ' + user_ids.join(', '));

                // find sha256 values for relevant gifts (msg.users)
                var gifts_sha256_hash = {}, j, gift;
                for (i = 0; i < user_ids.length; i++) {
                    user_id = user_ids[i];
                    if (!user_id_to_gifts.hasOwnProperty(user_id)) {
                        console.log(pgm + 'No gifts was found for user id ' + user_id);
                        continue;
                    }
                    console.log(pgm + 'user_id_gifts_index[' + user_id + '].length = ' + user_id_to_gifts[user_id].length);
                    for (j = 0; j < user_id_to_gifts[user_id].length; j++) {
                        gift = user_id_to_gifts[user_id][j];
                        if (!gift.sha256) continue; // no server gift signature or sha256 gift calculation error
                        // todo: add gift.updated_at_client property - apply oldest_gift_at filter
                        if (!gifts_sha256_hash[gift.gid]) gifts_sha256_hash[gift.gid] = gift.sha256;
                    } // for j
                } // for i
                console.log(pgm + 'gifts_sha256_hash = ' + JSON.stringify(gifts_sha256_hash));
                //gifts_sha256_hash =
                //    {"14239781692770120364":"ä Ùh¿G×Ñâô9ÔÀ4ÀXèk\u0010N~,\nB]M",
                //     "14239781692770348983":",F¯Ø\"Lo\u0004ö5é_Ï%p\\T¡(j{ï³o",
                //        ...
                //     "14244941900636888171":"¨Yr¤ï9ÉÀðn\u0000K JýôNèÅMêÛûCô"}

                var gifts_sha256_array = [];
                for (var gid in gifts_sha256_hash) {
                    gifts_sha256_array.push({gid: gid, sha256: gifts_sha256_hash[gid]});
                }

                // communication step 3 - insert gifts_sha256 message in outbox. will be send in next ping request
                var gifts_sha256_message = {
                    mid: Gofreerev.get_new_uid(),
                    request_mid: msg.mid,
                    msgtype: 'gifts_sha256',
                    ignore_invalid_gifts: ignore_invalid_gifts,
                    users: user_ids,
                    gifts: gifts_sha256_array
                };
                if (oldest_gift_at > 0) gifts_sha256_message.oldest_gift_at = oldest_gift_at;

                if (mailbox.hasOwnProperty('server_id')) {
                    // translate internal user ids to sha256 signatures before sending gifts_sha256 message
                    console.log(pgm + 'gifts_sha256_message (1) = ' + JSON.stringify(gifts_sha256_message));
                    //gifts_sha256_message =
                    //{"mid":"14273774200608483113","request_mid":"14273773969082891666","msgtype":"gifts_sha256",
                    //    "ignore_invalid_gifts":[],
                    //    "users":[920],
                    //    "gifts":[{"gid":"14253148989837740200","sha256":"9mÙ@¥ÔÖûÊ\u0010B«î¶Q:È\u0007k\u0013[´\u0019vCÛ\u0014Pm"},{"gid":"14253152345973353338","sha256":"9mÙ@¥ÔÖûÊ\u0010B«î¶Q:È\u0007k\u0013[´\u0019vCÛ\u0014Pm"},{"gid":"14253163835441202510","sha256":"9mÙ@¥ÔÖûÊ\u0010B«î¶Q:È\u0007k\u0013[´\u0019vCÛ\u0014Pm"},{"gid":"14253166119353097472","sha256":"9mÙ@¥ÔÖûÊ\u0010B«î¶Q:È\u0007k\u0013[´\u0019vCÛ\u0014Pm"},{"gid":"14253170024715544645","sha256":"gµï\u0015îé;;¯Æ'åéz²¦]^ý£ß½Rõl\"l\"ö"},{"gid":"14254791174816684686","sha256":"Çî\u0002t 31gõ¤7NÈªãÃÏ\u0018ÂØ\u0013 ×Ü*á\u0013ùÑ"},{"gid":"14255660363225768616","sha256":"·ï^ýEª0W\u0000Ê\u001cãC%âÝ=râ=p[rïYµ²¯¸"},{"gid":"14255663264284720316","sha256":"ÉÛ5}y­\u001cÓÙhuÂÈýËmêFÉê¥±\u0000ýÞ\\\u0015¦"},{"gid":"14255666249033078430","sha256":"yå·¾à¿ÒX\u0013¼\u0005þ8J|¼±¡`|Ýªy¨98ÉJ°"},{"gid":"14255715337351272927","sha256":":# ÅÚ¹Ì\u0015ûì\bJ{Ø\u000eø\u001e/\u001d\u000fÕý³U\u001d«"},{"gid":"14258782920140696549","sha256":"9mÙ@¥ÔÖûÊ\u0010B«î¶Q:È\u0007k\u0013[´\u0019vCÛ\u0014Pm"}]}" gofreerev.js:4504:0
                    if (error = userService.user_ids_to_remote_sha256(gifts_sha256_message.users, 'mutual_friends', mailbox.server_id, gifts_sha256_message, false)) {
                        // write error in log and return error message to other client
                        error = 'Could not send gifts_sha256 response to users_sha256 request. ' + error;
                        console.log(pgm + error + ' msg = ' + JSON.stringify(msg));
                        mailbox.outbox.push({
                            mid: Gofreerev.get_new_uid(),
                            request_mid: msg.mid,
                            msgtype: 'error',
                            error: error
                        });
                        return;
                    } // translate error
                    // translate ok
                    console.log(pgm + 'gifts_sha256_message (2) = ' + JSON.stringify(gifts_sha256_message));
                }

                // validate gifts_sha256 message before adding to outbox
                if (Gofreerev.is_json_message_invalid(pgm, gifts_sha256_message, 'gifts_sha256', '')) {
                    // error message has already been written to log
                    // todo: error debugging - no mutual friends was found
                    console.log(pgm + 'users = ' + JSON.stringify(user_ids));
                    console.log(pgm + 'gifts = ' + JSON.stringify(gifts_sha256_array));
                    console.log(pgm + 'user_id_to_gifts = ' + JSON.stringify(user_id_to_gifts));
                    // send error message to other device
                    var json_error = JSON.parse(JSON.stringify(tv4.error));
                    delete json_error.stack;
                    var json_errors = JSON.stringify(json_error);
                    error = 'Error when processing users_sha256 message. JSON schema validation error in following gifts_sha256 message. ' + json_errors;
                    console.log(pgm + error + ' msg = ' + JSON.stringify(msg));
                    mailbox.outbox.push({
                        mid: Gofreerev.get_new_uid(),
                        request_mid: msg.mid,
                        msgtype: 'error',
                        request_mid: msg.mid,
                        error: error
                    });
                    return;
                }

                // abort if identical gifts_sha256 message is already in outbox.
                var folders = {outbox: mailbox.outbox, sent: mailbox.sent}, folder, old_msg;
                var sent_at, elapsed_time;
                for (folder in folders) {
                    for (i = 0; i < folders[folder].length; i++) {
                        old_msg = folders[folder][i];
                        if (old_msg.msgtype == 'gifts_sha256') {
                            console.log(pgm + 'Warning. Found old gifts_sha256 message in ' + folder);
                            console.log(pgm + 'mailbox = ' + JSON.stringify(mailbox));
                            console.log(pgm + 'gifts_sha256 message = ' + JSON.stringify(gifts_sha256_message));
                            sent_at = parseInt(old_msg.mid.substr(0, 13));
                            elapsed_time = new Date().getTime() - sent_at;
                            console.log(pgm + 'sent_at = ' + sent_at + ', elapted_time = ' + elapsed_time);
                            if ((elapsed_time < 60000) && (old_msg.users.join(',') == gifts_sha256_message.users.join(','))) {
                                // new identical gifts_sha256 response less than 1 minute ago
                                error = 'Ignoring doublet users_sha256 request ' + msg.mid + '. Gifts_sha256 response ' + old_msg.mid + ' has already been sent less than 1 minute ago';
                                console.log(pgm + error + ' msg = ' + JSON.stringify(msg));
                                mailbox.outbox.push({
                                    mid: Gofreerev.get_new_uid(),
                                    request_mid: msg.mid,
                                    msgtype: 'error',
                                    request_mid: msg.mid,
                                    error: error
                                });
                                return;
                            }
                        }
                    } // for i
                } // for folder (outbox, sent)

                mailbox.outbox.push(gifts_sha256_message);
            }
            catch
                (err) {
                error = 'Fatal javascript error when processing users_sha256 message. ' + err.message;
                console.log(pgm + error);
                console.log(pgm + 'stack trace = ' + err.stack);
                mailbox.outbox.push({
                    mid: Gofreerev.get_new_uid(),
                    msgtype: 'error',
                    request_mid: msg.mid,
                    error: error
                });
            }

        }; // receive_message_users_sha256


        // clone gift object before adding to outgoing message
        // not all fields are used in message and some fields are updated before message is send
        var make_gift_clone = function (gift) {
            // optional accept gift operation
            var accepted_cid, accepted_at_client ;
            if (gift.hasOwnProperty('accepted_at_server')) {
                // accept gift operation complete
                accepted_cid = gift.accepted_cid ;
                accepted_at_client = gift.accepted_at_client ;
            };
            // optional delete gift operation
            var deleted_at_client ;
            if (gift.hasOwnProperty('deleted_at_server')) deleted_at_client = gift.deleted_at_client; // delete operation complete
            return {
                gid: gift.gid,
                giver_user_ids: Gofreerev.clone_array(gift.giver_user_ids),
                receiver_user_ids: Gofreerev.clone_array(gift.receiver_user_ids),
                created_at_client: gift.created_at_client,
                created_at_server: gift.created_at_server,
                price: gift.price,
                currency: gift.currency,
                direction: gift.direction,
                description: gift.description,
                open_graph_url: gift.open_graph_url,
                open_graph_title: gift.open_graph_title,
                open_graph_description: gift.open_graph_description,
                open_graph_image: gift.open_graph_image,
                like: gift.like,
                accepted_cid: accepted_cid,
                accepted_at_client: accepted_at_client,
                // todo: add accepted_at_server (integer)?
                deleted_at_client: deleted_at_client
                // todo: add deleted_at_server (integer)?
            };
        }; // make_gift_clone

        // clone comment object before adding to outgoing message
        // not all fields are used in message and some fields are updated before message is send
        var make_comment_clone = function (comment) {
            // optional new deal action (cancel, accept or reject new deal proposal)
            var new_deal_action, new_deal_action_by_user_ids, new_deal_action_at_client ;
            if (comment.hasOwnProperty('new_deal_action_at_server')) {
                // new deal action complete
                new_deal_action = comment.new_deal_action ;
                new_deal_action_by_user_ids = comment.new_deal_action_by_user_ids ;
                new_deal_action_at_client = comment.new_deal_action_at_client ;
            };
            // optional delete comment
            var deleted_at_client ;
            if (comment.hasOwnProperty('deleted_at_server')) deleted_at_client = comment.deleted_at_client ;
            return {
                cid: comment.cid,
                user_ids: Gofreerev.clone_array(comment.user_ids),
                price: comment.price,
                currency: comment.currency,
                comment: comment.comment,
                created_at_client: comment.created_at_client,
                created_at_server: comment.created_at_server,
                new_deal: comment.new_deal,
                new_deal_action: new_deal_action,
                new_deal_action_by_user_ids: Gofreerev.clone_array(new_deal_action_by_user_ids),
                new_deal_action_at_client: new_deal_action_at_client,
                // todo: add new_deal_action_at_server (integer)?
                deleted_at_client: deleted_at_client
                // todo: add deleted_at_server (integer)?
                // ,sha256: comment.sha256
            };
        }; // make_comment_clone

        // logical validate "send_gifts" message before send (receive_message_sync_gifts) and after receive (receive_message_send_gifts)
        // called after json validation but before sending send_gifts message / processing information in received send_gifts message
        // returns nil or error message
        // params:
        // - context: 'send' : sending message, 'receive' : receiving message
        var validate_send_gifts_message = function (mailbox, send_gifts, context) {
            var pgm = service + '.validate_send_gifts_message: ' ;
            var error ;
            if (context == 'send') console.log(pgm + 'validating send_gifts message before send') ;
            else if (context == 'receive') console.log(pgm + 'validating send_gifts message after received') ;
            else return 'System error. Invalid validate_send_gifts_message call. context = ' + context ;

            // check missing gifts array
            if (!send_gifts.gifts || !send_gifts.gifts.length || send_gifts.gifts.length == 0) return 'No gifts array or empty gifts array in send_gifts message.';

            // collect all user ids in send_gifts message (gift giver, gift receiver, comment creator)
            // user must be a mutual user (mailbox.mutual_user) or must be in msg.users array
            // in many situations an user id can be found in friends array
            // information in msg.users array is used as fallback if user is not found in friends array
            var expected_user_ids = [] ;

            // collect server ids in send_gifts message.
            // array with sha256 signatures for servers must be included in cross server messages
            // internal server ids on this server => sever sha256 signatures => internal server ids on other server
            var cross_server_message = mailbox.hasOwnProperty('server_id') ;
            var expected_server_ids = [] ;

            // check doublet gifts
            var new_gids = [], i, j, new_gift, doublet_gids = 0;
            for (i = 0; i < send_gifts.gifts.length; i++) {
                new_gift = send_gifts.gifts[i];
                if (new_gids.indexOf(new_gift.gid) != -1) doublet_gids += 1;
                else {
                    new_gids.push(new_gift.gid);
                    add_user_ids_to_array(new_gift.giver_user_ids, expected_user_ids, false) ;
                    add_user_ids_to_array(new_gift.receiver_user_ids, expected_user_ids, false) ;
                    if (expected_server_ids.indexOf(new_gift.created_at_server) == -1) expected_server_ids.push(new_gift.created_at_server) ;
                }
            } // for i
            if (doublet_gids > 0) return 'Found ' + doublet_gids + ' doublet gifts in sync_gifts/send_gifts sub message. gid must be unique.';
            new_gids = null;

            // check doublet comments
            var new_cids = [], doublet_cids = 0, j, new_comment;
            for (i = 0; i < send_gifts.gifts.length; i++) {
                new_gift = send_gifts.gifts[i];
                if (!new_gift.comments) continue;
                for (j = 0; j < new_gift.comments.length; j++) {
                    new_comment = new_gift.comments[j];
                    if (new_cids.indexOf(new_comment.cid) != -1) doublet_cids += 1;
                    else {
                        new_cids.push(new_comment.cid);
                        add_user_ids_to_array(new_comment.user_ids, expected_user_ids, false);
                        add_user_ids_to_array(new_comment.new_deal_action_by_user_ids, expected_user_ids, false);
                        if (expected_server_ids.indexOf(new_comment.created_at_server) == -1) expected_server_ids.push(new_comment.created_at_server) ;
                    }
                } // for j (comments)
            } // for i (gifts)
            if (doublet_cids > 0) return 'Found ' + doublet_cids + ' doublet comments in sync_gifts/send_gifts sub message. cid must be unique.';
            new_cids = null;

            // check received users in send_gifts.users
            var user_id ;
            var received_user_ids = [], user ;
            var doublet_user_ids = [] ;
            if (send_gifts.users) for (i=0 ; i<send_gifts.users.length ; i++) {
                user = send_gifts.users[i] ;
                user_id = user.user_id ;
                if (received_user_ids.indexOf(user_id) == -1) received_user_ids.push(user_id) ;
                else if (doublet_user_ids.indexOf(user_id) == -1) doublet_user_ids.push(user_id) ;
            }
            if (doublet_user_ids.length > 0) return 'Found doublet users ' + doublet_user_ids.join(', ') + ' in sync_gifts/send_gifts sub message. Users in users array must be unique.' ;

            // compare expected & received users
            var mutual_friends, friend ;
            if (cross_server_message) {
                // send_gifts message to/from other Gofreerev server using sha256 signatures instead of internal user ids
                if (context == 'send') {
                    // sending send_gifts message using remote sha256 signatures for users
                    mutual_friends = Gofreerev.clone_array(mailbox.mutual_friends) ;
                    error=userService.user_ids_to_remote_sha256(mutual_friends, 'mutual_friends', mailbox.server_id, send_gifts, false) ;
                    if (error) return 'System error. Cannot validate sync_gifts/send_gifts sub message. ' + error ;
                }
                else {
                    // receiving send_gifts message expecting sha256 signatures for users
                    mutual_friends = [] ;
                    for (i=0 ; i<mailbox.mutual_friends.length ; i++) {
                        user_id = mailbox.mutual_friends[i] ;
                        friend = userService.get_friend(user_id) ;
                        mutual_friends.push(friend.sha256) ;
                        if (friend.old_sha256) mutual_friends.push(friend.old_sha256) ; // allow messages with old signatures for a few minutes
                    } // for i
                }
            }
            else mutual_friends = mailbox.mutual_friends ; // internal user ids
            console.log(pgm + 'mutual_friends = ' + JSON.stringify(mutual_friends)) ;
            for (i=expected_user_ids.length-1 ; i >= 0 ; i--) {
                user_id = expected_user_ids[i] ;
                if (mutual_friends.indexOf(user_id) != -1) expected_user_ids.splice(i,1) ;
            } // for i (send_gifts_user_ids)
            var missing_user_ids = $(expected_user_ids).not(received_user_ids).get() ;
            if (missing_user_ids.length > 0) {
                return 'Users ' + missing_user_ids.join(', ') + ' were missing in sync_gifts/send_gifts sub message. All not mutual friends used in gifts array must be sent in users array as fallback information.' ;
            }
            var unexpected_user_ids = $(received_user_ids).not(expected_user_ids).get() ;
            if (unexpected_user_ids.length > 0) {
                return 'Unexpected users ' + unexpected_user_ids.join(', ') + ' were found in sync_gifts/send_gifts sub message. Only relevant not mutual friends must be sent in users array as fallback information.' ;
            }

            // check servers (only cross server send_gifts message)
            if (cross_server_message) {
                if (!send_gifts.servers) {
                    return 'Servers array was missing in a cross server sync_gifts/send_gifts sub message. Servers array must be included cross server messages' ;
                }
                var received_server_ids = [], doublet_server_ids = [], server_id ;
                for (i=0 ; i<send_gifts.servers.length ; i++) {
                    server_id = send_gifts.servers[i].server_id ;
                    if (received_server_ids.indexOf(server_id) == -1) received_server_ids.push(server_id) ;
                    else if (doublet_server_ids.indexOf(server_id) == -1) doublet_server_ids.push(server_id) ;
                }
                if (doublet_server_ids.length > 0) return 'Found doublet server ids ' + doublet_server_ids.join(', ') + ' in sync_gifts/send_gifts sub message. Server ids in servers array must be unique.' ;
                // compare expected and received server ids. 
                var missing_server_ids = $(expected_server_ids).not(received_server_ids).get() ;
                if (missing_server_ids.length > 0) {
                    console.log(pgm + 'expected_server_ids = ' + expected_server_ids.join(', ')) ;
                    console.log(pgm + 'received_server_ids = ' + received_server_ids.join(', ')) ;
                    return 'Server ids ' + missing_server_ids.join(', ') + ' were missing in sync_gifts/send_gifts sub message. All server ids from created_at_server must be sent in servers array.' ;
                }
                var unexpected_server_ids = $(received_server_ids).not(expected_server_ids).get() ;
                if (unexpected_server_ids.length > 0) {
                    return 'Unexpected server ids ' + unexpected_server_ids.join(', ') + ' were found in sync_gifts/send_gifts sub message. Only relevant server ids must be sent in servers array.' ;
                }
            }
            else {
                // within server message
                if (send_gifts.servers) {
                    return 'Unexpected servers array in a within server send_gifts message. Servers array is only used in cross server messages' ;
                }
            }

            // debug info
            console.log(pgm + 'send_gifts_received_user_ids  = ' + received_user_ids.join(', ')) ;
            console.log(pgm + 'send_gifts_expected_user_ids  = ' + expected_user_ids.join(', ')) ;
            console.log(pgm + 'send_gift_missing_user_ids    = ' + missing_user_ids.join(', ')) ;
            console.log(pgm + 'send_gift_unexpected_user_ids = ' + unexpected_user_ids.join(', ')) ;

        }; // validate_send_gifts_message


        // logical validate "request_gifts" message before send (receive_message_gifts_sha256) and after receive (receive_message_request_gifts)
        // called after json validation but before sending request_gifts / processing information in received request_gifts message
        // gids in request gifts message must be unique
        // returns nil or error message
        var validate_request_gifts_message = function (mailbox, request_gifts, context) {
            var pgm = service + '.validate_request_gifts_message: ' ;
            var error ;
            if (context == 'send') console.log(pgm + 'validating request_gifts message before send') ;
            else if (context == 'receive') console.log(pgm + 'validating request_gifts message after received') ;
            else return 'System error. Invalid validate_request_gifts_message call. context = ' + context ;

            // check missing gifts array - already checked in JSON validation!
            if (!request_gifts.gifts || !request_gifts.gifts.length || request_gifts.gifts.length == 0) return 'No gifts array or empty gifts array in request_gifts.';

            // check doublet gifts
            var gids = [], doublet_gids = 0, gid, i;
            for (i = 0; i < request_gifts.gifts.length; i++) {
                gid = request_gifts.gifts[i];
                if (gids.indexOf(gid) != -1) doublet_gids += 1;
                else gids.push(gid);
            } // for j (comments)
            if (doublet_gids > 0) return 'Found ' + doublet_gids + ' doublet gifts in sync_gifts/request_gifts sub message. gid must be unique.';

            // message ok

        } ; // validate_request_gifts_message


        // logical validate "invalid_gifts" message before send (receive_message_send_gifts) and after receive (receive_message_invalid_gifts)
        // called after json validation but before sending invalid_gifts message / processing information in received invalid_gifts message
        // returns nil or error message
        // params:
        // - context: 'send' : sending message, 'receive' : receiving message
        var validate_invalid_gifts_message = function (mailbox, invalid_gifts, context) {
            var pgm = service + '.validate_invalid_gifts_message: ' ;
            var error ;
            if (context == 'send') console.log(pgm + 'validating invalid_gifts message before send') ;
            else if (context == 'receive') console.log(pgm + 'validating invalid_gifts message after received') ;
            else return 'System error. Invalid validate_invalid_gifts_message call. context = ' + context ;

            // check missing gifts array
            if (!invalid_gifts.gifts || !invalid_gifts.gifts.length || invalid_gifts.gifts.length == 0) return 'No gifts array or empty gifts array in invalid_gifts message.';

            // check doublet gifts
            var new_gids = [], i, j, new_gift, doublet_gids = 0;
            for (i = 0; i < invalid_gifts.gifts.length; i++) {
                new_gift = invalid_gifts.gifts[i];
                if (new_gids.indexOf(new_gift.gid) != -1) doublet_gids += 1;
                else new_gids.push(new_gift.gid);
            } // for i
            if (doublet_gids > 0) return 'Found ' + doublet_gids + ' doublet gifts in sync_gifts/invalid_gifts sub message. gid must be unique.';

        }; // validate_invalid_gifts_message



        // communication step 3 - compare sha256 values for gifts (mutual friends)
        var receive_message_gifts_sha256 = function (device, mailbox, msg) {
            var pgm = service + '.receive_message_gifts_sha256: ' ;
            var error ;
            console.log(pgm + 'mailbox = ' + JSON.stringify(mailbox)) ;
            console.log(pgm + 'msg     = ' + JSON.stringify(msg)) ;

            // try catch block. send error message to other client in case of hard javascript errors
            try {

                // validate gifts_sha256 message before processing message
                if (Gofreerev.is_json_message_invalid(pgm, msg, 'gifts_sha256', '')) {
                    // move previous users_sha256 message to error folder
                    if (!move_previous_message(pgm, mailbox, msg.request_mid, 'gifts_sha256', false)) return; // ignore - not found in mailbox
                    // return JSON error to other device
                    var json_error = JSON.parse(JSON.stringify(tv4.error));
                    delete json_error.stack;
                    var json_errors = JSON.stringify(json_error);
                    var error = 'Receiver rejected gifts_sha256 message. JSON schema validation errors: ' + json_errors;
                    console.log(pgm + error + ' msg = ' + JSON.stringify(msg));
                    mailbox.outbox.push({
                        mid: Gofreerev.get_new_uid(),
                        request_mid: msg.mid,
                        msgtype: 'error',
                        request_mid: msg.mid,
                        error: error
                    });
                    return;
                }

                // abort if response to request msg.mid is already in mailbox
                // todo: refactor this check and add to other receive_message_xxxxx
                for (i = 0; i < mailbox.outbox.length; i++) {
                    if (mailbox.outbox[i].request_mid == msg.mid) {
                        console.log(pgm + 'Error. Response to gifts_sha256 message ' + msg.mid + ' is already in outbox.');
                        return;
                    }
                } // for i
                for (i = 0; i < mailbox.done.length; i++) {
                    if (mailbox.done[i].request_mid == msg.mid) {
                        console.log(pgm + 'Error. Response to gifts_sha256 message ' + msg.mid + ' is already in done.');
                        return;
                    }
                } // for i
                for (i = 0; i < mailbox.error.length; i++) {
                    if (mailbox.error[i].request_mid == msg.mid) {
                        console.log(pgm + 'Error. Response to gifts_sha256 message ' + msg.mid + ' is already in error.');
                        return;
                    }
                } // for i

                // move previous users_sha256 message to done folder
                if (!move_previous_message(pgm, mailbox, msg.request_mid, 'gifts_sha256', true)) return; // ignore - not found in mailbox

                // check for gifts_sha256 message from client on other Gofreerev server (using sha256 signature as user_id)
                var unknown_sha256_user_ids = [], i, user_id, index, friend, msg_users_old;
                if (mailbox.hasOwnProperty('server_id')) {
                    console.log(pgm + 'gifts_sha256 message from client on an other Gofreerev server. Translate sha256 signatures in msg.users to internal user ids');
                    console.log(pgm + 'msg.users (1) = ' + JSON.stringify(msg.users));

                    // keep a copy of old sha256 user ids before translation (for debug and error messages)
                    var msg_users_sha256 = [];
                    for (i = 0; i < msg.users.length; i++) msg_users_sha256.push(msg.users[i]);

                    //// print debug information for user id 2, 3, 920, 1126. todo: remove
                    //var debug_users = [2, 3, 920, 1126], debug_user ;
                    //for (i=0 ; i<debug_users.length ; i++) {
                    //    debug_user = userService.get_friend(debug_users[i]) ;
                    //    if (debug_user) console.log(pgm + 'debug_users[' + debug_users[i] + '] = ' + JSON.stringify(debug_user)) ;
                    //    else console.log(pgm + 'debug_users[' + debug_users[i] + '] was not found');
                    //} // for i

                    // todo: user.sha256 signatures changes when server secret changes
                    // todo: a message received after secret change can be with old sha256 signature.
                    // todo: keep old sha256 signature as a fallback for one or two minutes for old messages
                    // todo: see more todos in userService.get_friend_by_sha256
                    for (i = msg.users.length - 1; i >= 0; i--) {
                        user_id = msg.users[i];
                        friend = userService.get_friend_by_sha256(user_id);
                        if (friend) {
                            console.log(pgm + 'translating sha256 user_id ' + user_id + ' to internal user_id ' + friend.user_id);
                            msg.users[i] = friend.user_id;
                        }
                        else {
                            console.log(pgm + 'unknown sha256 user_id ' + user_id);
                            unknown_sha256_user_ids.push(user_id);
                            msg.users.splice(i, 1);
                        }
                    }
                    console.log(pgm + 'msg.users (2) = ' + JSON.stringify(msg.users));
                    if (unknown_sha256_user_ids.length > 0) console.log(pgm + 'unknown_sha256_user_ids = ' + JSON.stringify(unknown_sha256_user_ids));
                } // if

                // compare mailbox.mutual_friends and msg.users. list of users in msg must be a sublist of mutual friends
                var my_mutual_friends = mailbox.mutual_friends;
                var msg_users = msg.users;
                var invalid_user_ids = $(msg_users).not(my_mutual_friends).get();

                if (invalid_user_ids.length + unknown_sha256_user_ids.length > 0) {
                    // unknown or invalid user in users_sha256 message:
                    error = (invalid_user_ids.length + unknown_sha256_user_ids.length) + ' rejected users(s) in users_sha256 message';
                    if (msg_users_sha256) error += '. Received sha256 user signatures: ' + msg_users_sha256.join(', ');
                    if (unknown_sha256_user_ids.length > 0) error += '. Unknown sha256 user signatures: ' + unknown_sha256_user_ids.join(', ');
                    error += '. Received internal user ids: ' + msg_users.join(', ');
                    if (invalid_user_ids.length > 0) {
                        error += '. Expected user ids: ' + my_mutual_friends.join(', ');
                        error += '. Unknown mutual friends: ' + invalid_user_ids.join(', ');
                    }
                    console.log(pgm + error);
                    if (msg_users.length == 0) {
                        mailbox.outbox.push({
                            mid: Gofreerev.get_new_uid(),
                            request_mid: msg.mid,
                            msgtype: 'error',
                            error: error
                        });
                        return;
                    }
                    // continue without invalid user ids
                    msg_users = $(msg_users).not(invalid_user_ids).get();
                }

                // todo: users in this gifts_sha256 message should be identical to users in previous users_sha256 message (now in done)

                // find sha256 values for relevant gifts / users (sublist of mutual friends)
                var gifts_sha256_hash = {}, user_id, i, j, k, gift, gid;
                for (i = 0; i < msg_users.length; i++) {
                    user_id = msg_users[i];
                    if (!user_id_to_gifts.hasOwnProperty(user_id)) {
                        // no gifts for this user id
                        console.log(pgm + 'no gifts for user id ' + user_id);
                        continue;
                    }
                    console.log(pgm + 'user_id_gifts_index[' + user_id + '].length = ' + user_id_to_gifts[user_id].length);
                    for (j = 0; j < user_id_to_gifts[user_id].length; j++) {
                        gift = user_id_to_gifts[user_id][j];
                        if (!gift.sha256) continue; // no server gift signature or sha256 gift calculation error
                        gid = gift.gid;
                        // todo: add gift.updated_at_client property - apply oldest_gift_at filter
                        if (!gifts_sha256_hash[gid]) gifts_sha256_hash[gid] = {
                            my_sha256: gift.sha256,
                            msg_sha256: null
                        };
                    } // for j
                } // for i
                // add sha256 values received from other device
                for (i = 0; i < msg.gifts.length; i++) {
                    gid = msg.gifts[i].gid;
                    if (gifts_sha256_hash[gid]) gifts_sha256_hash[gid].msg_sha256 = msg.gifts[i].sha256;
                    else gifts_sha256_hash[gid] = {my_sha256: null, msg_sha256: msg.gifts[i].sha256};
                }
                // console.log(pgm + 'gifts_sha256_hash = ' + JSON.stringify(gifts_sha256_hash)) ;
                //gifts_sha256_hash =
                //{"14239781692770120364":{"my_sha256":"ä Ùh¿G×Ñâô9ÔÀ4ÀXèk\u0010N~,\nB]M","msg_sha256":null},
                //    "14239781692770348983":{"my_sha256":",F¯Ø\"Lo\u0004ö5é_Ï%p\\T¡(j{ï³o","msg_sha256":null},
                //    "14239781692770427293":{"my_sha256":"\u0006Ã!\u001a%¬c^þÒ*Ì]¾«û¥e$µ`By\u001f\u0017ëÌ×¾Æ","msg_sha256":null},
                //    "14239781692770522732":{"my_sha256":"S{F&ùúW]_¯M­LlBµ\u001dõ¤\u0012HTæÈAtS\u0015ù","msg_sha256":null},
                //    "14239781692770775148":{"my_sha256":"yÙùBÎM-/úï¤¯ã¹\u000eË¨\u001e%íaX©«áäú·","msg_sha256":null},
                //    "14239781692770876536":{"my_sha256":"\u0011î5E-ÙS´'è%Ù½©FäÆk9´Èl$ç6\u001a?Ü\nO","msg_sha256":null},
                //    "14239781692771119206":{"my_sha256":"Þ±ºVí\u0001í·\rtMFû+ú\u0013R\rêJO®Wü\u0001á¸","msg_sha256":null},
                //    "14239781692771120584":{"my_sha256":"ûu±Y|\"s\n@Ñ¨wú¢~¨«\u000eóH|bßê¨\u001fu/","msg_sha256":null},
                //    "14239781692771483562":{"my_sha256":"\u0002q½¾\u001b¶_¢g$\u000er(\u0012Û°WD ?°\u0004Zsæ\u001d","msg_sha256":null},
                //    "14239781692771530176":{"my_sha256":"\u0006ß»×äÈrÅ·;;ËgPø8{\u0011RÃoÁA±,ÌKH","msg_sha256":null},
                //    "14239781692771703391":{"my_sha256":"jF¶tã#V8kMÅÊHÉA\u001eBã¬H\u0005\u0016ìÇt\u001e¨ä\u001b","msg_sha256":null},
                //    "14239781692772499411":{"my_sha256":"¿_TÃ'^Wj¶\"f'SN~ç|ÃÚ¥wè\\A\u0014 \u0016g]","msg_sha256":null},
                //    "14239781692772777453":{"my_sha256":"ËJ&}Qig!'æ¬v<$ÿ¼±gøØ\u0006'\u0003Ì;É¹","msg_sha256":null},
                //    "14239781692773030964":{"my_sha256":"'HU\f«P¨nª NP7ÚöÛ\u000e\u0019\u0017}VmÜ¾\u0014\u0000Eû(","msg_sha256":null},
                //    "14239781692773321072":{"my_sha256":"DUu¢\u0001t6«nÇ!óØ\tçN@ÞS#3çßj1ã\u0006@","msg_sha256":null},
                //    "14239781692774532744":{"my_sha256":"<åN³è¤zXHK>d­¸\u0002L#zs·.\u0005","msg_sha256":null},
                //    "14239781692774974940":{"my_sha256":"¯\u001aÂZk·Xwc¢»\u0005i]ÞÁEjÚ\\?\bÐâm;ö","msg_sha256":null},
                //    "14239781692775813294":{"my_sha256":"\u0000_\u0019\u001dÈJR\f@Ì>ÈØ!êq¬z\u001bã-½ÙOI§.éþ","msg_sha256":null},
                //    "14239781692775882233":{"my_sha256":"íïö¸E7È×xã\u0019×\u0001}·÷l³ê{O1-Ô8+\u0016\"","msg_sha256":null},
                //    "14239781692776555896":{"my_sha256":"f\u001epB\u0001x8&\u0001\u0016\u001b°ö¨çM¤K\\_`\u0000\rúx\u001d","msg_sha256":null},
                //    "14239781692776993269":{"my_sha256":"çkÄa{[zn+%SeùS$EÌ­Þ\"öë\u000f½ú?Ä","msg_sha256":null},
                //    "14239781692777372502":{"my_sha256":"¯\u001aÂZk·Xwc¢»\u0005i]ÞÁEjÚ\\?\bÐâm;ö","msg_sha256":null},
                //    "14239781692777574345":{"my_sha256":"8HãÃ\u0017\u000fû:5V1Åô%ûK]\u0005\u000f\u0010óQ©\u00026bûV","msg_sha256":null},
                //    "14239781692778276592":{"my_sha256":"/ 4\u0006ýÆj-\u001e\u00032 &hÇ\u000f«>ÓEh»A\u001doÉ¹k½","msg_sha256":null},
                //    "14239781692778309061":{"my_sha256":"\u0002\u0016ß¨I\bp»­\r¯Z(Ý\u001e\u0001×óR)en\u0014?\u0016)","msg_sha256":null},
                //    "14239781692778518406":{"my_sha256":"\t\thÜ\u0001Ã¸2º³\u0010ÏÞî«8Ø¨¢2ge\u0007\u0003","msg_sha256":null},
                //    "14239781692778583942":{"my_sha256":"U\u0017\u0015\u000e\u0007~»|h\u001a<ðÖ<\u001ae\u000bÀJ¼\"ÁNbs×","msg_sha256":null},
                //    "14239781692779726598":{"my_sha256":"×?`EíQ\u000fkÞØN@-fÒ­\u0019³§qg©§zIG\u001b","msg_sha256":null},
                //    "14244918825228386518":{"my_sha256":"Éó6a[·ázÀ\u000e6Á$îÐìÎRuxßöá@|ýÃÕ3¼O","msg_sha256":null},
                //    "14244924316655606495":{"my_sha256":"qY)21\u0004òÊ\u0003¼E_G>*Ì\u001eðÂ\u001b}\u0019>ëÛÜRF","msg_sha256":null},
                //    "14244941900636888171":{"my_sha256":"¨Yr¤ï9ÉÀðn\u0000K JýôNèÅMêÛûCô","msg_sha256":null},
                //    "14239781115388288755":{"my_sha256":null,"msg_sha256":"¿q\u0018\u000f#©Jzfb\u00172¢\\9º43\u0001±½d­¼å\u0004[á"},
                //    "14239781115388735516":{"my_sha256":null,"msg_sha256":"¿q\u0018\u000f#©Jzfb\u00172¢\\9º43\u0001±½d­¼å\u0004[á"}
                //}

                // compare gift sha256 values. split gid's in 5 arrays
                var request_gids = [], send_gids = [], check_gids = [], ok_gids = [], error_gids = [];
                var sha256_values, compare;
                for (gid in gifts_sha256_hash) {
                    sha256_values = gifts_sha256_hash[gid];
                    compare = (sha256_values.my_sha256 ? '1' : '0') + (sha256_values.msg_sha256 ? '1' : '0');
                    switch (compare) {
                        case '00':
                            error_gids.push(gid);
                            break;
                        case '01':
                            // request gift from other device
                            request_gids.push(gid);
                            break;
                        case '10':
                            // send new gift to other device
                            send_gids.push(gid);
                            break;
                        case '11':
                            // check gift sha256 value
                            // send sub sha256 values to other device if difference in gift sha256 value
                            // the difference can be in gift and/or in comments
                            if (sha256_values.my_sha256 == sha256_values.msg_sha256) ok_gids.push(gid);
                            else check_gids.push(gid);
                            break;
                    } // end compare switch
                } // for gid

                // compare gifts resume
                if (request_gids.length > 0) console.log(pgm + 'request_gids = ' + request_gids.join(', '));
                if (send_gids.length > 0) console.log(pgm + 'send_gids = ' + send_gids.join(', '));
                if (check_gids.length > 0) console.log(pgm + 'check_gids = ' + check_gids.join(', '));
                if (ok_gids.length > 0) console.log(pgm + 'ok_gids = ' + ok_gids.join(', '));
                if (error_gids.length > 0) console.log(pgm + 'error_gids = ' + error_gids.join(', '));
                if (request_gids.length + send_gids.length + check_gids.length == 0) {
                    console.log(pgm + 'Gift replication finished. ' + ok_gids.length + ' identical gifts ' + error_gids.length + ' gifts with errors and were found');
                    if (error_gids.length > 0) console.log(pgm + 'Gifts with null sha256 values: ' + error_gids.join(', '));
                    // todo: send error or done response to other client
                    return;
                }

                // communication step 4:
                // - 1) send missing gifts to other device
                // - 2) request missing gifts from other device
                // - 3) send gifts sub sha256 values for changed gifts to other device
                // one message sync_gifts with 1-3 sub messages send_gifts, request_gifts and/or check_gifts
                var sync_gifts_message =
                {
                    mid: Gofreerev.get_new_uid(), // envelope mid
                    request_mid: msg.mid,
                    msgtype: 'sync_gifts',
                    mutual_friends: msg_users,
                    send_gifts: null, // optional send_gifts sub message 1)
                    request_gifts: null, // optional request_gifts sub message 2)
                    check_gifts: null // optional check_gifts sub message 3)
                };

                // - 1) send missing gifts to other device
                if (send_gids.length > 0) {
                    var send_gifts_sub_message = {
                        mid: Gofreerev.get_new_uid(),
                        msgtype: 'send_gifts',
                        gifts: [],
                        users: []
                    };
                    var gift_clone, users = [], send_gifts_users = [], user, send_invalid_gids = [];
                    for (i = 0; i < send_gids.length; i++) {
                        gid = send_gids[i];
                        if (!gid_to_gifts_index.hasOwnProperty(gid)) {
                            console.log(pgm + 'Could not send gift ' + gid + ' to other device. Index was not found.');
                            continue;
                        }
                        index = gid_to_gifts_index[gid];
                        if ((index < 0) || (index >= gifts.length)) {
                            console.log(pgm + 'Could not send gift ' + gid + ' to other device. Invalid gifts index (1).');
                            continue;
                        }
                        gift = gifts[index];
                        if (gift.gid != gid) {
                            console.log(pgm + 'Could not send gift ' + gid + ' to other device. Invalid gifts index (2).');
                            continue;
                        }
                        // validate gift before cloning for send_gifts sub message
                        error = invalid_gift(gift, [], 'send', mailbox);
                        if (error) {
                            console.log(pgm + 'Warning. Invalid gift was not added to send_gifts sub message.');
                            console.log(pgm + 'Gift ' + gift_clone.gid + ': ' + JSON.stringify(gift_clone));
                            console.log(pgm + 'Error message: ' + error);
                            send_invalid_gids.push(gid);
                            continue;
                        }

                        // clone gift - some interval properties are not replicated to other devices
                        // todo: 1 - change like from boolean to an array  with user ids and like/unlike timestamps for merge operation
                        // todo: 2 - add server side sha256_deleted signature to gift. Server could validate client_deleted_at and know that gift has been deleted
                        // todo: 3 - add url with optional file attachment (file upload has not been implemented yet)
                        // todo: 4 - clone user id arrays if sending gift to other gofreerev server (user id is replaced with sha256 signature)
                        gift_clone = make_gift_clone(gift);
                        // save relevant userids (giver, receiver and creator of comments) in gift_users buffer
                        add_user_ids_to_array(gift.giver_user_ids, send_gifts_users, false);
                        add_user_ids_to_array(gift.receiver_user_ids, send_gifts_users, false);
                        var comment;
                        if (gift.comments && (gift.comments.length > 0)) {
                            gift_clone.comments = [];
                            for (j = 0; j < gift.comments.length; j++) {
                                comment = gift.comments[j];

                                // todo: 1 - add server side sha256_deleted and/or sha256_action signature
                                //           a comment cannot be both accepted and deleted (delete gift to remove accepted deals)
                                //           it should be enough with one client side deleted_at_server=accepted_at_server field
                                // todo: 2 - clone user_ids array if sending message to other gofreerev server (user id is replaced with sha256 signature)
                                gift_clone.comments.push(make_comment_clone(comment));
                                // save relevant comment.user_ids in gift_users buffer
                                add_user_ids_to_array(comment.user_ids, send_gifts_users, false);
                                add_user_ids_to_array(comment.new_deal_action_by_user_ids, send_gifts_users, false);
                            } // for j (comments loop)
                        } // if comments
                        // validate gift_clone before adding gift to send_gifts sub message
                        error = invalid_gift(gift_clone, [], 'send', mailbox);
                        if (error) {
                            console.log(pgm + 'System error when adding gift to send_gifts sub message.');
                            console.log(pgm + 'Gift ' + gift_clone.gid + ': ' + JSON.stringify(gift_clone));
                            console.log(pgm + 'Error message: ' + error);
                            send_invalid_gids.push(gid);
                            continue; //
                        }
                        send_gifts_sub_message.gifts.push(gift_clone);
                    } // for i (send_gids loop)
                    if (send_invalid_gids.length > 0) console.log(pgm + 'Gifts with gid ' + send_invalid_gids.join(', ') + ' were not added to send_gifts message. See previous error messages i log.');

                    // add relevant users to send_gifts message - used as fallback information in case of "unknown user" error on receiving client
                    for (j = 0; j < send_gifts_users.length; j++) {
                        user_id = send_gifts_users[j];
                        if (mailbox.mutual_friends.indexOf(user_id) != -1) continue; // dont include mutual friends in send_gifts.users array
                        user = userService.get_friend(user_id);
                        // if (!user) console.log(pgm + 'Warning. Unknown friend user_id ' + user_id) ;
                        if (!user) user = userService.get_user(user_id); // fallback to "old" stored user info
                        if (!user) console.log(pgm + 'Error. Cannot add user info for unknown user_id ' + user_id);
                        send_gifts_sub_message.users.push({
                            user_id: user.user_id,
                            uid: user.uid,
                            provider: user.provider,
                            user_name: user.user_name,
                            api_profile_picture_url: user.api_profile_picture_url
                        });
                    } // for j (gift_users)
                    send_gifts_users.length = 0;

                    if (send_gifts_sub_message.gifts.length > 0) sync_gifts_message.send_gifts = send_gifts_sub_message;
                    else console.log(pgm + 'Error. No send_gifts sub message was added. See previous error messages in log.');
                } // if send_gids.length > 0

                // - 2) request missing gifts from other device
                if (request_gids.length > 0) {
                    var request_gifts_sub_message = {
                        mid: Gofreerev.get_new_uid(),
                        msgtype: 'request_gifts',
                        gifts: request_gids
                    };
                    sync_gifts_message.request_gifts = request_gifts_sub_message;
                } // request_gids.length > 0

                // - 3) send sub sha256 values for changed gifts to other device
                //      other device will check sub sha256 values and return gift, comments or both for gifts with different sha256 values
                if (check_gids.length > 0) {
                    var check_gifts_sub_message = {
                        mid: Gofreerev.get_new_uid(),
                        msgtype: 'check_gifts',
                        gifts: []
                    };
                    for (i = 0; i < check_gids.length; i++) {
                        gid = check_gids[i];
                        if (!gid_to_gifts_index.hasOwnProperty(gid)) {
                            console.log(pgm + 'Could not send gift ' + gid + ' sha256 values to other device. Index was not found.');
                            continue;
                        }
                        index = gid_to_gifts_index[gid];
                        if ((index < 0) || (index >= gifts.length)) {
                            console.log(pgm + 'Could not send gift ' + gid + ' sha256 values to other device. Invalid gifts index (1).');
                            continue;
                        }
                        gift = gifts[index];
                        if (gift.gid != gid) {
                            console.log(pgm + 'Could not send gift ' + gid + ' sha256 values to other device. Invalid gifts index (2).');
                            continue;
                        }
                        check_gifts_sub_message.gifts.push({
                            gid: gift.gid,
                            sha256: gift.sha256,
                            sha256_gift: gift.sha256_gift,
                            sha256_comments: gift.sha256_comments
                        });

                    } // for i (check_gids loop)
                    if (check_gifts_sub_message.gifts.length > 0) sync_gifts_message.check_gifts = check_gifts_sub_message;
                    else console.log(pgm + 'Error. No check_gifts sub message was added. See prevous error messages in log.');
                } // if check_gids.length > 0

                console.log(pgm + 'sync_gifts_message = ' + JSON.stringify(sync_gifts_message));
                // sync_gifts_messages =
                //   {"mid":"14245918981101515509",
                //    "request_mid":"14245918952724622555",
                //    "msgtype":"sync_gifts",
                //    "mutual_friends":["920"],
                //    "send_gifts":{"mid":"14245918981106696483",
                //                  "msgtype":"send_gifts",
                //                  "gifts":[{"gid":"14239781692770120364","giver_user_ids":[920,790],"receiver_user_ids":[],"created_at_client":1423731130,"created_at_server":1423978171,"currency":"USD","direction":"giver","description":"x","deleted_at":1423903100168,"sha256":"ä Ùh¿G×Ñâô9ÔÀ4ÀXèk\u0010N~,\nB]M"},
                //                           {"gid":"14239781692770348983","giver_user_ids":[920,790],"receiver_user_ids":[],"created_at_client":1423729517,"created_at_server":1423978171,"currency":"USD","direction":"giver","description":"x","deleted_at":1423903103507,"sha256":",F¯Ø\"Lo\u0004ö5é_Ï%p\\T¡(j{ï³o"},
                //                            ....
                //                           {"gid":"14244941900636888171","giver_user_ids":[920],"receiver_user_ids":[],"created_at_client":1415975141,"created_at_server":1424494193,"price":0,"currency":"SEK","direction":"giver","description":"Gofreerev share link","open_graph_url":"http://www.dr.dk/Nyheder/Kultur/Boeger/2014/11/09/151443.htm","open_graph_title":"Ingen kan slå denne mand: Alle vil foreviges med Jussi","open_graph_description":"Både den ægte vare og en papfigur af bestseller-forfatteren Jussi Adler-Olsen var populære blandt gæsterne på årets Bogforum.","open_graph_image":"http://www.dr.dk/NR/rdonlyres/20D580EF-8E8D-4E90-B537-B445ECC688CB/6035229/ccfa2f39e8be47fca7d011e1c1abd111_Jussiselfie.jpg","sha256":"¨Yr¤ï9ÉÀðn\u0000K JýôNèÅMêÛûCô"}]},
                //    "request_gifts":{"mid":"14245918981106107408",
                //                     "msgtype":"request_gifts",
                //                     "gifts":["14239781115388288755","14239781115388735516"]},
                //    "check_gifts":null}
                if ((sync_gifts_message.send_gifts == null) &&
                    (sync_gifts_message.request_gifts == null) &&
                    (sync_gifts_message.check_gifts == null)) {
                    console.log(pgm + 'Error. sync_gifts message was not sent. See previous errors in log.');
                    // todo: collect error and send error report to other client
                    return;
                }
                ;

                // translate user ids and server_ids before sending outgoing remote sync_gifts message to client on other Gofreerev server
                // ids are translated to sha256 signatures when communicating with clients on other Gofreerev servers (mailbox.server_id != null)
                // false: errors has already been written to log and send in a error message to other client
                if (!sync_gifts_translate_ids(msg, sync_gifts_message, mailbox)) return;

                // JS validate sync_gifts message before placing message in outbox
                if (Gofreerev.is_json_message_invalid(pgm, sync_gifts_message, 'sync_gifts', '')) {
                    // error message has already been written to log
                    // send error message to other device
                    var json_error = JSON.parse(JSON.stringify(tv4.error));
                    delete json_error.stack;
                    var json_errors = JSON.stringify(json_error);
                    var error = 'Could not process gifts_sha256 message. JSON schema validation error in sync_gifts response: ' + json_errors;
                    console.log(pgm + error + ' msg = ' + JSON.stringify(msg));
                    mailbox.outbox.push({
                        mid: Gofreerev.get_new_uid(),
                        request_mid: msg.mid,
                        msgtype: 'error',
                        request_mid: msg.mid,
                        error: error
                    });
                    return;
                }

                // check sync_gifts message for logical errors before placing message in outbox

                // 1) check sub message send_gifts for logical errors
                if (sync_gifts_message.send_gifts) {
                    // logical validate send_gifts sub messsage before sending sync_gifts message
                    error = validate_send_gifts_message(mailbox, sync_gifts_message.send_gifts, 'send');
                    if (error) {
                        var error = 'Could not process gifts_sha256 message. Logical error in sync_gifts response (send_gifts sub message) : ' + error;
                        console.log(pgm + error + ' msg = ' + JSON.stringify(msg));
                        mailbox.outbox.push({
                            mid: Gofreerev.get_new_uid(),
                            request_mid: msg.mid,
                            msgtype: 'error',
                            request_mid: msg.mid,
                            error: error
                        });
                        return;
                    }
                }

                // 2) check sub message request_gifts for logical errors
                if (sync_gifts_message.request_gifts) {
                    // logical validate request_gifts sub messsage before sending sync_gifts message
                    error = validate_request_gifts_message(mailbox, sync_gifts_message.request_gifts, 'send');
                    if (error) {
                        var error = 'Could not process gifts_sha256 message. Logical error in sync_gifts response (request_gifts sub message) : ' + error;
                        console.log(pgm + error + ' msg = ' + JSON.stringify(msg));
                        mailbox.outbox.push({
                            mid: Gofreerev.get_new_uid(),
                            request_mid: msg.mid,
                            msgtype: 'error',
                            request_mid: msg.mid,
                            error: error
                        });
                        return;
                    }
                }

                // todo: 3) check sub message check_gifts for logical errors

                // send sync_gifts message
                mailbox.outbox.push(sync_gifts_message);

            }
            catch
                (err) {
                error = 'Fatal javascript error when processing gifts_sha256 message. ' + err.message;
                console.log(pgm + error);
                console.log(pgm + 'stack trace = ' + err.stack);
                mailbox.outbox.push({
                    mid: Gofreerev.get_new_uid(),
                    msgtype: 'error',
                    request_mid: msg.mid,
                    error: error
                });
            }

        }; // receive_message_gifts_sha256


        // communication step 4 - receive message with 1-3 sub messages (send_gifts, request_gifts and check_gifts)
        // verify that request_mid is correct and add sub messages to messages array
        // the 1-6 sub messages will be processed in next steps in for j loop (see receive_messages)
        // params:
        // - device and mailbox - as usual
        // - messages - array with messages received from server
        // - index - index to current "sync_gift" message in messages array
        var receive_message_sync_gifts = function (device, mailbox, msg) {
            var pgm = service + '.receive_message_sync_gifts: ' ;
            var error ;

            // try catch block. send error message to other client in case of hard javascript errors
            try {

                // console.log(pgm + 'device   = ' + JSON.stringify(device)) ;
                console.log(pgm + 'mailbox  = ' + JSON.stringify(mailbox));
                console.log(pgm + 'msg      = ' + JSON.stringify(msg));

                // validate sync_gifts message before processing message
                if (Gofreerev.is_json_message_invalid(pgm, msg, 'sync_gifts', '')) {
                    // move previous gifts_sha256 message to error folder
                    if (!move_previous_message(pgm, mailbox, msg.request_mid, 'sync_gifts', false)) return; // ignore - not found in mailbox
                    // send error message to other device
                    var json_error = JSON.parse(JSON.stringify(tv4.error));
                    delete json_error.stack;
                    var json_errors = JSON.stringify(json_error);
                    error = 'Receiver rejected gifts_sha256 message. JSON schema validation errors: ' + json_errors;
                    console.log(pgm + error + ' msg = ' + JSON.stringify(msg));
                    mailbox.outbox.push({
                        mid: Gofreerev.get_new_uid(),
                        request_mid: msg.mid,
                        msgtype: 'error',
                        error: error
                    });
                    return;
                }

                // abort if response to request msg.mid is already in mailbox
                for (i = 0; i < mailbox.outbox.length; i++) {
                    if (mailbox.outbox[i].request_mid == msg.mid) {
                        console.log(pgm + 'Error. Response to gifts_sha256 message ' + msg.mid + ' is already in outbox.');
                        return;
                    }
                } // for i
                for (i = 0; i < mailbox.done.length; i++) {
                    if (mailbox.done[i].request_mid == msg.mid) {
                        console.log(pgm + 'Error. Response to gifts_sha256 message ' + msg.mid + ' is already in done.');
                        return;
                    }
                } // for i
                for (i = 0; i < mailbox.error.length; i++) {
                    if (mailbox.error[i].request_mid == msg.mid) {
                        console.log(pgm + 'Error. Response to gifts_sha256 message ' + msg.mid + ' is already in error.');
                        return;
                    }
                } // for i

                // move previous gifts_sha256 message to done folder
                if (!move_previous_message(pgm, mailbox, msg.request_mid, 'sync_gifts', true)) return; // ignore - not found in mailbox

                // check for sync_gifts message from client on other Gofreerev server (using sha256 signature as user_id)
                var unknown_sha256_user_ids = [], i, user_id, index, friend, msg_users_old;
                if (mailbox.hasOwnProperty('server_id')) {
                    console.log(pgm + 'sync_gifts message from client on an other Gofreerev server. Translate sha256 signatures in msg.users to internal user ids');
                    console.log(pgm + 'msg.mutual_friends (1) = ' + JSON.stringify(msg.mutual_friends));

                    // keep a copy of old sha256 user ids before translation (for debug and error messages)
                    var msg_users_sha256 = [];
                    var i;
                    for (i = 0; i < msg.mutual_friends.length; i++) msg_users_sha256.push(msg.mutual_friends[i]);

                    //// print debug information for user id 2, 3, 920, 1126. todo: remove
                    //var debug_users = [2, 3, 920, 1126], debug_user ;
                    //for (i=0 ; i<debug_users.length ; i++) {
                    //    debug_user = userService.get_friend(debug_users[i]) ;
                    //    if (debug_user) console.log(pgm + 'debug_users[' + debug_users[i] + '] = ' + JSON.stringify(debug_user)) ;
                    //    else console.log(pgm + 'debug_users[' + debug_users[i] + '] was not found');
                    //} // for i

                    // todo: user.sha256 signatures changes when server secret changes
                    // todo: a message received after secret change can be with old sha256 signature.
                    // todo: keep old sha256 signature as a fallback for one or two minutes for old messages
                    // todo: see more todos in userService.get_friend_by_sha256
                    for (i = msg.mutual_friends.length - 1; i >= 0; i--) {
                        user_id = msg.mutual_friends[i];
                        friend = userService.get_friend_by_sha256(user_id);
                        if (friend) {
                            console.log(pgm + 'translating sha256 user_id ' + user_id + ' to internal user_id ' + friend.user_id);
                            msg.mutual_friends[i] = friend.user_id;
                        }
                        else {
                            console.log(pgm + 'unknown sha256 user_id ' + user_id);
                            unknown_sha256_user_ids.push(user_id);
                            msg.mutual_friends.splice(i, 1);
                        }
                    }
                    console.log(pgm + 'msg.mutual_friends (2) = ' + JSON.stringify(msg.mutual_friends));
                    if (unknown_sha256_user_ids.length > 0) console.log(pgm + 'unknown_sha256_user_ids = ' + JSON.stringify(unknown_sha256_user_ids));
                } // if

                // compare mailbox.mutual_friends and msg.users. list of mutual friends in msg must be a sublist of mutual friends in mailbox (from server)
                var my_mutual_friends = mailbox.mutual_friends;
                var msg_mutual_friends = msg.mutual_friends;
                var invalid_user_ids = $(msg_mutual_friends).not(my_mutual_friends).get();

                // todo: msg_users must also be a subset of users from previous gifts_sha256 message now in done folder

                if (invalid_user_ids.length + unknown_sha256_user_ids.length > 0) {
                    // unknown or invalid user in users_sha256 message:
                    error = (invalid_user_ids.length + unknown_sha256_user_ids.length) + ' rejected users(s) in gifts_sync message';
                    if (msg_users_sha256) error += '. Received sha256 user signatures: ' + msg_users_sha256.join(', ');
                    if (unknown_sha256_user_ids.length > 0) error += '. Unknown sha256 user signatures: ' + unknown_sha256_user_ids.join(', ');
                    error += '. Received internal user ids: ' + msg_mutual_friends.join(', ');
                    if (invalid_user_ids.length > 0) {
                        error += '. Expected user ids: ' + my_mutual_friends.join(', ');
                        error += '. Unknown mutual friends: ' + invalid_user_ids.join(', ');
                    }
                    console.log(pgm + error);
                    if (msg_mutual_friends.length == 0) {
                        mailbox.outbox.push({
                            mid: Gofreerev.get_new_uid(),
                            request_mid: msg.mid,
                            msgtype: 'error',
                            error: error
                        });
                        return;
                    }
                    // continue without invalid user ids
                    msg_mutual_friends = $(msg_mutual_friends).not(invalid_user_ids).get();
                }

                // add sub messages (send_gifts, request_gifts. check_gifts, request_comments, invalid_gifts and invalid_comments) to inbox
                // keep reference (request_mid) to previous gifts_sha256 message - now in mailbox.done array
                if (msg.send_gifts) {
                    msg.send_gifts.request_mid = msg.request_mid;
                    msg.send_gifts.pass = 0; // 0: new send_gifts message, 1: waiting for gifts verification, 2: verified - waiting to be processed, 3: done:
                    msg.send_gifts.mutual_friends = Gofreerev.clone_array(msg_mutual_friends); // mutual friends array - used in sync_gifts response
                    mailbox.inbox.push(msg.send_gifts);
                }
                ;
                if (msg.request_gifts) {
                    msg.request_gifts.request_mid = msg.request_mid;
                    msg.request_gifts.mutual_friends = Gofreerev.clone_array(msg_mutual_friends); // mutual friends array - used in sync_gifts response
                    mailbox.inbox.push(msg.request_gifts);
                }
                ;
                if (msg.check_gifts) {
                    msg.check_gifts.request_mid = msg.request_mid;
                    msg.check_gifts.mutual_friends = Gofreerev.clone_array(msg_mutual_friends); // used if check_gifts message must be returned with sha256 values for comments
                    mailbox.inbox.push(msg.check_gifts);
                }
                ;
                if (msg.request_comments) {
                    msg.request_comments.request_mid = msg.request_mid;
                    msg.request_comments.mutual_friends = Gofreerev.clone_array(msg_mutual_friends); // mutual friends array - used in sync_gifts response
                    mailbox.inbox.push(msg.request_comments);
                }
                ;
                if (msg.invalid_gifts) {
                    msg.invalid_gifts.request_mid = msg.request_mid;
                    msg.invalid_gifts.pass = 0; // 0: new invalid_gifts message, 1: waiting for gifts verification, 2: verified - write error to log and create notication
                    mailbox.inbox.push(msg.invalid_gifts);
                }
                ;
                if (msg.invalid_comments) {
                    msg.invalid_comments.request_mid = msg.request_mid;
                    msg.invalid_gifts.pass = 0; // 0: new invalid_comments message, 1: waiting for comments verification, 2: verified - write error to log and create notication
                    mailbox.inbox.push(msg.invalid_comments);
                }
                ;

            }
            catch
                (err) {
                error = 'Fatal javascript error when processing sync_gifts message. ' + err.message;
                console.log(pgm + error);
                console.log(pgm + 'stack trace = ' + err.stack);
                mailbox.outbox.push({
                    mid: Gofreerev.get_new_uid(),
                    msgtype: 'error',
                    request_mid: msg.mid,
                    error: error
                });
            }

        } ; // receive_message_sync_gifts


        // compare two values. undefined == null == blank string
        var identical_values = function (a, b) {
            var a_is_empty = ((typeof a == 'undefined') || (a == null) || (a == '')) ;
            var b_is_empty = ((typeof b == 'undefined') || (b == null) || (b == '')) ;
            if (a_is_empty && b_is_empty) return true ;
            if (a_is_empty) return false ;
            if (b_is_empty) return false ;
            return (a == b);
        } ; // identical_values


        // compare two array with identical_values function
        var identical_array_values = function (a, b) {
            var a_is_empty = ((typeof a == 'undefined') || (a == null) || ((!$.isArray(a) && (a.length == 0)))) ;
            var b_is_empty = ((typeof b == 'undefined') || (b == null) || ((!$.isArray(b) && (b.length == 0)))) ;
            if (a_is_empty && b_is_empty) return true ;
            if (a_is_empty) return false ;
            if (b_is_empty) return false ;
            if (a.length != b.length) return false ;
            a.sort() ;
            b.sort() ;
            for (var i=0 ; i< a.length ; i++) {
                if (!identical_values(a[i], b[i])) return false ;
            };
            return true ;
        } ; // identical_values


        // communication step 4 - sub message from receive_message_sync_gifts
        // password => users_sha256 => gifts_sha256 => sync_gifts
        // has already been json validated in receive_message_sync_gifts
        // receive missing gifts from other device
        // receive_message_send_gifts is called more than once when receiving gifts from other device
        // pass 0: do some initial gift verification without checking
        // between pass 0 and pass 1 - check unknown server sha256 signatures in ping new_servers request/response
        // pass 1: insert new gifts in verify_gifts array for server sha256 signature check in next ping
        // between first and second pass - ping - verify sha256 signature for new gifts and and in some cases for old gifts
        // property verify_seq is set in verify_gifts_request and verified_at_server (true/false) is set in verify_gifts_response
        // note that response for remote gifts / remote verification can take some time
        // second pass - finish gift verification including server sha256 signature check - can request additional gift and comment verifications
        // third pass - do actions (insert, update, merge) gifts and comments
        // end - optional send sync_gifts message response to other client (gifts and errors)
        var receive_message_send_gifts = function (device, mailbox, msg) {
            var pgm = service + '.receive_message_send_gifts: ';
            var error ;

            // try catch block. send error message to other client in case of hard javascript errors
            try {

                console.log(pgm + 'mailbox  = ' + JSON.stringify(mailbox));
                console.log(pgm + 'msg      = ' + JSON.stringify(msg));
                console.log(pgm + 'msg.pass = ' + msg.pass); // 0: new send_gifts message, 1: waiting for gifts verification, 2: verified - reasy for pass 2, 3: done

                // collect gift error messages (invalid gifts and failed verify gifts requests)
                var gid, gift_errors = {}, no_gift_errors = 0, gift_error;

                if (msg.pass == 0) {

                    // pass 0 - check for some fatal errors before processing send_gifts message
                    // 1) gid and cid must be unique
                    // 2) users in msg.users array must be unique and be correct (all user ids in msg.users array except mutual friends)
                    // 3) sha256 signatures for servers must be in msg.servers array
                    error = validate_send_gifts_message(mailbox, msg, 'receive');
                    if (error) {
                        console.log(pgm + error + ' msg = ' + JSON.stringify(msg));
                        mailbox.outbox.push({
                            mid: Gofreerev.get_new_uid(),
                            msgtype: 'error',
                            request_mid: msg.mid,
                            error: error
                        });
                        return;
                    } // if error (validate_send_gifts_message)

                    // validate received gifts
                    var errors, new_gift, i, j, new_comment, comment_error;
                    for (i = 0; i < msg.gifts.length; i++) {
                        new_gift = msg.gifts[i];
                        gid = new_gift.gid;

                        if (mailbox.hasOwnProperty('server_id')) {
                            // gifts from an other Gofreerev server.
                            // user ids have been validated in validate_send_gifts_message and are either
                            // 1) sha256 signatures for remote users or
                            // 2) negative user ids for "unknown" users
                            // translate all received sha256 signatures to internal user ids
                            // console.log(pgm + 'msg = ' + JSON.stringify(msg)) ;
                            error = userService.sha256_to_user_ids(new_gift.giver_user_ids, msg);
                            if (error) {
                                // todo: use key+options error format
                                gift_errors[gid] = 'giver_user_ids: ' + error;
                                no_gift_errors += 1;
                                continue; // next gift
                            }
                            error = userService.sha256_to_user_ids(new_gift.receiver_user_ids, msg);
                            if (error) {
                                // todo: use key+options error format
                                gift_errors[gid] = 'receiver_user_ids: ' + error;
                                no_gift_errors += 1;
                                continue; // next gift
                            }
                            comment_error = false;
                            if (new_gift.comments) {
                                for (j = 0; j < new_gift.comments.length; j++) {
                                    new_comment = new_gift.comments[j];
                                    error = userService.sha256_to_user_ids(new_comment.user_ids, msg);
                                    if (error) {
                                        errors.push('gid=' + gid + ', cid=' + new_comment.cid + ', user_ids: error=' + error);
                                        comment_error = true;
                                        // todo: use key+options error format
                                        gift_errors[gid] = 'comment ' + new_comment.cid + ' user_ids: ' + error;
                                        no_gift_errors += 1;
                                        break;
                                    }
                                    error = userService.sha256_to_user_ids(new_comment.new_deal_action_by_user_ids, msg);
                                    if (error) {
                                        errors.push('gid=' + gid + ', cid=' + new_comment.cid + ', new_deal_action_by_user_ids: error=' + error);
                                        comment_error = true;
                                        // todo: use key+options error format
                                        gift_errors[gid] = 'comment ' + new_comment.cid + ' new_deal_action_by_user_ids: ' + error;
                                        no_gift_errors += 1;
                                        break;
                                    }
                                } // for j
                            } // if
                            if (comment_error) continue; // next gift
                            // sha256 signatures were translated without errors
                        } // if server_id

                        // note msg.users as second argument 2 to invalid_gift call
                        // allows gift validation to use msg.users as fallback information in case of unknown users in givers, receivers or comments
                        error = invalid_gift(new_gift, msg.users, 'receive', mailbox);
                        if (error) {
                            // todo 1: use key+options format for error message
                            // todo 2: invalid_gift function should return error message in format key+options
                            gift_errors[gid] = error;
                            no_gift_errors += 1;
                        }
                    } // for i (gifts)
                    // todo 1: collect gift errors and continue with valid gifts only. report invalid gifts in :invalid_gifts sub message. must use clone for gifts array. this message is processed multiple times
                    // todo 2: collect comment errors and continue with valid comments only. report invalid comments in :invalid_comments sub message. Must use clone for gifts array. this message is processed multiple times
                    if (no_gift_errors == msg.gifts.length) {
                        // abort send_gift processing. errors for all gifts in send_gifts message
                        errors = [];
                        for (gid in gift_errors) {
                            gift_error = gift_errors[gid];
                            if (typeof gift_error == 'object') error = I18n.t('js.gift_actions.' + gift_error.key, gift_error.options);
                            else error = gift_error;
                            errors.push('gid ' + gid + ', error:' + error);
                        }
                        error = errors.length + ' errors. No valid gifts was found in sync_gifts/send_gifts sub message. Errors: ' + errors.join('. ');
                        console.log(pgm + error + ' msg = ' + JSON.stringify(msg));
                        mailbox.outbox.push({
                            mid: Gofreerev.get_new_uid(),
                            msgtype: 'error',
                            request_mid: msg.mid,
                            error: error
                        });
                        return;
                    } // if

                    // calc sha256 values for gifts received from other client
                    for (i = 0; i < msg.gifts.length; i++) {
                        new_gift = msg.gifts[i];
                        gid = new_gift.gid;
                        if (gift_errors.hasOwnProperty(gid)) continue; // skip invalid gifts
                        sha256_values = gift_sha256_for_client(new_gift);
                        new_gift.sha256 = sha256_values[0];
                        new_gift.sha256_gift = sha256_values[1];
                        new_gift.sha256_comments = sha256_values[2];
                        if (gid == '14380945221613232297') console.log(pgm + 'gid = ' + gid + ', new_gift.sha256_comments = ' + new_gift.sha256_comments); // todo: remove - debugging
                        if (!new_gift.sha256) {
                            // todo: use key+options error format
                            gift_errors[gid] = 'Client side sha256 calculation failed';
                            no_gift_errors += 1;
                            continue;
                        }
                        if (!new_gift.hasOwnProperty('comments')) continue;
                        for (j = 0; j < new_gift.comments.length; j++) {
                            new_comment = new_gift.comments[j];
                            new_comment.sha256 = comment_sha256_for_client(new_comment, false);
                        }
                    }
                    if (no_gift_errors == msg.gifts.length) {
                        // abort send_gift processing. errors for all gifts in send_gifts message
                        errors = [];
                        for (gid in gift_errors) {
                            gift_error = gift_errors[gid];
                            if (typeof gift_error == 'object') error = I18n.t('js.gift_actions.' + gift_error.key, gift_error.options);
                            else error = gift_error;
                            errors.push('gid ' + gid + ', error:' + error);
                        }
                        error = errors.length + ' errors. No valid gifts was found in sync_gifts/send_gifts sub message. Errors: ' + errors.join('. ');
                        console.log(pgm + error + ' msg = ' + JSON.stringify(msg));
                        mailbox.outbox.push({
                            mid: Gofreerev.get_new_uid(),
                            msgtype: 'error',
                            request_mid: msg.mid,
                            error: error
                        });
                        return;
                    } // if sha256 calc errors
                    if (no_gift_errors > 0) {
                        // warning in log. continue with valid gifts
                        errors = [];
                        for (gid in gift_errors) errors.push('gid ' + gid + ', error:' + gift_errors[gid]);
                        console.log(pgm + no_gift_errors + ' gifts with errors in incoming send_gifts message. errors=' + errors.join('. ') + '. Continuing with ' + (msg.gifts.length - no_gifts_errors) + ' valid gifts.');
                    }

                    if (mailbox.hasOwnProperty('server_id')) {
                        // gifts from an other Gofreerev server.
                        // check for any unknown server sha256 signatures
                        // unknown server sha256 signatures must be validated between pass 0 and pass 1
                        var no_unknown_servers = 0, sha256;
                        for (i = 0; i < msg.servers.length; i++) {
                            sha256 = msg.servers[i].sha256;
                            if (sha256_to_server_id(sha256) != null) continue; // known server
                            no_unknown_servers += 1;
                            if (!unknown_servers.hasOwnProperty(sha256)) unknown_servers[sha256] = null;
                            console.log(pgm + 'unknown_servers["' + sha256 + '"] = ' + unknown_servers[sha256]);
                        } // for i
                        if (no_unknown_servers > 0) {
                            // unknown server. Push back to read folder at check after next ping
                            console.log(pgm + no_unknown_servers + ' unknown servers. wait for new_servers request/response in ping');
                            mailbox.read.push(msg);
                            console.log(pgm + 'mailbox.read.length = ' + mailbox.read.length);
                            return;
                        }
                        // no (more) unknown servers. translate server sha256 signatures
                        var other_server_id_to_sha256 = {}; // from internal server id on other gofreerev server to sha256 signature
                        var server;
                        for (i = 0; i < msg.servers.length; i++) {
                            server = msg.servers[i];
                            other_server_id_to_sha256[server.server_id] = server.sha256;
                        }
                        console.log(pgm + 'other_server_id_to_sha256 = ' + JSON.stringify(other_server_id_to_sha256));
                        for (i = 0; i < msg.gifts.length; i++) {
                            new_gift = msg.gifts[i];
                            if (gift_errors.hasOwnProperty(new_gift.gid)) continue; // skip error marked gifts
                            sha256 = other_server_id_to_sha256[new_gift.created_at_server];
                            new_gift.created_at_server = sha256_to_server_id(sha256);
                            if (!new_gift.comments) continue;
                            for (j = 0; j < new_gift.comments.length; j++) {
                                new_comment = new_gift.comments[j];
                                sha256 = other_server_id_to_sha256[new_comment.created_at_server];
                                new_comment.created_at_server = sha256_to_server_id(sha256);
                            } // for j
                        } // for i

                    } // if server_id

                    // ready for pass 1, 2 and 3
                    msg.pass = 1;
                } // if pass 0

                // one gifts loop with pass 1, 2 and 3 for each gift
                // pass 1: validation without server side sha256 check - find new gifts and new comments that must be server side validated
                // between pass 1 and 2: server side sha256 check - see ping verify_gifts_request and verify_gifts_response
                // pass 2: validation with server side sha256 check
                // pass 3: do actions (create gifts, update gifts, merge comments etc)
                // send_gifts message will be pushed back to mailbox.read folder until all relevant gifts and comments have been server validated
                // local gifts created on this server will be validated in next ping
                // validation for gifts created on other gofreerev servers can take some time (remove gift validation)

                var gifts_already_on_ignore_list = []; // array with gids - ignore invalid gifts from other client
                var client_gift_actions = 0; // number of client gift actions in progress (accept or delete)
                var client_comment_actions = 0; // number of client comment actions in progress (accept or delete)
                var identical_gift_and_comments = []; // array with gids
                var verify_new_gifts = 0; // number of new gifts that must be server validated
                var verifying_new_gifts = 0; // number of new gifts already in queue for server validation (offline client, remote gifts or errors)
                var new_gifts_invalid_sha = []; // array with gids. verify gift request failed for incoming new gift
                var verify_old_gifts = 0; // number of old gifts that must be server validated (gift changed and new gift is valid)
                var verifying_old_gifts = 0; // number of old gifts already in queue for server validation (offline client, remote gifts or errors)
                var old_gifts_invalid_sha = []; // array with gids
                var verify_new_comments = 0; // number of new comments that must be server validated
                var verifying_new_comments = 0; // number of new comments already in queue for server validation (offline client, remote gifts or errors)
                var new_comments_invalid_sha = []; // array with cids
                var verify_old_comments = 0; // number of old comments that must be server validated (comment changed and new comment is valid)
                var verifying_old_comments = 0; // number of old comments already in queue for server validation (offline client, remote comments or errors)
                var gift_index_system_errors = []; // gid array with gift index system errors - fatal javascript error
                var gid_validation_system_errors = []; // gid array with sha validation system errors - fatal javascript error
                var cid_validation_system_errors = []; // cid array with sha validation system errors - fatal javascript error
                var comment_index_system_errors = []; // cid array with comment index sytsem errors - fatal javascript errors
                var counterpart_errors = []; // gid array with gifts with invalid counter part update (other user) - only allowed when accepting a new deal proposal
                var gifts_without_mutual_friends; // array with gids - new gifts without mutual friends - ignore and report as warning in log
                var gifts_created = []; // array with gids - new created gifts
                var create_gift_errors = []; // array with gids - invalid new gift could not be created. See more info in log
                var create_comment_errors = []; // array with cids - invalid new comment could not be created. See more info in log
                var deleted_invalid_old_comments = []; // array with cids - old invalid comments that has been deleted
                var send_gifts = []; // array with gids - gift action in this client - no action in incoming message - send send_gifts message to other client with gifts
                var send_comments = []; // array with cids - comment action in this client - no comment action in incoming message - send send_gifts message to other client with (gifts and) comments
                var invalid_comment_changes = []; // array with error messages - comment change was invalid

                var index, old_gift, sha256_values, is_mutual_gift, user_id, cid, old_cids;
                var new_gift_creators, old_gift_creators, new_gift_counterpart, old_gift_counterpart;
                var old_gift_accepted, new_gift_accepted, gift_accept_action, gift_delete_action, gift_price_action, gift_like_action;
                var comments_pass, seconds;
                var gift, comment, old_comment, k, old_comment_index;


                // gifts loop. new_gift from send_gifts message. old_gift from gifts array
                for (i = 0; i < msg.gifts.length; i++) {
                    new_gift = msg.gifts[i];
                    gid = new_gift.gid;
                    if (gift_errors.hasOwnProperty(gid)) continue; // skip error marked gifts
                    if (is_gift_on_ignore_list(device, gid)) {
                        gifts_already_on_ignore_list.push(gid);
                        // todo: use key+options error format
                        gift_errors[gid] = 'Gift already on ignore list';
                        no_gift_errors += 1;
                        continue;
                    }
                    if (gid_to_gifts_index.hasOwnProperty(gid)) {
                        // existing gift
                        index = gid_to_gifts_index[gid];
                        if ((index < 0) || (index >= gifts.length)) {
                            // system error - error in javascript logic
                            gift_index_system_errors.push(gid);
                            continue;
                        }
                        ;
                        old_gift = gifts[index];
                        if (!old_gift || (old_gift.gid != gid)) {
                            // system error - error in javascript
                            gift_index_system_errors.push(gid);
                            continue;
                        }
                        ;
                        if (['accept', 'delete'].indexOf(old_gift.verify_gift_action) != -1) {
                            // wait for current client gift action to complete (accept or delete) before continue with compare/merge gift operation
                            client_gift_actions += 1;
                            continue;
                        }
                        // compare old (this client) and new gift (from other client)
                        if (old_gift.sha256 == new_gift.sha256) {
                            identical_gift_and_comments.push(gid);
                            continue;
                        }
                        if (old_gift.sha256_gift != new_gift.sha256_gift) {
                            // old gift != new gift when ignoring comments
                            // many gift fields are readonly but update is allowed for a few fields (like, unlike, accept and delete)

                            // verify gift received from other client
                            if (!new_gift.hasOwnProperty('verify_seq')) {
                                // new gift must be server validated before continuing (between pass 1 and pass 2)
                                verify_new_gifts += 1;
                                verify_gifts_add(new_gift, 'verify');
                                continue;
                            }
                            ;
                            if (!new_gift.hasOwnProperty('verified_at_server')) {
                                // new gift already in queue for server verification (offline, server not responding or remote gift)
                                verifying_new_gifts += 1;
                                continue;
                            }
                            ;
                            if (!new_gift.verified_at_server) {
                                // invalid signature for new gift - changed on other client or not correct in message
                                // old gift exist on this client:
                                // - todo 1: check if old gift has a valid signature and send valid gift to other client
                                // - todo 2: send a special invalid signature error message to other client.
                                new_gifts_invalid_sha.push(gid);
                                gift_errors[gid] = new_gift.verified_error;
                                no_gift_errors += 1;
                                continue;
                            }
                            ;

                            // pass 2 - new gift has been server verified. check and accept changes in this order:
                            // 1) receive likes and unlikes from other client
                            // 2) receive accept gift action from other client
                            // 3) receive delete gift action from other client
                            // 4) receive other gift changes from other client (errors)
                            // 5) push any changes gifts from this client to other client (likes, unlikes, accept gift and delete gift). see sync_gifts response to other client at end of this message

                            // todo: remove - debugging
                            console.log(pgm + 'old_gift = ' + JSON.stringify(old_gift));
                            console.log(pgm + 'new_gift = ' + JSON.stringify(new_gift));

                            // changed gift - check if readonly fields used in server side sha256 signature have been changed
                            if (new_gift.direction == 'giver') {
                                new_gift_creators = new_gift.giver_user_ids.sort().join(',');
                                new_gift_counterpart = (new_gift.receiver_user_ids || []).sort().join(',');
                            }
                            else {
                                new_gift_creators = new_gift.receiver_user_ids.sort().join(',');
                                new_gift_counterpart = (new_gift.giver_user_ids || []).sort().join(',');
                            }
                            if (old_gift.direction == 'giver') {
                                old_gift_creators = old_gift.giver_user_ids.sort().join(',');
                                old_gift_counterpart = (old_gift.receiver_user_ids || []).sort().join(',');
                            }
                            else {
                                old_gift_creators = old_gift.receiver_user_ids.sort().join(',');
                                old_gift_counterpart = (old_gift.giver_user_ids || []).sort().join(',');
                            }
                            if (!identical_values(old_gift.created_at_client, new_gift.created_at_client) || !identical_values(old_gift.direction, new_gift.direction) || !identical_values(old_gift_creators, new_gift_creators) ||
                                ((old_gift_counterpart != '') && (new_gift_counterpart != '') && (old_gift_counterpart != new_gift_counterpart)) || !identical_values(old_gift.description, new_gift.description) || !identical_values(old_gift.open_graph_url, new_gift.open_graph_url) || !identical_values(old_gift.open_graph_title, new_gift.open_graph_title) || !identical_values(old_gift.open_graph_description, new_gift.open_graph_description) || !identical_values(old_gift.open_graph_image, new_gift.open_graph_image) || !identical_values(old_gift.created_at_server, new_gift.created_at_server) ||
                                (old_gift.hasOwnProperty('accepted_cid') && new_gift.hasOwnProperty('accepted_cid') && !identical_values(old_gift.accepted_cid, new_gift.accepted_cid)) ||
                                (old_gift.hasOwnProperty('accepted_at_client') && new_gift.hasOwnProperty('accepted_at_client') && !identical_values(old_gift.accepted_at_client, new_gift.accepted_at_client)) ||
                                (old_gift.hasOwnProperty('deleted_at_client') && new_gift.hasOwnProperty('deleted_at_client') && !identical_values(old_gift.deleted_at_client, new_gift.deleted_at_client))) {
                                // changed readonly fields!
                                // fields used in server side sha256 signature are NOT identical for new and old gift
                                // could be a communication error or gift could have been modified by this or on other client
                                // new gift is valid. old gift must be invalid  - changed on this client or not saved correct
                                if (!old_gift.hasOwnProperty('verify_seq')) {
                                    // old gift must be server validated before continuing (between pass 1 and pass 2)
                                    verify_old_gifts += 1;
                                    delete old_gift.verified_at_server;
                                    verify_gifts_add(old_gift, 'verify');
                                    continue;
                                }
                                if (!old_gift.hasOwnProperty('verified_at_server')) {
                                    // old gift already in queue for server verification (offline, server not responding or remote gift)
                                    verifying_old_gifts += 1;
                                    continue;
                                }
                                if (!old_gift.verified_at_server) {
                                    // invalid signature for old gift - todo: old gift must be deleted and new gift accepted
                                    old_gifts_invalid_sha.push(gid);
                                    continue;
                                }
                                // system error - valid server side sha256 signature for old and new gift - and changed readonly fields
                                gid_validation_system_errors.push(gid);
                                continue;
                            } // if changed readonly fields!

                            // pass 2 - gift from other client has been server validated - readonly fields have not been changed
                            // check changes in gift - only few changes are allowed
                            // accept and delete actions changes server side sha256 signature (already validated) and are one direction actions
                            // todo: testcase - accept gift on one client and delete gift on an other client
                            // todo: 1) sub testcase: server delete gift before server accept gift
                            // todo: 2) sub testcase: server accept gift before server delete gift

                            old_gift_accepted = (old_gift.accepted_cid || old_gift.accepted_at_client);
                            new_gift_accepted = (new_gift.accepted_cid || new_gift.accepted_at_client);
                            gift_accept_action = ((old_gift_accepted && !new_gift_accepted) || (!old_gift_accepted && new_gift_accepted));
                            gift_delete_action = ((old_gift.deleted_at_client && !new_gift.deleted_at_client) || (!old_gift.deleted_at_client && new_gift.deleted_at_client));
                            gift_price_action = !gift_accept_action && ((old_gift.price != new_gift.price) || (old_gift.currency != new_gift.currency));
                            gift_like_action = (old_gift.like != new_gift.like); // todo: likes must be an array with like and unlike
                            if (!gift_accept_action && (old_gift_counterpart != new_gift_counterpart)) {
                                // counterpart can only be changed when accepting proposal
                                counterpart_errors.push(gid);
                                // todo: use key+options error format
                                gift_errors[gid] = 'Invalid counterpart update. Counterpart can only be updated for accept new deal proposal';
                                no_gift_errors += 1;
                                continue;
                            }

                            if (msg.pass == 3) {
                                // todo: add updated_at_client timestamp to gift. last update wins in a few situations
                                // updateable fields:
                                // 1) other user ids when proposal has been accepted - opposite of creator
                                //    there must a new proposal in comments with accepted = true
                                //    user ids in accepted proposal be identical with other user ids in gift
                                // 2) price - can be updated until accepted proposal and must after accept be identical with price accepted proposal
                                // 3) currency - can be updated until accepted proposal and must after accept be identical with price accepted proposal
                                // 4) like - todo: now a boolean. must be changed to a likes array with user ids and like/unlike timestamps. merge likes
                                // 5) deleted_at_client
                                // 6) accepted_cid
                                // 7) accepted_at_client

                                // allowed actions:
                                // a) price and currency change and not an accept gift action
                                // b) merge likes
                                // c) accept gift
                                // d) delete gift
                                // e) control. old and new gift should be identical
                                // analyse gift changes
                                // do actions
                                if (gift_price_action) {
                                    // todo: use price and currency from last changed gift. add updated_at_client to gift
                                    console.log(pgm + 'Error: Implement gift price action: old price = ' + old_gift.price + old_gift.currency + ', new price = ' + new_gift.price + new_gift.currency);
                                }
                                if (gift_like_action) {
                                    // todo: change like to array with userid and timestamps for like and unlike
                                    console.log(pgm + 'Error: Implement gift like action: old like = ' + JSON.stringify(old_gift.like) + ', new like = ' + JSON.stringify(new_gift.like));
                                }
                                if (gift_accept_action) {
                                    if (old_gift_accepted) {
                                        // todo: send gift to other client
                                    }
                                    else {
                                        // update gift with
                                    }
                                }


                            } // if pass 3

                        } // if old_gift.sha256_gift != new_gift.sha256_gift

                        // old and new gift are identical. check comments

                        if (old_gift.sha256_comments == new_gift.sha256_comments) {
                            // comments identical - minor changes in gift - merge gift in pass 3
                            merge_gifts.push(gid);
                            continue;
                        }

                        // comments are not identical.


                        old_cids = [];
                        if (old_gift.comments) for (j = 0; j < old_gift.comments.length; j++) old_cids.push(old_gift.comments[j].cid);
                        comments_pass = 2;
                        if (new_gift.comments) {
                            for (j = 0; j < new_gift.comments.length; j++) {
                                new_comment = new_gift.comments[j];
                                cid = new_comment.cid;

                                if (old_cids.indexOf(cid) != -1) {
                                    // lookup old comment
                                    old_comment = null;
                                    for (k = 0; k < old_gift.comments.length; k++) {
                                        if (old_gift.comments[k].cid == new_comment.cid) old_comment = old_gift.comments[k];
                                    }
                                    ;
                                    if (old_comment == null) {
                                        console.log(pgm + 'System error for cid ' + new_comment.cid + '. Found in old_cids array but not found in old gift comments array');
                                        comment_index_system_errors.push(new_comment.cid);
                                        continue;
                                    }
                                    ;
                                    if (['cancel', 'accept', 'reject', 'delete'].indexOf(old_comment.verify_comment_action) != -1) {
                                        // wait for client comment action to complete before continuing with compare/merge comment operation
                                        client_comment_actions += 1;
                                        comments_pass = 1;
                                    }
                                }
                                else {
                                    // new comment
                                    old_comment = null;
                                }
                                ;

                                // calculate sha256 value for comment. used when comparing gift and comments between clients. replicate gifts with changed sha256 value between clients
                                // readonly fields used in server side sha256 signature - update is NOT allowed - not included in comment_sha256_for_client
                                // - created_at_client    - readonly - used in client part of server side sha256 signature - not included in comment_sha256_for_client
                                // - comment              - readonly - used in client part of server side sha256 signature - not included in comment_sha256_for_client
                                // - price                - readonly - used in client part of server side sha256 signature - not included in comment_sha256_for_client
                                // - currency             - readonly - used in client part of server side sha256 signature - not included in comment_sha256_for_client
                                // - new_deal             - readonly - used in client part of server side sha256 signature - not included in comment_sha256_for_client
                                // - user_ids             - readonly - used in server side sha256 signature - not included in comment_sha256_for_client
                                // - created_at_server    - server number - returned from new comments request and not included in comment_sha256_for_client
                                // - new_deal_action      - blank, cancelled, accepted or rejected - only used for new deal proposals (new_deal=true), include in comment_sha256_for_client
                                // - new_deal_action_by_user_ids - relevant login user ids for new_deal_action (cancel, accept, reject) - subset of comment or gift creators - include in comment_sha256_for_client
                                // - new_deal_action_at_client - new deal action client unix timestamp - cancel, accept or reject - include in comment_sha256_for_client
                                // - deleted_at_client    - deleted at client unix timestamp - include in comment_sha256_for_client

                                // ignore unchanged comments
                                if (old_comment &&
                                    identical_values(old_comment.created_at_client, new_comment.created_at_client) &&
                                    identical_values(old_comment.comment, new_comment.comment) &&
                                    identical_values(old_comment.price, new_comment.price) &&
                                    identical_values(old_comment.currency, new_comment.currency) &&
                                    identical_values(old_comment.new_deal, new_comment.new_deal) &&
                                    identical_array_values(old_comment.user_ids, new_comment.user_ids) &&
                                    identical_values(old_comment.created_at_server, new_comment.created_at_server) &&
                                    identical_values(old_comment.new_deal_action, new_comment.new_deal_action) &&
                                    identical_array_values(old_comment.new_deal_action_by_user_ids, new_comment.new_deal_action_by_user_ids) &&
                                    identical_values(old_comment.new_deal_action_at_client, new_comment.new_deal_action_at_client) &&
                                    identical_values(old_comment.deleted_at_client, new_comment.deleted_at_client)) continue;

                                // new comments from other clients must always be server verified
                                if (!new_comment.hasOwnProperty('verify_seq')) {
                                    // new comment must be server validated before continuing (between pass 1 and pass 2)
                                    verify_new_comments += 1;
                                    verify_comments_add(new_gift, new_comment, 'verify');
                                    comments_pass = 1;
                                    continue; // wait for verify comments
                                }
                                if (!new_comment.hasOwnProperty('verified_at_server')) {
                                    // new comment already in queue for server verification (offline, server not responding or remote comment)
                                    // todo: how long time to wait for:
                                    //   a: offline client - no internet connection
                                    //   b: server not responding (error or timeout)
                                    //   c: remote comment verification (error or remote server not responding)
                                    seconds = Gofreerev.unix_timestamp() - new_comment.verify_comment_at;
                                    console.log(pgm + 'Waited ' + seconds + ' seconds for comment ' + new_comment.cid + ' verification');
                                    verifying_new_comments += 1;
                                    comments_pass = 1;
                                    continue; // wait for verify comments
                                }
                                if (!new_comment.verified_at_server) {
                                    // invalid signature for new comment - invalid on other client or incorrect in message
                                    new_comments_invalid_sha.push(gid);
                                    continue;
                                }
                                // new comment has been server verified and is ready for pass 2

                                // check readonly fields. old comment must be server verified if readonly fields have changed (possible invalid change on this client)
                                if (old_comment &&
                                    (!identical_values(old_comment.created_at_client, new_comment.created_at_client) || !identical_values(old_comment.comment, new_comment.comment) || !identical_values(old_comment.price, new_comment.price) || !identical_values(old_comment.currency, new_comment.currency) || !identical_values(old_comment.new_deal, new_comment.new_deal) || !identical_array_values(old_comment.user_ids, new_comment.user_ids) || !identical_values(old_comment.created_at_server, new_comment.created_at_server) ||
                                    (old_comment.hasOwnProperty('new_deal_action') && new_comment.hasOwnProperty('new_deal_action') && !identical_values(old_comment.new_deal_action, new_comment.new_deal_action)) ||
                                    (old_comment.hasOwnProperty('new_deal_action_at_client') && new_comment.hasOwnProperty('new_deal_action_at_client') && !identical_values(old_comment.new_deal_action_at_client, new_comment.new_deal_action_at_client)) ||
                                    (old_comment.hasOwnProperty('new_deal_action_by_user_ids') && new_comment.hasOwnProperty('new_deal_action_by_user_ids') && !identical_array_values(old_comment.new_deal_action_by_user_ids, new_comment.new_deal_action_by_user_ids)) ||
                                    (old_comment.hasOwnProperty('deleted_at_client') && new_comment.hasOwnProperty('deleted_at_client') && !identical_values(old_comment.deleted_at_client, new_comment.deleted_at_client)) )) {
                                    // new_comment is valid but readonly fields has been change.
                                    // old comment must be invalid and should be deleted before inserting new comment from other client
                                    if (!old_comment.hasOwnProperty('verify_seq')) {
                                        // old comment must be server validated before continuing (between pass 1 and pass 2)
                                        verify_old_comments += 1;
                                        verify_comments_add(old_gift, old_comment, 'verify');
                                        comments_pass = 1;
                                        continue; // wait for verify comments
                                    }
                                    if (!old_comment.hasOwnProperty('verified_at_server')) {
                                        // old comment already in queue for server verification (offline, server not responding or remote comment)
                                        // todo: how long time to wait for:
                                        //   a: offline client - no internet connection
                                        //   b: server not responding (error or timeout)
                                        //   c: remote comment verification (error or remote server not responding)
                                        seconds = Gofreerev.unix_timestamp() - old_comment.verify_comment_at;
                                        console.log(pgm + 'Waited ' + seconds + ' seconds for comment ' + old_comment.cid + ' verification');
                                        verifying_old_comments += 1;
                                        comments_pass = 1;
                                        continue; // wait for verify comments
                                    }
                                    if (!old_comment.verified_at_server) {
                                        // invalid signature for old comment - system error or unauthorized changed in localStorage in this client
                                        old_comments_invalid_sha.push(gid);
                                        // delete old invalid comment on this client
                                        old_comment_index = old_cids.indexOf(new_comment.cid);
                                        old_cids.splice(old_comment_index, 1);
                                        old_comment_index = null;
                                        for (k = 0; k < old_gift.comments.length; k++) {
                                            if (old_gift.comments[k].cid == new_comment.cid) old_comment_index = k;
                                        }
                                        ;
                                        old_gift.comments.splice(old_comment_index, 1);
                                        save_gift(old_gift);
                                        // old comment has been deleted. treat as gift with a new comment
                                        old_comment = null;
                                        deleted_invalid_old_comments.push(new_comment.cid);
                                        continue;
                                    }
                                    else {
                                        // system error. changed readonly fields and both old_comment and new_comment are valid
                                        cid_validation_system_errors.push(new_comment.cid);
                                        continue;

                                    }

                                } // if


                                // todo: add device.ignore_invalid_comments list? a gift could be correct except a single invalid comment!
                                if (!old_comment) {

                                    // new comment - should be from a friend or from a friend of a friend
                                    // - can also be a user from an other api provider
                                    // - can also be from a remote server where friend lists are not 100% synchronized

                                    // new comment ok - comment ready for pass 2
                                    console.log(pgm + 'new comment ' + new_comment.cid + ' ok - comment ready for pass 2');


                                    // create comment with created_at_server property (not a new comment)
                                    console.log(pgm + 'create new comment ' + new_comment.cid);
                                    comment = {
                                        cid: new_comment.cid,
                                        user_ids: new_comment.user_ids,
                                        comment: new_comment.comment,
                                        price: new_comment.price,
                                        currency: new_comment.currency,
                                        created_at_client: new_comment.created_at_client,
                                        created_at_server: new_comment.created_at_server,
                                        new_deal: new_comment.new_deal
                                    };
                                    // todo: validate new comment - return any errors to UI
                                    // extra control. gifts have already been validated in validate_send_gifts_message
                                    // todo: add msg.users to invalid_comment call. see invalid_gift call
                                    if (errors = invalid_comment(comment, [], 'receive', mailbox.server_id)) {
                                        console.log(pgm + 'Could not create new comment: ' + errors);
                                        console.log(pgm + 'comment = ' + JSON.stringify(comment));
                                        create_comment_errors.push(new_comment.cid);
                                        continue;
                                    }
                                    // console.log(pgm + 'cid = ' + new_comment.cid) ;
                                    // console.log(pgm + 'created_at_client = ' + new_comment.created_at_client) ;
                                    var old_no_rows = old_gift.show_no_comments || self.default_no_comments;
                                    if (!old_gift.hasOwnProperty('comments')) old_gift.comments = [];
                                    old_gift.comments.push(comment);
                                    // console.log(pgm + (old_gift.comments || []).length + ' comments after refresh and new comment') ;
                                    if (old_gift.comments.length > old_no_rows) {
                                        old_no_rows = old_no_rows + 1;
                                        old_gift.show_no_comments = old_no_rows;
                                    }
                                    userService.add_new_users(comment.user_ids, msg.users);
                                    save_gift(old_gift);


                                }
                                else {

                                    console.log(pgm + 'old_comment = ' + JSON.stringify(old_comment));
                                    console.log(pgm + 'new_comment = ' + JSON.stringify(new_comment));
                                    //old_comment =
                                    //  {"cid":"14323680230743366185",
                                    //    "user_ids":["7TXVE0hsVwC9iJneZ9MjESM2qG+go3VZ6fg1a4Y3Pbw="],
                                    //    "comment":"client 1",
                                    //    "currency":"usd",
                                    //    "created_at_client":1432368023,
                                    //    "created_at_server":1,
                                    //    "sha256":"¼õsZ\u001es¯\u000f\u000e±UÁ°®\u001f*µâ\u0000óÇEÙAíøî³"}
                                    //new_comment =
                                    //  {"cid":"14323680230743366185",
                                    //    "user_ids":[3],
                                    //    "currency":"usd",
                                    //    "comment":"client 1",
                                    //    "created_at_client":1432368023,
                                    //    "created_at_server":1,
                                    //    "deleted_at_client":1432646850,
                                    //    "sha256":"\u0006:ÑxV!!\t«¾!Nï?\f\nR\u0000Ðô]7\u001cÚ5è?ØW\u001f"}

                                    console.log(pgm + 'merge existing comment not implemented');

                                    // few changes are allowed for a comment.
                                    // unauthorized update of readonly fields has already been checked
                                    // now checking for new deal proposal action (cancel, accept or reject) and delete comment
                                    if (old_comment.hasOwnProperty('new_deal_action_at_client') && !new_comment.hasOwnProperty('new_deal_action_at_client')) {
                                        // new_deal_action on this client - no new_deal_action in incoming message. send comment and gift to other client
                                        console.log(pgm + 'Found comment ' + cid + ' with new_deal_action on this client. Must be sent to other client in a new send_gifts message');
                                        send_comments.push(cid);
                                        continue;
                                    }
                                    ;
                                    if (old_comment.hasOwnProperty('deleted_at_client') && !new_comment.hasOwnProperty('deleted_at_client')) {
                                        // comment deleted on this client - not deleted in incoming message. send comment and gift to other client
                                        console.log(pgm + 'Found deleted comment ' + cid + ' on this client. Must be sent to other client in a new send_gifts message');
                                        send_comments.push(cid);
                                        continue;
                                    }
                                    ;
                                    // must be a new_deal_action (cancel, accept or reject) or delete comment in incoming message
                                    if (error = invalid_comment_change(old_comment, new_comment)) {
                                        // todo: notification for this client and error message to other client
                                        console.log(pgm + 'Invalid change for comment ' + cid + ': ' + error);
                                        invalid_comment_changes.push(cid + ': ' + error);
                                        continue;
                                    }
                                    ;
                                    // comment ok. merge comment
                                    console.log(pgm + 'Comment ' + cid + ' ok. merge comment');
                                    if (new_comment.hasOwnProperty('new_deal_action')) old_comment.new_deal_action = new_comment.new_deal_action;
                                    if (new_comment.hasOwnProperty('new_deal_action_by_user_ids')) old_comment.new_deal_action_by_user_ids = new_comment.new_deal_action_by_user_ids;
                                    if (new_comment.hasOwnProperty('new_deal_action_at_client') && !old_comment.hasOwnProperty('new_deal_action_at_client')) {
                                        old_comment.new_deal_action_at_client = new_comment.new_deal_action_at_client;
                                        old_comment.new_deal_action_at_server = old_comment.created_at_server;
                                    }
                                    ;
                                    if (new_comment.hasOwnProperty('deleted_at_client') && !old_comment.hasOwnProperty('deleted_at_client')) {
                                        if (typeof old_gift.show_no_comments != 'undefined') old_gift.show_no_comments = gift.show_no_comments - 1;
                                        old_comment.deleted_at_client = new_comment.deleted_at_client;
                                        old_comment.deleted_at_server = old_comment.created_at_server;
                                    }
                                    ;
                                    save_gift(old_gift);
                                }
                                ;
                            } // for j (new_gift.comments)
                        } // if comments
                        if (comments_pass == 1) continue; // wait for verify comments

                        // end update existing gift
                        continue;
                    }

                    // new gift - must be a gift from a mutual friend - check - friend lists could be out of sync
                    is_mutual_gift = false;
                    for (j = 0; j < new_gift.giver_user_ids.length; j++) {
                        user_id = new_gift.giver_user_ids[j];
                        if (mailbox.mutual_friends.indexOf(user_id) != -1) is_mutual_gift = true;
                    }
                    for (j = 0; j < new_gift.receiver_user_ids.length; j++) {
                        user_id = new_gift.receiver_user_ids[j];
                        if (mailbox.mutual_friends.indexOf(user_id) != -1) is_mutual_gift = true;
                    }
                    if (!is_mutual_gift) {
                        // write warning in log. friend lists on the two clients could be out of sync.
                        gifts_without_mutual_friends.push(gid);
                        continue;
                    }

                    // new gift from a mutual friend.

                    // gift and comment sha256 signatures must be verified before continuing with pass 2
                    // local gifts (other users on this gofreerev server) are validated in next ping cycle
                    // remote gifts (from users on other gofreerev servers) take a little longer as gifts have to be remote validated

                    if (mailbox.hasOwnProperty('server_id')) {
                        // user ids have already been translated from sha256 signatures to internal user id or negative user id (unknown user)
                        // See userService.sha256_to_user_ids calls for user_id_giver, user_id_receiver and comment.user_id
                        // server id (created_at_server) has already been translated from sha256 signature to integer in end of pass 0.
                        console.log(pgm + 'pass = ' + msg.pass + ', verify remote gift ' + JSON.stringify(new_gift));
                        // verify remote gift
                        //   {"gid":"14254791174816684686","giver_user_ids":[2,-790],"receiver_user_ids":[],
                        //    "created_at_client":1425479117,"created_at_server":1,"currency":"usd","direction":"giver",
                        //    "description":"e","like":false,"deleted_at_client":1425804186,
                        //    "sha256":"Çî\u0002t 31gõ¤7NÈªãÃÏ\u0018ÂØ\u0013 ×Ü*á\u0013ùÑ",
                        //    "sha256_gift":"\"&»º¡&Q§æíB\rö)Uz/\u0019B\u0018,·E>Q°qÜ",
                        //    "sha256_comments":"_ìëfÿÈo8ÙRxlmilyÂÛÂ9ÝN´g)×:'ûWé"}

                    }
                    if (!new_gift.hasOwnProperty('verify_seq')) {
                        // new gift must be server validated before continuing (between pass 1 and pass 2)
                        verify_new_gifts += 1;
                        verify_gifts_add(new_gift, 'verify');
                        continue; // wait for verify gifts
                    }
                    ;
                    if (!new_gift.hasOwnProperty('verified_at_server')) {
                        // new gift already in queue for server verification (offline, server not responding or remote gift)
                        // todo: how long time to wait for:
                        //   a: offline client - no internet connection
                        //   b: server not responding (error or timeout)
                        //   c: remote gift verification (error or remote server not responding)
                        seconds = Gofreerev.unix_timestamp() - new_gift.verify_gift_at;
                        console.log(pgm + 'Waited ' + seconds + ' seconds for gift ' + gid + ' verification');
                        verifying_new_gifts += 1;
                        continue; // wait for verify gifts
                    }
                    ;
                    if (!new_gift.verified_at_server) {
                        // invalid signature for new gift - changed on other client or incorrect in message
                        // todo: send a special invalid signature error message to other client
                        new_gifts_invalid_sha.push(gid);
                        gift_errors[gid] = new_gift.verified_error;
                        no_gift_errors += 1;
                        continue;
                    }
                    ;
                    // new gift ok - gift ready for pass 2
                    comments_pass = 2;
                    if (new_gift.comments) {
                        // server validate new comments
                        for (j = 0; j < new_gift.comments.length; j++) {
                            new_comment = new_gift.comments[j];
                            cid = new_comment.cid;
                            // todo: add device.ignore_invalid_comments list? a gift could be correct except a single invalid comment!
                            if (!new_comment.hasOwnProperty('verify_seq')) {
                                // pass 1 - new comment must be server validated before continuing (between pass 1 and pass 2)
                                verify_new_comments += 1;
                                // verify_comments.push({gid: gid, comment: new_comment});
                                verify_comments_add(new_gift, new_comment, 'verify');
                                comments_pass = 1;
                                continue;
                            }
                            if (!new_comment.hasOwnProperty('verified_at_server')) {
                                // between pass 1 and 2 - new comment already in queue for server verification (offline, server not responding or remote gift)
                                verifying_new_comments += 1;
                                comments_pass = 1;
                                continue;
                            }
                            // pass 2 - comment has been server verified
                            if (!new_comment.verified_at_server) {
                                // invalid signature for new comment - changed on other client or not correct in message
                                // gift will be created but without invalid comments
                                new_comments_invalid_sha.push(cid);
                                continue;
                            }
                            // new comment ok - ready for pass 3


                        } // for j (comments)
                    }
                    ; // if
                    if (comments_pass == 1) continue; // wait for verify comments

                    // pass 2 - gift and comments have been server validated. no extra validations for new gifts

                    if (new_gift.pass == 3) {
                        // gift already created in a previous pass of this send_gifts message
                        gifts_created.push(gid);
                        continue;
                    }
                    ;

                    // pass 3 - create gift and valid comments
                    console.log(pgm + 'pass 3 - create new gift = ' + JSON.stringify(new_gift));
                    // create gift with created_at_server property (not a new gift)
                    gift = {
                        gid: new_gift.gid,
                        direction: new_gift.direction,
                        giver_user_ids: new_gift.giver_user_ids,
                        receiver_user_ids: new_gift.receiver_user_ids,
                        created_at_client: new_gift.created_at_client,
                        created_at_server: new_gift.created_at_server,
                        price: new_gift.price,
                        currency: new_gift.currency,
                        description: new_gift.description,
                        open_graph_url: new_gift.open_graph_url,
                        open_graph_title: new_gift.open_graph_title,
                        open_graph_description: new_gift.open_graph_description,
                        open_graph_image: new_gift.open_graph_image,
                        show: true,
                        new_comment: {comment: ""}
                    };
                    // extra control. gifts have already been validated in validate_send_gifts_message
                    if (errors = invalid_gift(gift, msg.users, 'receive', mailbox)) {
                        console.log(pgm + 'Could not create new gift: ' + errors);
                        console.log(pgm + 'gift = ' + JSON.stringify(gift));
                        create_gift_errors.push(new_gift.gid);
                        continue;
                    }
                    // add new gift to 1) JS array and 2) localStorage
                    save_new_gift(gift, msg.users);
                    new_gift.pass = 3;
                    gifts_created.push(gid);
                    if (!new_gift.comments || (new_gift.comments.length == 0)) continue; // new gift without comments

                    console.log(pgm + 'pass 3 - create comments for new gift. comments = ' + JSON.stringify(new_gift.comments));
                    // add valid comments for new gift
                    for (j = 0; j < new_gift.comments.length; j++) {
                        new_comment = new_gift.comments[j];
                        if (new_comment.verified_at_server) {
                            // create comment with created_at_server property (not a new comment)
                            cid = new_comment.cid;
                            comment = {
                                cid: new_comment.cid,
                                user_ids: new_comment.user_ids,
                                comment: new_comment.comment,
                                price: new_comment.price,
                                currency: new_comment.currency,
                                created_at_client: new_comment.created_at_client,
                                created_at_server: new_comment.created_at_server,
                                new_deal: new_comment.new_deal
                            };
                            // todo: validate new comment - return any errors to UI
                            // extra control. gifts have already been validated in validate_send_gifts_message
                            if (errors = invalid_comment(comment, [], 'receive', mailbox.server_id)) {
                                console.log(pgm + 'Could not create new comment: ' + errors);
                                console.log(pgm + 'comment = ' + JSON.stringify(comment));
                                create_comment_errors.push(new_comment.cid);
                                continue;
                            }
                            // console.log(pgm + 'cid = ' + new_comment.cid) ;
                            // console.log(pgm + 'created_at_client = ' + new_comment.created_at_client) ;
                            var old_no_rows = new_gift.show_no_comments || self.default_no_comments;
                            if (!gift.hasOwnProperty('comments')) gift.comments = [];
                            gift.comments.push(comment);
                            // console.log(pgm + (gift.comments || []).length + ' comments after refresh and new comment') ;
                            if (gift.comments.length > old_no_rows) {
                                old_no_rows = old_no_rows + 1;
                                gift.show_no_comments = old_no_rows;
                            }
                            userService.add_new_users(comment.user_ids, msg.users);
                            save_gift(gift);
                        } // if
                    } // for j (comments loop

                } // for i (gifts loop)

                // end gifts loop - pass 1, 2 or 3

                // check result of pass 1, 2 and 3 / continue with next pass if ok

                // check for system errors - write message in log, send error message and abort
                if (gift_index_system_errors.length > 0) {
                    // system error - error in javascript logic - abort processing of send_gifts message
                    error = 'System error. Invalid gifts index. Gifts: ' + gift_index_system_errors.join(', ');
                    console.log(pgm + error + '. msg = ' + JSON.stringify(msg));
                    mailbox.outbox.push({
                        mid: Gofreerev.get_new_uid(),
                        msgtype: 'error',
                        request_mid: msg.mid,
                        error: error
                    });
                    return;
                }
                if (gid_validation_system_errors.length > 0) {
                    // system error - error in javascript logic - abort processing of send_gifts message
                    // valid server side sha256 signature for old and new gift - must be a javascript error
                    error = 'System error. Readonly fields was updated for gift and both old and new gift has a valid sha256 signature. Gifts: ' + gid_validation_system_errors.join(', ');
                    console.log(pgm + error + ' msg = ' + JSON.stringify(msg));
                    mailbox.outbox.push({
                        mid: Gofreerev.get_new_uid(),
                        msgtype: 'error',
                        request_mid: msg.mid,
                        error: error
                    });
                    return;
                }
                ;

                if (client_gift_actions + client_comment_actions + verify_new_gifts + verifying_new_gifts + verify_old_gifts + verifying_old_gifts + verify_new_comments + verifying_new_comments > 0) {
                    // between pass 1 and pass 2.
                    // - waiting for local gift and comment action to complete. recheck after next ping.
                    // - waiting for server verification of gifts and comments. recheck after next ping.
                    // todo: max number of seconds/minutes to wait for remote gift and comment verification?
                    if (client_gift_actions > 0) console.log(pgm + 'Waiting for ' + client_gift_actions + ' client gift actions to complete (accept or delete.');
                    if (client_comment_actions > 0) console.log(pgm + 'Waiting for ' + client_comment_actions + ' client comment actions to complete (cancel, accept, reject or delete.');
                    if (verify_new_gifts + verifying_new_gifts + verify_old_gifts + verifying_old_gifts > 0) console.log(pgm + 'Waiting for ' + (verify_new_gifts + verifying_new_gifts + verify_old_gifts + verifying_old_gifts) + ' gifts to be server verified.');
                    if (verify_new_comments + verifying_new_comments > 0) console.log(pgm + 'Waiting for ' + (verify_new_comments + verifying_new_comments) + ' comments to be server verified.');
                    mailbox.read.push(msg);
                    console.log(pgm + 'mailbox.read.length = ' + mailbox.read.length);

                    // debug
                    console.log(pgm + 'verify_gifts = ' + JSON.stringify(verify_gifts));
                    console.log(pgm + 'verify_comments = ' + JSON.stringify(verify_comments));
                    return;
                }
                ;

                // error report in log and send error message. pass should be 3
                console.log(pgm + 'pass = ' + msg.pass + ', error report not full implemented');

                // gifts_already_on_ignore_list included in gifts_hash
                if (gifts_already_on_ignore_list.length > 0) console.log(pgm + 'Warning. Received gifts ' + gifts_already_on_ignore_list.join(', ') + ' already in ignore list (invalid on other client)');
                if (identical_gift_and_comments.length > 0) console.log(pgm + 'Ok. Received gifts ' + identical_gift_and_comments.join(', ') + ' already up-to-date');
                // new_gifts_invalid_sha included in gifts_hash
                if (new_gifts_invalid_sha.length > 0) console.log(pgm + 'Error. Received gifts ' + new_gifts_invalid_sha.join(', ') + ' with invalid sha256 signature (invalid on other client)');
                if (old_gifts_invalid_sha.length > 0) console.log(pgm + 'Error. Replacing gifts ' + old_gifts_invalid_sha.join(', ') + ' invalid on this client with valid gifts received from other client');
                // counterpart_errors are included in gift_errors hash
                if (counterpart_errors.length > 0) console.log(pgm + 'System error. Received gifts ' + counterpart_errors.join(', ') + ' with invalid counterpart update');
                if (gifts_created.length > 0) console.log(pgm + 'Ok. Created gifts ' + gifts_created.join(', '));
                if (send_gifts.length > 0) console.log(pgm + 'todo: send gifts ' + send_gifts.join(', ') + ' with action (cancel, accept, reject or delete) on this client to other client.');
                if (send_comments.length > 0) console.log(pgm + 'todo: send comments ' + send_comments.join(', ') + ' with action (cancel, accept, reject or delete) on this client to other client.');
                if (no_gift_errors > 0) { // xx
                    // write gift error messages to log. will be sent to other client in invalid_gifts sub message
                    console.log(pgm + 'Found ' + no_gift_errors + ' gifts with errors. gift_errors = ' + JSON.stringify(gift_errors));
                    errors = [];
                    for (gid in gift_errors) {
                        gift_error = gift_errors[gid];
                        if (typeof gift_error == 'object') error = I18n.t('js.gift_actions.' + gift_error.key, gift_error.options);
                        else error = gift_error;
                        errors.push('gid ' + gid + ', error:' + error);
                    }
                    console.log(pgm + 'gift errors: ' + errors.join('. '));
                } // if

                // todo: send message:

                // - error with error report. only errors that is not reported in invalid_gifts and invalid_comments sub messages

                // - send_gifts message with gift and comment actions to other client (send_gifts and send_comments). newest update on this client.
                var send_gifts_sub_message, send_gifts_users, send_gift, send_comment, gift_clone, comment_clone;
                if (send_gifts.length + send_comments.length > 0) {
                    send_gifts_sub_message = {
                        mid: Gofreerev.get_new_uid(),
                        msgtype: 'send_gifts',
                        gifts: [],
                        users: []
                    };
                    send_gifts_users = [];
                    for (i = 0; i < gifts.length; i++) {
                        gift = gifts[i];
                        gid = gift.gid;
                        // send gift?
                        send_gift = (send_gifts.indexOf(gid) != -1);
                        send_comment = false;
                        if (!send_gift && gift.hasOwnProperty('comments')) {
                            for (j = 0; j < ((!send_comment && gift.comments.length)); j++) {
                                comment = gift.comments[j];
                                if (send_comments.indexOf(comment.cid) != -1) send_comment = true;
                            }
                        } // if
                        if (!send_gift && !send_comment) continue;
                        // clone, validate and insert gift in send_gifts sub message
                        gift_clone = make_gift_clone(gift);
                        if (error = invalid_gift(gift_clone, [], 'send', mailbox)) {
                            console.log(pgm + 'Error. Invalid gift was not added to outgoing send_gifts sub message response.');
                            console.log(pgm + 'Gift ' + gift_clone.gid + ': ' + JSON.stringify(gift_clone));
                            console.log(pgm + 'Error message: ' + error);
                            gift_errors[gid] = 'Gift in incoming send_gifts sub message was ignores and gift in outgoing send_gifts sub message could not be sent due to error: ' + error;
                            continue;
                        }
                        send_gifts_sub_message.gifts.push(gift_clone);
                        add_user_ids_to_array(gift_clone.giver_user_ids, send_gifts_users, false);
                        add_user_ids_to_array(gift_clone.receiver_user_ids, send_gifts_users, false);
                        if (!gift.hasOwnProperty('comments')) continue;
                        // todo: check that only relevant (changed) comments are sent to other client
                        for (j = 0; j < gift.comments.length; j++) {
                            comment = gift.comments[j];
                            cid = comment.cid;
                            if (!send_gift) send_comment = (send_comments.indexOf(comment.cid) != -1);
                            if (!send_gift && !send_comment) continue;
                            // clone, validate and insert comment in send_gift sub message
                            comment_clone = make_comment_clone(comment);
                            add_user_ids_to_array(comment_clone.user_ids, send_gifts_users, false);
                            add_user_ids_to_array(comment_clone.new_deal_action_by_user_ids, send_gifts_users, false);
                            gift_clone.comments.push(comment_clone);
                        } // for j
                    } // for i
                    if (send_gifts_sub_message.gifts.length == 0) send_gifts_sub_message = null; // one or more invalid gifts. see log & is sent in invalid_gifts sub message
                    else {
                        // todo: DRY. also used in gifts_sha256 message and ...
                        // add relevant users to send_gifts message - used as fallback information in case of "unknown user" error on receiving client
                        var user;
                        for (j = 0; j < send_gifts_users.length; j++) {
                            user_id = send_gifts_users[j];
                            if (mailbox.mutual_friends.indexOf(user_id) != -1) continue; // dont include mutual friends in send_gifts.users array
                            user = userService.get_friend(user_id);
                            // if (!user) console.log(pgm + 'Warning. Unknown friend user_id ' + user_id) ;
                            if (!user) user = userService.get_user(user_id); // fallback to "old" stored user info
                            if (!user) {
                                console.log(pgm + 'Error. Cannot add user info for unknown user_id ' + user_id);
                                continue;
                            }
                            ; // if
                            send_gifts_sub_message.users.push({
                                user_id: user.user_id,
                                uid: user.uid,
                                provider: user.provider,
                                user_name: user.user_name,
                                api_profile_picture_url: user.api_profile_picture_url
                            });
                        } // for j (gift_users)
                    } // if
                } // if

                // - message with invalid gids and cids in incoming message (gift_errors hash and comment_errors hash)
                // todo: should only send relevant errors to other client (invalid sha256 signature, gift/comment does not exists etc). do not send invalid call errors, exceptions etc to other client
                var invalid_gifts;
                if (no_gift_errors > 0) {
                    invalid_gifts = {
                        mid: Gofreerev.get_new_uid(),
                        msgtype: 'invalid_gifts',
                        gifts: []
                    };
                    for (gid in gift_errors) {
                        if (!gift_errors.hasOwnProperty(gid)) continue;
                        gift_error = gift_errors[gid];
                        if (mailbox.hasOwnProperty('server_id') && (typeof gift_error == 'object')) error = I18n.t('js.gift_actions.' + gift_error.key, gift_error.options);
                        else error = gift_error;
                        invalid_gifts.gifts.push({gid: gid, error: error});
                    } // for
                } // if

                var invalid_comments; // todo: add invalid_comments hash?

                if (send_gifts_sub_message || invalid_gifts || invalid_comments) {
                    // return new sync_gifts message to other client
                    var sync_gifts_message = {
                        mid: Gofreerev.get_new_uid(), // envelope mid
                        request_mid: msg.mid,
                        msgtype: 'sync_gifts',
                        mutual_friends: Gofreerev.clone_array(msg.mutual_friends), // subset of mutual friends - from original sync gift message - todo: translate for remote messages?
                    };
                    if (send_gifts_sub_message) sync_gifts_message.send_gifts = send_gifts_sub_message;
                    if (invalid_gifts) sync_gifts_message.invalid_gifts = invalid_gifts;
                    if (invalid_comments) sync_gifts_message.invalid_comments = invalid_comments;
                    console.log(pgm + 'sync_gifts_message = ' + JSON.stringify(sync_gifts_message));

                    // translate user ids and server_ids before sending outgoing remote sync_gifts message to client on other Gofreerev server
                    // ids are translated to sha256 signatures when communicating with clients on other Gofreerev servers (mailbox.server_id != null)
                    // false: errors has already been written to log and send in a error message to other client
                    if (!sync_gifts_translate_ids(msg, sync_gifts_message, mailbox)) return;

                    // JS validate sync_gifts message before placing message in outbox
                    if (Gofreerev.is_json_message_invalid(pgm, sync_gifts_message, 'sync_gifts', '')) {
                        // error message has already been written to log
                        // send error message to other device
                        var json_error = JSON.parse(JSON.stringify(tv4.error));
                        delete json_error.stack;
                        var json_errors = JSON.stringify(json_error);
                        error = 'Could not process send_gifts message. JSON schema validation error in sync_gifts response: ' + json_errors;
                        console.log(pgm + error + ' msg = ' + JSON.stringify(msg));
                        mailbox.outbox.push({
                            mid: Gofreerev.get_new_uid(),
                            request_mid: msg.mid,
                            msgtype: 'error',
                            error: error
                        });
                        return;
                    }

                    // check sync_gifts message for logical errors before placing message in outbox

                    // 1) check sub message send_gifts for logical errors
                    if (sync_gifts_message.send_gifts) {
                        // logical validate send_gifts sub messsage before sending sync_gifts message
                        error = validate_send_gifts_message(mailbox, sync_gifts_message.send_gifts, 'send');
                        if (error) {
                            error = 'Could not process send_gifts response. Logical error in sync_gifts response (send_gifts sub message) : ' + error;
                            console.log(pgm + error + ' msg = ' + JSON.stringify(msg));
                            mailbox.outbox.push({
                                mid: Gofreerev.get_new_uid(),
                                request_mid: msg.mid,
                                msgtype: 'error',
                                error: error
                            });
                            return;
                        }
                    }

                    // 2) check sub message invalid_gifts for logical errors
                    if (sync_gifts_message.invalid_gifts) {
                        // logical validate invalid_gifts sub messsage before sending sync_gifts message
                        // - gid's must be unique
                        // - todo: gid's be in previous send_gifts message
                        error = validate_invalid_gifts_message(mailbox, sync_gifts_message.invalid_gifts, 'send');
                        if (error) {
                            error = 'Could not process send_gifts response. Logical error in sync_gifts response (invalid_gifts sub message) : ' + error;
                            console.log(pgm + error + ' msg = ' + JSON.stringify(msg));
                            mailbox.outbox.push({
                                mid: Gofreerev.get_new_uid(),
                                request_mid: msg.mid,
                                msgtype: 'error',
                                error: error
                            });
                            return;
                        }
                    }

                    // todo: 3) logical validate invalid_comments sub message.
                    // - cids must be unique
                    // - cids must be from previous send_gifts message?

                    // send sync_gifts message
                    mailbox.outbox.push(sync_gifts_message);
                }
                else {
                    // everything is ok. send OK message to other client?
                    console.log(pgm + 'todo: everything is ok. send OK message to other client?');
                }

            }
            catch (err) {
                error = 'Fatal javascript error when processing send_gifts message. ' + err.message ;
                console.log(pgm + error);
                console.log(pgm + 'stack trace = ' + err.stack) ;
                mailbox.outbox.push({
                    mid: Gofreerev.get_new_uid(),
                    msgtype: 'error',
                    request_mid: msg.mid,
                    error: error
                });
            }

        }; // receive_message_send_gifts


        // communication step 5 - receive any invalid gifts (gid and error message) from send_gifts processing from other client
        var receive_message_invalid_gifts = function (device, mailbox, msg) {
            var pgm = service + '.receive_message_invalid_gifts: ';
            console.log(pgm + 'mailbox  = ' + JSON.stringify(mailbox));
            console.log(pgm + 'msg      = ' + JSON.stringify(msg));
            var error ;

            if (msg.pass == 0) {
                // pass 0 - check for some fatal errors before processing invalid_gifts message
                // 1) gid's must be unique
                error = validate_invalid_gifts_message(mailbox, msg, 'receive');
                if (error) {
                    console.log(pgm + error + ' msg = ' + JSON.stringify(msg));
                    mailbox.outbox.push({
                        mid: Gofreerev.get_new_uid(),
                        msgtype: 'error',
                        request_mid: msg.mid,
                        error: error
                    });
                    return;
                } // if error
            } // if pass 0

            // find previous send_gifts message to other client
            var send_gifts_sub_message, i ;
            for (i=0 ; i<mailbox.done.length ; i++) {
                if (mailbox.done[i].mid == msg.request_mid) send_gifts_sub_message = mailbox.done[i] ;
            } // for i
            if (!send_gifts_sub_message || send_gifts_sub_message.msgtype != 'send_gifts') {
                error = 'Invalid_gifts messsage processing was aborted. Previous send_gifts message was not foound' ;
                console.log(pgm + error);
                mailbox.outbox.push({
                    mid: Gofreerev.get_new_uid(),
                    msgtype: 'error',
                    request_mid: msg.mid,
                    error: error
                });
                return;
            } // if
            console.log(pgm + 'send_gifts message = ' + JSON.stringify(send_gifts_sub_message));

            // initialize hashes:
            // 1) invalid_gifts_response_errors: from gid to error message received in invalid_gifts message
            // 2) send_gifts_request_gifts: from gid to gift in previous send_gifts message
            var invalid_gifts_response_errors = {}, gid ;
            for (i=0 ; i<msg.gifts.length  ; i++) {
                gid = msg.gifts[i].gid ;
                invalid_gifts_response_errors[gid] = msg.gifts[i].error ;
                if (msg.hasOwnProperty('server_id') && (typeof msg.gifts[i].error == 'object')) {
                    error = 'Invalid_gifts message processing was aborted. Expected english only error message. Received :key+:options format error message.' ;
                    console.log(pgm + error);
                    mailbox.outbox.push({
                        mid: Gofreerev.get_new_uid(),
                        msgtype: 'error',
                        request_mid: msg.mid,
                        error: error
                    });
                    return;
                }
            } // for
            console.log(pgm + 'invalid_gifts_response_errors = ' + JSON.stringify(invalid_gifts_response_errors)) ;

            var send_gifts_request_gifts = {} ;
            for (i=0 ; i<send_gifts_sub_message.gifts.length; i++) {
                gid = send_gifts_sub_message.gifts[i].gid ;
                if (!invalid_gifts_response_errors.hasOwnProperty(gid)) continue ;
                send_gifts_request_gifts[gid] = send_gifts_sub_message.gifts[i] ;
            } // for
            console.log(pgm + 'send_gifts_request_gifts = ' + JSON.stringify(send_gifts_request_gifts)) ;

            if (msg.pass == 0) {
                // check invalid gids. Must be in old send_gifts message
                var invalid_gids = [] ;
                for (gid in invalid_gifts_response_errors) if (!send_gifts_request_gifts.hasOwnProperty(gid)) invalid_gids.push(gid) ;
                console.log(pgm + 'invalid_gids = ' + invalid_gids.join(', '));
                if (invalid_gids.length > 0) {
                    error = 'Invalid invalid_gifts message. Received gids ' + invalid_gids.join(', ') + ' are not from previous send_gifts message' ;
                    console.log(pgm + error + '. msg = ' + JSON.stringify(msg));
                    mailbox.outbox.push({
                        mid: Gofreerev.get_new_uid(),
                        msgtype: 'error',
                        request_mid: msg.mid,
                        error: error
                    });
                    return;
                } // if

                // todo: check error format. should be object with key and options for within server error messages. Should be string with english error message from other Gofreerev servers

                // ready for pass 1 and 2
                msg.pass = 1 ;
            } // if

            // pass 1. verify gifts. recheck error message received in invalid_gifts message

            // check gifts in invalid_gifts message:
            // - wait for gift action in progress (accepting or deleting gift)
            // - changed gifts - send new send_gifts message to other client
            // - verify gift
            // - verifying gift
            var send_gift, send_gift_signature, gift ;
            var client_action_gids = [], changed_gids = [], verify_gids = [], verifying_gids = [] ;
            for (gid in send_gifts_request_gifts) {
                if (!send_gifts_request_gifts.hasOwnProperty(gid)) continue ;
                send_gift = send_gifts_request_gifts[gid] ;
                // find gift in gifts array
                if (!gid_to_gifts_index.hasOwnProperty(gid)) {
                    error = 'System error. Gid ' + gid + ' found in invalid_gifts and send_gifts messages but was not in gid_to_gifts_index. invalid_gifts message processing aborted.' ;
                    console.log(pgm + 'error message from other client was: ' + invalid_gifts_response_errors[gid]) ;
                    console.log(pgm + error) ;
                    // todo: add notification
                    return ;
                }
                // pending gift action?
                gift = gifts[gid_to_gifts_index[gid]] ;
                if (['accept','delete'].indexOf(gift.verify_gift_action) != -1) {
                    // wait for client gift action to complete before continue with invalid_gifts message
                    client_action_gids.push(gid) ;
                    continue ;
                }
                // changed gift since send_gifts message was sent to other client?
                send_gift_signature = gift_sha256_for_client(send_gift) ;
                send_gift.sha256_gift = send_gift_signature[1] ;
                if (gift.sha256_gift != send_gift.sha256_gift) {
                    changed_gids.push(gid) ;
                    continue ;
                }
                // verify gift.

                if (!gift.hasOwnProperty('verify_seq')) {
                    // gift must be server validated before continuing (between pass 1 and pass 2)
                    verify_gids.push(gid);
                    verify_gifts_add(gift, 'verify');
                    continue;
                };
                if (!gift.hasOwnProperty('verified_at_server')) {
                    // gift already in queue for server verification (offline, server not responding or remote gift)
                    verifying_gids.push(gid);
                    continue;
                };

            }; // for
            if (client_action_gids.length + verify_gids.length + verifying_gids.length > 0) {
                // wait for gift action and verify gift to complete before processing invalid_gifts message
                if (client_action_gids.length > 0) console.log(pgm + 'Waiting for ' + client_action_gids.length + ' client gift actions to complete (accept or delete.') ;
                if (verify_gids.length + verifying_gids.length > 0) console.log(pgm + 'Waiting for ' + (verify_gids.length + verifying_gids.length) + ' gifts to be server verified.');
                mailbox.read.push(msg);
                return;
            } // if


            // pass 2. all gifts in invalid_gifts has been rechecked
            msg.pass = 2 ;

            // - send new send_gifts message (changed gifts)
            // - return error message (valid in this client + invalid in other client)
            // - error report and notification
            send_gifts_sub_message = null ;
            var send_gifts_users, gift_clone, invalid_gifts = [], comment, invalid_gift_error, invalid_gift_error_key, gift_error, gift_error_key ;
            if (changed_gids.length > 0) {
                send_gifts_sub_message = {
                    mid: Gofreerev.get_new_uid(),
                    msgtype: 'send_gifts',
                    gifts: [],
                    users: []
                };
                send_gifts_users = [] ;
            } // if

            for (gid in send_gifts_request_gifts) {
                if (!send_gifts_request_gifts.hasOwnProperty(gid)) continue ;
                send_gift = send_gifts_request_gifts[gid] ;
                gift = gifts[gid_to_gifts_index[gid]] ;
                if (changed_gids.indexOf(gid) != -1) {
                    // changed gift. send new send_gifts message with changed gift
                    error = invalid_gift(gift, [], 'send', mailbox) ;
                    if (error) {
                        console.log(pgm + 'Warning. Changed and invalid gift was not added to send_gifts sub message.') ;
                        console.log(pgm + 'Gift ' + gid + ': ' + JSON.stringify(gift_clone));
                        console.log(pgm + 'Error message: ' + error) ;
                        invalid_gifts.push('Gift ' + gid + ': ' + error) ;
                        continue ;
                    } // if
                    gift_clone = make_gift_clone(gift) ;
                    // save relevant userids (giver, receiver and creator of comments) in gift_users buffer
                    add_user_ids_to_array(gift.giver_user_ids, send_gifts_users, false) ;
                    add_user_ids_to_array(gift.receiver_user_ids, send_gifts_users, false) ;
                    if (gift.hasOwnProperty('comments')) {
                        if (gift.comments.length > 0) gift_clone.comments = [] ;
                        for (i=0 ; i<gift.comments.length ; i++) {
                            comment = gift.comments[i] ;
                            new_gift.commments.push(make_comment_clone(comment)) ;
                            add_user_ids_to_array(comment.user_ids, expected_user_ids, false);
                            add_user_ids_to_array(comment.new_deal_action_by_user_ids, expected_user_ids, false);
                        }
                    }
                    send_gifts_sub_message.gifts.push(gift_clone) ;
                }
                else {
                    // verify gift operation completed. Report error in this and other client. Error messages should be identical!
                    // todo: check identical :key if :key+:options error format is being used for within server error messages
                    // todo: call invalid_gifts?
                    console.log(pgm + 'Gift ' + gid + ' could not be replicated to other client.');
                    invalid_gift_error = invalid_gifts_response_errors[gid] ;
                    if (typeof invalid_gift_error == 'object') {
                        invalid_gift_error_key = invalid_gift_error.key ;
                        invalid_gift_error = I18n.t('js.gift_actions.' + invalid_gift_error, invalid_gift_error.options) ;
                    }
                    else invalid_gift_error_key = null ;
                    console.log(pgm + 'Error message from other client was: ' + error) ;
                    if (gift.verified_at_server) {
                        console.log(pgm + 'No error was found for gift on this client!') ;
                        gift_error_key = null ;
                    }
                    else {
                        gift_error = gift.verified_error ;
                        if (typeof gift_error == 'object') {
                            gift_error_key = gift_error.key ;
                            gift_error = I18n.t('js.gift_actions.' + gift_error.key, gift_error.options) ;
                        }
                        else gift_error_key = null ;
                        console.log(pgm + 'Error message on this client is    : ' + gift_error);
                    }
                    // check for identical error key (both clients on this Gofreerev server only)
                    console.log(pgm + 'invalid_gift_error_key = ' + invalid_gift_error_key);
                    console.log(pgm + 'gift_error_key         = ' + gift_error_key);
                }
            }; // for

            if (send_gifts_sub_message && (send_gifts_sub_message.gifts.length == 0)) {
                send_gifts_sub_message = null ;
                invalid_gifts.push('Error for all changed gifts in new send_gifts message') ;
            } // if
            if (invalid_gifts.length > 0) console.log(pgm + 'errors: ' + invalid_gifts.join('. ')) ;
            if (send_gifts_sub_message) console.log(pgm + 'send_gifts_sub_message = ' + JSON.stringify(send_gifts_sub_message)) ;

            console.log(pgm + 'Error. receive message invalid_gifts not implemented') ;
        }; // receive_message_invalid_gifts


        // communication step 5 - receive any invalid comments (cid and error message) from send_gifts processing from other client
        var receive_message_invalid_comms = function (device, mailbox, msg) {
            var pgm = service + '.receive_message_invalid_comms: ';
            console.log(pgm + 'mailbox  = ' + JSON.stringify(mailbox));
            console.log(pgm + 'msg      = ' + JSON.stringify(msg));

            console.log(pgm + 'Error. Not implemented') ;
        }; // receive_message_invalid_comms


        // error in client to client communication
        // other client could not process a previous sent messge
        // print error in log and move previous message to error folder
        var receive_message_error = function (device, mailbox, msg) {
            var pgm = service + '.receive_message_error: ' ;

            console.log(pgm + 'mailbox = ' + JSON.stringify(mailbox)) ;
            console.log(pgm + 'msg     = ' + JSON.stringify(msg)) ;
            console.log(pgm + 'error = ' + msg.error) ;

            if (!msg.request_mid) return ; // no previous message

            // find previous message
            var request_msgtype = null ;
            for (var i=0 ; i<mailbox.sent.length ; i++) {
                if (mailbox.sent[i].mid == msg.request_mid) request_msgtype = mailbox.sent[i].msgtype ;
            }
            if (!request_msgtype) {
                for (var i=0 ; i<mailbox.outbox.length ; i++) {
                    if (mailbox.outbox[i].mid == msg.request_mid) request_msgtype = mailbox.outbox.msgtype ;
                }
            }
            if (!request_msgtype) return ; // no previous message

            // move previous message to error folder in mailbox
            move_previous_message(pgm, mailbox, msg.request_mid, 'error', false) ;
        }; // receive_message_error


        // communication step 4 - sub message from receive_message_sync_gifts
        // missing gifts request from other device
        var receive_message_request_gifts = function (device, mailbox, msg) {
            var pgm = service + '.receive_message_request_gifts: ' ;
            var error ;
            // console.log(pgm + 'device   = ' + JSON.stringify(device)) ;
            console.log(pgm + 'mailbox  = ' + JSON.stringify(mailbox)) ;
            console.log(pgm + 'msg      = ' + JSON.stringify(msg)) ;
            // msg =
            //   {"mid":"14378467393465841259","msgtype":"request_gifts",
            //    "gifts":["14375634617167046898"],
            //    "request_mid":"14378467336125097959", "users":[4]}

            // logical validate request_gifts message (has already been json validated in receive_message_sync_gifts)
            // 1) gids must be unique
            error = validate_request_gifts_message(mailbox, msg, 'receive') ;
            if (error) {
                console.log(pgm + error + ', msg = ' + JSON.stringify(msg));
                mailbox.outbox.push({
                    mid: Gofreerev.get_new_uid(),
                    msgtype: 'error',
                    request_mid: msg.mid,
                    error: error
                });
                return;
            } // if error (validate_request_gifts_message)

            // gifts must exist and must be from mutual friends
            var unknown_gids = [] ; // array with gids - gift was not found
            var not_mutual_friends_gids = [] ; // array with gids - gift is not from a mutual friend
            var invalid_gids = [] ; // array with gids - gift is invalid and can not be send to other clients (requester)
            var ok_gids = [] ; // array with gids - gift was found and added to outgoing sync_gifts (send_gifts sub) message

            var send_gifts_sub_message = {
                mid: Gofreerev.get_new_uid(),
                msgtype: 'send_gifts',
                gifts: [],
                users: []
            };
            var send_gifts_users = [] ;
            var i, gid, gift, gift_clone, in_mutual_friends, j, k, user_id, comment_clone ;
            for (i=0 ; i<msg.gifts.length ; i++) {
                gid = msg.gifts[i] ;
                if (!gid_to_gifts_index.hasOwnProperty(gid)) {
                    unknown_gids.push(gid) ;
                    continue ;
                };
                gift = gifts[gid_to_gifts_index[gid]] ;

                // gift has found. clone gift and validate. dont't send invalid gifts to other client
                gift_clone = make_gift_clone(gift) ;
                error = invalid_gift(gift_clone, [], 'send', mailbox) ;
                if (error) {
                    console.log(pgm + 'Warning. Invalid gift was not added to send_gifts sub message.') ;
                    console.log(pgm + 'Gift ' + gift_clone.gid + ': ' + JSON.stringify(gift_clone));
                    console.log(pgm + 'Error message: ' + error) ;
                    invalid_gids.push(gid) ;
                    continue ;
                };

                // check if gift is from a mutual friend. todo: remove. there is a multiple friends check in invalid_gifts
                in_mutual_friends = false ;
                if (gift.hasOwnProperty('giver_user_ids')) {
                    for (k=0 ; k<gift.giver_user_ids.length ; k++) {
                        user_id = gift.giver_user_ids[k] ;
                        if (mailbox.mutual_friends.indexOf(user_id) != -1) in_mutual_friends = true ;

                    } // for k
                }; // if
                if (gift.hasOwnProperty('receiver_user_ids')) {
                    for (k=0 ; k<gift.receiver_user_ids.length ; k++) {
                        user_id = gift.receiver_user_ids[k] ;
                        if (mailbox.mutual_friends.indexOf(user_id) != -1) in_mutual_friends = true ;

                    } // for k
                }; // if
                if (!in_mutual_friends) {
                    not_mutual_friends_gids.push(cid) ;
                    continue ;
                };

                // gift ok and from a mutual friend. Add to send_gifts sub message
                // save relevant userids in gift_users buffer
                ok_gids.push(gid) ;
                add_user_ids_to_array(gift_clone.giver_user_ids, send_gifts_users, false) ;
                add_user_ids_to_array(gift_clone.receiver_user_ids, send_gifts_users, false) ;
                send_gifts_sub_message.gifts.push(gift_clone) ;

                // add comments to send_gifts sub message + save relevant userids in gift_users buffer
                if (!gift.hasOwnProperty('comments')) continue ;
                if (gift.comments.length == 0) continue ;
                gift_clone.comments = [] ;
                for (j=0 ; j<gift.comments.length ; j++) {
                    comment_clone = make_comment_clone(gift.comments[j]);
                    add_user_ids_to_array(comment_clone.user_ids, send_gifts_users, false) ;
                    add_user_ids_to_array(comment_clone.new_deal_action_by_user_ids, send_gifts_users, false) ;
                    gift_clone.comments.push(comment_clone) ;
                } ; // for j

            }; // for i (msg.gifts)

            console.log(pgm + 'request_gifts        = ' + msg.gifts.join(', ')) ;
            console.log(pgm + 'ok_gids                 = ' + ok_gids.join(', ')) ;
            if (not_mutual_friends_gids.length > 0) console.log(pgm + 'not_mutual_friends_gids = ' + not_mutual_friends_gids.join(', ')) ;
            if (invalid_gids.length > 0) console.log(pgm + 'invalid_gids       = ' + invalid_gids.join(', ')) ;
            if (unknown_gids.length > 0) console.log(pgm + 'unknown_gids            = ' + unknown_gids.join(', ')) ;

            if (ok_gids.length == 0) {
                // errors in request gifts request. No valid gid's was found.
                var errors = [] ;
                if (not_mutual_friends_gids.length > 0) errors.push('not_mutual_friends_gids = ' + not_mutual_friends_gids.join(', ')) ;
                if (invalid_gids.length > 0) errors.push('invalid_gids = ' + invalid_gids.join(', ')) ;
                if (unknown_gids.length > 0) errors.push('unknown_gids = ' + unknown_gids.join(', ')) ;
                error = 'Errors in sync_gifts/request_gifts sub message. ' + errors.join(', ') ;
                console.log(pgm + error + ', msg = ' + JSON.stringify(msg));
                mailbox.outbox.push({
                    mid: Gofreerev.get_new_uid(),
                    msgtype: 'error',
                    request_mid: msg.mid,
                    error: error
                });
                return;
            } ;
            if (not_mutual_friends_gids.length + invalid_gids.length + unknown_gids.length > 0) {
                console.log(pgm + 'Warning. Ignoring invalid gids ' +
                    not_mutual_friends_gids.concat(invalid_gids).concat(unknown_gids).join(', ') +
                    ' in incoming request_gifts message. Only validgifts ' + ok_gids.join(', ') +
                    ' are included in outgoing send_gifts message') ;
            } ;
            console.log(pgm + 'send_gifts_sub_message  = ' + JSON.stringify(send_gifts_sub_message)) ;
            console.log(pgm + 'send_gifts_users = ' + JSON.stringify(send_gifts_users)) ;

            // todo: DRY. also used in gifts_sha256 message and ...
            // add relevant users to send_gifts message - used as fallback information in case of "unknown user" error on receiving client
            var user ;
            for (j=0 ; j<send_gifts_users.length ; j++) {
                user_id = send_gifts_users[j] ;
                if (mailbox.mutual_friends.indexOf(user_id) != -1) continue ; // dont include mutual friends in send_gifts.users array
                user = userService.get_friend(user_id) ;
                // if (!user) console.log(pgm + 'Warning. Unknown friend user_id ' + user_id) ;
                if (!user) user = userService.get_user(user_id) ; // fallback to "old" stored user info
                if (!user) {
                    console.log(pgm + 'Error. Cannot add user info for unknown user_id ' + user_id) ;
                    continue ;
                }; // if
                send_gifts_sub_message.users.push({
                    user_id: user.user_id,
                    uid: user.uid,
                    provider: user.provider,
                    user_name: user.user_name,
                    api_profile_picture_url: user.api_profile_picture_url
                }) ;
            } // for j (gift_users)

            var sync_gifts_message = {
                mid: Gofreerev.get_new_uid(), // envelope mid
                request_mid: msg.mid,
                msgtype: 'sync_gifts',
                mutual_friends: Gofreerev.clone_array(msg.mutual_friends), // subset of mutual friends - from original sync gift message
                send_gifts: send_gifts_sub_message, // optional sub message 1)
            };

            // translate user ids and server_ids before sending outgoing remote sync_gifts message to client on other Gofreerev server
            // ids are translated to sha256 signatures when communicating with clients on other Gofreerev servers (mailbox.server_id != null)
            // false: errors has already been written to log and send in a error message to other client
            if (!sync_gifts_translate_ids(msg, sync_gifts_message, mailbox)) return ;

            // JS validate sync_gifts message before placing message in outbox
            if (Gofreerev.is_json_message_invalid(pgm,sync_gifts_message,'sync_gifts','')) {
                // error message has already been written to log
                // send error message to other device
                var json_error = JSON.parse(JSON.stringify(tv4.error));
                delete json_error.stack;
                var json_errors = JSON.stringify(json_error) ;
                error = 'Could not process request_gifts message. JSON schema validation error in sync_gifts response: ' + json_errors ;
                console.log(pgm + error + ' msg = ' + JSON.stringify(msg)) ;
                mailbox.outbox.push({
                    mid: Gofreerev.get_new_uid(),
                    request_mid: msg.mid,
                    msgtype: 'error',
                    error: error
                }) ;
                return ;
            }

            // check sync_gifts message for logical errors before placing message in outbox
            // 1) check sub message send_gifts for logical errors
            if (sync_gifts_message.send_gifts) {
                // logical validate send_gifts sub messsage before sending sync_gifts message
                error = validate_send_gifts_message(mailbox, sync_gifts_message.send_gifts, 'send') ;
                if (error) {
                    error = 'Could not process request_gifts message. Logical error in sync_gifts response (send_gifts sub message) : ' + error ;
                    console.log(pgm + error + ' msg = ' + JSON.stringify(msg)) ;
                    mailbox.outbox.push({
                        mid: Gofreerev.get_new_uid(),
                        request_mid: msg.mid,
                        msgtype: 'error',
                        error: error
                    }) ;
                    return ;
                }
            }

            // send sync_gifts message
            mailbox.outbox.push(sync_gifts_message) ;
        }; // receive_message_request_gifts


        // logical validate "request_comments" message before send (receive_message_check_gifts) and after receive (receive_message_request_comms)
        // called after json validation but before sending request_comments / processing information in received request_comments message
        // cids in request comments message must be unique
        // returns nil or error message
        var validate_request_comms_message = function (mailbox, request_comments, context) {
            var pgm = service + '.validate_request_comms_message: ' ;
            var error ;
            if (context == 'send') console.log(pgm + 'validating request_comments message before send') ;
            else if (context == 'receive') console.log(pgm + 'validating request_comments message after received') ;
            else return 'System error. Invalid validate_request_comms_message call. context = ' + context ;

            // check missing comments array - already checked in JSON validation!
            if (!request_comments.comments || !request_comments.comments.length || request_comments.comments.length == 0) return 'No comments array or empty comments array in request_comments.';

            // check doublet comments
            var cids = [], doublet_cids = 0, cid, i;
            for (i = 0; i < request_comments.comments.length; i++) {
                cid = request_comments.comments[i];
                if (cids.indexOf(cid) != -1) doublet_cids += 1;
                else cids.push(cid);
            } // for j (comments)
            if (doublet_cids > 0) return 'Found ' + doublet_cids + ' doublet comments in sync_gifts/request_comments sub message. cid must be unique.';

            // message ok

        } ; // validate_request_comms_message


        // translate user ids and server_ids before sending outgoing remote sync_gifts message to client on other Gofreerev server
        // ids are translated to sha256 signatures when communicating with clients on other Gofreerev servers (mailbox.server_id != null)
        // returns true (ok) or false (error). any errors has been written to log and send in a error message to other client
        var sync_gifts_translate_ids = function (msg, sync_gifts_message, mailbox) {
            var pgm = service + '.sync_gifts_translate_user_ids: ' ;
            var error, i, gift, j, comment ;

            if (!mailbox.hasOwnProperty('server_id')) return true ; // not a remote message

            // sync_gifts message to client on an other Gofreerev server
            // translate internal user ids to sha256 signatures before sending sync_gifts message
            // 1) translate users array in message header
            // 2) send_gifts: translate user ids in giver_user_ids, receiver_user_ids, comment user ids and users
            console.log(pgm + 'sync_gifts_message (1) = ' + JSON.stringify(sync_gifts_message));
            if (error=userService.user_ids_to_remote_sha256(sync_gifts_message.mutual_friends, 'mutual_friends', mailbox.server_id, sync_gifts_message, false)) {
                // write error in log and return error message to other client
                error = 'Could not send sync_gifts response to ' + msg.msgtype + ' request. ' + error ;
                console.log(pgm + error + ' msg = ' + JSON.stringify(msg)) ;
                mailbox.outbox.push({
                    mid: Gofreerev.get_new_uid(),
                    request_mid: msg.mid,
                    msgtype: 'error',
                    error: error
                }) ;
                return false;
            };

            if (sync_gifts_message.send_gifts) {
                // translate user ids in giver_user_ids, receiver_user_ids and comment user_ids
                // use remote sha256 signatures for remote users and negative user id for "unknown" users
                for (i = 0; i < sync_gifts_message.send_gifts.gifts.length; i++) {
                    gift = sync_gifts_message.send_gifts.gifts[i];
                    if (error=userService.user_ids_to_remote_sha256(gift.giver_user_ids, 'gift.giver_user_ids', mailbox.server_id, sync_gifts_message, true)) {
                        // write error in log and return error message to other client
                        error = 'Could not send sync_gifts response to ' + msg.msgtype + ' request. ' + error ;
                        console.log(pgm + error + ' msg = ' + JSON.stringify(msg)) ;
                        mailbox.outbox.push({
                            mid: Gofreerev.get_new_uid(),
                            request_mid: msg.mid,
                            msgtype: 'error',
                            error: error
                        }) ;
                        return false;
                    }
                    ;
                    if (error=userService.user_ids_to_remote_sha256(gift.receiver_user_ids, 'gift.receiver_user_ids', mailbox.server_id, sync_gifts_message, true)) {
                        // write error in log and return error message to other client
                        error = 'Could not send sync_gifts response to ' + msg.msgtype + ' request. ' + error ;
                        console.log(pgm + error + ' msg = ' + JSON.stringify(msg)) ;
                        mailbox.outbox.push({
                            mid: Gofreerev.get_new_uid(),
                            request_mid: msg.mid,
                            msgtype: 'error',
                            error: error
                        }) ;
                        return false;
                    }
                    ;
                    if (gift.comments) {
                        for (j = 0; j < gift.comments.length; j++) {
                            if (error=userService.user_ids_to_remote_sha256(gift.comments[j].user_ids, 'comment.user_ids', mailbox.server_id, sync_gifts_message, true)) {
                                // write error in log and return error message to other client
                                error = 'Could not send sync_gifts response to ' + msg.msgtype + '. ' + error ;
                                console.log(pgm + error + ' msg = ' + JSON.stringify(msg)) ;
                                mailbox.outbox.push({
                                    mid: Gofreerev.get_new_uid(),
                                    request_mid: msg.mid,
                                    msgtype: 'error',
                                    error: error
                                }) ;
                                return false;
                            } ;
                            if (error=userService.user_ids_to_remote_sha256(gift.comments[j].new_deal_action_by_user_ids, 'comment.new_deal_action_by_user_ids', mailbox.server_id, sync_gifts_message, true)) {
                                // write error in log and return error message to other client
                                error = 'Could not send sync_gifts response to ' + msg.msgtype + '. ' + error ;
                                console.log(pgm + error + ' msg = ' + JSON.stringify(msg)) ;
                                mailbox.outbox.push({
                                    mid: Gofreerev.get_new_uid(),
                                    request_mid: msg.mid,
                                    msgtype: 'error',
                                    error: error
                                }) ;
                                return false;
                            } ;

                        } // for j (comments(
                    } // if (comments)
                } // for i (gifts)

                // translate user ids in send_gifts.users array

                // replace internal user ids with remote sha256 signatures
                var user_ids = [] ;
                // todo: use clone_array
                for (i=0 ; i<sync_gifts_message.send_gifts.users.length ; i++) user_ids.push(sync_gifts_message.send_gifts.users[i].user_id) ;
                if (error=userService.user_ids_to_remote_sha256(user_ids, 'send_gifts.users', mailbox.server_id, sync_gifts_message, true)) {
                    // write error in log and return error message to other client
                    error = 'Could not send sync_gifts response to ' + msg.msgtype + '. ' + error ;
                    console.log(pgm + error + ', msg = ' + JSON.stringify(msg)) ;
                    mailbox.outbox.push({
                        mid: Gofreerev.get_new_uid(),
                        request_mid: msg.mid,
                        msgtype: 'error',
                        error: error
                    }) ;
                    return false;
                };
                // no errors. replace user ids
                for (i=0 ; i<sync_gifts_message.send_gifts.users.length ; i++) sync_gifts_message.send_gifts.users[i].user_id = user_ids[i] ;
                console.log(pgm + 'sync_gifts_message (2) = ' + JSON.stringify(sync_gifts_message));

                // add servers array with translation for internal created_at_server integer to server sha256 signature
                // created_at_server=0 : current gofreerev server
                // created_at_server>0 : gift/comment from an other gofreerev server
                var internal_server_ids = [] ;
                for (i = 0; i < sync_gifts_message.send_gifts.gifts.length; i++) {
                    gift = sync_gifts_message.send_gifts.gifts[i];
                    if (internal_server_ids.indexOf(gift.created_at_server) == -1) internal_server_ids.push(gift.created_at_server) ;
                    // gift.created_at_server = server_id_to_sha256(gift.created_at_server);
                    if (!gift.comments) continue;
                    for (j = 0; j < gift.comments.length; j++) {
                        comment = gift.comments[j];
                        if (internal_server_ids.indexOf(comment.created_at_server) == -1) internal_server_ids.push(comment.created_at_server) ;
                        // comment.created_at_server = server_id_to_sha256(comment.created_at_server);
                    } // for j (comments)
                } // for i (gifts)
                sync_gifts_message.send_gifts.servers = [] ;
                for (i=0 ; i<internal_server_ids.length ; i++) {
                    sync_gifts_message.send_gifts.servers.push({
                        server_id: internal_server_ids[i],
                        sha256: server_id_to_sha256(internal_server_ids[i])
                    }) ;
                }

            } // if send_gifts

            console.log(pgm + 'sync_gifts_message (3) = ' + JSON.stringify(sync_gifts_message));

            return true ;
        } ; // sync_gifts_translate_ids


        // communication step 4 - sub message from receive_message_sync_gifts
        // other client has detected different gift.sha256 values for one or more gifts
        // compare gift sub sha256 values and send gift, comments or both to other client
        var receive_message_check_gifts = function (device, mailbox, msg) {
            var pgm = service + '.receive_message_check_gifts: ' ;
            var error ;
            // console.log(pgm + 'device   = ' + JSON.stringify(device)) ;
            console.log(pgm + 'mailbox  = ' + JSON.stringify(mailbox)) ;
            console.log(pgm + 'msg      = ' + JSON.stringify(msg)) ;
            // msg =
            //   {"mid":"14320233440548746338","msgtype":"check_gifts",
            //    "gifts":[{"gid":"14318503987470039958",
            //              "sha256":"\u0004uzÌªs´IöÜÍnQ\u001c\u001d\u001b_¥»cij°ªÍrÁÍMá",
            //              "sha256_gift":"Ürn¥J9³¸Yhj\u001d\róÅ? vböÞ/D1\u0019\u0016ø¶","sha256_comments":"dlM<»0©Mã{U«\tï1³\u000b]Ó0,\u0000´\u001cÙò«"},
            //             {"gid":"14319404121313532052",
            //              "sha256":"\u0004uzÌªs´IöÜÍnQ\u001c\u001d\u001b_¥»cij°ªÍrÁÍMá",
            //              "sha256_gift":"Ürn¥J9³¸Yhj\u001d\róÅ? vböÞ/D1\u0019\u0016ø¶","sha256_comments":"dlM<»0©Mã{U«\tï1³\u000b]Ó0,\u0000´\u001cÙò«"},
            //             {"gid":"14319571254533652857",
            //              "sha256":"\u0004uzÌªs´IöÜÍnQ\u001c\u001d\u001b_¥»cij°ªÍrÁÍMá",
            //              "sha256_gift":"Ürn¥J9³¸Yhj\u001d\róÅ? vböÞ/D1\u0019\u0016ø¶","sha256_comments":"dlM<»0©Mã{U«\tï1³\u000b]Ó0,\u0000´\u001cÙò«"},
            //             {"gid":"14319575639123588713",
            //              "sha256":"\u0004uzÌªs´IöÜÍnQ\u001c\u001d\u001b_¥»cij°ªÍrÁÍMá",
            //              "sha256_gift":"Ürn¥J9³¸Yhj\u001d\róÅ? vböÞ/D1\u0019\u0016ø¶","sha256_comments":"dlM<»0©Mã{U«\tï1³\u000b]Ó0,\u0000´\u001cÙò«"}],
            //    "request_mid":"14320233347208437968"}

            // merge sha256 gift signatures for the two clients
            var merge_gifts = {}, i, msg_gift, index, gid, my_gift, merge_gift ;
            var invalid_gids = [] ; // array with unknown unique gift ids gid
            var identical_gids = [] ; // array with gids for identical gift and comments
            var j, msg_comment, cid, merge_comment, my_comment ;
            var return_check_gifts_message = false ;
            var identical_comments, sha256_values ;
            for (i = 0; i < msg.gifts.length; i++) {
                msg_gift = msg.gifts[i];
                gid = msg_gift.gid;
                if (gid_to_gifts_index.hasOwnProperty(gid)) {
                    index = gid_to_gifts_index[gid];
                    my_gift = gifts[index];
                }
                else {
                    // error. todo: send error message? there must be an error in previous gifts_sha256 message!
                    invalid_gids.push(gid);
                    continue;
                };
                merge_gift = {
                    msg_sha256: msg_gift.sha256,
                    my_sha256: my_gift.sha256,
                    msg_sha256_gift: msg_gift.sha256_gift,
                    my_sha256_gift: my_gift.sha256_gift,
                    msg_sha256_comments: msg_gift.sha256_comments,
                    my_sha256_comments: my_gift.sha256_comments,
                };
                merge_gift.identical_gift = (merge_gift.my_sha256_gift == merge_gift.msg_sha256_gift) ;
                merge_gift.identical_comments = (merge_gift.my_sha256_comments == merge_gift.msg_sha256_comments) ;
                if (merge_gift.identical_gift && merge_gift.identical_comments) {
                    identical_gids.push(gid) ;
                    continue ;
                }
                if (!merge_gift.identical_comments) {
                    // compare sha256 values for comments. My comments and any comments in check_gift message
                    merge_gift.comments = {} ;
                    if (msg_gift.hasOwnProperty('comments')) {
                        // received check_gift message WITH sha256 signatures for comments (returned check_gift message)
                        console.log(pgm + 'msg_gift.comments.length = ' + msg_gift.comments.length );
                        console.log(pgm + 'msg_gift.comments = ' + JSON.stringify(msg_gift.comments) );
                        for (j=0 ; j<msg_gift.comments.length ; j++) {
                            msg_comment = msg_gift.comments[j] ;
                            cid = msg_comment.cid ;
                            merge_comment = { msg_sha256: msg_comment.sha256 } ;
                            merge_gift.comments[cid] = merge_comment ;
                        } // for j (msg_gift.comments)
                    }
                    else {
                        // incoming check_gifts message WITHOUT sha256 values for comments
                        // return check_gifts message to other client WITH sha256 values for comments
                        return_check_gifts_message = true;
                    }
                    if (my_gift.comments) {
                        console.log(pgm + 'my_gift.comments.length = ' + my_gift.comments.length);
                        console.log(pgm + 'my_gift.comments = ' + JSON.stringify(my_gift.comments));
                        for (j=0 ; j<my_gift.comments.length ; j++) {
                            my_comment = my_gift.comments[j] ;
                            cid = my_comment.cid ;
                            merge_comment = merge_gift.comments[cid] || {} ;
                            if (merge_comment.hasOwnProperty('my_sha256')) {
                                console.log(pgm + 'System error. Gift ' + gid + ' has two comments with cid ' + cid) ;
                                invalid_gids.push(gid) ;
                                return_check_gifts_message = false;
                                continue ;
                            };
                            merge_comment.my_sha256 = my_comment.sha256 ;
                            merge_gift.comments[cid] = merge_comment ;
                        } // for j (my_gift.comments)
                    } // if
                    // check comments hash. comments should not be identical
                    identical_comments = true ;
                    for (cid in merge_gift.comments) {
                        if (!merge_gift.comments.hasOwnProperty(cid)) continue ;
                        merge_comment = merge_gift.comments[cid] ;
                        if (merge_comment.my_sha256 != merge_comment.msg_sha256) identical_comments = false ;
                    } // for
                    if (identical_comments) {
                        console.log(pgm + 'sha256 calc error for gift ' + gid + '. comments are identical but gift.sha256_comments were not identical.') ;
                        // recheck sha256 calc for gift in this client
                        sha256_values = gift_sha256_for_client(my_gift) ;
                        console.log(pgm + 'merge_gift.my_sha256_comments = ' + merge_gift.my_sha256_comments +
                            ', merge_gift.msg_sha256_comments = ' + merge_gift.msg_sha256_comments +
                            ', sha256_values[2] = ' + sha256_values[2]) ;
                        if (merge_gift.my_sha256_comments == sha256_values[2]) console.log(pgm + 'sha256_comments calc in this client is correct.') ;
                        else if (merge_gift.msg_sha256_comments == sha256_values[2]) console.log(pgm + 'sha256_comments calc in received check_gifts message is correct.') ;
                        else console.log(pgm + 'sha256_comments calc is not correct.') ;
                    } // if
                } // if
                if (invalid_gids.indexOf(gid) == -1) merge_gifts[gid] = merge_gift;
            } // for i (msg.gifts)
            console.log(pgm + 'invalid_gids = ' + invalid_gids.join(', ')) ;
            console.log(pgm + 'merge_gifts = ' + JSON.stringify(merge_gifts)) ;
            //merge_gifts =
            //  {"14323048627287885889":
            //     {"msg_sha256":"\u0004uzÌªs´IöÜÍnQ\u001c\u001d\u001b_¥»cij°ªÍrÁÍMá","my_sha256":"9mÙ@¥ÔÖûÊ\u0010B«î¶Q:È\u0007k\u0013[´\u0019vCÛ\u0014Pm",
            //      "msg_sha256_gift":"Ürn¥J9³¸Yhj\u001d\róÅ? vböÞ/D1\u0019\u0016ø¶","my_sha256_gift":"Ürn¥J9³¸Yhj\u001d\róÅ? vböÞ/D1\u0019\u0016ø¶",
            //      "msg_sha256_comments":"dlM<»0©Mã{U«\tï1³\u000b]Ó0,\u0000´\u001cÙò«","my_sha256_comments":"_ìëfÿÈo8ÙRxlmilyÂÛÂ9ÝN´g)×:'ûWé",
            //      "identical_gift":true,"identical_comments":false,
            //      "comments":{"14323680230743366185":{}}}}

            console.log(pgm + 'return_check_gifts_message = ' + return_check_gifts_message) ;

            var check_gifts_message, sync_gifts_message ;
            if (return_check_gifts_message) {
                // received check_gift message WITHOUT sha256 values for comments.
                // return check_gifts message (sync_gifts sub message) to other client WITH sha256 values for comments
                check_gifts_message = {
                    mid: Gofreerev.get_new_uid(),
                    msgtype: 'check_gifts',
                    gifts: []
                };
                for (gid in merge_gifts) {
                    merge_gift = merge_gifts[gid];
                    if (merge_gift.identical_comments) continue ;
                    msg_gift = {
                        gid: gid,
                        sha256: merge_gift.my_sha256,
                        sha256_gift: merge_gift.my_sha256_gift,
                        sha256_comments: merge_gift.my_sha256_comments,
                        comments: []
                    };
                    for (cid in merge_gift.comments) {
                        msg_comment = merge_gift.comments[cid] ;
                        if (!msg_comment.hasOwnProperty('my_sha256')) continue ;
                        msg_gift.comments.push({ cid: cid, sha256: msg_comment.my_sha256}) ;
                    } // for cid (merge_gift.comments)
                    check_gifts_message.gifts.push(msg_gift) ;
                } // for gid (merge_gifts)

                sync_gifts_message =
                {
                    mid: Gofreerev.get_new_uid(), // envelope mid
                    request_mid: msg.mid,
                    msgtype: 'sync_gifts',
                    mutual_friends: msg.mutual_friends, // subset of mutual friends - from original sync gift message
                    check_gifts: check_gifts_message // optional sub message 3)
                };

                // translate sync_gifts_message.users before sending outgoing remote sync_gifts message to client on other Gofreerev server
                // ids are translated to sha256 signatures when communicating with clients on other Gofreerev servers (mailbox.server_id != null)
                // false: errors has already been written to log and send in a error message to other client
                if (!sync_gifts_translate_ids(msg, sync_gifts_message, mailbox)) return ;

                // JS validate sync_gifts message before placing message in outbox
                if (Gofreerev.is_json_message_invalid(pgm,sync_gifts_message,'sync_gifts','')) {
                    // error message has already been written to log
                    // send error message to other device
                    var json_error = JSON.parse(JSON.stringify(tv4.error));
                    delete json_error.stack;
                    var json_errors = JSON.stringify(json_error) ;
                    error = 'Could not process check_gifts return message. JSON schema validation error in sync_gifts message: ' + json_errors ;
                    console.log(pgm + error + ' msg = ' + JSON.stringify(msg)) ;
                    mailbox.outbox.push({
                        mid: Gofreerev.get_new_uid(),
                        request_mid: msg.mid,
                        msgtype: 'error',
                        error: error
                    }) ;
                    return ;
                }

                // send sync_gifts message with check_gifts sub message
                mailbox.outbox.push(sync_gifts_message) ;

                return ;

            } // if

            // there should now be sha256 signatures for all changed comments
            // merge_gifts =
            //  {"14323048627287885889":
            //     {"msg_sha256":"\u0004uzÌªs´IöÜÍnQ\u001c\u001d\u001b_¥»cij°ªÍrÁÍMá","my_sha256":"9mÙ@¥ÔÖûÊ\u0010B«î¶Q:È\u0007k\u0013[´\u0019vCÛ\u0014Pm",
            //        "msg_sha256_gift":"Ürn¥J9³¸Yhj\u001d\róÅ? vböÞ/D1\u0019\u0016ø¶","my_sha256_gift":"Ürn¥J9³¸Yhj\u001d\róÅ? vböÞ/D1\u0019\u0016ø¶",
            //        "msg_sha256_comments":"dlM<»0©Mã{U«\tï1³\u000b]Ó0,\u0000´\u001cÙò«","my_sha256_comments":"_ìëfÿÈo8ÙRxlmilyÂÛÂ9ÝN´g)×:'ûWé",
            //        "identical_gift":true,"identical_comments":false,
            //        "comments":{"14323680230743366185":{"msg_sha256":"¼õsZ\u001es¯\u000f\u000e±UÁ°®\u001f*µâ\u0000óÇEÙAíøî³"}}}}

            // actions:
            // - identical gift and comments - see identical_gids array  - no action - not in merge_gifts hash - see identical_gids array
            // - changed gift                - send changed gift
            // - changed comments            - optional send unchanged gift + send new and changed comments + request missing comments
            // - changed gift and comments   - send changed gift + send new and changed comments + request missing comments
            // todo: use sync_gifts message. add sub message request_comments to sync_gifts message
            var send_gifts_sub_message = {
                mid: Gofreerev.get_new_uid(),
                msgtype: 'send_gifts',
                gifts: [],
                users: []
            }, send_gifts_users = [];
            var request_comments_sub_message = {
                mid: Gofreerev.get_new_uid(),
                msgtype: 'request_comments',
                comments: []
            };

            var send_gift, gift_clone, send_comment, request_comment, k ;
            for (gid in merge_gifts) {
                merge_gift = merge_gifts[gid] ;
                // send gift?
                if (merge_gift.identical_gift && !merge_gift.identical_comments) {
                    // send gift unless only comments to request_comments message
                    send_gift = false ;
                    for (cid in merge_gift.comments) {
                        merge_comment = merge_gift.comments[cid] ;
                        if (merge_comment.hasOwnProperty('my_sha256')) {
                            if (!merge_comment.hasOwnProperty('msg_sha256')) send_gift = true ; // send new comment to other client
                            else if (merge_comment.my_sha256 != merge_comment.msg_sha256) send_gift = true ; // send changed comment to other client
                        }
                    } // for j (merge_gift.comments)

                }
                else send_gift = true ;
                console.log(pgm + 'gid = ' + gid + ', send_gift = ' + send_gift) ;

                if (send_gift) {
                    index = gid_to_gifts_index[gid];
                    my_gift = gifts[index];
                    // clone gift - some interval properties are not replicated to other devices
                    // todo: 1 - change like from boolean to an array  with user ids and like/unlike timestamps for merge operation
                    // todo: 2 - add server side sha256_deleted signature to gift. Server could validate client_deleted_at and know that gift has been deleted
                    // todo: 3 - add url with optional file attachment (file upload has not been implemented yet)
                    gift_clone = make_gift_clone(my_gift) ;
                    // save relevant userids (giver, receiver and creator of comments) in send_gifts_users buffer
                    add_user_ids_to_array(my_gift.giver_user_ids, send_gifts_users, false);
                    add_user_ids_to_array(my_gift.receiver_user_ids, send_gifts_users, false);
                }; // if send_gift

                if (merge_gift.hasOwnProperty('comments')) {
                    // add comments to send_gifts or request_comments sub messages
                    for (cid in merge_gift.comments) {
                        merge_comment = merge_gift.comments[cid] ;
                        // send or request comment?
                        send_comment = false ;
                        request_comment = false ;
                        if (merge_comment.hasOwnProperty('my_sha256')) {
                            if (!merge_comment.hasOwnProperty('msg_sha256')) send_comment = true ; // send new comment to other client
                            else if (merge_comment.my_sha256 != merge_comment.msg_sha256) send_comment = true ; // send changed comment to other client
                        }
                        else request_comment = true ;
                        console.log(pgm + 'cid = ' + cid + ', send_comment = ' + send_comment + ', request_comment = ' + request_comment) ;
                        if (send_comment) {
                            // add comment to send_gifts sub message
                            my_comment = null ;
                            for (k=0 ; k<my_gift.comments.length ; k++) if (my_gift.comments[k].cid == cid) my_comment = my_gift.comments[k] ;

                            // todo: 1 - add server side sha256_deleted and/or sha256_action signature
                            //           a comment cannot be both accepted and deleted (delete gift to remove accepted deals)
                            //           it should be enough with one client side deleted_at_server=accepted_at_server field
                            if (!gift_clone.hasOwnProperty('comments')) gift_clone.comments = [] ;
                            gift_clone.comments.push(make_comment_clone(my_comment)) ;
                            // save relevant comment.user_ids in gift_users buffer
                            add_user_ids_to_array(my_comment.user_ids, send_gifts_users, false) ;
                            add_user_ids_to_array(my_comment.new_deal_action_by_user_ids, send_gifts_users, false) ;

                        } // if send_comment
                        if (request_comment) {
                            // add comment to request_comments sub message
                            request_comments_sub_message.comments.push(cid) ;
                        }
                    } // for j (merge_gift.comments)

                } // if merge_gift.comments

                if (send_gift) {
                    // validate gift_clone before adding gift to send_gifts sub message
                    error = invalid_gift(gift_clone, [], 'send', mailbox) ;
                    if (error) {
                        console.log(pgm + 'System error when adding gift to send_gifts sub message.') ;
                        console.log(pgm + 'Gift ' + gift_clone.gid + ': ' + JSON.stringify(gift_clone));
                        console.log(pgm + 'Error message: ' + error) ;
                        continue ;
                    }
                    send_gifts_sub_message.gifts.push(gift_clone) ;

                } // if send_gift

            } // for i (merge_gifts)

            if (send_gifts_sub_message.gifts.length == 0) send_gifts_sub_message = null ;
            if (request_comments_sub_message.comments.length == 0) request_comments_sub_message = null ;
            console.log(pgm + 'send_gifts_sub_message = ' + JSON.stringify(send_gifts_sub_message)) ;
            console.log(pgm + 'request_comments_sub_message = ' + JSON.stringify(request_comments_sub_message)) ;

            var user, user_id ;
            if (send_gifts_sub_message) {
                // todo: DRY. also used in gifts_sha256 message and ...
                // add relevant users to send_gifts message - used as fallback information in case of "unknown user" error on receiving client
                for (j=0 ; j<send_gifts_users.length ; j++) {
                    user_id = send_gifts_users[j] ;
                    if (mailbox.mutual_friends.indexOf(user_id) != -1) continue ; // dont include mutual friends in send_gifts.users array
                    user = userService.get_friend(user_id) ;
                    // if (!user) console.log(pgm + 'Warning. Unknown friend user_id ' + user_id) ;
                    if (!user) user = userService.get_user(user_id) ; // fallback to "old" stored user info
                    if (!user) {
                        console.log(pgm + 'Error. Cannot add user info for unknown user_id ' + user_id) ;
                        continue ;
                    }; // if
                    send_gifts_sub_message.users.push({
                        user_id: user.user_id,
                        uid: user.uid,
                        provider: user.provider,
                        user_name: user.user_name,
                        api_profile_picture_url: user.api_profile_picture_url
                    }) ;
                } // for j (gift_users)
            }

            sync_gifts_message = {
                mid: Gofreerev.get_new_uid(), // envelope mid
                request_mid: msg.mid,
                msgtype: 'sync_gifts',
                mutual_friends: Gofreerev.clone_array(msg.mutual_friends), // subset of mutual friends - from original sync gift message - todo: translate for remote messages?
                send_gifts: send_gifts_sub_message, // optional sub message 1)
                request_comments: request_comments_sub_message // optional sub message 4)
            };

            // translate user ids and server_ids before sending outgoing remote sync_gifts message to client on other Gofreerev server
            // ids are translated to sha256 signatures when communicating with clients on other Gofreerev servers (mailbox.server_id != null)
            // false: errors has already been written to log and send in a error message to other client
            if (!sync_gifts_translate_ids(msg, sync_gifts_message, mailbox)) return ;

            // JS validate sync_gifts message before placing message in outbox
            if (Gofreerev.is_json_message_invalid(pgm,sync_gifts_message,'sync_gifts','')) {
                // error message has already been written to log
                // send error message to other device
                json_error = JSON.parse(JSON.stringify(tv4.error));
                delete json_error.stack;
                json_errors = JSON.stringify(json_error) ;
                error = 'Could not process check_gifts message. JSON schema validation error in sync_gifts response: ' + json_errors ;
                console.log(pgm + error + ' msg = ' + JSON.stringify(msg)) ;
                mailbox.outbox.push({
                    mid: Gofreerev.get_new_uid(),
                    request_mid: msg.mid,
                    msgtype: 'error',
                    request_mid: msg.mid,
                    error: error
                }) ;
                return ;
            }

            // check sync_gifts message for logical errors before placing message in outbox

            // 1) check sub message send_gifts for logical errors
            if (sync_gifts_message.send_gifts) {
                // logical validate send_gifts sub messsage before sending sync_gifts message to other client
                error = validate_send_gifts_message(mailbox, sync_gifts_message.send_gifts, 'send') ;
                if (error) {
                    var error = 'Could not process gifts_sha256 message. Logical error in sync_gifts response (send_gifts sub message) : ' + error ;
                    console.log(pgm + error + ' msg = ' + JSON.stringify(msg)) ;
                    mailbox.outbox.push({
                        mid: Gofreerev.get_new_uid(),
                        request_mid: msg.mid,
                        msgtype: 'error',
                        request_mid: msg.mid,
                        error: error
                    }) ;
                    return ;
                }; // if
            }; // if

            // check sub message request_comments for logical errors
            if (sync_gifts_message.request_comments) {
                // logical validate request_comments sub message before sending sync_gifts message to other client
                // 1) cids must be unique
                var error = validate_request_comms_message(mailbox, sync_gifts_message.request_comments, 'send') ;
                if (error) {
                    console.log(pgm + error + ' msg = ' + JSON.stringify(msg));
                    mailbox.outbox.push({
                        mid: Gofreerev.get_new_uid(),
                        msgtype: 'error',
                        request_mid: msg.mid,
                        error: error
                    });
                    return;
                } // if
            }; // if

            // send sync_gifts message
            mailbox.outbox.push(sync_gifts_message) ;

        }; // receive_message_check_gifts


        // communication step 4 - sub message from receive_message_sync_gifts
        // other client is requesting missing comments from this client (see check_gifts message)
        // gift must be from mutual friends (giver and/or receiver)
        // comment can be from a friend of a friend or be from a not logged api provider
        var receive_message_request_comms = function (device, mailbox, msg) {
            var pgm = service + '.receive_message_request_comms: ' ;

            // console.log(pgm + 'device   = ' + JSON.stringify(device)) ;
            console.log(pgm + 'mailbox  = ' + JSON.stringify(mailbox)) ;
            console.log(pgm + 'msg      = ' + JSON.stringify(msg)) ;
            // msg =
            //   {"mid":"14336001555803691502","request_mid":"14336001491398636683","msgtype":"sync_gifts",
            //       "users":["5J5L6uh773z7PGtzfsOF/0Mn4uDk/8QUZUOLfuLnz9U="],
            //       "request_comments":{"mid":"14336001555761351210","msgtype":"request_comments","comments":["14336000949698090073"]}}
            
            // logical validate request_comments message - incoming message has already been JSON validated in receive_message_sync_gifts
            // check for some fatal errors before processing request_comments message
            // 1) cids must be unique
            var error = validate_request_comms_message(mailbox, msg, 'receive') ;
            if (error) {
                console.log(pgm + error + ', msg = ' + JSON.stringify(msg));
                mailbox.outbox.push({
                    mid: Gofreerev.get_new_uid(),
                    msgtype: 'error',
                    request_mid: msg.mid,
                    error: error
                });
                return;
            } // if error (validate_request_comms_message)

            var not_mutual_friends_cids = [] ; // array with cids - gift is not from mutual friends (mailbox.mutual_friends)
            var invalid_gift_cids =  [] ; // array with cids - gift is invalid and cannot be send to other client (requester) todo: send request_gifts request to correct error?
            var invalid_comment_cids = [] ; // array with cids - comment is invalid and cannot be send to other client (requester)
            var ok_cids = [] ; // array with cids - comment found and added to send_gifts sub message
            var unknown_cids = [] ; // array with cids - commment not found

            var send_gifts_sub_message = {
                mid: Gofreerev.get_new_uid(),
                msgtype: 'send_gifts',
                gifts: [],
                users: []
            };
            var send_gifts_users = [] ;
            var gid_to_send_gifts_index = {}; // from gid to index in send_gifts_sub_message.gifts array

            // find gifts and comments and validate message. Gifts (giver/receiver) must be from mutual friends (mailbox.mutual_friends)
            var i, gift, gid, j, comment, cid, in_mutual_friends, k, user_id, index, gift_clone, error, comment_clone ;
            for (i=0 ; i<gifts.length ; i++) {
                gift = gifts[i] ; // xxx
                gid = gift.gid ;
                if (!gift.hasOwnProperty('comments') || (gift.comments.length == 0)) continue ;
                for (j=0; j<gift.comments.length ; j++) {
                    comment = gift.comments[j] ;
                    cid = comment.cid ;
                    if (msg.comments.indexOf(cid) == -1) continue ;

                    // comment was found. clone commment and validate. don't send invalid comments to other client
                    comment_clone = make_comment_clone(comment) ;
                    error = invalid_comment(comment_clone, [], 'send', mailbox.server_id) ;
                    if (error) {
                        console.log(pgm + 'Warning. Invalid comment was not added to send_gifts sub message.') ;
                        console.log(pgm + 'Comment ' + comment_clone.cid + ': ' + JSON.stringify(comment_clone));
                        console.log(pgm + 'Error message: ' + error) ;
                        invalid_comment_cids.push(gid) ;
                        continue ;
                    };

                    // check if gift is from a mutual friend
                    in_mutual_friends = false ;
                    if (gift.hasOwnProperty('giver_user_ids')) {
                        for (k=0 ; k<gift.giver_user_ids.length ; k++) {
                            user_id = gift.giver_user_ids[k] ;
                            if (mailbox.mutual_friends.indexOf(user_id) != -1) in_mutual_friends = true ;

                        } // for k
                    }; // if
                    if (gift.hasOwnProperty('receiver_user_ids')) {
                        for (k=0 ; k<gift.receiver_user_ids.length ; k++) {
                            user_id = gift.receiver_user_ids[k] ;
                            if (mailbox.mutual_friends.indexOf(user_id) != -1) in_mutual_friends = true ;

                        } // for k
                    }; // if
                    if (!in_mutual_friends) {
                        not_mutual_friends_cids.push(cid) ;
                        continue ;
                    };

                    // gift is from a mutual friend. find or clone gift for send_gifts message
                    if (gid_to_send_gifts_index.hasOwnProperty(gid)) {
                        // gift already in send_gifts sub message
                        index = gid_to_send_gifts_index[gid] ;
                        gift_clone = send_gifts_sub_message.gifts[index] ;
                    }
                    else {
                        // add gift to send_gifts sub message
                        // clone gift for send_gifts sub message
                        // clone gift - some interval properties are not replicated to other devices
                        // todo: 1 - change like from boolean to an array  with user ids and like/unlike timestamps for merge operation
                        // todo: 2 - add server side sha256_deleted signature to gift. Server could validate client_deleted_at and know that gift has been deleted
                        // todo: 3 - add url with optional file attachment (file upload has not been implemented yet)
                        // todo: 4 - clone user id arrays if sending gift to other gofreerev server (user id is replaced with sha256 signature)
                        // todo: refactor clone gift operation.
                        gift_clone = make_gift_clone(gift) ;
                        // validate gift_clone before adding to send_gifts sub message
                        error = invalid_gift(gift_clone, [], 'send', mailbox) ;
                        if (error) {
                            console.log(pgm + 'Warning. Invalid gift was not added to send_gifts sub message.') ;
                            console.log(pgm + 'Gift ' + gift_clone.gid + ': ' + JSON.stringify(gift_clone));
                            console.log(pgm + 'Error message: ' + error) ;
                            invalid_gift_cids.push(cid) ;
                            continue ;
                        };
                        // save relevant userids in gift_users buffer
                        add_user_ids_to_array(gift.giver_user_ids, send_gifts_users, false) ;
                        add_user_ids_to_array(gift.receiver_user_ids, send_gifts_users, false) ;
                        // add gift to send gifts message
                        gid_to_send_gifts_index[gid] = send_gifts_sub_message.gifts.length ;
                        send_gifts_sub_message.gifts.push(gift_clone) ;
                    }; // if

                    // add comment clone
                    if (!gift_clone.hasOwnProperty('comments')) gift_clone.comments = [] ;
                    gift_clone.comments.push(comment_clone) ;
                    // save relevant userids in gift_users buffer
                    add_user_ids_to_array(comment_clone.user_ids, send_gifts_users, false) ;
                    add_user_ids_to_array(comment_clone.new_deal_action_by_user_ids, send_gifts_users, false) ;
                    ok_cids.push(cid) ;
                }; // for j (comments)
            }; // for i (gifts)

            unknown_cids = $(msg.comments).not(ok_cids).not(not_mutual_friends_cids).not(invalid_gift_cids).not(invalid_comment_cids).get() ;
            console.log(pgm + 'request_comments        = ' + msg.comments.join(', ')) ;
            console.log(pgm + 'ok_cids                 = ' + ok_cids.join(', ')) ;
            if (not_mutual_friends_cids.length > 0) console.log(pgm + 'not_mutual_friends_cids = ' + not_mutual_friends_cids.join(', ')) ;
            if (invalid_gift_cids.length > 0) console.log(pgm + 'invalid_gift_cids       = ' + invalid_gift_cids.join(', ')) ;
            if (invalid_comment_cids.length > 0) console.log(pgm + 'invalid_comment_cids    = ' + invalid_comment_cids.join(', ')) ;
            if (unknown_cids.length > 0) console.log(pgm + 'unknown_cids            = ' + unknown_cids.join(', ')) ;

            if (ok_cids.length == 0) {
                // errors in request comments request. No valid cid's was found.
                var errors = [] ;
                if (not_mutual_friends_cids.length > 0) errors.push('not_mutual_friends_cids = ' + not_mutual_friends_cids.join(', ')) ;
                if (invalid_gift_cids.length > 0) errors.push('invalid_gift_cids       = ' + invalid_gift_cids.join(', ')) ;
                if (invalid_comment_cids.length > 0) errors.push('invalid_comment_cids    = ' + invalid_comment_cids.join(', ')) ;
                if (unknown_cids.length > 0) errors.push('unknown_cids            = ' + unknown_cids.join(', ')) ;
                error = 'Errors in sync_gifts/request_comments sub message. ' + errors.join(', ') ;
                console.log(pgm + error + ', msg = ' + JSON.stringify(msg));
                mailbox.outbox.push({
                    mid: Gofreerev.get_new_uid(),
                    msgtype: 'error',
                    request_mid: msg.mid,
                    error: error
                });
                return;
            } ;
            if (not_mutual_friends_cids.length + invalid_gift_cids.length + invalid_comment_cids.length + unknown_cids.length > 0) {
                console.log(pgm + 'Warning. Ignoring invalid cids ' +
                    not_mutual_friends_cids.concat(invalid_gift_cids).concat(invalid_comment_cids).concat(unknown_cids).join(', ') +
                    ' in incoming request_comments message. Only valid comments ' + ok_cids.join(', ') +
                    ' are included in outgoing send_gifts message') ;
            } ;
            console.log(pgm + 'send_gifts_sub_message  = ' + JSON.stringify(send_gifts_sub_message)) ;

            // todo: DRY. also used in gifts_sha256 message and ...
            // add relevant users to send_gifts message - used as fallback information in case of "unknown user" error on receiving client
            var user ;
            for (j=0 ; j<send_gifts_users.length ; j++) {
                user_id = send_gifts_users[j] ;
                if (mailbox.mutual_friends.indexOf(user_id) != -1) continue ; // dont include mutual friends in send_gifts.users array
                user = userService.get_friend(user_id) ;
                // if (!user) console.log(pgm + 'Warning. Unknown friend user_id ' + user_id) ;
                if (!user) user = userService.get_user(user_id) ; // fallback to "old" stored user info
                if (!user) console.log(pgm + 'Error. Cannot add user info for unknown user_id ' + user_id) ;
                send_gifts_sub_message.users.push({
                    user_id: user.user_id,
                    uid: user.uid,
                    provider: user.provider,
                    user_name: user.user_name,
                    api_profile_picture_url: user.api_profile_picture_url
                }) ;
            } // for j (gift_users)

            var sync_gifts_message = {
                mid: Gofreerev.get_new_uid(), // envelope mid
                request_mid: msg.mid,
                msgtype: 'sync_gifts',
                mutual_friends: Gofreerev.clone_array(msg.mutual_friends), // subset of mutual friends - from original sync gift message
                send_gifts: send_gifts_sub_message, // optional sub message 1)
            };

            // translate user ids and server_ids before sending outgoing remote sync_gifts message to client on other Gofreerev server
            // ids are translated to sha256 signatures when communicating with clients on other Gofreerev servers (mailbox.server_id != null)
            // false: errors has already been written to log and send in a error message to other client
            if (!sync_gifts_translate_ids(msg, sync_gifts_message, mailbox)) return ;

            // JS validate sync_gifts message before placing message in outbox
            if (Gofreerev.is_json_message_invalid(pgm,sync_gifts_message,'sync_gifts','')) {
                // error message has already been written to log
                // send error message to other device
                json_error = JSON.parse(JSON.stringify(tv4.error));
                delete json_error.stack;
                json_errors = JSON.stringify(json_error) ;
                error = 'Could not process request_comments message. JSON schema validation error in sync_gifts response: ' + json_errors ;
                console.log(pgm + error + ' msg = ' + JSON.stringify(msg)) ;
                mailbox.outbox.push({
                    mid: Gofreerev.get_new_uid(),
                    request_mid: msg.mid,
                    msgtype: 'error',
                    request_mid: msg.mid,
                    error: error
                }) ;
                return ;
            }

            // check sync_gifts message for logical errors before placing message in outbox

            // 1) check sub message send_gifts for logical errors
            if (sync_gifts_message.send_gifts) {
                // logical validate send_gifts sub messsage before sending sync_gifts message
                error = validate_send_gifts_message(mailbox, sync_gifts_message.send_gifts, 'send') ;
                if (error) {
                    var error = 'Could not process request_comments message. Logical error in sync_gifts response (send_gifts sub message) : ' + error ;
                    console.log(pgm + error + ' msg = ' + JSON.stringify(msg)) ;
                    mailbox.outbox.push({
                        mid: Gofreerev.get_new_uid(),
                        request_mid: msg.mid,
                        msgtype: 'error',
                        request_mid: msg.mid,
                        error: error
                    }) ;
                    return ;
                }
            }

            // send sync_gifts message
            mailbox.outbox.push(sync_gifts_message) ;

        }; // receive_message_request_comms


        // receive encrypted messages from other devices
        // - process rsa password message
        // - save symmetric decrypted messages in inbox for process_messages function
        var receive_messages = function (response) {
            var pgm = service + '.receive_messages: ' ;
            // console.log(pgm + 'receive ' + JSON.stringify(response)) ;
            if (response.error) {
                console.log(pgm + 'Error when sending and receiving messages. ' + response.error) ;
                if (!response.messages) return ;
            }
            var encrypt, prvkey ;
            var msg_server_envelope, key, index, mailbox, did, device, msg, msg_csv_rsa_enc, msg_csv, msg_json_sym_enc, msg_client_envelope ;
            var decrypted_key, symmetric_password ;
            // move any temporary parked symmetric encrypted messages to response.messages array
            // ( symmetric encrypted message received before symmetric password setup was completed )
            while (unencrypted_messages.length > 0) {
                msg_server_envelope = unencrypted_messages.shift() ;
                response.messages.push(msg_server_envelope) ;
            }
            for (var i=0 ; i<response.messages.length ; i++) {
                msg_server_envelope = response.messages[i] ;
                key = msg_server_envelope.sender_did + msg_server_envelope.sender_sha256 ;
                if (!key_mailbox_index.hasOwnProperty(key)) {
                    console.log(pgm + 'Error. Ignoring message from device ' + msg_server_envelope.sender_did + ' with unknown key ' + key + '. message = ' + JSON.stringify(msg_server_envelope)) ;
                    continue ;
                };
                index = key_mailbox_index[key] ;
                mailbox = mailboxes[key_mailbox_index[key]] ;
                if (!mailbox) {
                    console.log(pgm + 'Error. Ignoring message from device '  + msg_server_envelope.sender_did + ' with unknown index ' + index + '. message = ' + JSON.stringify(msg_server_envelope)) ;
                    continue ;
                }
                did = mailbox.did ;
                device = devices[did] ;
                // console.log(pgm + 'did = ' + did  + ', device = ' + JSON.stringify(device)) ;
                if (!device || !device.pubkey) {
                    console.log(pgm + 'Error. Ignoring message from device '  + did + ' with key ' + key + '. Public key has not yet been received. Message = ' + JSON.stringify(msg_server_envelope)) ;
                    continue ;
                }

                // decrypt incoming message.
                // field msg_server_envelope.key is rsa encrypted and field msg_server_envelope.message is symmetric encrypted.
                // decrypt rsa part of message (key)
                if (!encrypt) {
                    encrypt = new JSEncrypt();
                    prvkey = Gofreerev.getItem('prvkey');
                    encrypt.setPrivateKey(prvkey);
                }
                decrypted_key = encrypt.decrypt(msg_server_envelope.key);
                symmetric_password = decrypted_key;

                // symmetric decrypt message
                msg_json_sym_enc = msg_server_envelope.message ;
                try {
                    msg_csv = Gofreerev.decrypt(msg_json_sym_enc, symmetric_password)
                }
                catch (err) {
                    console.log(pgm + 'Ignoring symmetric decrypt error ' + err.message) ;
                    continue ;
                }
                msg_client_envelope = JSON.parse(msg_csv) ;
                // console.log(pgm + 'sym decrypt: msg_json_sym_enc = ' + msg_json_sym_enc) ;
                // console.log(pgm + 'sym decrypt: msg_json = ' + msg_json) ;
                // console.log(pgm + 'sym decrypt: client msg = ' + JSON.stringify(msg_client_envelope)) ;
                if (!msg_client_envelope.messages || !msg_client_envelope.messages.length) {
                    console.log(pgm + 'Error. Ignoring message from device ' + did + '. Array with messages was not found. Client message = ' + JSON.stringify(msg_client_envelope)) ;
                    continue ;
                }
                // move new messages received from server to inbox
                while (msg_client_envelope.messages.length > 0) {
                    msg = msg_client_envelope.messages.shift() ;
                    mailbox.inbox.push(msg) ;
                } // while

            } // for i (one message from each device)
        }; // receive_messages

        // process decrypted messages in mailbox (inbox + read folders)
        var process_messages = function () {
            var pgm = service + '.process_messages: ';
            // loop for all mailbox and process any messages in 1) inbox and 2) read
            // any new "read" messages generated when processing inbox messages will be processed after next ping
            var i, mailbox, old_read_length, msg, did, key, device;
            for (i = 0; i < mailboxes.length; i++) { //x
                mailbox = mailboxes[i];
                if (mailbox.inbox.length + mailbox.read.length == 0) continue ;
                did = mailbox.did ;
                key = mailbox.key ;
                device = devices[did] ;
                // console.log(pgm + 'did = ' + did  + ', device = ' + JSON.stringify(device)) ;
                if (!device || !device.pubkey) {
                    console.log(pgm + 'Error. Ignoring messages from device '  + did + 'with key ' + key + '. Public key has not yet been received.') ;
                    continue ;
                }
                if (mailbox.read.length > 0) console.log(pgm + mailbox.read.length + ' messages was moved from mailbox.read to mailbox.inbox');
                while (mailbox.read.length > 0) {
                    msg = mailbox.read.shift();
                    mailbox.inbox.push(msg);
                }
                // process messages in inbox (old read from previous ping and new just received messages from this ping)
                while (mailbox.inbox.length > 0) {
                    msg = mailbox.inbox.shift();
                    console.log('-') ;
                    console.log('-') ;
                    switch (msg.msgtype) {
                        case 'users_sha256':
                            // communication step 2 - compare sha256 values for users (mutual friends)
                            receive_message_users_sha256(device, mailbox, msg);
                            break;
                        case 'gifts_sha256':
                            // communication step 3 - compare sha256 values for gifts (mutual friends)
                            receive_message_gifts_sha256(device, mailbox, msg);
                            break;
                        case 'sync_gifts':
                            // communication step 4 - receive message with 1-3 sub messages (send_gifts, request_gifts and check_gifts)
                            // verify that request_mid is correct and add sub messages to inbox
                            receive_message_sync_gifts(device, mailbox, msg);
                            break;
                        case 'send_gifts':
                            // communication step 4 - sub message from sync_gifts - receive missing gifts from other device
                            receive_message_send_gifts(device, mailbox, msg);
                            console.log(pgm + 'mailbox.read.length = ' + mailbox.read.length);
                            break;
                        case 'request_gifts':
                            // communication step 4 - sub message from sync_gifts - send missing gift to other device
                            receive_message_request_gifts(device, mailbox, msg);
                            break;
                        case 'check_gifts':
                            // communication step 4 - sub message from sync_gifts - check gifts sub sha256 values and return gift, comments or both
                            receive_message_check_gifts(device, mailbox, msg);
                            break;
                        case 'request_comments':
                            // communication step 4 - sub message from sync_gifts - return requested comments in a send_gifts message
                            receive_message_request_comms(device, mailbox, msg);
                            break;
                        case 'invalid_gifts':
                            // communication step 5 - sub message from sync_gifts - receive invalid gifts and error messages from send_gifts message processing
                            receive_message_invalid_gifts(device, mailbox, msg);
                            break ;
                        case 'invalid_comments':
                            // communication step 5 - sub message from sync_gifts - receive invalid comments and error messages from send_gifts message processing
                            receive_message_invalid_comms(device, mailbox, msg);
                            break ;
                        case 'error':
                            // error in client to client communication - print error in log and move previous message to error folder
                            receive_message_error(device, mailbox, msg);
                            break;
                        default:
                            console.log(pgm + 'Unknown msgtype ' + msg.msgtype + ' in inbox. msg = ' + JSON.stringify(msg));
                    } // end msgtype switch
                } // while msg in mailbox.inbox
            } // for i (one message from each device)
        }; // process_messages


        return {
            new_gift: new_gift,
            init_new_gift: init_new_gift,
            gifts: gifts,
            invalid_comment: invalid_comment,
            invalid_comment_change: invalid_comment_change,
            invalid_gift: invalid_gift,
            invalid_gift_change: invalid_gift_change,
            add_friends_to_users: add_friends_to_users,
            load_gifts: load_gifts,
            refresh_gift: refresh_gift,
            refresh_gift_and_comment: refresh_gift_and_comment,
            save_new_gift: save_new_gift,
            save_gift: save_gift,
            sync_gifts: sync_gifts,
            remove_old_errors: remove_old_errors,
            verify_gifts_add: verify_gifts_add,
            new_servers_request: new_servers_request,
            new_servers_response: new_servers_response,
            verify_gifts_request: verify_gifts_request,
            verify_gifts_response: verify_gifts_response,
            verify_comments_add: verify_comments_add,
            verify_comments_request: verify_comments_request,
            verify_comments_response: verify_comments_response,
            pubkeys_request: pubkeys_request,
            pubkeys_response: pubkeys_response,
            update_mailboxes: update_mailboxes,
            send_messages: send_messages,
            receive_messages: receive_messages,
            process_messages: process_messages,
            messages_sent: messages_sent,
            messages_not_sent: messages_not_sent
        };

        // end GiftService
    }]);
