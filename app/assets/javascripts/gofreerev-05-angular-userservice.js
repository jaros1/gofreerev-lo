// Gofreerev angularJS code

angular.module('gifts')
    .factory('UserService', ['TextService', 'NotiService', '$window', '$http', '$q', '$locale', function(textService, notiService, $window, $http, $q, $locale) {
        var self = this ;
        var service = 'UserService' ;
        console.log(service + ' loaded') ;

        // initialize list with providers. used in validations and in main/auth page
        var providers = [] ;
        (function () {
            var api_names = Gofreerev.rails['API_CAMELIZE_NAME'] ;
            for (var key in api_names) {
                if (api_names.hasOwnProperty(key)) {
                    providers.push(key) ;
                }
            }
            // console.log(service + ': providers = ' + JSON.stringify(providers)) ;
        })();

        // see navController.ping. keep track of client online/offline status ;
        var is_online = true ;

        // friends - downloaded from api friend list and saved temporary in local storage
        // ( see also users array - users used in gifts and comments permanently stored in local storage )
        var friends = [] ;
        var friends_index_by_user_id = {} ; // from internal user id to index in friends array
        var friends_index_by_sha256 = {} ; // from friend.sha256 to index in friends array (only friends on other Gofreerev servers)
        var friends_index_by_old_sha256 = {} ; // from friend.old_sha256 to index in friends array (only friends on other Gofreerev servers)

        var friends_sha256_last_updated ;

        var provider_stat = function (friends) {
            if (typeof friends == 'undefined') return '' ;
            if (friends == null) return '' ;
            if (friends.length == 0) return '' ;
            var hash = {} ;
            var i, friend, provider ;
            for (i=0 ; i<friends.length ; i++) {
                friend = friends[i] ;
                provider = friend.provider;
                if (!hash.hasOwnProperty(provider)) hash[provider] = { users: 0, friends: 0} ;
                hash[provider].users += 1 ;
                if (friend.friend <= 2) hash[provider].friends += 1 ;
            }
            var stat = '' ;
            for (provider in hash) {
                if (stat != '') stat = stat += ', ' ;
                stat += provider + ' ' + hash[provider].friends + ' (' + hash[provider].users + ')' ;
            }
            return stat ;
        }; // provider_stat

        // there must be minimum one friend for each logged in provider (friendlist downlist error)
        function check_friend_lists () {
            var pgm = service + '.check_friend_lists: ' ;
            var no_friends = get_oauth(), provider ;
            for (provider in no_friends) if (no_friends.hasOwnProperty(provider)) no_friends[provider] = 0 ;
            var i, friend ;
            for (i=0 ; i<friends.length ; i++) {
                friend = friends[i] ;
                if (!no_friends.hasOwnProperty(friend.provider)) no_friends[friend.provider] = -1 ; // not logged in with this provider
                else if (no_friends[friend.provider] >= 0) no_friends[friend.provider] += 1 ; // logged in
                else no_friends[friend.provider] -= 1 ; // not logged in
            }
            // todo: add notification if logged in and no friends for one or more providers. there must be a friend list download problem
            for (provider in no_friends) if (no_friends.hasOwnProperty(provider)) {
                if (no_friends[provider] == 0) console.log(pgm + 'Warning. No friend list was found for ' + provider) ;
                else if ((no_friends[provider] < 0) && (providers.indexOf(provider) == -1)) console.log(pgm + 'Error. Found friend list for unknown provider ' + provider) ;
            }
        } // check_friend_lists

        var remote_sha256_array_to_hash = function(remote_sha256_array) {
            var remote_sha256_hash = {}, i ;
            for (i=0 ; i<remote_sha256_array.length ; i++) remote_sha256_hash[remote_sha256_array[i].server_id] = remote_sha256_array[i].sha256 ;
            return remote_sha256_hash ;
        }; // remote_sha256_to_hash

        // init array with friends init.
        // initialized at page load and after device login with friend list for all login providers
        // params:
        // - array: friend list
        // - optional timestamp for last friend.sha256 update (server secret update). friend.old_sha256 is valid for 3 minutes after last friend.sha256 update
        var init_friends = function (array, friends_sha256_update_at) {
            var pgm = service + '.init_friends: ' ;
            // console.log(service + '.init_users: users = ' + JSON.stringify(array)) ;
            friends = array ;
            if (friends_sha256_update_at) friends_sha256_last_updated = friends_sha256_update_at ;
            friends_index_by_user_id = {};
            friends_index_by_sha256 = {} ;
            friends_index_by_old_sha256 = {} ;
            var i, friend, hash ;
            for (i=0 ; i<friends.length ; i++) {
                friend = friends[i] ;
                friends_index_by_user_id[friend.user_id] = i;
                // only friends on other Gofreerev servers.
                // sha256 and old_sha256 signatures is used when receiving messages from users on other Gofreerev servers
                if (friend.hasOwnProperty('sha256')) friends_index_by_sha256[friend.sha256] = i ;
                // old sha256 signatures. Valid for 1-2 minutes after changing server secret.
                // only relevant if secret was changed just before page load or api provider login (friend list downloads)
                if (friend.hasOwnProperty('old_sha256')) friends_index_by_old_sha256[friend.old_sha256] = i ;
                // remote_sha256 - only friends on remote servers - used when sending messages to other Gofreerev servers
                // make sure that remote_sha256 is a hash with server id as key
                if (friend.hasOwnProperty('remote_sha256') && (friend.remote_sha256.constructor == Array)) {
                    friend.remote_sha256 = remote_sha256_array_to_hash(friend.remote_sha256) ;
                }
            }
            console.log(pgm + 'friends = ' + JSON.stringify(friends)) ;
            check_friend_lists() ;
        }; // init_friends

        // refresh friends list in next ping? Used when receiving :refresh => true for one or more friends in short friend list in ping
        // server has detected out-of-date user info on this server in a incoming server to server message
        // client most send oauth info to server in next ping and refresh friends information
        self.refresh_friends_list = {} ;
        self.refresh_friends_list_nid = null ;

        // update friends js array: replace: true: overwrite/replace old friends, false: add/keep old friends
        // called from do_tasks after api and device login. new friend lists downloaded from api provider
        // friends_sha256_update_at == null : called from sync_friends (two or more identical logins in a browser)
        var update_friends = function (new_friends, replace, friends_sha256_update_at) {
            // new_friends is friends list returned from do_tasks / util.generic_post_login - executed at page startup and after api provider logins
            var pgm = service + '.update_friends: ' ;
            // console.log(pgm + 'new_friends = ' + JSON.stringify(new_friends)) ;
            var i ;
            if (friends_sha256_update_at) {
                // friend.sha256 updated within the last 3 minutes. friend.old_sha256 is valid for 3 minutes after friends_sha256_update_at
                if (friends_sha256_last_updated && (friends_sha256_last_updated < Gofreerev.unix_timestamp() - 180)) {
                    // blank old_sha256 before adding new friends info
                    for (i=0 ; i<friends.length ; i++) delete friends[i].old_sha256 ;
                }
                friends_sha256_last_updated = friends_sha256_update_at;
            }
            var extern_user_ids = {} ; // extern user id uid/provider - must be unique
            var extern_user_id ;
            for (i=0 ; i<friends.length ; i++) {
                extern_user_id = friends[i].uid + '/' + friends[i].provider ;
                if (extern_user_ids.hasOwnProperty(extern_user_id)) console.log(pgm + 'Error. Doublet extern user id ' + extern_user_id + ' in friends array.') ;
                else extern_user_ids[extern_user_id] = i ;
            }
            // update friends array with minimal changes (friends info is used in angularJS filters)
            // insert or update
            var refresh_index = false ;
            var new_friend, j, old_friend, remote_sha256 ;
            var refresh_provider = {} ; // provider => boolean. true if friend list for provider must be refresh in next ping
            for (i = 0; i < new_friends.length; i++) {
                new_friend = new_friends[i];
                // add download unix timestamp to friend info. not used in friends array but used in users array if friend user id is used in gifts or comments
                if (!new_friend.hasOwnProperty('verified_at')) new_friend.verified_at = Gofreerev.unix_timestamp();
                // refresh friend list in next ping? true if receiving refresh=true for one or more friends
                if (!refresh_provider.hasOwnProperty(new_friend.provider)) refresh_provider[new_friend.provider] = false ;
                if (new_friend.refresh) refresh_provider[new_friend.provider] = true ;
                // old or new friend?
                if (friends_index_by_user_id.hasOwnProperty(new_friend.user_id)) {
                    // old friend - update changed fields
                    j = friends_index_by_user_id[new_friend.user_id];
                    if ((friends[j].uid != new_friend.uid) || (friends[j].provider != new_friend.provider)) {
                        // error: unique extern user id cannot be updated (
                        console.log(
                            pgm + 'Error. Cannot update readonly fields in friend list. User id ' + user_id +
                            '. Old extern user id was ' + friends[j].uid + '/' + friends[j].provider +
                            '. New extern user id is ' + new_friend.uid + '/' + new_friend.provider + '.');
                        continue;
                    }
                    if (friends[j].user_name != new_friend.user_name) friends[j].user_name = new_friend.user_name;
                    if (friends[j].api_profile_picture_url != new_friend.api_profile_picture_url) {
                        friends[j].api_profile_picture_url = new_friend.api_profile_picture_url;
                    }
                    if (friends[j].friend != new_friend.friend) friends[j].friend = new_friend.friend;
                    // sha256 & old_sha256 - used when receiving messages from other gofreerev servers
                    if (friends[j].sha256 != new_friend.sha256) {
                        delete friends_index_by_sha256[friends[j].sha256] ;
                        friends[j].sha256 = new_friend.sha256;
                        friends_index_by_sha256[friends[j].sha256] = i ;
                    }
                    if (friends[j].old_sha256 != new_friend.old_sha256) {
                        if (friends[j].old_sha256) delete friends_index_by_old_sha256[friends[j].old_sha256] ;
                        friends[j].old_sha256 = new_friend.old_sha256;
                        if (friends[j].old_sha256) friends_index_by_old_sha256[friends[j].old_sha256] = i ;
                    }
                    // remote_sha256 - used when sending messages to other gofreerev servers
                    // make sure that remote_sha256 is a hash
                    if (new_friend.hasOwnProperty('remote_sha256')) {
                        remote_sha256 = new_friend.remote_sha256 ;
                        if (remote_sha256.constructor == Array) remote_sha256 = remote_sha256_array_to_hash(remote_sha256) ;
                        if (!friends[j].hasOwnProperty('remote_sha256')) friends[j].remote_sha256 = remote_sha256 ;
                        else if (JSON.stringify(remote_sha256) != JSON.stringify(friends[j].remote_sha256)) friends[j].remote_sha256 = remote_sha256 ;
                    }
                    else if (friends[j].hasOwnProperty('remote_sha256')) delete friends[j].remote_sha256 ;
                    if (friends[j].verified_at != new_friend.verified_at) friends[j].verified_at = new_friend.verified_at;
                }
                else {
                    // insert new friend
                    extern_user_id = new_friend.uid + '/' + new_friend.provider;
                    if (extern_user_ids.hasOwnProperty(extern_user_id)) {
                        console.log(pgm + 'Error. Ignoring new friend with doublet extern user id ' + extern_user_id + '.') ;
                        old_friend = friends[extern_user_ids[extern_user_id]] ;
                        console.log(pgm + 'old friend = ' + JSON.stringify(old_friend));
                        console.log(pgm + 'new friend = ' + JSON.stringify(new_friend));
                        continue ;
                    }
                    if (new_friend.hasOwnProperty('remote_sha256') && (new_friend.remote_sha256.constructor == Array)) {
                        new_friend.remote_sha256 = remote_sha256_array_to_hash(new_friend.remote_sha256) ;
                    }
                    extern_user_ids[extern_user_id] = friends.length ;
                    friends_index_by_user_id[new_friend.user_id] = friends.length;
                    friends_index_by_sha256[new_friend.sha256] = friends.length ;
                    friends_index_by_old_sha256[new_friend.old_sha256] = friends.length ;
                    friends.push(new_friend);
                    refresh_index = true;
                }
            } // for i (new_friends)
            if (replace) {
                // delete old friends
                var no_deleted = 0 ;
                var new_users_index_by_user_id = {} ;
                for (i=0 ; i<new_friends.length ; i++) new_users_index_by_user_id[new_friends[i].user_id] = i ;
                // var old_friend ;
                for (i=friends.length-1 ; i >= 0 ; i--) {
                    old_friend = friends[i] ;
                    if (!new_users_index_by_user_id.hasOwnProperty(old_friend.user_id)) {
                        friends.splice(i, 1);
                        no_deleted += 1 ;
                        refresh_index = true ;
                    }
                }
            }
            // refresh index
            if (refresh_index) {
                friends_index_by_user_id = {};
                for (i=0 ; i<friends.length ; i++) friends_index_by_user_id[friends[i].user_id] = i ;
            }
            Gofreerev.setItem('friends', JSON.stringify(friends)) ;
            console.log(pgm + 'friends = ' + JSON.stringify(friends)) ;
            // refresh friend lists?
            console.log(pgm + 'old refresh_friends_list = ' + JSON.stringify(self.refresh_friends_list)) ;
            var provider ;
            for (provider in self.refresh_friends_list) {
                if (!refresh_provider.hasOwnProperty(provider)) console.log(pgm + 'Error. Expected friend list was not received for ' + provider) ;
                else if (refresh_provider[provider] == false) {
                    console.log(pgm + 'Ok. received expected friend list for ' + provider) ;
                    delete self.refresh_friends_list[provider] ;
                    delete refresh_provider[provider] ;
                    // add notification
                    self.refresh_friends_list_nid = notiService.add_notification({
                            notitype: 'friend_list', key: 'updated', options: {provider: provider},
                            nid: self.refresh_friends_list_nid,
                            url:'todo: add angular user settings url'}) ;
                }
                else {
                    console.log(pgm + 'Error. Expected full friend list. Received short friend list with refresh = true for provider ' + provider) ;
                }
            } // for provider
            for (provider in refresh_provider) {
                if (!refresh_provider[provider]) continue ;
                if (self.refresh_friends_list.hasOwnProperty(provider)) continue ;
                self.refresh_friends_list[provider] = Gofreerev.unix_timestamp() ;
                console.log(pgm + 'update_friends call with refresh=true. new_friends = ' + JSON.stringify(new_friends)) ; // todo: remove - debugging doublet friend list download in testrun-43
            }
            console.log(pgm + 'new refresh_friends_list = ' + JSON.stringify(self.refresh_friends_list)) ;
            check_friend_lists() ;
        }; // update_friends


        // less that <n> milliseconds between util/ping for client_userid
        // there must be more than one browser tab open with identical client login
        // sync changes in users array in local storage with js users array
        var sync_friends = function () {
            var pgm = 'NavCtrl.sync_friends: ' ;
            var old_length = friends.length ;
            var old_stat = provider_stat(friends) ;
            var new_users = JSON.parse(Gofreerev.getItem('friends')) ;
            update_friends(new_users, true, null) ;
            var new_length = friends.length ;
            var new_stat = provider_stat(friends) ;
            //console.log(
            //    pgm + 'sync users. ' + (new_length-old_length) + ' users was inserted/deleted. ' +
            //    'old JS users = ' + old_length + ', new JS users = ' + new_length + '. ' +
            //    'there was ' + new_users.length + ' users in localstorage.') ;
            //// "UserService.ping: sync users. 0 users was inserted/deleted. old JS users = 108, new JS users = 108. there was 7 users in localstorage.
            //console.log(pgm + 'old stat: ' + old_stat) ;
            //console.log(pgm + 'new stat: ' + new_stat) ;
        }; // sync_friends


        var is_logged_in = function () {
            if (typeof friends == 'undefined') return false ;
            for (var i=0 ; i< friends.length ; i++ ) if (friends[i].friend == 1) return true ;
            return false ;
        };
        var client_userid = function() {
            var userid = Gofreerev.getItem('userid') ;
            if (typeof userid == 'undefined') return 0 ;
            if (userid == null) return 0 ;
            if (userid == '') return 0 ;
            userid = parseInt(userid) ;
            return userid ;
        };
        var client_secret = function() {
            if (client_userid() == 0) return null ;
            var secret = Gofreerev.getItem('secret') ;
            if (!secret) {
                secret = (Math.random() + 1).toString(10).substring(2,12) ;
                Gofreerev.setItem('secret', secret) ;
            }
            return secret ;
        };
        var is_logged_in_with_device = function () {
            var user_id = client_userid() ;
            // console.log('is_logged_in_with_device: user_id = ' + user_id) ;
            return (user_id > 0) ;
        };
        // get encrypted oauth hash from local storage - returns null if errors
        var get_oauth = function () {
            var pgm = service + '.get_oauth: ' ;
            // get old oauth
            var oauth_str = Gofreerev.getItem('oauth') ;
            var oauth ;
            if ((typeof oauth_str == 'undefined') || (oauth_str == null) || (oauth_str == '')) oauth = {} ;
            else oauth = JSON.parse(oauth_str) ;
            // console.log(pgm + 'oauth = ' + JSON.stringify(oauth)) ;
            return oauth ;
        }; // get_oauth
        var is_logged_in_with_provider = function (provider) {
            var pgm = service + '.is_logged_in_with_provider: ' ;
            if (typeof provider == 'undefined') return is_logged_in_with_device() ;
            if (provider == null) return is_logged_in_with_device() ;
            if (provider == 'gofreerev') return is_logged_in_with_device() ;
            var oauth = get_oauth() ;
            // console.log(pgm + 'oauth = ' + JSON.stringify(oauth)) ;
            // console.log(pgm + 'provider = ' + provider) ;
            var is_logged_in = oauth.hasOwnProperty(provider) ;
            // console.log(pgm + provider + ' = ' + is_logged_in) ;
            return is_logged_in ;
        };
        var no_friends = function () {
            if (!is_logged_in()) return false ;
            for (var i=0 ; i< friends.length ; i++ ) if (friends[i].friend == 2) return false ;
            return true ;
        };
        // friend lookup with internal user id
        var get_friend = function (user_id) {
            if (typeof friends == 'undefined') return null ;
            if (typeof user_id == 'undefined') return null ;
            var i = friends_index_by_user_id[user_id] ;
            if (typeof i == 'undefined') return null ;
            var friend = friends[i] ;
            if (!friend.short_user_name) {
                var user_name_a = friend.user_name.split(' ') ;
                if (user_name_a.length > 1) friend.short_user_name = user_name_a[0] +  ' ' + user_name_a[1].substr(0,1) ;
                else friend.short_user_name = friend.user_name ;
            }
            // if (user_id == 1016) console.log(service + '.get_friend: user = ' + JSON.stringify(user)) ;
            return friend ;
        };
        // friend lookup with sha256 signature. used when receiving messages from clients on other Gofreerev servers
        var get_friend_by_sha256 = function (sha256) {
            var pgm = service + '.get_friend_by_sha256: ' ;
            // console.log(pgm + 'friends_index_by_sha256 = ' + JSON.stringify(friends_index_by_sha256)) ;
            // console.log(pgm + 'sha256 = ' + sha256) ;
            if (typeof friends == 'undefined') {
                console.log(pgm + 'error: friends array is undefined') ;
                return null ;
            }
            if (typeof sha256 == 'undefined') {
                console.log(pgm + 'error. sha256 param is undefined') ;
                return null ;
            }
            var i = friends_index_by_sha256[sha256] ;
            if ((typeof i == 'undefined') && friends_sha256_last_updated && (friends_sha256_last_updated > Gofreerev.unix_timestamp()-300)) {
                // fallback option 1: system secret and friends sha256 signatures changed within the last 3 minutes
                // allow messages with old sha256 signatures to arrive with old signatures
                i = friends_index_by_old_sha256[sha256] ;
            }
            if (typeof i == 'undefined') {
                // add fallback actions for:
                // todo: a) receiving expired sha256 signature. secret changed on this server within last 1-2 minutes.
                //          accept messages sent from other Gofreerev server before secret change and arrived on this Gofreerev server after secret change
                //          must know timestamp for secret change on this Gofreerev server
                //          must know old friend.sha256 before secret change
                //          or ask other Gofreerev server to resend message with new sha256 signatures
                // todo: b) receiving new valid sha256 signature.
                //          secret has changed on this Gofreerev server but friend.sha256 still have old value
                //          must know timestamp for secret change on this Gofreerev server
                //          must request new friend.sha256 signature before processing incoming message
                // todo: c) client could resend messages in outbox after detecting secret change for other Gofreerev server
                //          ( changed friends.remote_sha256 signatures in mailboxes (ping friends response)
                //          messages in outbox have been sent but response have not yet been received
                //          messages are moved from outbox to done or error when response to outgoing message are received
                //          should also be a special error response with unknown sha256 signature flag
                //          client checks timestamp for secret change and resents old message with new she256 signatures
                console.log(pgm + 'friends_index_by_sha256 = ' + JSON.stringify(friends_index_by_sha256)) ;
                return null ;
            }
            var friend = friends[i] ;
            if (!friend.short_user_name) {
                var user_name_a = friend.user_name.split(' ') ;
                if (user_name_a.length > 1) friend.short_user_name = user_name_a[0] +  ' ' + user_name_a[1].substr(0,1) ;
                else friend.short_user_name = friend.user_name ;
            }
            // if (user_id == 1016) console.log(service + '.get_friend: user = ' + JSON.stringify(user)) ;
            return friend ;
        } ;
        var get_closest_friend = function (user_ids) {
            var pgm = service + '.get_closest_friend: ' ;
            // console.log(pgm + 'user_ids = ' + JSON.stringify(user_ids)) ;
            if (typeof friends == 'undefined') return null ;
            if (friends == null) return null ;
            if (friends.length == 0) return null ;
            if (typeof user_ids == 'undefined') return null ;
            if (user_ids == null) return null ;
            if (user_ids.length == 0) return null ;
            var closest_user = null ;
            var closest_user_friend_status = 9 ;
            var user ;
            for (var i=0 ; i<user_ids.length ; i++) {
                user = get_friend(user_ids[i]) ;
                // if (user) console.log(pgm + 'get_friend(' + user_ids[i] + ').friend = ' + user.friend) ;
                // else console.log(pgm + 'user with id ' + user_ids[i] + ' was not found') ;
                if (user && (user.friend < closest_user_friend_status)) {
                    closest_user = user ;
                    closest_user_friend_status = user.friend ;
                }
            }
            // if (closest_user) console.log(pgm + 'found user with user id ' + closest_user.user_id) ;
            // else console.log(pgm + 'closest user was not found') ;
            return closest_user ;
        }; // get_closest_friend
        var get_userids_friend_status = function (user_ids) {
            var user = get_closest_friend(user_ids) ;
            if (!user) return null ;
            return user.friend ;
        }; // get_userids_friend_status
        var get_login_users = function () {
            var pgm = service + '.get_login_users: ' ;
            var login_users = [] ;
            if (typeof friends == 'undefined') return login_users ;
            for (var i=0 ; i<friends.length ; i++) {
                if (friends[i].friend == 1) login_users.push(friends[i]) ;
            }
            // debug info
            //var text = 'length = ' + login_users.length ;
            //var user ;
            //for (var i=0 ; i<login_users.length ; i++) {
            //    user = login_users[i] ;
            //    text += ', ' + user.user_name + ' (' + user.user_id + ')' ;
            //}
            //console.log(pgm + text) ;
            return login_users ;
        };
        var get_login_userids = function () {
            var pgm = service + '.get_login_userids: ' ;
            if (typeof friends == 'undefined') return [] ;
            var userids = [] ;
            // console.log(pgm + 'users.length = ' + users.length) ;
            for (var i=0 ; i<friends.length ; i++) {
                // console.log(pgm + 'users[i] = ' + JSON.stringify(users[i])) ;
                // console.log(pgm + 'users[' + i + '].friend = ' + users[i].friend) ;
                if (friends[i].friend == 1) userids.push(friends[i].user_id) ;
            }
            // console.log(pgm + 'userids.length = ' + userids.length) ;
            return userids ;
        };
        // get default currency from locale. use for new user accounts. for example en-us => usd
        var get_default_currency = function () {
            var pgm = service + '.get_default_currency: ' ;
            var default_language = 'en' ;
            var default_currency = 'usd' ;
            var id = $locale.id ;
            var language = id ? id.substr(0,2) : default_language ;
            var currency = Gofreerev.rails['COUNTRY_TO_CURRENCY'][language] || default_currency ;
            if (Gofreerev.rails['ACTIVE_CURRENCIES'].indexOf(currency) == -1) currency = default_currency ;
            // console.log(pgm + '$locale.id = ' + id + ', language = ' + language + ', currency = ' + currency) ;
            return currency ;
        };
        var get_currency = function  () {
            var currency = Gofreerev.getItem('currency') ;
            if (currency) return currency ;
            currency = get_default_currency() ;
            Gofreerev.setItem('currency', currency) ;
            return currency ;
        };
        var find_giver = function (gift) {
            var giver, user, i ;
            for (i=0 ; i<gift.giver_user_ids.length ; i++) {
                user = get_friend(gift.giver_user_ids[i]) ;
                if (user) {
                    if (user.friend == 1) return user ; // giver is a login user
                    if (!giver) giver = user ;
                }
            }
            // giver is not a login in user
            return giver ;
        };
        var find_receiver = function (gift) {
            var receiver, user, i ;
            for (i=0 ; i<gift.receiver_user_ids.length ; i++) {
                user = get_friend(gift.receiver_user_ids[i]) ;
                if (user) {
                    if (user.friend == 1) return user ; // receiver is a login user
                    if (!receiver) receiver = user ;
                }
            }
            // receiver is not a login in user
            return receiver ;
        };

        // logout:
        // - null: device log out
        // - provider: provider log out (provider facebook,  google+, linkedin etc)
        // - *: log out all providers but keep device log in
        var logout = function (provider) {
            var pgm = service + '.logout: ' ;
            console.log(pgm + 'provider = ' + provider) ;
            var old_client_userid = client_userid() ;
            // console.log(pgm + 'debug 1') ;
            if ((typeof provider == 'undefined') || (provider == null) || (provider == 'gofreerev')) {
                // device log out = session log out - note that no local storage info are removed
                // console.log(pgm + 'debug 2') ;
                provider = null ;
                Gofreerev.removeItem('password') ;
                Gofreerev.removeItem('userid') ;
                Gofreerev.removeItem('sid') ;
                // giftService.load_gifts() ; // moved to AuthCtrl
            }
            else if (provider == '*') {
                console.log(pgm + 'Received "Not logged in" response from ping. Not logged in on server. Log out all providers on client.') ;
                friends = [] ;
                friends_index_by_user_id = {} ;
                Gofreerev.setItem('friends', JSON.stringify(friends)) ;
                save_oauth({}) ;
                self.expires_at = {} ;
                self.refresh_tokens = {} ;
                provider = null ;
            }
            else {
                // log in provider log out
                // remove users
                // console.log(pgm + 'debug 3') ;
                var old_length = friends.length ;
                var old_stat = provider_stat(friends) ;
                // console.log(pgm + 'removing ' + provider + ' users. old users.length = ' + users.length) ;
                for (var i=friends.length-1 ; i >= 0 ; i--) {
                    if (friends[i].provider == provider) {
                        // console.log(pgm + 'remove user ' + users[i].user_name + ' + with index ' + i) ;
                        friends.splice(i, 1);
                    }
                }
                friends_index_by_user_id = {} ;
                for (i=0 ; i<friends.length ; i++) friends_index_by_user_id[friends[i].user_id] = i ;
                var new_length = friends.length ;
                var new_stat = provider_stat(friends) ;
                console.log(pgm + 'removed ' + (new_length-old_length) + ' ' + provider + ' users. new users.length = ' + new_length) ;
                console.log(pgm + 'old stat: ' + old_stat) ;
                console.log(pgm + 'new stat: ' + new_stat) ;
                Gofreerev.setItem('friends', JSON.stringify(friends)) ;
                // remove provider from local encrypted oauth hash
                // console.log(pgm + 'debug 4') ;
                remove_oauth(provider) ;
            }; // if
            // update login userids in server session
            // console.log(pgm + 'debug 5') ;
            var logout_request = { client_userid: old_client_userid};
            if (provider) logout_request.provider = provider ;
            var json_errors ;
            if (json_errors=Gofreerev.is_json_request_invalid(pgm, logout_request, 'logout')) return $q.reject(json_errors) ;
            if (!is_online) console.log(pgm + 'todo: how to handle logout request when offline?') ;
            $http.post('/util/logout.json', logout_request)
                .then(function (response) {
                    console.log(pgm + 'logout ok = ' + JSON.stringify(response)) ;
                    if (response.data.error) console.log(pgm + 'logout error = ' + response.data.error) ;
                    // validate logout response received from server (should only be error message)
                    var json_errors ;
                    if (json_errors=Gofreerev.is_json_response_invalid(pgm, response.data, 'logout', '')) return $q.reject(json_errors) ;
                },
                function (error) {
                    console.log(pgm + 'logout error = ' + JSON.stringify(error)) ;
                    return $q.reject(JSON.stringify(error)) ;
                }) ;
        }; // logout

        // test data - users - todo: receive array with users after login (login users and friends)
        // friend:
        //   1) logged in user         - show detailed info + clickable user div
        //   2) mutual friends         - show detailed info + clickable user div
        //   3) follows (F)            - show few info + clickable user div
        //   4) stalked by (S)         - show few info + clickable user div
        //   5) deselected api friends - show few info + not clickable user div
        //   6) friends of friends     - show few info + not clickable user div
        //   7) friends proposals      - not clickable user div
        //   8) others                 - not clickable user div
        //   9) unknown user           - not clickable user div
        var test_users = [{
            user_id: 920,
            provider: 'facebook',
            user_name: 'Jan Roslind',
            balance: null,
            api_profile_picture_url: 'https://fbcdn-profile-a.akamaihd.net/hprofile-ak-xpf1/v/t1.0-1/p100x100/996138_4574555377673_8850863452088448507_n.jpg?oh=2e909c6d69752fac3c314e1975daf583&oe=5502EE27&__gda__=1426931048_182d748d6d46db7eb51077fc36365623',
            friend: 1, // me=logged in user
            currency: 'DKK'
        },
            {
                user_id: 791,
                provider: 'linkedin',
                user_name: 'Jan Roslind',
                balance: null,
                api_profile_picture_url: 'https://media.licdn.com/mpr/mprx/0_527SxeD4nB0V6Trf5HytxIfNnPeU6XrfFIU-xIuWWnywJ8F7doxTAw4bZjHk5iAikfSPKuYGV9tQ',
                friend: 2, // friend of logged in user
                currency: 'DKK'
            },
            {
                user_id: 998,
                provider: 'instagram',
                user_name: 'gofreerev gofreerev',
                balance: null,
                api_profile_picture_url: 'https://instagramimages-a.akamaihd.net/profiles/profile_1092213433_75sq_1392313136.jpg',
                friend: 1, // me=logged in user
                currency: 'DKK'
            }
        ] ;
        // load users from local storage or test users array
        // init_users(JSON.parse(Gofreerev.getItem('friends')) || test_users) ;
        // console.log(service + ': getItem("friends") = ' + Gofreerev.getItem('friends')) ;
        if (Gofreerev.getItem('friends')) init_friends(JSON.parse(Gofreerev.getItem('friends')), null) ;
        else Gofreerev.setItem('friends', JSON.stringify([])) ;

        var save_oauth = function (oauth) {
            var pgm = service + '.save_oauth: ' ;
            // console.log(pgm + 'debug 1') ;
            // encrypt and save updated oauth
            var oauth_str = JSON.stringify(oauth) ;
            // console.log(pgm + 'oauth_str = ' + oauth_str) ;
            Gofreerev.setItem('oauth', oauth_str) ;
            // console.log(pgm + 'debug 3') ;
        };

        // cache some oauth information - used in ping
        self.expires_at = {} ; // unix timestamps for oauth access tokens
        self.refresh_tokens = {} ; // true/false - only used for google+ offline access
        var cache_oauth_info = function () {
            var pgm = service + 'cache_oauth_info. ' ;
            var oauth = get_oauth() ;
            for (var provider in oauth) {
                if (!oauth.hasOwnProperty(provider)) continue ;
                // todo: remove after debug
                if ((typeof provider == 'undefined') || (provider == null) || (provider == 'undefined')) {
                    console.log(pgm + 'error in oauth hash. oauth = ' + JSON.stringify(oauth)) ;
                    delete oauth[provider] ;
                    save_oauth(oauth) ;
                    continue ;
                }
                self.expires_at[provider] = oauth[provider].expires_at ;
                self.refresh_tokens[provider] = oauth[provider].hasOwnProperty('refresh_token') ;
            }
        }; // init_expires_at
        cache_oauth_info() ;

        // save oauth received from server into oauth in local storage
        // oauth authorization are stored on server and in client (encrypted with passwords stored in client)
        var add_oauth = function (new_oauth) {
            var pgm = service + '.add_oauth: ' ;
            // console.log(pgm + 'oauth = ' + JSON.stringify(new_oauth)) ;
            var oauth = get_oauth() ;
            if (oauth == null) {
                console.log(pgm + 'old oauth was not found. see previous error. new oauth was not added') ;
                return ;
            }
            // merge new oauth into current oauth - loop for each login provider
            for (var key in new_oauth) if (new_oauth.hasOwnProperty(key)) {
                if (providers.indexOf(key) == -1) {
                    // todo: find invalid call
                    console.log(pgm + 'invalid provider ' + key + ' in add_oauth call.') ;
                    continue ;
                }
                oauth[key] = new_oauth[key] ;
                // cache some information for quick access in ping operation
                self.expires_at[key] = oauth[key].expires_at ;
                self.refresh_tokens[key] = oauth[key].hasOwnProperty('refresh_token') ;
            }
            save_oauth(oauth) ;
            console.log(pgm + 'expires_at = ' + JSON.stringify(self.expires_at) + ', refresh_tokens = ' + JSON.stringify(self.refresh_tokens)) ;
        }; // add_oauth

        // remove provider from oauth hash.
        var remove_oauth = function (provider) {
            var pgm = service + '.remove_oauth: ' ;
            console.log(pgm + 'provider = ' + provider) ;
            // console.log(pgm + 'debug 1') ;
            var oauth = get_oauth() ;
            // console.log(pgm + 'debug 2') ;
            if (oauth == null) {
                console.log(pgm + 'old oauth was not found. see previous error. oauth was not changed') ;
                return ;
            }
            // remove provider and save
            // console.log(pgm + 'debug 3') ;
            console.log(pgm + 'before: hasOwnProperty[' + provider + '] = ' + oauth.hasOwnProperty(provider)) ;
            delete oauth[provider] ;
            console.log(pgm + 'after : hasOwnProperty[' + provider + '] = ' + oauth.hasOwnProperty(provider)) ;
            // console.log(pgm + 'debug 4') ;
            save_oauth(oauth) ;
            // console.log(pgm + 'debug 5') ;
            // update unencrypted has with expires_at timestamps
            delete self.expires_at[provider] ;
            delete self.refresh_tokens[provider] ;
            // console.log(pgm + 'debug 6') ;
            console.log(pgm + 'expires_at = ' + JSON.stringify(self.expires_at) + ', refresh_tokens = ' + JSON.stringify(self.refresh_tokens)) ;
        }; // remove_oauth

        // process expired tokens response - used in login and ping response processing
        var expired_tokens_response = function (expired_tokens, context) {
            var pgm = 'expired_tokens_response: ' ;
            if (!expired_tokens) return ;
            var provider, i ;
            for (i=0 ; i<expired_tokens.length ; i++) {
                provider = expired_tokens[i] ;
                if ((provider == 'google_oauth2') && (context == 'ping')) {
                    // send google+ refresh token to server in next ping (refresh_tokens_request)
                    console.log(pgm + 'send google+ refresh token to server in next refresh_tokens_request') ;
                    self.expires_at[provider] = self.expires_at[provider] - 24*60*60 ; // expired one day ago
                }
                else {
                    console.log(pgm + 'log off for ' + provider + '. access token was expired') ;
                    remove_oauth(provider) ;
                }
            }
        }; // expired_tokens_response

        // convert oauth hash/array - saved as hash but sent/received (json) as array
        var oauth_array_to_hash = function (oauth_array) {
            var oauth, oauth_hash = {} ;
            for (var i=0 ; i<oauth_array.length ; i++) {
                oauth = oauth_array[i] ;
                oauth_hash[oauth.provider] = oauth ;
                delete oauth_hash[oauth.provider].provider ;
            }
            return oauth_hash ;
        }; // oauth_array_to_hash
        var oauth_hash_to_array = function (oauth_hash) {
            var oauth, oauth_array = [] ;
            for (var provider in oauth_hash) {
                if (!oauth_hash.hasOwnProperty(provider)) continue ;
                oauth = oauth_hash[provider] ;
                oauth.provider = provider ;
                oauth_array.push(oauth) ;
            }
            return oauth_array ;
        }; // oauth_hash_to_array

        // process oauths array response - used in login and ping response processing
        var oauths_response = function (oauth_array) {
            var pgm = 'oauths_response: ' ;
            if (!oauth_array) return ;
            if ((oauth_array.length == 1) && (oauth_array[0].provider == 'google_oauth2') && (!oauth_array[0].refresh_token)) {
                // received a dummy google+ oauth token from server ping
                // must be failed attempt to renew google+ refresh token on server
                // see rails: application_controller.check_expired_tokens
                console.log(pgm + 'Refreshed dummy google+ oauth from server') ;
                console.log(pgm + 'oauth_array = ' + JSON.stringify(oauth_array)) ;
                remove_oauth('google_oauth2') ;
                return ;
            }

            // convert from array to an hash before calling add_oauth
            console.log(pgm + 'oauth_array = ' + JSON.stringify(oauth_array)) ;
            var oauth_hash = oauth_array_to_hash(oauth_array) ;
            console.log(pgm + 'oauth_hash = ' + JSON.stringify(oauth_hash)) ;
            add_oauth(oauth_hash) ;

        }; // oauths_response
        
        // after local login - send local oauth to server
        // server checks tokens and inserts tokens into server session (encrypted in session table and secret in session cookie)
        var send_oauth = function () {
            var pgm = service + '.send_oauth: ' ;
            // console.log(pgm + 'oauth = ' + JSON.stringify(new_oauth)) ;
            // get client_userid and password for current local login
            var userid = client_userid() ;
            if (userid == 0) {
                console.log(pgm + 'device userid was not found. oauth was not saved') ;
                return ;
            }
            // get old oauth
            var oauth_str = Gofreerev.getItem('oauth') ;
            //if ((typeof oauth_str == 'undefined') || (oauth_str == null) || (oauth_str == '') || (oauth_str == '{}')) {
            //    console.log(pgm + 'no oauth to send to server') ;
            //    return $q.reject('') ; // empty promise error response
            //}
            // null oauth is allowed. did, client_secret and public key are sent to server after device login
            var oauth ;
            if ((typeof oauth_str == 'undefined') || (oauth_str == null) || (oauth_str == '') || (oauth_str == '{}')) oauth = null;
            else oauth = oauth_hash_to_array(JSON.parse(oauth_str)) ;
            // send oauth hash (authorization for one or more login providers) to server
            // oauth authorization is validated on server by fetching fresh friends info (api_client.gofreerev_get_friends)
            var login_request = {
                client_userid: userid,
                client_secret: client_secret(),
                client_timestamp: (new Date).getTime(),
                oauths: oauth,
                did: Gofreerev.getItem('did'),
                pubkey: Gofreerev.getItem('pubkey')} ;
            // validate json login request before sending request to server
            var json_errors ;
            if (json_errors=Gofreerev.is_json_request_invalid(pgm, login_request, 'login')) return $q.reject(json_errors) ;
            console.log(pgm + 'login_request = ' + JSON.stringify(login_request)) ;
            if (!is_online) console.log(pgm + 'todo: how to handle login request when offline. should disable login button until online.') ;
            return $http.post('/util/login.json', login_request)
                .then(function (response) {
                    // console.log(pgm + 'post login response = ' + JSON.stringify(response)) ;
                    if (response.data.error) {
                        console.log(pgm + 'post login error = ' + response.data.error) ;
                        return $q.reject(response.data.error) ;
                    }
                    // validate login response received from server
                    var json_errors ;
                    if (json_errors=Gofreerev.is_json_response_invalid(pgm, response.data, 'login', '')) return $q.reject(json_errors) ;
                    // check expired access token (server side check)
                    if (response.data.expired_tokens) expired_tokens_response(response.data.expired_tokens, 'login') ;
                    // check for new oauth authorization (google+ only)
                    if (response.data.oauths) oauths_response(response.data.oauths) ;
                    // check users array
                    if (response.data.friends) {
                        // fresh user info array was received from server
                        console.log(pgm + 'ok response. friends = ' + JSON.stringify(response.data.friends)) ;
                        // insert relevant user info info js array
                        init_friends(response.data.friends, response.data.friends_sha256_update_at) ;
                        // save in local storage
                        // todo: note that users array can by big and maybe have to be stripped for irrelevant users
                        Gofreerev.setItem('friends', JSON.stringify(response.data.friends)) ;
                    }
                    // promise - continue with success or error?
                    if (response.data.error || !response.data.friends) return $q.reject(response.data.error || 'No friend lists was downloaded') ;
                },
                function (error) {
                    console.log(pgm + 'post login error = ' + JSON.stringify(error)) ;
                    return $q.reject(JSON.stringify(error)) ;
                }) ;

        }; // send_oauth

        // send_oauth array in ping for friend list update
        // used after detection out-of-date user info in incoming server to server message
        // client must update friend list to bring user info up-to-date for server to server communication
        // todo: add user notification when friend list update is started from server
        // todo: add user setting. allow/prevent friend list update requested by server
        var refresh_friends_list_request = function () {
            var pgm = service + '.refresh_friends_list_request: ' ;
            if (Object.keys(self.refresh_friends_list).length == 0) return null ;
            console.log(pgm + 'refresh_friends_list = ' + JSON.stringify(self.refresh_friends_list)) ;
            // get oauth
            var oauth_str = Gofreerev.getItem('oauth') ;
            var oauth_hash = JSON.parse(oauth_str) ;
            // convert to array. but only providers in refresh_friend_list hash
            var oauth, oauth_array = [] ;
            for (var provider in self.refresh_friends_list) {
                if (!oauth_hash.hasOwnProperty(provider)) {
                    console.log(pgm + 'Error. Cannot refresh friend list for not logged in provider ' + provider) ;
                    continue;
                }
                oauth = oauth_hash[provider] ;
                oauth.provider = provider ;
                oauth_array.push(oauth) ;
            };
            if (oauth_array.length == 0) return null ;
            return oauth_array ;
        }; // refresh_friends_list_request

        var check_logged_in_providers = function (now) {
            var logged_in_provider = false; // true if one not expired api login
            var expired_providers = []; // array with any expired login providers
            var refresh_tokens_request; // array with refresh token (google+ only)

            // console.log(pgm + 'time = ' + (new Date()).toUTCString());
            // console.log(pgm + 'self.expires_at = ' + JSON.stringify(self.expires_at) + ', refresh_tokens = ' + JSON.stringify(self.refresh_tokens)) ;
            var oauth;
            for (var provider in self.expires_at) {
                if (!self.expires_at.hasOwnProperty(provider)) continue;
                if (self.expires_at[provider] > now) logged_in_provider = true;
                else if (self.refresh_tokens[provider]) {
                    // google+ - access token expired but can maybe be renewed on server with refresh token
                    logged_in_provider = true;
                    // add refresh token in next ping request
                    if (!refresh_tokens_request) refresh_tokens_request = [];
                    if (!oauth) oauth = get_oauth();
                    refresh_tokens_request.push({
                        provider: '' + provider,
                        refresh_token: oauth[provider].refresh_token
                    });
                } // special refresh token for google+
                else expired_providers.push(provider);
            }
            for (var i = 0; i < expired_providers.lenghth; i++) {
                provider = expired_providers[i];
                console.log(pgm + 'log off for ' + provider + '. access token was expired');
                remove_oauth(provider);
            }
            return {
                logged_in_provider: logged_in_provider,
                refresh_tokens_request: refresh_tokens_request
            };
        }; // check_logged_in_providers

        // convert an array of internal user ids to an array of external user ids
        // return null if unknown user ids in input array
        var get_external_user_ids = function (internal_user_ids) {
            var pgm = service + '.get_external_user_ids: ' ;
            if (typeof internal_user_ids == 'undefined') return null ;
            if (internal_user_ids == null) return null ;
            if (internal_user_ids.length == 0) return [] ;
            var external_user_ids = [], user, internal_user_id, external_user_id ;
            for (var i=0 ; i<internal_user_ids.length ; i++) {
                internal_user_id = internal_user_ids[i] ;
                user = get_friend(internal_user_id) ;
                if (!user) {
                    console.log(pgm + 'Warning. Unknown internal user id ' + internal_user_id) ;
                    return null ; // should force an error in calling routine
                }
                external_user_id = user.uid + '/' + user.provider ;
                if (external_user_ids.indexOf(external_user_id) != -1) console.log(pgm + 'Warning. Doublet user ids in ' + internal_user_ids.join(', ') + '.') ;
                else external_user_ids.push(external_user_id) ;
            }
            return external_user_ids ;
        }; // get_external_user_ids ;

        // before send msg to other Gofreerev server. replace internal user ids with remote sha256 signatures from friends
        // internal user ids = mailbox.mutual_friends = ping.user_ids = mutual_friends from ping online users response
        // remote sha256 signatures from friends.remote_sha256 hash (from short friends list returned from ping)
        // params:
        // - user_ids - input/output - replace internal user ids with remote sha256 signature. please use array clone to prevent change of original array
        // - array_name - name of user_ids array for debug and error messages
        // - server_id - from mailbox - used must have a remote sha256 signature on server_id
        // - msg - message for debug information
        // - force - false: raise error for unknown remote sha256 - true: use negative user id for unknown remote sha256
        // returns nil (ok) or an error message
        var user_ids_to_remote_sha256 = function (user_ids, array_name, server_id, msg, force) {
            var pgm = service + '.user_ids_to_remote_sha256: ' ;
            if ((typeof user_ids == 'undefined') || (user_ids == null)) return null ; // null array ok (receiver_user_ids, new_deal_action_by_user_ids etc)
            console.log(pgm + array_name + ' = ' + JSON.stringify(user_ids) + ', typeof user_ids = ' + typeof user_ids) ; // todo: remove debugging
            var remote_sha256_values = [] ;
            var i, user_id, friend, remote_sha256, error ;
            for (i=0 ; i<user_ids.length ; i++) {
                user_id = user_ids[i] ;
                if (typeof user_id != 'number') {
                    error = 'System error in user_ids_to_remote_sha256. ' + array_name + ' must be an array of integers' ;
                    console.log(pgm + error) ;
                    console.log(pgm + 'user_ids = ' + JSON.stringify(user_ids)) ;
                    console.log(pgm + 'msg     = ' + JSON.stringify(msg)) ;
                    var x = 1 / 0 ; // stack dump
                    return error ;
                }
                friend = get_friend(user_id) ;
                if (!friend && force) friend = get_user(user_id) ;
                if (!friend) {
                    error = 'System error in user_ids_to_remote_sha256. Cannot send ' + msg.msgtype + ' to other Gofreerev server. Error in ' + array_name + '. Friend with user id ' + user_id + ' was not found' ;
                    console.log(pgm + error) ;
                    console.log(pgm + 'msg     = ' + JSON.stringify(msg)) ;
                    return error ;
                }
                if ((user_id < 0) && force) {
                    // already using negative user id for unknown user received from other Gofreerev server
                    console.log(pgm + 'Warning for ' + array_name + ' array. Using negative user_id ' + user_id + ' for "old" unknown user in ' + msg.msgtype + ' message') ;
                    remote_sha256_values.push(user_id) ;
                    continue ;
                }
                if (!friend.remote_sha256) {
                    if (force) {
                        console.log(pgm + 'Warning for ' + array_name + ' array. User id ' + user_id + ' do not have a remote sha256 signature. Using negative user_id ' + (-user_id) + ' in ' + msg.msgtype + ' message') ;
                        remote_sha256_values.push(-user_id) ;
                        continue ;
                    }
                    else {
                        error = 'System error in user_ids_to_remote_sha256. Cannot send ' + msg.msgtype + ' message to other Gofreerev server. Error in ' + array_name + '. No remote_sha256 hash was found for user id ' + user_id ;
                        console.log(pgm + error) ;
                        console.log(pgm + 'msg     = ' + JSON.stringify(msg)) ;
                        console.log(pgm + 'friend  = ' + JSON.stringify(friend)) ;
                        return error;
                    }
                }
                remote_sha256 = friend.remote_sha256[server_id] ;
                if (!remote_sha256) {
                    if (force) {
                        console.log(pgm + 'Warning for ' + array_name + ' array. User id ' + user_id + ' do not have a remote sha256 signature. Using negative user_id ' + (-user_id) + ' in ' + msg.msgtype + ' message') ;
                        remote_sha256_values.push(-user_id) ;
                    }
                    else {
                        error = 'System error in user_ids_to_remote_sha256. Cannot send ' + msg.msgtype + ' message to other Gofreerev server. Error in ' + array_name + ' .Remote_sha256 was not found for user id ' + user_id + ' and server id ' + server_id ;
                        console.log(pgm + error) ;
                        console.log(pgm + 'msg     = ' + JSON.stringify(msg)) ;
                        console.log(pgm + 'friend  = ' + JSON.stringify(friend)) ;
                        return error ;
                    }
                }
                remote_sha256_values.push(remote_sha256) ;
            } // for i

            // translate ok. overwrite values in input array.
            for (i=0 ; i<user_ids.length ; i++) user_ids[i] = remote_sha256_values[i] ;
            return null ;
        }; // user_ids_to_remote_sha256;


        // after receiving msg from an other Gofreerev server. Translate known sha256 signatures to internal user ids
        // user ids in msg are either sha256 signatures (remote users) or negative user ids (unknown users)
        var sha256_to_user_ids = function (sha256_signatures, msg) {
            var pgm = service + '.sha256_to_user_ids: ' ;
            if ((typeof sha256_signatures == 'undefined') || (sha256_signatures == null)) return null ;
            var user_ids = [];
            var i, sha256, friend, translate = false ;
            for (i=0 ; i<sha256_signatures.length ; i++) {
                sha256 = sha256_signatures[i] ;
                if (typeof sha256 == 'number') {
                    // should be a negative integer for unknown user
                    // console.log(pgm + 'msg = ' + JSON.stringify(msg)) ;
                    if (sha256 >= 0) return 'Invalid integer user id ' + sha256 + ' in ' + msg.msgtype + ' message' ;
                    if (sha256 != Math.round(sha256)) return 'Invalid integer user id ' + sha256 + ' in ' + msg.msgtype + ' message' ;
                    user_ids.push(sha256) ;
                    continue ;
                }
                if (typeof sha256 != 'string') return 'Invalid user id ' + JSON.stringify(sha256) + ' in ' + msg.msgtype + ' message' ;
                friend = get_friend_by_sha256(sha256) ;
                if (!friend) return 'Unknown sha256 signature ' + sha256 + ' in ' + msg.msgtype + ' message' ;
                translate = true ;
                user_ids.push(friend.user_id) ;
            } // for i
            if (!translate) return null ; // no sha256 signatures found
            // translate ok
            for (i=0 ; i<sha256_signatures.length ; i++) sha256_signatures[i] = user_ids[i] ;
            return null ;
        }; // sha256_to_user_ids


        // user functions (friends and other users used in gifts and comments) ==>

        // js array with users in localStorage - that is users used in gifts and comments
        // stored so that gifts and comments always are valid when authorization and friend lists changes
        // ( see also friends array - temporary storage of friends list downloaded from api provider )
        var users = [] ;
        var users_index_by_user_id = {} ;
        var init_users_index = function () {
            users_index_by_user_id = {};
            for (var i=0 ; i<users.length ; i++) users_index_by_user_id[users[i].user_id] = i ;
        };

        // load users from localStorage
        var load_users = function () {
            var pgm = service + '.load_users: ' ;
            var users_tmp = Gofreerev.getItem('users') ;
            if (users_tmp) users = JSON.parse(users_tmp) ;
            else users = [] ;
            init_users_index() ;
            console.log(pgm + 'users = ' + JSON.stringify(users)) ;
        };
        load_users();

        var save_users = function () {
            var pgm = service + '.save_users: ' ;
            console.log(pgm + 'users = ' + JSON.stringify(users)) ;
            Gofreerev.setItem('users', JSON.stringify(users)) ;
        }; // save_users

        // return user from users array
        var get_user = function (user_id) {
            var pgm = service + '.get_user: ' ;
            // console.log(pgm + 'user_id = ' + user_id) ;
            // console.log(pgm + 'users = ' + JSON.stringify(users)) ;
            // console.log(pgm + 'users_index_by_user_id = ' + JSON.stringify(users_index_by_user_id)) ;
            if (typeof users == 'undefined') return null ;
            if (typeof user_id == 'undefined') return null ;
            var i = users_index_by_user_id[user_id] ;
            if (typeof i == 'undefined') return null ;
            var user = users[i] ;
            return user ;
        }; // get_user

        // add users used in create_new_gift and create_new_comment to localStorage
        // empty send_gifts_users array: gift created on this client. users must be login users. friend from friends array with friend = 1
        // non empty send_gifts_users array: gift from an other client. users can be login users, friend or unknown users from send_gifts message
        // users from friends array are always verified users
        // users from send_gifts_users array are always non verified users
        var add_new_users = function (user_ids, send_gifts_users) {
            var pgm = service + '.add_new_users: ' ;
            if ((typeof user_ids == 'undefine') || (user_ids == null)) return ;
            if (user_ids.length == 0) return ;
            var save = false, user_id, friend, i, j, k ;
            for (i=0 ; i<user_ids.length ; i++) {
                user_id = user_ids[i] ;
                if (users_index_by_user_id.hasOwnProperty(user_id)) continue ; // already save in localStorage
                friend = get_friend(user_id) ;
                if (send_gifts_users.length == 0) {
                    // local created gift or comment. user most be a login user
                    if (!friend || (friend.friend != 1)) {
                        console.log(pgm + 'Invalid call. ' + user_id + ' is not an logged in user') ;
                        continue ;
                    }
                }
                else {
                    // remote created gift or comment. user can be a login user, a friend or an unknown user from send_gifts message users array
                    if (!friend) {
                        k = null ;
                        for (j=0 ; j<send_gifts_users.length ; j++) if (send_gifts_users[j].user_id == user_id) k = j ;
                        if (k != null) friend = send_gifts_users[k] ;
                    }
                    if (!friend) {
                        console.log(pgm + 'Invalid call. ' + user_id + ' is not an logged in user, a friend or a user from send_gifts message') ;
                        console.log(pgm + 'user_id = ' + JSON.stringify(user_id)) ;
                        console.log(pgm + 'send_gifts_users = ' + JSON.stringify(send_gifts_users)) ;
                        continue ;
                    }
                } ;
                // clone friend before adding to users index. Friend status not used but verification timestamp is required
                friend = {
                    user_id: friend.user_id,
                    uid: friend.uid,
                    provider: friend.provider,
                    user_name: friend.user_name,
                    api_profile_picture_url: friend.api_profile_picture_url,
                    verified_at: friend.verified_at
                } ;
                if (friend.verified_at) friend.verified_at = Gofreerev.unix_timestamp() ;
                users_index_by_user_id[user_id] = users.length ;
                users.push(friend) ;
                save = true ;
            } // for i
            if (save) save_users() ;
        }; // add_new_users

        // add friends from friends array to users array - used in data migration (load_gifts). todo: remove
        var add_friends_to_users = function (user_ids) {
            var pgm = service + '.add_friends_to_users: ' ;
            if ((typeof user_ids == 'undefine') || (user_ids == null)) return ;
            if (user_ids.length == 0) return ;
            var save = false, user_id, friend ;
            for (var i=0 ; i<user_ids.length ; i++) {
                user_id = user_ids[i] ;
                if (users_index_by_user_id.hasOwnProperty(user_id)) {
                    // already in users js/localStorage
                    // todo: check for changed fields
                    continue ;
                }
                friend = get_friend(user_id) ;
                if (!friend) {
                    console.log(pgm + 'Invalid call. ' + user_id + ' was not found in friend lists') ;
                    continue ;
                }
                // clone friend before adding to users index. Friend status not used but verification timestamp is required
                friend = {
                    user_id: friend.user_id,
                    uid: friend.uid,
                    provider: friend.provider,
                    user_name: friend.user_name,
                    api_profile_picture_url: friend.api_profile_picture_url,
                    verified_at: friend.verified_at
                } ;
                if (friend.verified_at) friend.verified_at = Gofreerev.unix_timestamp() ;
                users_index_by_user_id[user_id] = users.length ;
                users.push(friend) ;
                save = true ;
            } // for i
            if (save) save_users() ;
        }; // add_friends_to_users


        // <== users functions


        return {
            is_online: is_online,
            providers: providers,
            load_users: load_users,
            is_logged_in: is_logged_in,
            is_logged_in_with_device: is_logged_in_with_device,
            is_logged_in_with_provider: is_logged_in_with_provider,
            no_friends: no_friends,
            get_login_users: get_login_users,
            get_login_userids: get_login_userids,
            get_friend: get_friend,
            get_friend_by_sha256: get_friend_by_sha256,
            get_currency: get_currency,
            get_closest_friend: get_closest_friend,
            get_userids_friend_status: get_userids_friend_status,
            find_giver: find_giver,
            find_receiver: find_receiver,
            logout: logout,
            client_userid: client_userid,
            client_secret: client_secret,
            update_friends: update_friends,
            sync_friends: sync_friends,
            oauth_array_to_hash: oauth_array_to_hash,
            add_oauth: add_oauth,
            remove_oauth: remove_oauth,
            send_oauth: send_oauth,
            refresh_friends_list_request: refresh_friends_list_request,
            cache_oauth_info: cache_oauth_info,
            check_logged_in_providers: check_logged_in_providers,
            expired_tokens_response: expired_tokens_response,
            oauths_response: oauths_response,
            get_external_user_ids: get_external_user_ids,
            add_new_users: add_new_users,
            get_user: get_user,
            add_friends_to_users: add_friends_to_users,
            user_ids_to_remote_sha256: user_ids_to_remote_sha256,
            sha256_to_user_ids: sha256_to_user_ids
        };
        // end UserService
    }]);
