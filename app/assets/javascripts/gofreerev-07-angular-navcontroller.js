// Gofreerev angularJS code

angular.module('gifts')
    .controller('NavCtrl', ['TextService', 'UserService', 'GiftService', '$timeout', '$http', '$q', function(textService, userService, giftService, $timeout, $http, $q) {
        var controller = 'NavCtrl' ;
        console.log(controller + ' loaded') ;
        var self = this ;
        self.userService = userService ;
        self.texts = textService.texts ;

        // ping server once every minute - server maintains a list of online users / devices
        var ping_interval = Gofreerev.rails['PING_INTERVAL'] ;
        var ping = function (old_ping_interval) {
            var pgm = controller + '.ping: ' ;
            var userid = userService.client_userid() ;
            if (userid == 0) {
                // no device login
                console.log(pgm + 'wait - no device login') ;
                $timeout(function () { ping(ping_interval); }, ping_interval) ;
                return ;
            };
            // check logins - there must be minimum one not expired login
            // returns logged_in_provider: true/false and an optional oauth array with refresh token for expired google+ login
            var new_client_timestamp = (new Date).getTime() ; // unix timestamp with milliseconds
            var now = Math.floor(new_client_timestamp/1000) ; // unix timestamp
            var result = userService.check_logged_in_providers(now) ;
            if (!result.logged_in_provider) {
                // no social network logins was found
                console.log(pgm + 'wait - no social network logins was found') ;
                $timeout(function () { ping(ping_interval); }, ping_interval) ;
                return ;
            }
            // cleanup old error messages
            giftService.remove_old_link_errors() ;
            // make ping request
            var sid = Gofreerev.getItem('sid') ;
            // todo: add accept_gifts request and response
            // todo: add friend list update (changed signatures)
            var ping_request = {
                client_userid: userid,
                sid: sid,
                client_timestamp: new_client_timestamp,
                new_gifts: giftService.new_gifts_request(),
                new_servers: giftService.new_servers_request(),
                verify_gifts: giftService.verify_gifts_request(),
                delete_gifts: giftService.delete_gifts_request(),
                new_comments: giftService.new_comments_request(),
                verify_comments: giftService.verify_comments_request(),
                pubkeys: giftService.pubkeys_request(),
                refresh_tokens: result.refresh_tokens_request,
                oauths: userService.refresh_friends_list_request(),
                messages: giftService.send_messages()
            };
            for (var key in ping_request) if (ping_request[key] == null) delete ping_request[key] ;
            // validate json request before sending ping to server
            if (Gofreerev.is_json_request_invalid(pgm, ping_request, 'ping')) {
                console.log(pgm + 'Ping loop aborted. Please correct error.') ;
                return ;
            }
            $http.post('/util/ping.json', ping_request).then(
                function (response) {
                    // schedule next ping.
                    // console.log(pgm + 'ok. old_ping_interval = ' + old_ping_interval) ;
                    // console.log(pgm + 'ok. ok.data.interval = ' + ok.data.interval) ;
                    if (response.data.interval && (response.data.interval >= 1000)) ping_interval = response.data.interval ;
                    $timeout(function () { ping(ping_interval); }, ping_interval) ;

                    // validate ping response received from server
                    // todo: report ping errors to inbox.
                    if (Gofreerev.is_json_response_invalid(pgm, response.data, 'ping', '')) return ;
                    // process ping response
                    if (response.data.error) {
                        console.log(pgm + 'error: ' + response.data.error) ;
                        if (response.data.error == 'Not logged in') userService.logout('*') ;
                    }
                    if (response.data.friends) {
                        // system secret and friends sha256 signatures has been changed. update friend with new information
                        // old sha256 signature is valid for 3 minutes after friends_sha256_update_at unix timestamp
                        // console.log(pgm + 'ok. friends = ' + JSON.stringify(response.data.friends)) ;
                        // console.log(pgm + 'ok. friends_sha256_update_at = ' + JSON.stringify(response.data.friends_sha256_update_at)) ;
                        userService.update_friends(response.data.friends, false, response.data.friends_sha256_update_at) ; // replace=false - add new friends
                    }
                    // check online users/devices - create a mail box for each online device
                    if (response.data.online) giftService.update_mailboxes(response.data.online) ;
                    // check for new public keys for online users/devices
                    if (response.data.pubkeys) giftService.pubkeys_response(response.data.pubkeys) ;
                    // get timestamps for newly created gifts from server
                    if (response.data.new_gifts) giftService.new_gifts_response(response.data.new_gifts) ;
                    // get result of new servers request (unknown server sha256 signatures received from other devices (new gifts))
                    if (response.data.new_servers) giftService.new_servers_response(response.data.new_servers) ;
                    // get result of gift verification (gifts received from other devices)
                    if (response.data.verify_gifts) giftService.verify_gifts_response(response.data.verify_gifts) ;
                    // get result of delete gifts request
                    if (response.data.delete_gifts) giftService.delete_gifts_response(response.data.delete_gifts) ;
                    // get timestamps for newly created comments from server
                    if (response.data.new_comments) giftService.new_comments_response(response.data.new_comments) ;
                    // get result of comment verification (comments received from other devices)
                    if (response.data.verify_comments) giftService.verify_comments_response(response.data.verify_comments) ;
                    // check expired access token (server side check)
                    if (response.data.expired_tokens) userService.expired_tokens_response(response.data.expired_tokens, 'ping') ;
                    // check for new oauth authorization (google+ only)
                    if (response.data.oauths) userService.oauths_response(response.data.oauths) ;
                    // check for new messages from other devices
                    if (response.data.messages) giftService.receive_messages(response.data.messages) ;
                    giftService.messages_sent() ;
                    giftService.process_messages() ;

                    // check interval between client timestamp and previous client timestamp
                    // interval should be 60000 = 60 seconds
                    // console.log(pgm + 'ok. ok.data.old_client_timestamp = ' + ok.data.old_client_timestamp) ;
                    if (!response.data.old_client_timestamp) return ; // first ping for new session
                    var interval = new_client_timestamp - response.data.old_client_timestamp ;
                    // console.log(pgm + 'ok. interval = ' + interval) ;
                    if (interval > old_ping_interval - 100) return ;
                    console.log(
                        pgm + 'ok. multiple logins for client userid ' + userid +
                        '. old timestamp = ' + response.data.old_client_timestamp +
                        ', new timestamp = ' + new_client_timestamp +
                        ',interval = ' + interval);
                    // sync JS users array with any changes in local storage users string
                    userService.sync_friends() ;
                    giftService.sync_gifts() ;
                },
                function (error) {
                    // schedule next ping
                    console.log(pgm + 'error. old_ping_interval = ' + old_ping_interval) ;
                    $timeout(function () { ping(ping_interval); }, ping_interval) ;
                    console.log(pgm + 'error = ' + JSON.stringify(error)) ;

                    // move messages from mailbox.sending to mailbox.outbox - resend in next ping
                    giftService.messages_not_sent() ;

                })
        }; // ping
        $timeout(function () { ping(ping_interval); }, ping_interval) ;
        console.log(controller + '.start ping process. start up ping interval = ' + ping_interval) ;

        var get_js_timezone = function () {
            return -(new Date().getTimezoneOffset()) / 60.0 ;
        };
        var start_do_tasks_spinner = function ()
        {
            var spinner_id = 'ajax-tasks-spinner' ;
            var spinner = document.getElementById(spinner_id) ;
            if (spinner) spinner.style.display = '' ;
            else Gofreerev.add2log('start_do_tasks_spinner: spinner was not found') ;
        }; // start_do_tasks_spinner
        var stop_do_tasks_spinner = function ()
        {
            var spinner_id = 'ajax-tasks-spinner' ;
            var spinner = document.getElementById(spinner_id) ;
            if (spinner) spinner.style.display = 'none' ;
            else Gofreerev.add2log('stop_tasks_form_spinner: spinner was not found') ;
        }; // stop_tasks_form_spinner

        // post page task - execute some post-page / post-login ajax tasks and get fresh json data from server (oauth and users)
        var do_tasks = function () {
            var pgm = controller + '.do_tasks: ' ;
            var userid = userService.client_userid() ;
            if (userid == 0) return ; // only relevant for logged in users
            console.log(pgm + 'start');
            var secret = userService.client_secret() ;
            var do_tasks_request = {client_userid: userid} ;
            var msg = ' Some server tasks was not executed and the page will not be working 100% as expected' ;
            if (Gofreerev.is_json_request_invalid(pgm, do_tasks_request, 'do_tasks', msg)) return ;
            start_do_tasks_spinner();
            $http.post('/util/do_tasks.json', do_tasks_request)
                .then(function (response) {
                    // console.log(pgm + 'response = ' + JSON.stringify(response)) ;
                    stop_do_tasks_spinner() ;
                    if (response.data.error) {
                        console.log(pgm + 'Error when executing required "startup" tasks.' + msg + '. error = ' + response.data.error) ;
                        // todo: stop or continue?
                    }
                    // validate do_tasks response received from server
                    var json_errors ;
                    if (json_errors=Gofreerev.is_json_response_invalid(pgm, response.data, 'do_tasks', msg)) return $q.reject(json_errors);
                    var oauths = response.data.oauths ;
                    if (oauths) {
                        // new oauth token(s) received from util.generic_post_login task (token, expires_at and refresh token)
                        console.log(pgm + 'oauths = ' + JSON.stringify(oauths)) ;
                        oauths = userService.oauth_array_to_hash(oauths) ;
                        userService.add_oauth(oauths) ;
                    }
                    var new_friends = response.data.friends ;
                    if (new_friends) {
                        // new friend lists received from util.generic_post_login task
                        console.log(pgm + 'new friends = ' + JSON.stringify(new_friends)) ;
                        userService.update_friends(new_friends, false, response.data.friends_sha256_update_at) ; // replace=false - add new friends
                    }
                },
                function (error) {
                    stop_do_tasks_spinner() ;
                    console.log(pgm + 'error = ' + JSON.stringify(error)) ;
                }) ;

        };
        $timeout(do_tasks, 1000);
        // end NavCtrl
    }]);
