// Gofreerev angularJS code

angular.module('gifts')
    .controller('GiftsCtrl', ['$location', '$http', '$document', '$window', '$sce', '$timeout',  'UserService', 'GiftService', 'TextService',
                     function ($location, $http, $document, $window, $sce, $timeout, userService, giftService, textService) {
        var controller = 'GiftsCtrl' ;
        console.log(controller + ' loaded') ;
        var self = this;

        self.texts = textService.texts ;
        self.userService = userService ;
        self.giftService = giftService ;

        self.default_no_comments = 3 ;

        self.is_logged_in = function () {
            return userService.is_logged_in() ;
        };
        self.no_friends = function () {
            return userService.no_friends() ;
        };
        self.login_users = function () {
            return userService.get_login_users() ;
        };
        self.login_user_ids = function () {
            return userService.get_login_userids() ;
        };

        // gifts filter. hide deleted gift. hide hidden gifts. used in ng-repeat
        self.gifts_filter = function (gift, index) {
            var pgm = controller + '.gifts_filter: ' ;
            var show_gift = true ;
            if (gift.deleted_at_client) return false ;
            if (!gift.show) return false ;
            // check friend status. giver or receiver must be login user or a friend of login user
            var friend ;
            friend = userService.get_userids_friend_status(gift.giver_user_ids) ;
            // console.log(pgm + 'gid = ' + gift.gid + ', giver_user_ids = ' + JSON.stringify(gift.giver_user_ids) + ', receiver_user_ids = ' + JSON.stringify(gift.receiver_user_ids) + 'friend status = ' + friend) ;
            if (friend && (friend <= 2)) return true ;
            friend = userService.get_userids_friend_status(gift.receiver_user_ids) ;
            if (friend && (friend <= 2)) return true ;
            return false ;
        };

        self.no_gifts = function() {
            if (typeof giftService.gifts == 'undefined') return true  ;
            if (typeof giftService.gifts.length == 'undefined') return true ;
            return (giftService.gifts.length == 0) ;
        };

        // comments filter. hide deleted comments. used in ng-repeat
        self.comments_filter = function (comment, index) {
            var pgm = controller + '.comments_filter: ' ;
            var show ;
            if (comment.deleted_at_client) show = false ;
            else show = true ;
            // console.log(pgm + 'cid = ' + comment.cid + ', show = ' + show) ;
            return show ;
        };


        self.user_div_on_click = function (user_ids) {
            var pgm = controller + '.user_div_on_click ' ;
            console.log(pgm + 'user_ids = ' + JSON.stringify(user_ids)) ;
            if (typeof user_ids == 'undefined') {
                // error - user_id array not found in users array
                console.log(pgm + 'error: user_ids is undefined') ;
                return;
            }
            var user_id = user_ids[0] ;
            var user = userService.get_friend(user_id) ;
            if (!user) return ; // error - user not found in users array
            if (!user.friend) return ; // error - no friend status was found
            if ([1,2,3,4].indexOf(user.friend) == -1) return ; // ok - not clickable div
            var locale = I18n.currentLocale() || I18n.defaultLocale ;
            // ok - redirect to users/show page
            // todo: use windows redirect or angular single page app?
            // $location.url('/' + locale + '/users/' + user_id) ;
            window.top.location.assign('/' + locale + '/users/' + user_id) ;
        }; // user_div_on_click

        var vertical_overflow = function (text_id) {
            var pgm = 'GiftsCtrl.vertical_overflow: ' ;
            var text = document.getElementById(text_id) ;
            if (!text) {
                Gofreerev.add2log(pgm + 'error. overflow div ' + text_id + ' was not found') ;
                return false ;
            }
            // check style
            if (text.style.overflow == 'visible') {
                Gofreerev.add2log(pgm + 'show_full_text has already been activated for ' + text_id) ;
                return false ;
            }
            // check for vertical overflow
            var screen_width = ($document.width !== undefined) ? $document.width : $document.body.offsetWidth;
            var screen_width_factor = screen_width / 320.0 ;
            if (screen_width_factor < 1) screen_width_factor = 1 ;
            var text_max_height = parseInt(text.style.maxHeight) ;
            if (text.scrollHeight * screen_width_factor < text_max_height) return false ; // small text - overflow is not relevant
            if (text.scrollHeight <= text.clientHeight) return false ; // not actual with current screen width
            // vertical text overflow found
            return true ;
        }; // vertical_overflow

        // gift link + description - show "show-more-text" link if long gift description with vertical text overflow 
        // return false if small text without vertical overflow
        // link 1: above image (picture attachment), link 2: together with other gift links (no picture attachment)
        self.show_full_gift_link = function (gift, link) {
            var pgm = controller + '.show_full_gift_link: ' ;
            // find overflow div
            var text_id = gift.gid + "-overflow-text" ;
            if (!vertical_overflow(text_id)) return false ; // error or no vertical overflow
            // vertical text overflow found - check for picture true/false
            var picture ;
            if ((typeof gift.api_picture_url != 'undefined') && (gift.api_picture_url != null)) {
                // picture attachment - any picture with error are marked with gift.api_picture_url_on_error_at = true
                if ((typeof gift.api_picture_url_on_error_at != 'undefined') && (gift.api_picture_url_on_error_at == true)) picture = false ;
                else picture = true ;
            }
            else if ((typeof gift.open_graph_image != 'undefined') && (gift.open_graph_image != null)) {
                // open graph image
                // todo: add error check for open graph image as error check for image attachment?
                picture = true ;
            }
            else {
                // no picture
                picture = false
            }
            // show overflow link? link 1 used for gift with pictures, link 2 used for gift without pictures
            var show ;
            if (link == 1) show = picture ;
            else if (link == 2) show = !picture ;
            else show = false ;
            // console.log(pgm + 'gid = ' + gift.gid + ', link = ' + link + ', picture = ' + picture + ', show = ' + show) ;
            return show ;
        }; // show_full_gift_link

        // show "show-more-text" link if long comment description with vertical text overflow
        self.show_full_comment_link = function (comment) {
            var pgm = controller + '.show_full_comment_link: ' ;
            // find overflow div
            var text_id = comment.cid + "-overflow-text" ;
            var x = vertical_overflow(text_id) ;
            if (comment.cid == '14229743962942303238') console.log(pgm + 'vertical_overflow("' + text_id + '") = ' + x) ; // todo: debug
            return x ;
        }; // show_full_comment_link

        // show full gift description. remove style maxHeight and overflow from div container
        self.show_full_gift_click = function(gift) {
            // show full text for div with overflow
            var pgm = 'GiftsCtrl.show_full_text: ' ;
            // find overflow div
            var text_id = gift.gid + "-overflow-text" ;
            var text = document.getElementById(text_id) ;
            if (!text) return ; // error - div with gift link and description was not found
            // remove max height ( and hide show-more-text link)
            text.style.maxHeight = 'none' ;
            text.style.overflow = 'visible' ;
        }; // show_full_gift_click

        // show full comment description. remove style maxHeight and overflow from div container
        self.show_full_comment_click = function(comment) {
            // show full text for div with overflow
            var pgm = controller + '.show_full_comment_click: ' ;
            console.log(pgm + 'cid = ' + comment.cid) ;
            // find overflow div
            var text_id = comment.cid + "-overflow-text" ;
            var text = document.getElementById(text_id) ;
            if (!text) return ; // error - div with comment link and description was not found
            // remove max height ( and hide show-more-text link)
            text.style.maxHeight = 'none' ;
            text.style.overflow = 'visible' ;
        }; // show_full_comment_click

        // show/hide table row with gift api_picture_url?
        // only show row if api_picture_url and not error marked
        // rails code: <% if api_gift.picture? and !api_gift.api_picture_url_on_error_at  -%>
        self.show_api_picture_url = function (gift) {
            if ((typeof gift.api_picture_url != 'undefined') && (gift.api_picture_url != null)) {
                // image image attachment
                if ((typeof gift.api_picture_url_on_error_at != 'undefined') && (gift.api_picture_url_on_error_at == true)) return false ;
                else return true ;
            }
            else return false ;
        }; // show_api_picture_url

        // show/hide table row with gift open graph image
        self.show_open_graph_image = function (gift) {
            if ((typeof gift.open_graph_image != 'undefined') && (gift.open_graph_image != null)) return true ;
            else return false ;
        };

        // show/hide table row with gift open graph title
        self.show_open_graph_title = function (gift) {
            if ((typeof gift.open_graph_title != 'undefined') && (gift.open_graph_title != null)) return true ;
            else return false ;
        };

        // show/hide table row with gift open graph description
        self.show_open_graph_description = function (gift) {
            if ((typeof gift.open_graph_description != 'undefined') && (gift.open_graph_description != null)) return true ;
            else return false ;
        };

        self.like_gift = function (gift) {
            giftService.refresh_gift(gift);
            gift.like = true ;
            giftService.save_gift(gift) ;
        };
        self.unlike_gift = function (gift) {
            giftService.refresh_gift(gift);
            gift.like = false ;
            giftService.save_gift(gift) ;
        };

        self.follow_gift = function (gift) {
            giftService.refresh_gift(gift);
            gift.follow = true ;
            giftService.save_gift(gift) ;
        };
        self.unfollow_gift = function (gift) {
            giftService.refresh_gift(gift);
            gift.follow = false ;
            giftService.save_gift(gift) ;
        };

        // delete gift. show delete link if login user(s) is giver or receiver of gift
        self.show_delete_gift = function (gift) {
            if (!self.gifts_filter(gift, null)) return false ; // gift already removed from page
            var user = userService.find_giver(gift) ;
            if (user && (user.friend == 1)) return true ;
            user = userService.find_receiver(gift) ;
            if (user && (user.friend == 1)) return true ;
            return false ;
        };
        self.delete_gift = function (gift) {
            var pgm = controller + '.delete_gft: ' ;
            giftService.refresh_gift(gift);
            if (!self.show_delete_gift(gift)) return ;
            var confirm_options = { price: gift.price, currency: gift.currency };
            // todo: show/insert error messages under gifts link in main/gifts page? like old insert_gift_links_errors_table JS method
            if (gift.received_at && gift.price && (gift.price != 0.0)) {
                var giver = userService.find_giver(gift) ;
                if (!giver) {
                    Gofreerev.add2log(pgm + 'error: giver was not found for gid ' + gift.gid) ;
                    return ;
                }
                var receiver = userService.find_receiver(gift) ;
                if (!receiver) {
                    Gofreerev.add2log(pgm + 'error: receiver was not found for gid ' + gift.gid) ;
                    return ;
                }
                if ((giver.friend != 1) && (receiver.friend != 1)) {
                    Gofreerev.add2log(pgm + 'error: delete not allowed for gid ' + gift.gid) ;
                    return ;
                }
                var keyno ;
                if ((giver.friend == 1) && (receiver.friend == 1)) keyno = 2 ; // simple confirm
                else {
                    // confirm with warning
                    keyno = 1;
                    confirm_options['user_name'] = is_giver ? receiver.user_name : giver.user_name ;
                }
            }
            else keyno = 2 ; // simple confirm
            // confirm dialog
            var confirm_key = "js.gifts.confirm_delete_gift_" + keyno ;
            var confirm_text = I18n.t(confirm_key, confirm_options) ;
            if (!confirm(confirm_text)) return ;
            gift.deleted_at_client = Gofreerev.unix_timestamp() ;
            giftService.save_gift(gift) ;
            giftService.verify_gifts_add(gift, 'delete') ;
        }; // delete_gift

        self.hide_gift = function (gift) {
            giftService.refresh_gift(gift);
            if (!self.gifts_filter(gift, null)) return ; // already removed from page
            var confirm_text = I18n.t("js.gifts.confirm_hide_gift") ;
            if (!confirm(confirm_text)) return ;
            gift.show = false ;
            giftService.save_gift(gift) ;
        };

        self.show_older_comments = function (gift) {
            return ((gift.show_no_comments || self.default_no_comments) < (gift.comments || []).length) ;
        };
        self.show_older_comments_text = function (gift) {
            var old_no_rows = gift.show_no_comments || self.default_no_comments ;
            var new_no_rows = Math.min((gift.comments || []).length, old_no_rows + 10) ;
            var no_older_comments = new_no_rows - old_no_rows ;
            if (no_older_comments <= 1) return I18n.t('js.gifts.show_older_comment') ;
            else return I18n.t('js.gifts.show_older_comments', {no_older_comments: no_older_comments}) ;
        };
        self.show_older_comments_click = function (gift) {
            if (!gift.show_no_comments) gift.show_no_comments = self.default_no_comments ;
            gift.show_no_comments = gift.show_no_comments + 10 ;
        };

        self.show_delete_comment_link = function (gift, comment) {
            // from rails Comment.show_delete_comment_link?
            var pgm = controller + '.show_delete_comment_link. gid = ' + gift.gid + ', cid = ' + comment.cid + '. ';
            if (comment.new_deal_action == 'accepted') return false ; // delete accepted proposal is not allow - delete gift is allowed
            if (comment.deleted_at_client) return false ; // comment has already been marked as deleted
            // console.log(pgm) ;
            // ok to delete if login user(s) is giver/reciever
            var login_user_ids = userService.get_login_userids() ;
            if ($(login_user_ids).filter(gift.giver_user_ids).length > 0) {
                // login user(s) is giver
                // console.log(pgm + 'login user is giver') ;
                return true ;
            }
            if ($(login_user_ids).filter(gift.receiver_user_ids).length > 0) {
                // login user(s) is receiver
                // console.log(pgm + 'login user is receiver') ;
                return true ;
            }
            if ($(login_user_ids).filter(comment.user_ids).length > 0) {
                // login user(s) has created this comment
                // console.log(pgm + 'login_user has created the comment') ;
                return true ;
            }
            // console.log(pgm + 'login_user_ids = ' + JSON.stringify(login_user_ids) +
            // ', giver_user_ids = ' + JSON.stringify(gift.giver_user_ids) +
            // ', receiver_user_ids = ' + JSON.stringify(gift.receiver_user_ids) +
            // ', comment.user_ids = ' + JSON.stringify(comment.user_ids)) ;
            return false ;
        };

        self.delete_comment = function (gift, comment) {
            var pgm = controller + '.delete_comment: ' ;
            giftService.refresh_gift_and_comment(gift, comment) ;
            if (!comment.cid) {
                console.log(pgm + 'Comment removed in refresh_gift_and_comment') ;
                return ;
            } // comment has been deleted
            if (!self.show_delete_comment_link(gift,comment)) return ; // delete link no longer active
            if (confirm(self.texts.comments.confirm_delete_comment)) {
                comment.deleted_at_client = Gofreerev.unix_timestamp() ;
                if (typeof gift.show_no_comments != 'undefined') gift.show_no_comments = gift.show_no_comments - 1 ;
                giftService.save_gift(gift) ;
                giftService.verify_comments_add(gift, comment, 'delete') ;
            };
            // console.log(pgm + 'cid = ' + comment.cid + ', deleted_at_client = ' + comment.deleted_at_client) ;
        };

        self.show_cancel_new_deal_link = function (gift,comment) {
            // from rails Comment.show_cancel_new_deal_link?
            if (comment.new_deal != true) return false ;
            if (comment.new_deal_action) return false ; // already cancelled, rejected or accepted
            var login_user_ids = userService.get_login_userids() ;
            if ($(login_user_ids).filter(comment.user_ids).length == 0) return false ;
            return true ;
        };
        self.cancel_new_deal = function (gift,comment) {
            var pgm = controller + '.cancel_new_deal: ' ;
            giftService.refresh_gift_and_comment(gift, comment) ;
            if (!comment.cid) return ; // comment has been deleted
            if (!self.show_cancel_new_deal_link(gift,comment)) return ; // cancel link no longer active
            if (!confirm(self.texts.comments.confirm_cancel_new_deal)) return ;
            var login_user_ids = userService.get_login_userids() ;
            var user_ids = $(login_user_ids).filter(comment.user_ids).get() ;
            // console.log(pgm + 'login_user_ids   = ' + JSON.stringify(login_user_ids)) ;
            // console.log(pgm + 'comment.user_ids = ' + JSON.stringify(comment.user_ids)) ;
            // console.log(pgm + 'user_ids         = ' + JSON.stringify(user_ids)) ;
            comment.new_deal_action = 'cancel' ;
            comment.new_deal_action_by_user_ids = user_ids ;
            comment.new_deal_action_at_client = Gofreerev.unix_timestamp() ;
            giftService.save_gift(gift) ;
            var error ;
            if (error=giftService.verify_comments_add(gift, comment, 'cancel')) {
                console.log(pgm + 'cancel new deal proposal failed with ' + error) ;
                comment.link_error = error ;
                comment.link_error_at = Gofreerev.unix_timestamp() ;
                delete comment.new_deal_action ;
                delete comment.new_deal_action_by_user_ids ;
                delete comment.new_deal_action_at_client ;
                giftService.save_gift(gift) ;
            } ;
        }; // cancel_new_deal

        // user "other" user ids to be used when closing a deal (adding giver or receiver user ids to gift)
        // helper method used in show_accept_new_deal_link and accept_new_deal
        // filter gift creator with login users and compare with creator of new deal proposal
        function get_deal_close_by_user_ids (gift, comment) {
            var pgm = controller + '.get_deal_closed_by_user_ids: ' ;
            if (comment.new_deal != true) return [] ;
            if (comment.new_deal_action) return [] ; // already cancelled, rejected or accepted
            if (gift.accepted_at_client || gift.accepted_cid) return [] ; // accepted
            // merge login users and creators of gift - minimum one login is required
            var login_user_ids = userService.get_login_userids() ;
            var gift_user_ids = (gift.direction == 'giver') ? gift.giver_user_ids : gift.receiver_user_ids ;
            var user_ids = $(login_user_ids).filter(gift_user_ids).get() ;
            if (user_ids.length == 0) return [] ;
            // find providers - old gift creator & logged in
            var user_providers = [], user ;
            for (var i= 0 ; i<user_ids.length ; i++) {
                user = userService.get_friend(user_ids[i]) ;
                user_providers.push(user.provider) ;
            }
            // there must be minimum one common provider between creator of gift, login users and creator of comment
            // users logged in with common providers will see user information for giver and receiver
            // users not logged in with common providers will in some situations see "unknown user" for giver or provider
            user_ids = [] ;
            var comment_providers = [] ;
            for (i=0 ; i<comment.user_ids.length ; i++) {
                user = userService.get_friend(comment.user_ids[i]) ;
                if (user && (user_providers.indexOf(user.provider) != -1)) user_ids.push(comment.user_ids[i]) ;
            }
            return user_ids ;
        } // get_deal_close_by_user_ids

        self.show_accept_new_deal_link = function (gift,comment) {
            // from rails Comment.show_accept_new_deal_link?
            var pgm = controller + 'show_accept_new_deal_link: ' ;
            var user_ids = get_deal_close_by_user_ids(gift, comment) ;
            if (user_ids.length == 0) return false ;
            // check friend relation with creator of new deal proposal
            // friends relation can have changed - or maybe not logged in with provider or correct provider user
            var user = userService.get_closest_friend(user_ids);
            if (typeof user == 'undefined') return false ;
            if (user == null) return false ;
            return (user.friend <= 2) ;
        };
        self.accept_new_deal = function (gift,comment) {
            giftService.refresh_gift_and_comment(gift, comment) ;
            if (!comment.cid) return ; // comment has been deleted
            var user_ids = get_deal_close_by_user_ids(gift, comment) ;
            if (user_ids.length == 0) return ;
            if (!confirm(self.texts.comments.confirm_accept_new_deal)) return ; // operation cancelled
            // accept deal
            if (gift.direction == 'giver') gift.receiver_user_ids = user_ids ;
            else gift.giver_user_ids = user_ids ;
            gift.accepted_cid = comment.cid ;
            gift.accepted_at_client = Gofreerev.unix_timestamp() ;
            comment.new_deal_action = 'accepted' ;
            comment.new_deal_action_by_user_ids = user_ids ;
            comment.new_deal_action_at_client = Gofreerev.unix_timestamp() ; ;
            giftService.save_gift(gift) ;
        };

        self.show_reject_new_deal_link = function (gift,comment) {
            return self.show_accept_new_deal_link(gift,comment) ;
        };
        self.reject_new_deal = function (gift,comment) {
            giftService.refresh_gift_and_comment(gift, comment) ;
            if (!comment.cid) return ; // comment has been deleted
            var user_ids = get_deal_close_by_user_ids(gift, comment) ;
            if (user_ids.length == 0) return ;
            if (!confirm(self.texts.comments.confirm_reject_new_deal)) return ; // operation cancelled
            // reject deal
            comment.rejected_by_user_ids = user_ids ; // todo: remove
            comment.rejected_at_client = Gofreerev.unix_timestamp() ; // todo: remove
            comment.new_deal_action = 'rejected' ;
            comment.new_deal_action_by_user_ids = user_ids ;
            comment.new_deal_action_at_client = Gofreerev.unix_timestamp() ; ;
            giftService.save_gift(gift) ;
        };

        self.show_new_deal_checkbox = function (gift) {
            // see also formatNewProposalTitle
            if (gift.accepted_at_client || gift.accepted_cid) return false ; // closed deal
            var login_user_ids = userService.get_login_userids() ;
            if (gift.direction == 'giver') {
                if ($(login_user_ids).filter(gift.giver_user_ids).length > 0) return false ; // login user(s) is giver
            }
            else {
                if ($(login_user_ids).filter(gift.receiver_user_ids).length > 0) return false ; // login user(s) is receiver
            }
            return true ;
        };

        // new gift default values - moved to giftService
        self.new_gift = giftService.new_gift ;
        function init_new_gift () {
            giftService.init_new_gift() ;
        };
        init_new_gift() ;

        // new gift link open graph preview in gifts/index page ==>

        // fetch open graph meta tags from server with ajax and display preview information under link
        // typing delay 2 seconds before sending ajax request to server.

        var gift_open_graph_url_timer;                // timer identifier

        // helper - reset all open graph variables except open_graph_url
        function reset_open_graph_preview () {
            self.new_gift.open_graph_description = null ;
            self.new_gift.open_graph_title = null ;
            self.new_gift.open_graph_image = null ;
            self.new_gift.open_graph_error = null ;
            Gofreerev.clear_flash_and_ajax_errors() ;
        }

        // user is done typing - get open graph meta tags in an ajax request
        function gift_open_graph_url_done() {
            var pgm = 'GiftsCtrl.gift_open_graph_url_done: ';
            var userid = userService.client_userid() ;
            if (userid == 0) {
                console.log(pgm + 'Error. Not logged in.') ;
                return  ;
            }
            reset_open_graph_preview();
            if (self.new_gift.open_graph_url == '') return;
            // check url & get open graph meta tags - timeout 3 seconds
            var open_graph_request = {
                client_userid: userid,
                client_timestamp: (new Date).getTime(),
                url: self.new_gift.open_graph_url
            } ;
            var config = {timeout: 3000} ;
            if (Gofreerev.is_json_request_invalid(pgm, open_graph_request, 'open_graph')) {
                self.new_gift.open_graph_error = $sce.trustAsHtml('Error in preview request for link. See more information in browser log.') ;
                return ;
            }
            $http.post('/util/open_graph.json', open_graph_request, config)
                .then(function (response) {
                    // OK response - can be empty - could by be an error message
                    // console.log(pgm + 'ok. response = ' + JSON.stringify(response));
                    // validate open_graph response received from server
                    if (Gofreerev.is_json_response_invalid(pgm, response.data, 'open_graph', '')) {
                        self.new_gift.open_graph_error = $sce.trustAsHtml('Error in preview response for link. See more information in browser log.') ;
                        return ;
                    }
                    if (response.data.error) {
                        // "nice" error message from server
                        self.new_gift.open_graph_error = $sce.trustAsHtml(response.data.error);
                    }
                    else if (response.data.url) {
                        // ok response from rails with preview info
                        // dirty File Upload plugin/angular integration ==>
                        // remove any preview from File Upload plugin
                        var preview2 = $('#gift_preview');
                        if (preview2) preview2.empty();
                        var disp_gift_file = document.getElementById('disp_gift_file');
                        if (disp_gift_file) disp_gift_file.value = '';
                        // <== dirty File Upload plugin/angular integration
                        // insert open graph preview
                        self.new_gift.open_graph_url = response.data.url;
                        self.new_gift.open_graph_description = response.data.description;
                        self.new_gift.open_graph_title = response.data.title;
                        self.new_gift.open_graph_image = response.data.image;
                    }
                    else {
                        // ok response from rails - url must be invalid
                        null;
                    }
                }, function (error) {
                    // ERROR response - server not responding, timeout, other http errors
                    // status == 0 (try again later) used for:
                    // 1) firefox work offline     - few ms
                    // 2) rails server not running - few ms
                    // 3) rails server timeout     > 3000 ms
                    // console.log(pgm + 'error respose ' + JSON.stringify(error));
                    var starttime = error.config.data.client_timestamp;
                    var endtime = (new Date).getTime();
                    var elapsedtime = endtime - starttime;
                    //console.log('/util/open_graph.json: error: status = ' + error.status +
                    //', starttime = ' + starttime + ', endtime = ' + endtime +
                    //', timeout = ' + error.config.timeout + ', elapsedtime = ' + elapsedtime);
                    if (error.status != 0) console.log(pgm + 'error respose ' + JSON.stringify(error));
                    if (error.status == 0) self.new_gift.open_graph_error = $sce.trustAsHtml(I18n.t('js.new_gift.open_graph_timeout'));
                    else self.new_gift.open_graph_error = $sce.trustAsHtml(I18n.t('js.new_gift.open_graph_error', {status: error.status}));
                });
        } // gift_open_graph_url_done

        // new_gift.open_graph_url ng-change
        self.new_gift_open_graph_url_change = function () {
            // setup timer. fire ajax request in 2 seconds unless cancelled by a new new_gift_open_graph_url ng-change
            clearTimeout(gift_open_graph_url_timer);
            if (!self.new_gift.open_graph_url) reset_open_graph_preview() ;
            else gift_open_graph_url_timer = setTimeout(gift_open_graph_url_done, 2000);
        };

        // <== new gift link open graph preview in gifts/index page

        // resize input textarea after current digest cycle is finish
        // todo: find a better way to trigger textarea resize event in angularJS
        var resize_textarea = function (text) {
            var textareas = $window.document.getElementsByTagName('textarea') ;
            var textarea ;
            for (var i=0 ; i<textareas.length ; i++) if (textareas[i].value == text) textarea = textareas[i] ;
            if (textarea) {
                $timeout(function () {
                    Gofreerev.autoresize_text_field(textarea) ;
                }, 0, false) ;
            }
        };

        // new_gift ng-submit
        self.create_new_gift = function () {
            var pgm = controller + '.create_new_gift: ' ;
            self.new_gift.error = null ;
            var gift = {
                gid: Gofreerev.get_new_uid(),
                giver_user_ids: [],
                receiver_user_ids: [],
                created_at_client: Gofreerev.unix_timestamp(),
                price: self.new_gift.price,
                currency: self.new_gift.currency,
                direction: self.new_gift.direction,
                description: self.new_gift.description,
                open_graph_url: self.new_gift.open_graph_url,
                open_graph_title: self.new_gift.open_graph_title,
                open_graph_description: self.new_gift.open_graph_description,
                open_graph_image: self.new_gift.open_graph_image,
                show: true,
                new_comment: {comment: ""}
            };
            if (gift.direction == 'giver') gift.giver_user_ids = userService.get_login_userids() ;
            else gift.receiver_user_ids = userService.get_login_userids() ;
            var errors ;
            if (errors=giftService.invalid_gift(gift, [], 'create', null)) {
                self.new_gift.error = 'Could not create new gift: ' + errors ;
                console.log(pgm + 'Could not create gift: ' + self.new_gift.error) ;
                console.log(pgm + 'gift = ' + JSON.stringify(gift)) ;
                return ;
            };
            // add new gift to 1) JS array and 2) localStorage
            giftService.save_new_gift(gift) ;
            // send create gift action to server (server side signature)
            giftService.verify_gifts_add(gift, 'create') ;
            // resize description textarea after current digest cycle is finish
            resize_textarea(gift.description) ;
            // reset new gift form
            init_new_gift() ;
            // add new gift to local storage
        }; // self.create_new_gift

        // new comment ng-submit
        self.create_new_comment = function (gift) {
            var pgm = 'GiftsCtrl.create_new_comment: ' ;
            // console.log(pgm + (gift.comments || []).length + ' comments before refresh') ;
            giftService.refresh_gift(gift) ;
            // console.log(pgm + (gift.comments || []).length + ' comments after refresh') ;
            // $window.alert(pgm + 'gift = ' + JSON.stringify(gift) + ', new_comment = ' + JSON.stringify(gift.new_comment)) ;
            if (typeof gift.comments == 'undefined') gift.comments = [] ;
            // note that user_ids can be from other login providers than giver and/or creator of gift
            //
            var new_comment = {
                cid: Gofreerev.get_new_uid(),
                user_ids: userService.get_login_userids(),
                comment: gift.new_comment.comment,
                price: gift.new_comment.price,
                currency: userService.get_currency(),
                created_at_client: Gofreerev.unix_timestamp(),
                new_deal: gift.new_comment.new_deal
            } ;
            var errors ;
            if (errors=giftService.invalid_comment(new_comment, [], 'create', null)) {
                gift.new_comment.error = 'Could not create new comment: ' + errors ;
                gift.new_comment.error_at = Gofreerev.unix_timestamp() ;
                console.log(pgm + 'Could not create comment: ' + gift.new_comment.error) ;
                console.log(pgm + 'comment = ' + JSON.stringify(comment)) ;
                return ;
            }
            // console.log(pgm + 'cid = ' + new_comment.cid) ;
            // resize comment textarea after current digest cycle is finish
            resize_textarea(new_comment.comment) ;
            // console.log(pgm + 'created_at_client = ' + new_comment.created_at_client) ;
            gift.new_comment.comment = null ;
            gift.new_comment.price = null ;
            gift.new_comment.new_deal = false ;
            delete gift.new_comment.error ;
            delete gift.new_comment.error_at ;
            var old_no_rows = gift.show_no_comments || self.default_no_comments ;
            gift.comments.push(new_comment) ;
            // console.log(pgm + (gift.comments || []).length + ' comments after refresh and new comment') ;
            if (gift.comments.length > old_no_rows) {
                old_no_rows = old_no_rows + 1 ;
                gift.show_no_comments = old_no_rows ;
            }
            // reset size for new comment textarea after current digest cycle
            $timeout(function () {
                var text = $window.document.getElementById(gift.gid + '-new-comment') ;
                if (text) Gofreerev.autoresize_text_field(text) ;
            }, 0, false) ;
            userService.add_new_login_users(new_comment.user_ids) ;
            giftService.save_gift(gift) ;
            // send create comment action to server (server side signature)
            giftService.verify_comments_add(gift, new_comment, 'create') ;
        }; // create_new_comment

        // end GiftsCtrl
    }]);
