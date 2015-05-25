// Gofreerev angularJS code

angular.module('gifts')
    .factory('NotiService', ['TextService', function (textService) {
        var self = this ;
        var service = 'NotiService' ;
        console.log(service + ' loaded') ;

        // load any old notification (nid => folder => messages)
        var notifications = [] ;
        (function () {
            // load any stored notifications
            var stored_notifications = Gofreerev.getItem('noti') ;
            if (stored_notifications) notifications = JSON.parse(stored_notifications) ;
        })();

        var notification_nid_index = {} ; // nid => pos in notifications array
        function init_notification_nid_index () {
            notification_nid_index = {} ;
            for (var i=0 ; i<notifications.length ; i++) notification_nid_index[notifications[i].nid] = i ;
        }
        init_notification_nid_index() ;

        // hash with known notification types. save=true => save in localStorage
        var notification_types = {
            add_noti: { title: I18n.t('js.noti_title.add_noti'), save: false },
            delete_gift: { title: I18n.t('js.noti_title.delete_gift'), save: true }
        } ;

        // add notification - returns an nid (unique notification id) - used as id for repeating notifications - for example ping errors
        // args is an object with notitype, key, options, url, nid and extra:
        // - notitype must exist in notificatin_types
        // - translation key <notitype>_<key> must exist in locales (en, da etc)
        // - optional options with options for translation key
        // - url is an options angularJS url - link to gift, user etc
        // - nid is old/previous nid. used for repeating notifications. for example ping or communication errors
        // - extra is optional extra information. for example gid
        var add_notification = function (args) {
            var pgm = service + '.add_notification: ';
            JSON.parse(JSON.stringify(args)) ; // stack trace if args is not stringify-able / cannot is saved in localStorage
            if ((typeof args.notitype != 'string') || (typeof args.key != 'string')) {
                console.log(pgm + 'System error. Missing required arguments notitype and key when calling add_notification. args = ' + JSON.stringify(args)) ;
                add_notification({notitype: 'add_noti', key: 'req', options: {args: JSON.stringify(args)}});
                return undefined_variable ; // show stack trace in log
            }

            // save: true: save notification in localStorage. false: save only temporary in js notifications array
            var save = false, error, key ;
            if (!notification_types.hasOwnProperty(args.notitype)) {
                console.log(pgm + 'System error. Unknown notitype ' + args.notitype + ' when calling add_notification') ;
                add_notification({notitype: 'add_noti', key: 'notitype', options: {notitype: args.notitype }});
                return undefined_variable ; // show stack trace in log
            }
            else if (typeof notification_types[args.notitype].save != 'boolean') {
                console.log(pgm + 'Warning. Missing or invalid save property for notification type ' + args.notitype + '. Must be true or false.');
                add_notification({notitype: 'add_noti', key: 'save', options: {notitype: args.notitype, save: JSON.stringify(args.save)}});
                notification_types[args.notitype].save = false;
            }
            else save = notification_types[args.notitype].save;

            if (typeof notification_types[args.notitype].title != 'string') {
                console.log(pgm + 'Warning. Missing or invalid title property for notification type ' + args.notitype + '. Must be a text string.');
                add_notification({notitype: 'add_noti', key: 'title', options: {notitype: args.notitype, title: JSON.stringify(notification_types[notitype].title)}});
                notification_types[args.notitype].title = 'Notification type ' + args.notitype + ' with missing or invalid title.';
            } ;

            // find or create folder.
            var now = Gofreerev.unix_timestamp();
            var nid = args.nid ;
            var index, folder;
            if (nid) {
                // check if folder nid still exists
                if (notification_nid_index.hasOwnProperty(nid)) {
                    index = notification_nid_index[nid] ;
                    folder = notifications[index] ;
                    if (index > 0) {
                        // move folder with newest messages to top
                        notifications.splice(index, 1) ;
                        notifications.unshift(folder) ;
                        init_notification_nid_index() ;
                    }
                }
            }
            if (!folder) {
                // add new folder
                nid = Gofreerev.get_new_uid();
                folder = { nid: nid, count: 0, created_at: now, updated_at: now, save: false, messages: []} ;
                notifications.unshift(folder) ;
                if (notifications.length > 20) notifications.length = 20; // max 20 folders with max 5 messages in each folder = max 100 messages
                init_notification_nid_index() ;
            };
            if (save) folder.save =true ;
            if (folder.save) save=true ;

            // find or create message. max 5 messages in each folder / for each nid
            // messages are identical if notitype, key, options, url and extra are identical
            // don't include timestamps in extra
            var new_message = { notitype: args.notitype, key: args.key } ;
            if (args.options) new_message.options = args.options ;
            if (args.url) new_message.url = args.url ;
            if (args.extra) new_message.extra = args.extra ;
            var new_message_json = JSON.stringify(new_message) ;
            var i, old_message, old_message_clone ;
            index = -1 ;
            for (i=0 ; i<folder.messages.length ; i++) {
                old_message = folder.messages[i] ;
                old_message_clone = { notitype: old_message.notitype, key: old_message.key} ;
                if (old_message.options) old_message_clone.options = old_message.options ;
                if (old_message.url) old_message_clone.url = old_message.url ;
                if (old_message.extra) old_message_clone.extra = old_message.extra ;
                if (new_message_json == JSON.stringify(old_message_clone)) { index = i ; break ; };
            } // for i (folder.messages)
            if (index == -1) {
                new_message.created_at = now ;
                new_message.updated_at = now ;
                new_message.count = 1 ;
                folder.messages.unshift(new_message) ;
                if (folder.messages.length > 5) folder.messages.length = 5 ;
            }
            else {
                old_message = folder.messages[index] ;
                old_message.updated_at = now ;
                old_message.count += 1 ;
            }
            folder.count += 1 ;
            folder.updated_at = now ;

            // output to log
            key = 'js.noti.' + args.notitype + '_' + args.key ;
            console.log(pgm + key + ' = ' + I18n.t(key, args.options)) ;

            // keep "last" 20 notification.
            if (notifications.length > 20) {
                init_notification_nid_index() ;
            }

            // save only notifications with save=true
            if (save) {
                var notifications_clone = [] ;
                for (i=0 ; i<notifications.length ; i++) {
                    folder = notifications[i] ;
                    if (folder.save) notifications_clone.push(folder) ;
                }
                Gofreerev.setItem('noti', JSON.stringify(notifications_clone));
            }

            return nid;
        }; // add_notification

        return {
            notifications: notifications,
            add_notification: add_notification
        };
    }]);