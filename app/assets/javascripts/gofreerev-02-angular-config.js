// Gofreerev angularJS code

angular.module('gifts', ['ngRoute'])
    .config(function ($routeProvider) {
        var get_local_userid = function () {
            var userid = Gofreerev.getItem('userid');
            if (typeof userid == 'undefined') return '0';
            else if (userid == null) return '0';
            else if (userid == '') return '0';
            else return ('' + parseInt(userid));
        };
        // todo: add route to show gift - as gifts page with one gift and without create new gift
        // todo: is there any reason for :userid in angularJS - will not be 100% correct if link to a gift is shared with an other gofreerev-lo user
        // todo: /gifts/ is only allowed for api provider logins. that is: users.length > 0
        $routeProvider
            .when('/gifts/:userid?', {
                templateUrl: 'main/gifts',
                controller: 'GiftsCtrl as ctrl',
                resolve: {
                    check_userid: ['$route', '$location', function ($route, $location) {
                        // check /:userid in url
                        var userid = get_local_userid();
                        if (userid != $route.current.params.userid) {
                            // invalid or missing /:userid in url
                            $location.path('/gifts/' + userid);
                            $location.replace();
                            return ;
                        }
                        // check api provider login
                        var oauth = Gofreerev.getItem('oauth') ;
                        if (oauth) oauth = JSON.parse(oauth) ;
                        if (!oauth || (oauth.length == 0)) {
                            // no api provider login
                            $location.path('/auth/' + userid);
                            $location.replace();
                        }
                    }]
                }
            })
            .when('/auth/:userid?', {
                templateUrl: 'main/auth',
                controller: 'AuthCtrl as ctrl',
                resolve: {
                    check_userid: ['$route', '$location', function ($route, $location) {
                        var userid = get_local_userid();
                        if (userid != $route.current.params.userid) {
                            $location.path('/auth/' + userid);
                            $location.replace();
                        }
                    }]
                }
            })
            .otherwise({
                redirectTo: function (routeParams, path, search) {
                    var userid = Gofreerev.getItem('userid');
                    if (typeof userid == 'undefined') userid = 0;
                    else if (userid == null) userid = 0;
                    else if (userid == '') userid = 0;
                    else userid = parseInt(userid);
                    return '/gifts/' + userid;
                }
            });
        // end config (ng-routes)
    }
)
    // cache routeprovider template urls so that inside page navigation is working offline
    .run(['$templateCache', '$http', function($templateCache, $http) {
        // auth page - login and logout
        $http.get('main/auth', {cache:$templateCache})
        $http.get('/images/gofreerev.png', {cache:$templateCache})
        $http.get('/images/connected.png', {cache:$templateCache})
        $http.get('/images/disconnect.png', {cache:$templateCache})
        $http.get('/images/facebook.png', {cache:$templateCache})
        $http.get('/images/flickr.png', {cache:$templateCache})
        $http.get('/images/disconnected.png', {cache:$templateCache})
        $http.get('/images/connect.png', {cache:$templateCache})
        $http.get('/images/foursquare.png', {cache:$templateCache})
        $http.get('/images/google_oauth2.png', {cache:$templateCache})
        $http.get('/images/twitter.png', {cache:$templateCache})
        $http.get('/images/linkedin.png', {cache:$templateCache})
        $http.get('/images/vkontakte.png', {cache:$templateCache})
        $http.get('/images/instagram.png', {cache:$templateCache})
        // gifts page
        $http.get('main/gifts', {cache:$templateCache})
}]);