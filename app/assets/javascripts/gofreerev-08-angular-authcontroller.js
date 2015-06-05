// Gofreerev angularJS code

angular.module('gifts')
    .controller('AuthCtrl', ['TextService', 'UserService', 'GiftService', '$window', '$location', function(textService, userService, giftService, $window, $location) {
        console.log('AuthCtrl loaded') ;
        var self = this ;
        self.userService = userService ;
        self.texts = textService.texts ;
        // console.log('AuthCtrl. providers = ' + JSON.stringify(self.providers)) ;
        self.is_gofreerev = function (provider) {
            return (provider.provider == 'gofreerev')
        };

        // radio group login or register?
        var passwords_str = Gofreerev.getItem("passwords") ;
        var passwords_a ;
        if (passwords_str === null) {
            passwords_a = [] ;
        }
        else {
            passwords_a = JSON.parse(passwords_str) ;
        }
        if (passwords_a.length == 0) self.register = 'x' ;
        else self.register = '' ;

        self.device_password = '' ;
        self.confirm_device_password = '' ;
        self.is_logged_in = function (provider) {
            return userService.is_logged_in_with_provider(provider)
        };
        self.login = function (provider) {
            if (userService.is_logged_in_with_provider(provider)) return ;
            var userid = Gofreerev.getItem('userid') ;
            $window.location.href = '/auth/' + provider + '?client_userid=' + userid ;
        };
        self.is_logged_off = function (provider) {
            return !userService.is_logged_in_with_provider(provider)
        };
        self.logout = function (provider) {
            var logged_in = userService.is_logged_in_with_provider(provider) ;
            if (!logged_in) console.loog('AuthCtrl.logout. error. not logged in with ' + provider) ;
            if (!logged_in) return ;
            console.log('AuthCtrl.logout: debug 2') ;
            userService.logout(provider) ;
            if ((typeof provider == 'undefined') || (provider == null) || (provider == 'gofreerev')) {
                // login changed. reload users and gifts
                userService.load_users() ;
                giftService.load_gifts() ;
            }
            console.log('AuthCtrl.logout: debug 3') ;
            $location.path('/auth/0') ;
            $location.replace() ;
        };
        self.trafic_light_status = function (provider) {
            if (userService.is_logged_in_with_provider(provider)) return 'connected' ;
            else return 'disconnected' ;
        };
        self.register_disabled = function() {
            var device_password = $window.document.getElementById('device_password').value ;
            if (device_password.length < 10) return true ;
            if (device_password.length > 50) return true ;
            var confirm_device_password = $window.document.getElementById('confirm_device_password').value ;
            return (device_password != confirm_device_password) ;
        };
        self.login_or_register_error = '' ;
        var set_login_or_register_error = function (error) {
            // todo: not working - error from userService.send_oauth is NOT injected into view!
            self.login_or_register_error = error ;
            // workaround - use old tasks error table in page header
            if (error != '') Gofreerev.add_to_tasks_errors(error) ;
        };
        set_login_or_register_error('') ;
        self.login_or_register = function() {
            var pgm = 'AuthCtrl.login_or_register: ' ;
            var create_new_account = (self.register != '') ;
            var userid = Gofreerev.client_login(self.device_password, create_new_account) ;
            if (userid == 0) {
                alert('Invalid password');
            }
            else {
                // clear login form
                self.device_password = '' ;
                self.confirm_device_password = '' ;
                self.register = '' ;
                // cache some oauth information used in ping.
                userService.cache_oauth_info() ;
                // console.log('AuthCtrl.login_or_register: userid = ' + userid) ;
                userService.load_users() ;
                giftService.load_gifts() ;
                // send old oauth to server for recheck and copy to session
                // todo: userService should return a promise, and this promise should be used to inject any error messages into auth page
                // console.log(pgm + 'calling send_oauth') ;
                set_login_or_register_error('') ;
                userService.send_oauth().then(function (response) {
                    console.log(pgm + 'send_oauth ok') ;
                    // friend list received from server - copy any missing users to users js array / localStorage - all user ids in gifts and comments must be in users
                    giftService.add_friends_to_users() ;
                }, function (error) {
                    console.log(pgm + 'send oauth error = ' + error) ;
                    set_login_or_register_error(error) ;
                });
                // console.log(pgm + 'send_oauth was called') ;
                $location.path('/auth/' + userid) ;
                $location.replace();
            }
        };
        // end AuthCtrl
    }]);
