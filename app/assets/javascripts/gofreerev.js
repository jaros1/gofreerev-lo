// some global JS variables - see app layout and shared/show_more_rows partial
// var debug_ajax, show_more_rows_table ;

// fix missing Array.indexOf in IE8
// http://stackoverflow.com/questions/3629183/why-doesnt-indexof-work-on-an-array-ie8
if (!Array.prototype.indexOf)
{
    Array.prototype.indexOf = function(elt /*, from*/)
    {
        var len = this.length >>> 0;

        var from = Number(arguments[1]) || 0;
        from = (from < 0)
            ? Math.ceil(from)
            : Math.floor(from);
        if (from < 0)
            from += len;

        for (; from < len; from++)
        {
            if (from in this &&
                this[from] === elt)
                return from;
        }
        return -1;
    };
}

// Gofreerev closure start
var Gofreerev = (function() {

    // constants from ruby on rails. see ruby_to.js.erb
    var rails = {} ;

    // keep track of "ajaxing". allow running ajax to complete before leaving page
    var ajaxing = false ;
    var leaving_page = false ;
    $(document).ajaxStart(function() {
        ajaxing = true;
    });
    $(document).ajaxStop(function() {
        ajaxing = false;
    });
    $(document).ready(function () {
        leaving_page = false ;
    });

    // error helper functions

    // for client side debugging - writes JS messages to debug_log div - only used if DEBUG_AJAX = true
    // debug messages are temp stored in a temp JS array temp_debug_log until page and rails['DEBUG_AJAX'] is ready
    function ajax_debug () {
        return rails['DEBUG_AJAX'] ;
    } ;
    var temp_debug_log = [] ;
    function empty_temp_debug_log() {
        if (ajax_debug() != true) { temp_debug_log = null ; return }
        var log = document.getElementById('debug_log') ;
        if (!log) return ;
        if (temp_debug_log.length > 0) {
            for (var i=0 ; i<temp_debug_log.length ; i++) log.innerHTML = log.innerHTML + temp_debug_log[i] + '<br>' ;
            temp_debug_log = [] ;
        }
    } // empty_temp_debug_log
    function add2log (text) {
        if (ajax_debug() == false) return ;
        var log = document.getElementById('debug_log') ;
        if (!log) {
            // buffer log messages in JS array until page is ready
            temp_debug_log.push(text) ;
            return
        }
        empty_temp_debug_log() ;
        log.innerHTML = log.innerHTML + text + '<br>' ;
    } // add2log

    // empty temp debug log
    $(document).ready(function () {
        empty_temp_debug_log() ;
    });


    // this ajax flash is used when inserting or updating gifts and comments in gifts table
    // todo: add some kind of flash when removing (display=none) rows from gifts table
    function ajax_flash (id)
    {
        // add2log('ajax_flash: id = ' + id) ;
        $('#' + id).css({'background-color':'green'}).animate({'background-color':'white'}, 2000) ;
    } // ajax_flash

    // effect for flash message in page header
    $(document).ready(function () {
        var id = 'notification' ;
        if (!document.getElementById(id)) return ;
        ajax_flash(id) ;
    });

    // ajax flash for table rows - for example new rows in ajax_task_errors table
    function ajax_flash_new_table_rows (tablename, number_of_rows)
    {
        var pgm = 'ajax_flash_new_table_rows: ' ;
        // add2log(pgm + 'table_name = ' + tablename + ', number_of_rows = ' + number_of_rows) ;
        var table = document.getElementById(tablename) ;
        if (!table) return ;
        var rows = table.rows ;
        if (rows.length < number_of_rows) number_of_rows = rows.length ;
        var now = (new Date()).getTime() ;
        var id ;
        // add2log(pgm + 'number_of_rows = ' + number_of_rows) ;
        for (i=rows.length-number_of_rows ; i < rows.length ; i++) {
            id = 'afe-' + now + '-' + i ;
            rows[i].id = id;
            ajax_flash(id) ;
        } // for
    } // ajax_flash_new_table_rows

    // add error to tasks_error table in page header
    function add_to_tasks_errors (error) {
        var pgm = 'add_to_tasks_errors: ' ;
        var table = document.getElementById('tasks_errors') ;
        if (!table) {
            add2log(pgm + 'tasks_errors table was not found.') ;
            add2log(pgm + 'error: ' + error + '.') ;
            return ;
        }
        delete_old_error(table, error) ;
        var length = table.length ;
        var row = table.insertRow(length) ;
        var cell1 = row.insertCell(0) ;
        cell1.innerHTML = error ;
        var cell2 = row.insertCell(1) ;
        cell2.innerHTML = (new Date).getTime() ;
        ajax_flash_new_table_rows('tasks_errors', 1);
    } // add_to_tasks_errors

    function add2log_ajax_error (pgm, jqxhr, textStatus, errorThrown) {
        add2log(pgm) ;
        add2log('jqxhr = ' + jqxhr);
        add2log('jqxhr.target = ' + jqxhr.target);
        add2log('textStatus = ' + textStatus);
        add2log('errorThrown = ' + errorThrown);
        if (errorThrown && (errorThrown != '')) return errorThrown ;
        if (textStatus && (textStatus != '')) return textStatus ;
        return 'error' ;
    } // add2log_ajax_error

    // clear error messages in page header before ajax request. For example before submitting new gift
    function clear_ajax_errors(table_id) {
        // empty table with ajax messages if any
        var pgm = 'clear_ajax_errors: ' ;
        add2log(pgm + 'table_id = ' + table_id) ;
        var table = document.getElementById(table_id) ;
        if (!table) return ;
        var rows = table.rows ;
        var row ;
        for (var i=rows.length-1 ; i>= 0 ; i--) {
            row = rows[i] ;
            row.parentNode.removeChild(row) ;
        } // for
    } // clear_ajax_errors
    function clear_flash_and_ajax_errors() {
        // clear old flash message if any
        var notification = document.getElementById('notification');
        if (notification) notification.innerHTML = '' ;
        // empty table with task (error) messages if any
        clear_ajax_errors('tasks_errors') ;
    } // clear_flash_and_ajax_errors

    // onchange helper used in user/edit page. ajax update user currency
    function onchange_currency (self) {
        // check if submit is ok (are there other unsaved data in page?)
        var user_currency_old_id;
        user_currency_old_id = document.getElementById('user_currency_old');
        if ((user_currency_old_id) && (user_currency_old_id.value == self.value)) return ;
        var currency_submit = document.getElementById('currency_submit');
        // todo: check safari 5 workaround. See show_more_rows
        if (currency_submit) currency_submit.click() ; // ok rails ajax submit
        else self.form.submit() ; // error forms submit with js text response
    } // onchange_currency

    // keep track of "ajaxing". allow running ajax to complete before leaving page
    // this solution gives a nice message when user clicks on a http link (leaving page).
    // It could be nice with a solution that also gives a message for ajax request (not leaving page).
    window.onbeforeunload = function() {
        if (ajaxing) {
            // Waiting for some finish some unfinished business to finish. Please wait.
            // todo: second click re-flash effect not working
            if (leaving_page) ajax_flash_new_table_rows('tasks_errors', 1) ;
            else add_to_tasks_errors(I18n.t('js.general.ajax_leave_page', {location: 1, debug: 0})) ;
        }
        leaving_page = true;
    }; // window.onbeforeunload


    var last_user_ajax_comment_at ; // timestamp (JS Date) for last new comment created by user
    // todo: reset last_user_ajax_comment_at was used in old gofreerev-fb version with turbolinks
    //       and turbolinks are not relevant in angularJS version (using routes)
    //
    function reset_last_user_ajax_comment_at () {
        last_user_ajax_comment_at = null ;
    }


    // 3. functions used in util/new_messages_count ajax call.

    // catch load errors  for api pictures. Gift could have been deleted. url could have been changed
    // gift ids with invalid picture urls are collected in a global javascript array and submitted to server in 2 seconds
    // on error gift.api_picture_url_on_error_at is set and a new picture url is looked up if possible
    // JS array with gift ids
    var missing_api_picture_urls = [];

    // function used in onload for img tags
    function imgonload(img) {
        // todo: not implemented - move to angularJS (GiftService) - gid in data attribute
        return ;
        var api_gift_id ;
        if (img.dataset) api_gift_id = img.dataset.id ;
        else api_gift_id = img.getAttribute('data-id') ;
        var flickr = img.src.match(/^https?:\/\/farm\d+\.staticflickr\.com\//) ;
        //    add2log('imgonload. api gift id = ' + api_gift_id + ', img.width = ' + img.width + ', img.height = ' + img.height +
        //        ', naturalWidth = ' + img.naturalWidth + ', naturalHeight = ' + img.naturalHeight + ', complete = ' + img.complete) ;
        if ((img.width <= 1) && (img.height <= 1)) {
            // image not found - url expired or api picture deleted
            // alert('changed picture url: gift_id = ' + giftid + ', img = ' + img + ', width = ' + img.width + ', height = ' + img.height) ;
            missing_api_picture_urls.push(api_gift_id);
        }
        else if ((img.naturalWidth <= 1) && (img.naturalHeight <= 1)) {
            // image not found - url expired or api picture deleted
            // alert('changed picture url: gift_id = ' + giftid + ', img = ' + img + ', width = ' + img.width + ', height = ' + img.height) ;
            missing_api_picture_urls.push(api_gift_id);
        }
        else if (flickr && (img.width == 500) && (img.height == 374) ) {
            // Flickr: could be https://s.yimg.com/pw/images/photo_unavailable.gif (width 500, height 374)
            // there is no javascript method to direct redirect. Mark picture as missing and let the server check picture and redirect
            missing_api_picture_urls.push(api_gift_id);
            img.width = 200; // rescale
        }
        else {
            // image found. rescale
            img.width = 200;
        }
    } // imgonload
    // function used in onload for img tags
    function imgonerror(img) {
        // todo: not implemented - move to angularJS (GiftService) - gid in data attribute
        return ;
        var api_gift_id ;
        if (img.dataset) api_gift_id = img.dataset.id ;
        else api_gift_id = img.getAttribute('data-id') ;
        add2log('imgonerror. api gift id = ' + api_gift_id + ', img.width = ' + img.width + ', img.height = ' + img.height +
        ', naturalWidth = ' + img.naturalWidth + ', naturalHeight = ' + img.naturalHeight + ', complete = ' + img.complete) ;
        missing_api_picture_urls.push(api_gift_id);
    } // imgonerror


    // http://stackoverflow.com/questions/152483/is-there-a-way-to-print-all-methods-of-an-object-in-javascript
    function getMethods(obj) {
        var result = [];
        for (var id in obj) {
            try {
                if (typeof(obj[id]) == "function") {
                    result.push(id + ": " + obj[id].toString());
                }
            } catch (err) {
                result.push(id + ": inaccessible");
            }
        }
        return result;
    }


    // auto resize text fields
    // found at http://stackoverflow.com/questions/454202/creating-a-textarea-with-auto-resize
    var observe;
    if (window.attachEvent) {
        observe = function (element, event, handler) {
            element.attachEvent('on' + event, handler);
        };
    }
    else {
        observe = function (element, event, handler) {
            element.addEventListener(event, handler, false);
        };
    }
    function autoresize_text_field(text) {
        function resize() {
            text.style.height = 'auto';
            text.style.height = text.scrollHeight + 'px';
        }

        /* 0-timeout to get the already changed text */
        function delayedResize() {
            window.setTimeout(resize, 0);
        }

        observe(text, 'change', resize);
        observe(text, 'cut', delayedResize);
        observe(text, 'paste', delayedResize);
        observe(text, 'drop', delayedResize);
        observe(text, 'keydown', delayedResize);

        text.focus();
        text.select();
        resize();
    }


    // http://stackoverflow.com/questions/10944396/how-to-calculate-ms-since-midnight-in-javascript
    function getMsSinceMidnight() {
        var d = new Date() ;
        var e = new Date(d);
        return d - e.setHours(0,0,0,0);
    } // getMsSinceMidnight
    function getSecondsSinceMidnight() {
        return 1.0 * getMsSinceMidnight() / 1000 ;
    } // getSecondsSinceMidnight

    // todo: move to angularJS NavCtrl
    function get_js_timezone() {
        return -(new Date().getTimezoneOffset()) / 60.0 ;
    }

    // delete old messages before inserting new identical error message
    function delete_old_error (table, error) {
        var rows = table.rows ;
        if (rows.length == 0) return ;
        for (var i=rows.length-1 ; i>=0 ; i--) {
            if (rows[i].cells[0].innerHTML == error) table.deleteRow(i) ;
        }
    } // delete_old_error


    // write ajax error to ajax error table within page - for example ajax error tables under gift links or under each comment
    // called from move_tasks_errors2 and from gift/comment link ajax handlers
    // ajax error tables under gift links and comments are created dynamic when needed
    function add_to_tasks_errors2 (table_id, error) {
        if (table_id == 'show-more-rows-errors') {
            // also inject error message into top of page
            clear_ajax_errors('show-more-rows-errors') ;
            add_to_tasks_errors(error) ;
        }
        var pgm = 'add_to_tasks_errors2: ' ;
        var table = document.getElementById(table_id) ;
        if (!table) {
            add2log(pgm + table_id + ' was not found.') ;
            add2log(pgm + 'error was ' + error + '') ;
            add_to_tasks_errors(pgm + 'expected error table ' + table_id + ' was not found. Error ' + error) ;
            return ;
        }
        delete_old_error(table, error) ;
        var length = table.rows.size ;
        add2log(pgm + 'length = ' + length) ;
        var row = table.insertRow(length) ;
        var cell1 = row.insertCell(0) ;
        cell1.innerHTML = error ;
        var cell2 = row.insertCell(1) ;
        cell2.innerHTML = (new Date).getTime() ;
        ajax_flash_new_table_rows(table_id, 1);
    } // add_to_tasks_errors2

    // as add_to_tasks_errors2 - but create missing tasks error table within page
    function add_to_tasks_errors3(table_id, msg)
    {
        var table = document.getElementById(table_id);
        if (!table) {
            // create missing table
            if (!create_com_link_errors_table(table_id)) {
                // write to error table in page header
                add_to_tasks_errors(msg + ' (inject not implemented for error message with id ' + table_id + ').');
                return;
            }
            // error table was created
        }
        // add to error table inside page
        add_to_tasks_errors2(table_id, msg);
    } // add_to_tasks_errors3

    // move ajax error messages from tasks_errors2 to more specific location in page
    // first column is error message. Second column is id for error table in page
    // tasks_errors table in page header will be used of more specific location can not be found
    function move_tasks_errors2() {
        var pgm = 'move_tasks_errors2: ' ;
        add2log(pgm + 'start') ;
        var from_table = document.getElementById('tasks_errors2');
        if (!from_table) {
            add2log(pgm + 'tasks_errors2 was not found') ;
            add_to_tasks_errors(I18n.t('js.general.tasks_errors2_missing', {location: 16, debug: 1}));
            return;
        }
        var rows = from_table.rows;
        var lng = rows.length;
        var row, cells, msg, to_table_id, to_table;
        var re1, giftid, ref_id, ref, new_tr, new_td, j;
        add2log(pgm + lng + ' rows in tasks_errors2 table') ;
        for (var i = lng - 1; i >= 0; i--) {
            row = rows[i];
            cells = row.cells;
            if (cells.length != 2) {
                add_to_tasks_errors(I18n.t('js.general.tasks_errors2_invalid', {row: i, expected: 2, found: cells.length, location: 16, debug: 1}));
                continue;
            }
            msg = cells[0].innerHTML;
            to_table_id = cells[1].innerHTML;
            add2log(pgm + 'msg = ' + msg + ', to_table_id = ' + to_table_id);
            add_to_tasks_errors3(to_table_id,msg) ;
            row.parentNode.removeChild(row);
        } // for
        // alert('move_tasks_errors2. lng = ' + lng);
    } // move_tasks_errors2


    // display cookie_note div for the first SHOW_COOKIE_NOTE seconds when a new user visits gofreerev
    function hide_cookie_note() {
        var cookie_node = document.getElementById('cookie_note') ;
        if (!cookie_node) return ;
        cookie_node.style.display = 'none' ;
    } // hide_cookie_note


    // set JS timezone in tasks form
    // send to server in util/to_tasks
    $(document).ready(function() {
        var timezone = document.getElementById("timezone") ;
        if (!timezone) return ;
        timezone.value = get_js_timezone();
        // add2log('timezone = ' + timezone.value) ;
    });

    // local or session storage functions ==>

    // values in sessionStorage:
    // - data are discarded when user closes browser tab
    // - only userid and password keys
    // - never <userid> prefix before key
    // - values are not compressed or encrypted

    // values in localStorage:
    // - data are preserved when user closes tab or browser
    // - some values are global values without <userid> prefix. others are user specific values with <userid> prefix
    // - some values are encrypted (keys, authorization and other sensible information)
    // - encryption: key is as only item encrypted with password (human text). All other encrypted items are is encrypted with key (random string)
    // - some values are compressed (users and gifts arrays)
    // - rules (local_storage_rules) are derived from key name
    // - default values are <userid> prefix, no encryption and no compression (write warning in console.log)

    var storage_rules = {
        currency: {session: false, userid: true, compress: false, encrypt: false}, // currency code (ISO 4217)
        did: {session: false, userid: true, compress: false, encrypt: false}, // new unique device id
        friends: {session: false, userid: true, compress: true, encrypt: true}, // array with downloaded friends info from login
        gifts: {session: false, userid: true, compress: true, encrypt: true}, // "array" with gifts - encrypted - pseudo rule used for gift_1, gift_2 etc
        key: {session: false, userid: true, compress: true, encrypt: true}, // random password - used for localStorage encryption
        noti: {session: false, userid: true, compress: true, encrypt: true}, // "array" with notifications (message in UI) - only some type of notifications are saved in localStorage
        password: {session: true, userid: false, compress: false, encrypt: false}, // session password in clear text
        passwords: {session: false, userid: false, compress: false, encrypt: false}, // array with hashed passwords. size = number of accounts
        oauth: {session: false, userid: true, compress: true, encrypt: true}, // login provider oauth authorization
        prvkey: {session: false, userid: true, compress: true, encrypt: true}, // for encrypted user to user communication
        pubkey: {session: false, userid: true, compress: true, encrypt: false}, // for encrypted user to user communication
        secret: {session: false, userid: true, compress: true, encrypt: false}, // client secret - used as secret element in device.sha256 - 10 digits
        seq: {session: false, userid: true, compress: true, encrypt: false}, // sequence - for example used in verify_gifts request and response
        sid: {session: true, userid: false, compress: false, encrypt: false}, // unique session id - changes for every new device login
        userid: {session: true, userid: false, compress: false, encrypt: false}, // session userid (1, 2, etc) in clear text
        users: {session: false, userid: true, compress: true, encrypt: true} // array with users used in gifts and comments
    };

    // first character in stored value is an encryption/compression storage flag
    // storage flag makes it possible to select best compression method
    // and storage flag makes it possible to later change storage rules for already saved values
    var storage_flags = {
        a: { compress: 0, encrypt: 0, sequence: 0}, // clear text - not compressed, not encrypted
        b: { compress: 0, encrypt: 1, sequence: 0}, // encrypted only - not compressed
        c: { compress: 1, encrypt: 0, sequence: 0}, // LZString synchronous compression, not encrypted
        d: { compress: 1, encrypt: 1, sequence: 0}, // LZString synchronous compression, compress => encrypt
        e: { compress: 1, encrypt: 1, sequence: 1}, // LZString synchronous compression, encrypt => compress
        f: { compress: 2, encrypt: 0, sequence: 0}, // LZMA level 1 asynchronous compression, not encrypted
        g: { compress: 2, encrypt: 1, sequence: 0}, // LZMA level 1 asynchronous compression, compress => encrypt
        h: { compress: 2, encrypt: 1, sequence: 1}, // LZMA level 1 asynchronous compression, encrypt => compress
        i: { compress: 3, encrypt: 0, sequence: 0}, // compression 3, not encrypted (reserved / not implemented)
        j: { compress: 3, encrypt: 1, sequence: 0}, // compression 3, compress => encrypt (reserved / not implemented)
        k: { compress: 3, encrypt: 1, sequence: 1}, // compression 3, encrypt => compress (reserved / not implemented)
        l: { compress: 4, encrypt: 0, sequence: 0}, // compression 4, not encrypted (reserved / not implemented)
        m: { compress: 4, encrypt: 1, sequence: 0}, // compression 4, compress => encrypt (reserved / not implemented)
        n: { compress: 4, encrypt: 1, sequence: 1}  // compression 4, encrypt => compress (reserved / not implemented)
    } ;

    // reverse index - from compress*encrypt*sequence (binary 0-19) to storage flag a-n
    var storage_flag_index = {} ;
    function storage_options_bin_key (storage_options) {
        return 4*storage_options.compress + 2*storage_options.encrypt + storage_options.sequence ;
    }
    (function () {
        var storage_flag ; // a-n
        var index ; // 0-19
        for (storage_flag in storage_flags) {
            if (storage_flags.hasOwnProperty(storage_flag)) {
                index = storage_options_bin_key(storage_flags[storage_flag]) ;
                storage_flag_index[index] = storage_flag ;
            }
        }
    })();

    // todo: how to handle "no more space" in local storage?
    // 1) only keep newer gifts and relevant users in local storage
    //    gifts and users arrays should be saved in local storage in one operation to allow automatic space management
    //    add oldest_gift_at timestamp. Ignore gifts with timestamp before oldest_gift_id when sync. gifts with other devices
    //    or oldest_gift_id pointer. Ignore gifts with gift_id < oldest_gift_ud when sync. gifts when other devices
    // 2) a possibility is to store old blocks with gifts and users on server encrypted with pubkey
    //    that is show-more-rows functionality at end of page
    //    send a server request to get old data block. Return old data block and insert into users and gifts js arrays
    //    old data block stored on server can be changed if user info changes, friendship changes, or gifts are change or are deleted

    // symmetric encrypt sensitive data in local storage.
    // password is saved in session storage and is deleted when user closes tab in browser
    // also used for symmetric encryption in communication between clients
    function encrypt (text, password) {
        var output_wa ;
        output_wa = CryptoJS.AES.encrypt(text, password, { format: CryptoJS.format.OpenSSL }); //, { mode: CryptoJS.mode.CTR, padding: CryptoJS.pad.AnsiX923, format: CryptoJS.format.OpenSSL });
        return output_wa.toString(CryptoJS.format.OpenSSL) ;
    }
    function decrypt (text, password) {
        var output_wa ;
        output_wa = CryptoJS.AES.decrypt(text, password, { format: CryptoJS.format.OpenSSL }); // , { mode: CryptoJS.mode.CTR, padding: CryptoJS.pad.AnsiX923, format: CryptoJS.format.OpenSSL });
        return output_wa.toString(CryptoJS.enc.Utf8) ;
    }

    // LZString compress and decompress strings - fast and synchronous compress and decompress
    // https://github.com/pieroxy/lz-string
    // http://pieroxy.net/blog/pages/lz-string/guide.html)
    function compress1 (text) {
        return LZString.compressToUTF16(text);
    }
    function decompress1 (text) {
        return LZString.decompressFromUTF16(text) ;
    }

    // LZMA level 1 compress and decompress strings - not as fast as LZString - runs asynchronous
    // setItem uses LZString in compression. At end setItem submit a asynchronous task to check if LZMA level 1 compress is better
    // todo: LZMA disabled until I find a good method to convert byte array output from LZMA.compress into an utf-16 encoded string

    // lzma_compress0 - sequence = 0 - not encrypted or normal compress => encrypt sequence
    // lzma_compress1 - sequence = 1 - encrypted and reverse encrypt => compress sequence

    // params:
    // - key and value - original inputs to setItem
    // - session: true: sessionStorage, false: localStorage
    // - password: null: not encrypted, != null: encrypted
    // - length: length of lzstring compressed value (without storage flag)
    function lzma_compress1(key, value, session, password, length) {
        var pgm = 'lzma_compress1: ';
        value = encrypt(value, password);
        // start compress
        // var lzma = new LZMA;
        LZMA.compress(value, 1, function (value) {
            // compress result received
            console.log(pgm + 'compress result received. value = ' + value) ;
            if (value.length >= length) return;
            // lzma compress sequence 2 was better than lzstring compress and/or lzma compress sequence = 0 (compress => encrypt)
            console.log(pgm + 'key = ' + key + '. lzma compress sequence 2 was better than lzstring compress and/or lzma compress sequence = 0 (compress => encrypt)') ;
            // find storage flag and save new compressed value
            var storage_options = {compress: 2, encrypt: 1, sequence: 1};
            var bin_key = storage_options_bin_key(storage_options);
            var storage_flag = storage_flag_index[bin_key];
            if (!storage_flag) {
                console.log(pgm + 'Warning. key ' + key + ' was not optimized. Could not found storage flag for storage options = ' + JSON.stringify(storage_options));
                return;
            }
            value = storage_flag + value;
            // save
            if (session) sessionStorage.setItem(key, value);
            else localStorage.setItem(key, value);
        }, null);
    } // lzma_compress1
    function lzma_compress0(key, value, session, password, length) {
        var pgm = 'lzma_compress0: ';
        var save_value = value;
        // start compress
        // var lzma = new LZMA;
        LZMA.compress(value, 1, function (value) {
            // compress result received
            console.log(pgm + 'compress result received. value = ' + value) ;
            if (password) value = encrypt(value, password);
            if (value.length < length) {
                // lzma compress was better than lzstring compress
                console.log(pgm + 'key = ' + key + '. lzma compress was better than lzstring compress') ;
                // find storage flag and save new compressed value
                var storage_options = {compress: 2, encrypt: (password ? 1 : 0), sequence: 0};
                var bin_key = storage_options_bin_key(storage_options);
                var storage_flag = storage_flag_index[bin_key];
                if (!storage_flag) {
                    console.log(pgm + 'Warning. key ' + key + ' was not optimized. Could not found storage flag for storage options = ' + JSON.stringify(storage_options));
                    return;
                }
                value = storage_flag + value;
                // save
                if (session) sessionStorage.setItem(key, value);
                else localStorage.setItem(key, value);
                length = value.length - 1;
            }
            ;
            // start start_lzma_compress1 if encrypted - sequence = 1 - encrypt before compress
            if (password) lzma_compress1(key, save_value, session, password, length);
        }, null);
    } // check_lzma_compress

    // look storage rules for key. add default values and write warning to console log when using defaults
    function get_local_storage_rule (key) {
        var pgm = 'Gofreerev.get_local_storage_rule: ' ;
        var key_options ;
        if (storage_rules.hasOwnProperty(key)) key_options = storage_rules[key] ;
        else {
            console.log(pgm + 'Warning. ' + key + ' was not found in local_storage_rules hash.') ;
            key_options = {session: false, userid: true, compress: false, encrypt: false} ;
        }
        if (!key_options.hasOwnProperty('session')) {
            console.log(pgm + 'Warning. using default value session=false for key ' + key) ;
            key_options.session = false ;
        }
        if (!key_options.hasOwnProperty('userid')) {
            key_options.userid = !key_options.session ;
            console.log(pgm + 'Warning. using default value userid=' + key_options.userid + ' for key ' + key) ;
        }
        if (!key_options.hasOwnProperty('compress')) {
            console.log(pgm + 'Warning. using default value compress=false for key ' + key) ;
            key_options.compress = false ;
        }
        if (!key_options.hasOwnProperty('encrypt')) {
            console.log(pgm + 'Warning. using default value encrpt=false for key ' + key) ;
            key_options.encrypt = false ;
        }
        //if (!key_options.hasOwnProperty('key')) {
        //    console.log(pgm + 'Warning. using default value key=false for key ' + key) ;
        //    key_options.key = false ;
        //}
        return key_options ;
    } // get_local_storage_rule

    // get/set item
    function getItem (key) {
        var pgm = 'Gofreerev.getItem: ' ;
        // if (key == 'password') console.log(pgm + 'caller: ' + arguments.callee.caller.toString()) ;
        var pseudo_key = key.match(/^gift_[0-9]+$/) ? 'gifts' : key ; // use gifts rule for gift_1, gift_1 etc
        var rule = get_local_storage_rule(pseudo_key) ;
        if (rule.encrypt) var password_type = (key == 'key' ? 'password' : 'key') ; // key is as only variable encrypted with human password
        // userid prefix?
        if (rule.userid) {
            var userid = getItem('userid') ;
            if ((typeof userid == 'undefined') || (userid == null) || (userid=='')) userid = 0 ;
            else userid = parseInt(userid) ;
            if (userid == 0) {
                // console.log(pgm + 'Error. key ' + key + ' is stored with userid prefix but userid was not found') ;
                return null ;
            }
            key = userid + '_' + key ;
        }
        // read stored value
        var value = rule.session ? sessionStorage.getItem(key) : localStorage.getItem(key) ;
        if ((typeof value == 'undefined') || (value == null) || (value == '')) return null ; // key not found

        // get storage flag - how was data stored - first character in value
        var storage_flag = value.substr(0,1) ;
        value = value.substr(1) ;
        var storage_options = storage_flags[storage_flag] ;
        if (!storage_options) {
            console.log(pgm + 'Error. Invalid storage flag ' + storage_flag + ' was found for key ' + key) ;
            return null ;
        }

        // decompress
        if ((storage_options.compress > 0) && (storage_options.sequence == 1)) {
            // reverse encrypt => compress sequence was used when saving this data. decompress before decrypt
            // console.log(pgm + key + ' before decompress = ' + value) ;
            value = decompress1(value) ;
        }

        // decrypt
        if (storage_options.encrypt) {
            // console.log(pgm + key + ' before decrypt = ' + value) ;
            var password = getItem(password_type) ; // use key or password
            if ((typeof password == 'undefined') || (password == null) || (password == '')) {
                console.log(pgm + 'Error. key ' + key + ' is stored encrypted but ' + password_type + ' was not found') ;
                return null ;
            }
            value = decrypt(value, password);
        }

        // decompress
        if ((storage_options.compress > 0) && (storage_options.sequence == 0)) {
            // normal compress => encrypt sequence was used when saving this data. decompress after decrypt
            // console.log(pgm + key + ' before decompress = ' + value) ;
            value = decompress1(value) ;
        }

        // ready
        // if (storage_options.encrypt || storage_options.compress) console.log(pgm + key + ' after decrypt and decompress = ' + value) ;
        // if (key.match(/oauth/)) console.log('getItem. key = ' + key + ', value = ' + value) ;
        return value ;
    } // getItem

    function setItem (key, value) {
        var pgm = 'Gofreerev.setItem: ' ;
        var save_value = value ; // for optional lzma_compress0
        var pseudo_key = key.match(/^gift_[0-9]+$/) ? 'gifts' : key ; // use gifts rule for gift_1, gift_1 etc
        var rule = get_local_storage_rule(pseudo_key) ;
        if (rule.encrypt) var password_type = (key == 'key' ? 'password' : 'key') ; // key is as only variable encrypted with human password
        // userid prefix?
        if (rule.userid) {
            var userid = getItem('userid') ;
            if ((typeof userid == 'undefined') || (userid == null) || (userid=='')) userid = 0 ;
            else userid = parseInt(userid) ;
            if (userid == 0) {
                // console.log(pgm + 'Error. key ' + key + ' is stored with userid prefix but userid was not found') ;
                return ;
            }
            key = userid + '_' + key ;
        }
        // check password
        var password ;
        if (rule.encrypt) {
            password = getItem(password_type) ; // use key or password
            if ((typeof password == 'undefined') || (password == null) || (password == '')) {
                console.log(pgm + 'Error. key ' + key + ' is stored encrypted but ' + password_type + ' was not found') ;
                return ;
            }
        }
        var sequence ;
        if (rule.compress && rule.encrypt) {
            // compress and encrypt. find best sequence
            // sequence 0 : normal sequence - compress before encrypt
            // sequence 1 : reverse sequence - encrypt before compress
            var value1 = encrypt(compress1(value), password) ;
            var value2 = compress1(encrypt(value, password)) ;
            if (value1.length <= value2.length) {
                sequence = 0 ;
                value = value1 ;
            }
            else {
                sequence = 1 ;
                value = value2 ;
            }
        }
        else {
            sequence = 0 ;
            // compress?
            if (rule.compress) value = compress1(value) ;
            // encrypt?
            if (rule.encrypt) value = encrypt(value, password);
        }
        // set storage flag - how are data stored - first character in value
        var storage_options = { compress: (rule.compress ? 1 : 0),
                                encrypt: (rule.encrypt ? 1 : 0),
                                sequence: sequence };
        var bin_key = storage_options_bin_key(storage_options) ;
        var storage_flag = storage_flag_index[bin_key] ;
        if (!storage_flag) {
            console.log(pgm + 'Error. key ' + key + ' was not saved. Could not found storage flag for storage options = ' + JSON.stringify(storage_options)) ;
            return ;
        }
        value = storage_flag + value ;
        // save
        // if (key.match(/oauth/)) console.log('setItem. key = ' + key + ', value = ' + value) ;
        if (rule.session) sessionStorage.setItem(key, value) ;
        else localStorage.setItem(key, value) ;
        // optimize compression for saved value

        // todo: disabled until I find a method to convert byte array returned from LZMA.compress into an valid utf-16 string
        // check if lzma compress if better than lzstring compress
        // if (rule.compress) lzma_compress0(key, save_value, rule.session, password, value.length-1) ;
    } // setItem

    function removeItem (key) {
        var pgm = 'Gofreerev.setItem: ' ;
        var pseudo_key = key.match(/^gift_[0-9]+$/) ? 'gifts' : key ; // use gifts rule for gift_1, gift_1 etc
        var rule = get_local_storage_rule(pseudo_key) ;
        // sessionStorage or localStorage?
        var storage = rule.session ? sessionStorage : localStorage ;
        // userid prefix?
        if (rule.userid) {
            var userid = getItem('userid') ;
            if ((typeof userid == 'undefined') || (userid == null) || (userid=='')) userid = 0 ;
            else userid = parseInt(userid) ;
            if (userid == 0) {
                console.log(pgm + 'Error. key ' + key + ' is stored with userid prefix but userid was not found') ;
                return null ;
            }
            key = userid + '_' + key ;
        }
        // remove
        if (rule.session) sessionStorage.removeItem(key) ;
        else localStorage.removeItem(key) ;
    } // removeItem

    // generate "unique" id - 20 character decimal string - unix timestamp with milliseconds and random decimals
    // this id should very likely be unique within a network of friends (no guarantees)
    // used for did (unique device id), sid (unique session id), gid (unique gift id) and cid (unique comment id)
    function get_new_uid () {
        var id = new Date().getTime() + (Math.random() + 1).toString(10).substring(2,9) ;
        return id ;
    } // get_new_uid

    // sha256 digest - used for one way password encryption and signatures for gifts and comments
    // arguments: list of input fields to sha256 calculation
    // todo: ignore empty fields at end of input? will allow adding new empty fields to gifts and comments signature without destroying old signatures
    function sha256 () {
        var texts = [] ;
        for (var i=0; i < arguments.length; i++) {
            switch(typeof arguments[i]) {
                case 'string' :
                    texts.push(arguments[i]) ;
                    break ;
                case 'boolean':
                    texts.push(arguments[i].toString()) ;
                    break ;
                case 'number':
                    texts.push(arguments[i].toString());
                    break ;
                case 'undefined':
                    texts.push('') ;
                    break ;
                default:
                    // null or an object
                    if (arguments[i] == null) texts.push('') ;
                    else texts.push(JSON.stringify(arguments[i])) ;
            } // switch
        };
        // strip empty fields from end of sha256 input
        while ((texts.length > 0) && (texts[texts.length-1] == '')) texts.length = texts.length - 1 ;
        var text = texts.length == 0 ? '' : texts.join(',') ;
        return CryptoJS.SHA256(text).toString(CryptoJS.enc.Latin1);
    } // sha256

    // client login (password from client-login-dialog-form)
    // 0 = invalid password, > 0 : userid
    // use create_new_account = true to force create a new user account
    // support for more than one user account
    function client_login (password, create_new_account) {
        var password_sha256, passwords_s, passwords_a, i, userid, did, crypt, pubkey, prvkey, prvkey_aes, giftid_key ;
        password_sha256 = sha256(password);
        // passwords: array with hashed passwords. size = number of accounts
        passwords_s = getItem('passwords') ;
        if ((passwords_s == null) || (passwords_s == '')) passwords_a = [] ;
        else passwords_a = JSON.parse(passwords_s) ;
        // check old accounts
        for (i=0 ; i<passwords_a.length ; i++) {
            if (password_sha256 == passwords_a[i]) {
                // log in ok - account existsgetItem
                userid = i+1 ;
                // save login
                setItem('userid', userid) ;
                setItem('password', password) ;
                if (!getItem('sid')) setItem('sid', Gofreerev.get_new_uid()) ;
                return userid ;
            }
        }
        // password was not found
        if ((passwords_a.length == 0) || create_new_account) {
            // create new account
            userid = passwords_a.length + 1 ; // sequence = number of user accounts in local storage
            // save login in sessionStorage
            // note that password is saved in clear text in sessionStorage
            // please use device log out or close browser tab when finished
            setItem('userid', userid) ;
            setItem('password', password) ;
            if (!getItem('sid')) setItem('sid', Gofreerev.get_new_uid()) ;
            // setup new account
            did = Gofreerev.get_new_uid() ; // unique device id
            passwords_a.push(password_sha256) ;
            passwords_s = JSON.stringify(passwords_a) ;
            // generate key pair for client to client RSA encryption (symmetric password handshake)
            crypt = new JSEncrypt({default_key_size: 2048});
            crypt.getKey();
            pubkey = crypt.getPublicKey();
            prvkey = crypt.getPrivateKey();
            // key for symmetric encryption in localStorage - 80-120 characters (avoid using human text in encryption)
            var key_lng = Math.round(Math.random()*40)+80 ;
            var key = Gofreerev.generate_random_password(key_lng) ;
            // save new user account
            setItem('key', key) ;
            setItem('did', did) ; // unique device id
            setItem('prvkey', prvkey) ; // private key - only used on this device - never sent to server or other clients
            setItem('pubkey', pubkey) ; // public key - sent to server and other clients
            setItem('seq', '0') ; // sequence, for example used in verify gifts request/response
            setItem('passwords', passwords_s) ; // array with sha256 hashed passwords. length = number of accounts
            return userid ;
        }
        // invalid password (create_new_account=false)
        return 0 ;
    } // client_login

    // local storage functions <==

    // show/hide ajax debug log checkbox in bottom of page. Only used if ajax_debug? / DEBUG_AJAX is true
    function show_debug_log_checkbox(checkbox) {
        var debug_log = document.getElementById('debug_log') ;
        if (!debug_log) {
            add2log('show_debug_log_checkbox: debug log was no found') ;
            return ;
        }
        if (checkbox.checked) debug_log.style.display = '' ;
        else debug_log.style.display = 'none' ;
    }

    // workaround for doublet language code in url, /en/en/<controller>/<action>
    // error must be in /config/routes.rb and/or how url_for is being used in app
    // do not add controllers with 2 letter name
    function remove_doublet_language_code (url) {
        var url_a = url.split('/') ;
        if (url_a.length < 5) return url ;
        var lancode1 = url_a[3] ;
        var lancode2 = url_a[4] ;
        if (lancode1 != lancode2) return url ;
        if (!lancode1.match(/^[a-z]{2}$/)) return url ;
        url_a.splice(3,1) ;
        url = url_a.join('/') ;
        return url ;
    } // remove_doublet_language_code

    // change language. Note that unsaved post, comment and updates are discarded when changing language
    function update_language(self) {
        var href = window.location.href ;
        add2log('old href = ' + href + ', self.value = ' + self.value) ;
        href = remove_doublet_language_code(href) ;
        var href_a = href.split('/') ;
        if (href_a[3].match(/^[a-z]{2}$/)) href_a[3] =  self.value ;
        else href_a.splice(3,0,self.value) ;
        href = href_a.join('/') ;
        add2log('new href = ' + href) ;
        window.location.href = href ;
    } // update_language


    // Fix bug. App is displayed in a iFrame for opera < 12.16
    // http://stackoverflow.com/questions/326069/how-to-identify-if-a-webpage-is-being-loaded-inside-an-iframe-or-directly-into-t
    function inIframe () {
        try {
            return window.self !== window.top;
        } catch (e) {
            return true;
        }
    } // inIframe

    // unix timestamp (seconds since 1970)
    function unix_timestamp () {
        return Math.floor((new Date).getTime()/1000) ;
    };

    // check if json request is invalid. used in do_tasks, login, logout and ping
    // returns null (ok) or an error message
    function is_json_request_invalid (pgm, json_request, action, msg) {
        if (!msg) msg = '' ;
        // remove null keys before checking json
        for (var key in json_request) if (json_request[key] == null) delete json_request[key];
        // check if schema definition exists
        var json_schema = action + '_request';
        var error ;
        if (!Gofreerev.rails['JSON_SCHEMA'].hasOwnProperty(json_schema)) {
            console.log(pgm + 'Error. JSON schema defintion for ' + json_schema + ' was not found. ' + action + ' request was not sent to server.');
            error = 'JSON schema definition ' + json_schema + ' was not found. ' + action + ' request was not sent to server. ' + msg ;
            console.log(pgm + error);
            return error;
        }
        // validate json request before sending action to server
        if (tv4.validate(json_request, Gofreerev.rails['JSON_SCHEMA'][json_schema])) {
            // todo: rsa or mix encrypt request before sending ajax request to server
            //       required for insecure http connection and could be used as extra security in a https connection
            //       signature { encryption: 'mix', key: key, message: message } where key is an random rsa encrypted password
            return null;
        }
        // report error
        var json_error = JSON.parse(JSON.stringify(tv4.error));
        delete json_error.stack;
        var json_errors = JSON.stringify(json_error) ;
        error = 'Error in JSON ' + action + ' request. ' + action + ' request was not sent to server.' + msg ;
        console.log(pgm + error);
        console.log(pgm + 'request: ' + JSON.stringify(json_request));
        console.log(pgm + 'schema: ' + JSON.stringify(Gofreerev.rails['JSON_SCHEMA'][json_schema]));
        console.log(pgm + 'errors : ' + json_errors);
        return error + '. ' + json_errors ;
    } // is_json_request_invalid

    // check if json request is invalid. used in do_tasks, login, logout and ping
    // returns null (ok) or an error message
    function is_json_message_invalid (pgm, json_msg, json_schema, msg) {
        if (!msg) msg = '' ;
        // remove null keys before checking json
        for (var key in json_msg) if (json_msg[key] == null) delete json_msg[key];
        // check if schema definition exists
        var error ;
        if (!Gofreerev.rails['JSON_SCHEMA'].hasOwnProperty(json_schema)) {
            console.log(pgm + 'Error. JSON schema defintion for ' + json_schema + ' was not found. ' + json_schema + ' message was not sent to other client.');
            error = 'JSON schema definition ' + json_schema + ' was not found. ' + json_schema + ' message was not sent to other client. ' + msg ;
            console.log(pgm + error);
            return error;
        }
        // validate json message before sending message to server and to other client
        if (tv4.validate(json_msg, Gofreerev.rails['JSON_SCHEMA'][json_schema])) return null;
        // report error
        var json_error = JSON.parse(JSON.stringify(tv4.error));
        delete json_error.stack;
        var json_errors = JSON.stringify(json_error) ;
        error = 'Error in JSON ' + json_schema + ' message. ' + json_schema + ' message was not sent to other client.' + msg ;
        console.log(pgm + error);
        console.log(pgm + 'message: ' + JSON.stringify(json_msg));
        console.log(pgm + 'schema: ' + JSON.stringify(Gofreerev.rails['JSON_SCHEMA'][json_schema]));
        console.log(pgm + 'errors : ' + json_errors);
        return error + '. ' + json_errors ;
    } // is_json_request_invalid


    // check if json response is invalid. used in do_tasks, login, logout and ping
    // returns null (ok) or an error message
    function is_json_response_invalid (pgm, json_response, action, msg) {
        if (!msg) msg = '' ;
        // check if schema definition exists
        var json_schemaname = action + '_response';
        var error ;
        if (!Gofreerev.rails['JSON_SCHEMA'].hasOwnProperty(json_schemaname)) {
            error = 'JSON schema definition ' + json_schemaname + ' was not found. ' + action + ' response could not be validated. ' + msg ;
            console.log(pgm + error);
            return error;
        }
        var json_schema = Gofreerev.rails['JSON_SCHEMA'][json_schemaname] ;
        // todo: decrypt any encrypted response before json validation
        //       that is response with signature { encryption: 'mix', key: key, message: message }
        //       rsa decrypt key and use key to symmetric decrypt message
        //       should always use encryption on insecure http connection
        //       could use encryption as extra security on https connections
        // validate do_tasks response received from server
        if (tv4.validate(json_response, json_schema)) return null ;
        // report error
        var json_error = JSON.parse(JSON.stringify(tv4.error));
        delete json_error.stack;
        var json_errors = JSON.stringify(json_error) ;
        error = 'Error in JSON ' + action + ' response from server. ' + msg ;
        console.log(pgm + error);
        console.log(pgm + 'response: ' + JSON.stringify(json_response));
        console.log(pgm + 'schema: ' + JSON.stringify(Gofreerev.rails['JSON_SCHEMA'][json_schemaname]));
        console.log(pgm + 'errors : ' + json_errors);
        // return error
        return error + '. ' + json_errors ;
    } // is_json_response_invalid

    // generate password - used in client to client communication (symmetric encryption)
    // note: don't used comma "," in password. Comma is used as field seperator in rsa array
    function generate_random_password (length) {
        var character_set = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ 0123456789![]{}#%&/()=?+-:;_-.@$|£' ;
        var password = [], index, char ;
        for (var i=0 ; i<length ; i++) {
            index = Math.floor(Math.random()*character_set.length) ;
            char = character_set.substr(index,1) ;
            password.push(char) ;
        } ;
        return password.join('') ;
    } // generate_random_password

    // sequence - for example used in verify gifts request and response
    function get_next_seq () {
        if (!getItem('userid')) return null ; // error - not logged in
        var seq = getItem('seq') ;
        if (!seq) {
            seq = '0' ;
            setItem('seq', seq) ;
        }
        seq = parseInt(seq) + 1 ;
        setItem('seq', seq.toString()) ;
        return seq ;
    } // get_next_seq

    // export public used methods (views)
    return {
        // constants from ruby on rails. see ruby_to.js.erb
        rails: rails,
        // error handlers
        clear_ajax_errors: clear_ajax_errors, // used in application.js.erb
        clear_flash_and_ajax_errors: clear_flash_and_ajax_errors, // used in angularJS module
        move_tasks_errors2: move_tasks_errors2, // used in application.js.erb
        add_to_tasks_errors: add_to_tasks_errors, // used in angularjs modules
        imgonload: imgonload, // check invalid or missing pictures - used in gifts/index page
        imgonerror: imgonerror, // check invalid or missing pictures - used in gifts/index page
        show_debug_log_checkbox: show_debug_log_checkbox, // show/hide debug log in html page
        add2log: add2log, // used in angularjs module
        // view helpers
        onchange_currency: onchange_currency, // ajax update currency in users/edit page
        inIframe: inIframe, // Fix bug. App is displayed in a iFrame for opera < 12.16
        reset_last_user_ajax_comment_at: reset_last_user_ajax_comment_at, // used in gifts/index page
        autoresize_text_field: autoresize_text_field,
        // local storage helpers
        getItem: getItem,
        setItem: setItem,
        removeItem: removeItem,
        compress1: compress1,
        decompress1: decompress1,
        encrypt: encrypt,
        decrypt: decrypt,
        // angular helpers
        get_new_uid: get_new_uid,
        sha256: sha256,
        client_login: client_login,
        client_sym_encrypt: encrypt,
        client_sym_decrypt: decrypt,
        unix_timestamp: unix_timestamp,
        is_json_request_invalid: is_json_request_invalid,
        is_json_response_invalid: is_json_response_invalid,
        is_json_message_invalid: is_json_message_invalid,
        generate_random_password: generate_random_password,
        get_next_seq: get_next_seq
    };
})();
// Gofreerev closure end


// angularJS code

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
    })
    .factory('TextService', ['$sce', function($sce) {
        console.log('TextService loaded') ;

        var self = this;

        var appname = Gofreerev.rails['APP_NAME'];

        // language specific gift controller constants
        // todo: client side change language without page refresh?
        self.init_language_constants = function () {
            self.language = I18n.locale || I18n.defaultLocale;
            self.texts = {
                appname: appname,
                new_gift: {
                    header_line: I18n.t('js.new_gift.header_line'),
                    price_title: I18n.t('js.new_gift.price_title',
                        {
                            min_interest: Gofreerev.rails['NEG_INT_POS_BALANCE_PER_YEAR'],
                            max_interest: Gofreerev.rails['NEG_INT_NEG_BALANCE_PER_YEAR']
                        }),
                    price_prompt: I18n.t('js.new_gift.price_prompt'),
                    price_placeholder: I18n.t('js.new_gift.price_placeholder'),
                    price_free: I18n.t('js.new_gift.price_free'),
                    direction_giver_prompt: I18n.t('js.new_gift.direction_giver_prompt'),
                    direction_receiver_prompt: I18n.t('js.new_gift.direction_receiver_prompt'),
                    description_title: I18n.t('js.new_gift.description_title'),
                    description_prompt: I18n.t('js.new_gift.description_prompt'),
                    description_placeholder: I18n.t('js.new_gift.description_placeholder'),
                    submit_button_text: I18n.t('js.new_gift.submit_button_text'),
                    file_prompt: I18n.t('js.new_gift.file_prompt'),
                    file_placeholder: I18n.t('js.new_gift.file_placeholder'),
                    link_prompt1: I18n.t('js.new_gift.link_prompt1'),
                    link_prompt2: I18n.t('js.new_gift.link_prompt2'),
                    link_placeholder: I18n.t('js.new_gift.link_placeholder')
                },
                gifts: {
                    header: {
                        giver: I18n.t('js.gifts_header.giver'),
                        receiver: I18n.t('js.gifts_header.receiver'),
                        link_and_text: I18n.t('js.gifts_header.link_and_text')
                    },
                    link_title: I18n.t('js.gifts.gift_link_title'),
                    show_full_text: I18n.t('js.gifts.show_full_text'),
                    like_gift: I18n.t('js.gifts.like_gift'),
                    unlike_gift: I18n.t('js.gifts.unlike_gift'),
                    follow_gift: I18n.t('js.gifts.follow_gift'),
                    unfollow_gift: I18n.t('js.gifts.unfollow_gift'),
                    delete_gift: I18n.t('js.gifts.delete_gift'),
                    confirm_delete_gift_1: I18n.t('js.gifts.confirm_delete_gift_1'), // confirm with warning (balance changed)
                    confirm_delete_gift_2: I18n.t('js.gifts.confirm_delete_gift_2'),  // confirm without warning
                    hide_gift: I18n.t('js.gifts.hide_gift'),
                    confirm_hide_gift: I18n.t('js.gifts.confirm_hide_gift'),
                    no_gifts_was_found_html: $sce.trustAsHtml(I18n.t('js.gifts.no_gifts_was_found_html', {appname: appname})),
                    no_friends_was_found_html: $sce.trustAsHtml(I18n.t('js.gifts.no_friends_was_found_html', {appname: appname})),
                    invite_friends_prompt: I18n.t('js.gifts.invite_friends_prompt'),
                    invite_friends_message_title: I18n.t('js.gifts.invite_friends_message_title', {appname: appname}),
                    invite_friends_message_body: I18n.t('js.gifts.invite_friends_message_body')
                },
                comments: {
                    comment_text: I18n.t('js.comments.comment_text'),
                    show_full_text: I18n.t('js.comments.show_full_text'),
                    cancel_new_deal: I18n.t('js.comments.cancel_new_deal'),
                    confirm_cancel_new_deal: I18n.t('js.comments.confirm_cancel_new_deal'),
                    accept_new_deal: I18n.t('js.comments.accept_new_deal'),
                    confirm_accept_new_deal: I18n.t('js.comments.confirm_accept_new_deal'),
                    reject_new_deal: I18n.t('js.comments.reject_new_deal'),
                    confirm_reject_new_deal: I18n.t('js.comments.confirm_reject_new_deal'),
                    delete_comment: I18n.t('js.comments.delete_comment'),
                    confirm_delete_comment: I18n.t('js.comments.confirm_delete_comment')
                },
                new_comment: {
                    check_box_prompt: I18n.t('js.new_comment.check_box_prompt'),
                    comment_placeholder: I18n.t('js.new_comment.comment_placeholder'),
                    submit_button_text: I18n.t('js.new_comment.submit_button_text')
                },
                auth: {
                    app_login_header: I18n.t('js.auth.app_login_header', {appname: appname}),
                    app_login_title: I18n.t('js.auth.app_login_title', {appname: appname}),
                    provider_login_header: I18n.t('js.auth.provider_login_header', {appname: appname}),
                    provider_login_title: I18n.t('js.auth.provider_login_title', {appname: appname}),
                    password_prompt: I18n.t('js.auth.password_prompt'),
                    password_placeholder: I18n.t('js.auth.password_placeholder', {appname: appname}),
                    log_in_button: I18n.t('js.auth.log_in_button'),
                    confirm_password_prompt: $sce.trustAsHtml(I18n.t('js.auth.confirm_password_prompt')),
                    confirm_password_placeholder: I18n.t('js.auth.confirm_password_placeholder', {appname: appname}),
                    register_button: I18n.t('js.auth.register_button'),
                    radio_log_in_prompt: I18n.t('js.auth.radio_log_in_prompt'),
                    radio_register_prompt: I18n.t('js.auth.radio_register_prompt')
                },
                page_header: {
                    home_link_text: I18n.t('js.page_header.home_link_text'),
                    log_in_link_text: I18n.t('js.page_header.log_in_link_text')
                }
            };
        };
        self.init_language_constants();

        return {
            language: self.language,
            texts: self.texts,
            init_language_constants: self.init_language_constants
        };
        // end TextService
    }])
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
            var save = false, error, key, error ;
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
            for (var i=0 ; i<folder.messages.length ; i++) {
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
    }])
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

        // friends - downloaded from api friend list and saved temporary in local storage
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

        // update friends js array: replace: true: overwrite/replace old friends, false: add/keep old friends
        // called from do_tasks after api and device login. new friend lists downloaded from api provider
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
            for (i = 0; i < new_friends.length; i++) {
                new_friend = new_friends[i];
                // add download unix timestamp to friend info. not used in friends array but used in users array if friend user id is used in gifts or comments
                if (!new_friend.hasOwnProperty('verified_at')) new_friend.verified_at = Gofreerev.unix_timestamp();
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
                for (var i=0 ; i<new_friends.length ; i++) new_users_index_by_user_id[new_friends[i].user_id] = i ;
                var old_friend ;
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
                for (var i=0 ; i<friends.length ; i++) friends_index_by_user_id[friends[i].user_id] = i ;
            }
            Gofreerev.setItem('friends', JSON.stringify(friends)) ;
            console.log(pgm + 'friends = ' + JSON.stringify(friends)) ;
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
                var i = friends_index_by_old_sha256[sha256] ;
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
            var currency = get_default_currency() ;
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
                console.log(pgm + 'received "Not logged in" response from ping. Not logged in on server. Log out all providers on client.') ;
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
            }
            // update login userids in server session
            // console.log(pgm + 'debug 5') ;
            var logout_request = { client_userid: old_client_userid};
            if (provider) logout_request.provider = provider ;
            var json_errors ;
            if (json_errors=Gofreerev.is_json_request_invalid(pgm, logout_request, 'logout')) return $q.reject(json_errors) ;
            $http.post('/util/logout.json', logout_request)
                .then(function (response) {
                    // console.log(pgm + 'logout response = ' + JSON.stringify(response)) ;
                    if (response.data.error) console.log(pgm + 'logout error = ' + response.data.error) ;
                    // validate logout response received from server (should only be error message)
                    var json_errors ;
                    if (json_errors=Gofreerev.is_json_response_invalid(pgm, response.data, 'logout', '')) return $q.reject(json_errors) ;
                },
                function (error) {
                    console.log(pgm + 'log out error = ' + JSON.stringify(error)) ;
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

        };

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
        // - user_ids - input/output - replace internal user ids with remote sha256 signature
        // - server_id - from mailbox - used must have a remote sha256 signature on server_id
        // - msg - message for debug information
        // - force - false: raise error for unknown remote sha256 - true: use negative user id for unknown remote sha256
        var user_ids_to_remote_sha256 = function (user_ids, server_id, msg, force) {
            var pgm = service + '.user_ids_to_remote_sha256: ' ;
            var remote_sha256_values = [] ;
            var i, user_id, friend, remote_sha256 ;
            for (i=0 ; i<user_ids.length ; i++) {
                user_id = user_ids[i] ;
                if (typeof user_id != 'number') {
                    console.log(pgm + 'System error. Invalid call. User_ids must be an array of integers') ;
                    console.log(pgm + 'user_ids = ' + JSON.stringify(user_ids)) ;
                    console.log(pgm + 'msg     = ' + JSON.stringify(msg)) ;
                    return false ;
                }
                friend = get_friend(user_id) ;
                if (!friend && force) friend = get_user(user_id) ;
                if (!friend) {
                    console.log(pgm + 'System error. Cannot send ' + msg.msgtype + ' to other Gofreerev server. Friend with user id ' + user_id + ' was not found') ;
                    console.log(pgm + 'msg     = ' + JSON.stringify(msg)) ;
                    return false ;
                }
                if (!friend.remote_sha256) {
                    if (force) {
                        console.log(pgm + 'Warning. User id ' + user_id + ' do not have a remote sha256 signature. Using negative user_id ' + (-user_id) + ' in ' + msg.msgtype + ' message') ;
                        remote_sha256_values.push(-user_id) ;
                        continue ;
                    }
                    else {
                        console.log(pgm + 'System error. Cannot send ' + msg.msgtype + ' message to other Gofreerev server. No remote_sha256 hash was found for user id ' + user_id) ;
                        console.log(pgm + 'msg     = ' + JSON.stringify(msg)) ;
                        console.log(pgm + 'friend  = ' + JSON.stringify(friend)) ;
                        return false;
                    }
                }
                remote_sha256 = friend.remote_sha256[server_id] ;
                if (!remote_sha256) {
                    if (force) {
                        console.log(pgm + 'Warning. User id ' + user_id + ' do not have a remote sha256 signature. Using negative user_id ' + (-user_id) + ' in ' + msg.msgtype + ' message') ;
                        remote_sha256_values.push(-user_id) ;
                    }
                    else {
                        console.log(pgm + 'System error. Cannot send ' + msg.msgtype + ' message to other Gofreerev server. Remote_sha256 was not found for user id ' + user_id + ' and server id ' + server_id) ;
                        console.log(pgm + 'msg     = ' + JSON.stringify(msg)) ;
                        console.log(pgm + 'friend  = ' + JSON.stringify(friend)) ;
                        return false ;
                    }
                }
                remote_sha256_values.push(remote_sha256) ;
            } // for i

            // translate ok. overwrite values in input array
            for (i=0 ; i<user_ids.length ; i++) user_ids[i] = remote_sha256_values[i] ;
            return true ;
        }; // user_ids_to_remote_sha256;


        // after receiving msg from an other Gofreerev server. Translate known sha256 signatures to internal user ids
        // user ids in msg are either sha256 signatures (remote users) or negative user ids (unknown users)
        var sha256_to_user_ids = function (sha256_signatures, server_id, msg) {
            var pgm = service + '.sha256_to_user_ids: ' ;
            var user_ids = [];
            var i, sha256, friend, translate = false ;
            for (i=0 ; i<sha256_signatures.length ; i++) {
                sha256 = sha256_signatures[i] ;
                if (typeof sha256 == 'number') {
                    // should be a negative integer for unknown user
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
        // stored so that gifts and comments always are valid if authorization and friend lists changes
        var users = [] ;
        var users_index_by_user_id = {} ;
        var init_users_index = function () {
            users_index_by_user_id = {};
            for (var i=0 ; i<users.length ; i++) users_index_by_user_id[users[i].user_id] = i ;
        };

        // load users from localStorage
        var load_users = function () {
            var users_tmp = Gofreerev.getItem('users') ;
            if (users_tmp) users = JSON.parse(users_tmp) ;
            else users = [] ;
            init_users_index() ;
        };
        load_users();

        var save_users = function () {
            Gofreerev.setItem('users', JSON.stringify(users)) ;
        };

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

        // add login users used in create_new_gift and create_new_comment to localStorage
        // users from friends array are always verified users
        var add_new_login_users = function (login_user_ids) {
            var pgm = service + '.add_new_login_users: ' ;
            if ((typeof login_user_ids == 'undefine') || (login_user_ids == null)) return ;
            if (login_user_ids.size == 0) return ;
            var save = false, user_id, friend ;
            for (var i=0 ; i<login_user_ids.length ; i++) {
                user_id = login_user_ids[i] ;
                if (users_index_by_user_id.hasOwnProperty(user_id)) continue ; // already in localStorage
                friend = get_friend(user_id) ; // xxx
                if (!friend || (friend.friend != 1)) {
                    console.log(pgm + 'Invalid call. ' + user_id + ' is not an logged in user') ;
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
        }; // add_new_login_users

        // add friends from friends array to users array - used in data migration (load_gifts). todo: remove
        var add_friends_to_users = function (user_ids) {
            var pgm = service + '.add_friends_to_users: ' ;
            if ((typeof user_ids == 'undefine') || (user_ids == null)) return ;
            if (user_ids.size == 0) return ;
            var save = false, user_id, friend ;
            for (var i=0 ; i<user_ids.length ; i++) {
                user_id = user_ids[i] ;
                if (users_index_by_user_id.hasOwnProperty(user_id)) continue ; // already in users js/localStorage
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
            providers: providers,
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
            cache_oauth_info: cache_oauth_info,
            check_logged_in_providers: check_logged_in_providers,
            expired_tokens_response: expired_tokens_response,
            oauths_response: oauths_response,
            get_external_user_ids: get_external_user_ids,
            add_new_login_users: add_new_login_users,
            get_user: get_user,
            add_friends_to_users: add_friends_to_users,
            user_ids_to_remote_sha256: user_ids_to_remote_sha256,
            sha256_to_user_ids: sha256_to_user_ids
        };
        // end UserService
    }])
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
        var invalid_comment = function (comment) {
            var pgm = service + '.invalid_comment: ' ;
            console.log(pgm + 'Not implemented') ;
            return null ;
        };
        var invalid_comment_change = function (old_comment, new_comment) {
            var pgm = service + '.invalid_changed_comment: ' ;
            console.log(pgm + 'Not implemented') ;
            return null ;
        };

        // todo: add gift validations.
        // - invalid_gift is called from create_new_gift, when receiving new gifts from other clients and before sending gifts to other clients
        // - invalid_gift_change is called in any local updates and when merging gift information from other clients into local gift
        // user_users is an optional array with new users (used when validating new gifts received from other clients)
        var invalid_gift = function (gift, new_users) {
            var pgm = service + '.invalid_gift: ' ;
            var errors = [] ;
            // fields to validate:
            //  1) gid - unique gift id - js unix timestamp (10) with milliseconds (3) and random numbers (7) - total 20 decimals
            //  2) giver_user_ids and/or receiver_user_ids
            //  3) created_at_client unix timestamp - 10 decimals - used in gift signature on server
            //  4) price => {:type => %w(undefined number), :minimum => 0, :multipleOf => 0.01 },
            //  5) currency: optional currency - set when gift is created or when gift is accepted by a friend - iso4217 with restrictions
            //  6) direction: giver or receiver
            //  7) description   :description => {:type => 'string'},
            //  8) open_graph_url => {:type => %w(undefined string) },
            //  9) open_graph_title => {:type => %w(undefined string) },
            // 10) open_graph_description => {:type => %w(undefined string) },
            // 11) open_graph_image => {:type => %w(undefined string) },
            // 12) like - todo: must be changed to an array with user ids and like/unlike timestamps
            // 13) deleted_at_client => {:type => %w(undefined integer), :minimum => uid_from, :maximum => uid_to},
            // 14) accepted_cid => {:type => %w(undefined string), :pattern => uid_pattern},
            // 15) accepted_at_client => {:type => %w(undefined integer), :minimum => uid_from, :maximum => uid_to},
            // 16) comments array

            // new_users from send_gifts sub message (sync_gifts) - fallback information used in case of unknown user
            var new_users_index = {} ;
            for (var i=0 ; i<new_users.length ; i++) new_users_index[new_users[i].user_id] = new_users[i] ;
            console.log(pgm + 'new_users_index = ' + JSON.stringify(new_users_index)) ;

            //  1) gid - unique gift id - js unix timestamp (10) with milliseconds (3) and random numbers (7) - total 20 decimals
            var from_unix_timestamp = Math.floor((new Date('2014-01-01')).getTime()/1000) ;
            var to_unix_timestamp =  Math.floor((new Date).getTime()/1000) + 24*60*60;
            if (!gift.gid) errors.push('Required gid (unique gift id) is missing') ;
            else if (typeof gift.gid != 'string') errors.push('Invalid gid (unique gift id). Gid must be a string with 20 digits') ;
            else if (!gift.gid.match(/^[0-9]{20}$/)) errors.push('Invalid gid (unique gift id). Gid must be a string with 20 digits') ;
            else if (parseInt(gift.gid.substr(0,10)) < from_unix_timestamp) errors.push('Invalid gid (unique gift id). The first 10 digits must be a valid unix timestamp') ;
            else if (parseInt(gift.gid.substr(0,10)) > to_unix_timestamp) errors.push('Invalid gid (unique gift id). The first 10 digits must be a valid unix timestamp') ;

            //  2) giver_user_ids and/or receiver_user_ids
            // must be friend or user or in new_users
            var giver_user_ids = gift.giver_user_ids || [] ;
            var receiver_user_ids = gift.receiver_user_ids || [] ;
            if ((giver_user_ids.length == 0) && (receiver_user_ids.length ==0)) errors.push('Gift without giver or receiver is not allowed') ;
            var user_ids, providers, user_id, user ;
            user_ids = [] ;
            providers = [] ;
            var logged_in_user = false ;
            var friend = false ;
            for (var i=0 ; i<giver_user_ids.length ; i++) {
                user_id = giver_user_ids[i] ;
                if (user_ids.indexOf(user_id) != -1) {
                    errors.push('Giver is invalid. Doublet user ids in giver_user_ids' + giver_user_ids.join(', ')) ;
                    break ;
                }
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
                }
            } // for i
            user_ids = [] ;
            providers = [] ;
            for (var i=0 ; i<receiver_user_ids.length ; i++) {
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
                }
            } // for i
            if ($(giver_user_ids).filter(receiver_user_ids).length > 0) {
                errors.push('Giver/receiver is invalid. Found common user id in giver and receiver user ids. A user cannot be both giver and receiver of a gift') ;
            }
            if ((giver_user_ids.length == 0) && (gift.direction == 'giver')) {
                errors.push('Giver is invalid. Cannot be empty for direction=giver') ;
            }
            else if (gift.accepted_cid || gift.accepted_at_client) {
                errors.push('Giver is invalid. Cannot be empty for an accepted deal') ;
            }
            if ((receiver_user_ids.length == 0) && (gift.direction == 'receiver')) {
                errors.push('Receiver is invalid. Cannot be empty for direction=receiver') ;
            }
            else if (gift.accepted_cid || gift.accepted_at_client) {
                errors.push('Receiver is invalid. Cannot be empty for an accepted deal') ;
            }

            //  3) created_at_client unix timestamp - 10 decimals - used in gift signature on server
            if (!gift.created_at_client) errors.push('Required created_at_client unix timestamp is missing') ;
            else if (gift.created_at_client < from_unix_timestamp) errors.push('Invalid created_at_client unix timestamp') ;
            else if (gift.created_at_client > to_unix_timestamp) errors.push('Invalid created_at_client unix timestamp') ;

            //  4) price => {:type => %w(undefined number), :minimum => 0, :multipleOf => 0.01 },
            // console.log(pgm + 'price = ' + gift.price + ', typeof price = ' + typeof gift.price) ;
            if ((typeof gift.price != 'undefined') && (gift.price != null)) {
                if (typeof gift.price != 'number') errors.push('Price is invalid. Must be an number >= 0') ;
                else if (gift.price < 0) errors.push('Price is invalid. Must be an number >= 0') ;
                else if (gift.price != Math.round(gift.price, 2)) errors.push('Price is invalid. Max 2 decimals are allowed in prices') ;
            }

            //  5) currency: optional currency - set when gift is created or when gift is accepted by a friend - iso4217 with some restrictions
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

            //  6) direction: giver or receiver
            if (!gift.direction) errors.push('Required direction is missing') ;
            else if (typeof gift.direction != 'string') errors.push('Direction is invalid. Must be giver or receiver') ;
            else if (['giver', 'receiver'].indexOf(gift.direction) == -1) errors.push('Direction is invalid. Must be giver or receiver') ;
            else if ((gift.direction == 'giver') && (giver_user_ids.length == 0)) errors.push('Direction is giver but no giver user ids was found') ;
            else if ((gift.direction == 'receiver') && (receiver_user_ids.length == 0)) errors.push('Direction is receiver but no receiver user ids was found') ;

            //  7) description   :description => {:type => 'string'},
            if ((typeof gift.description != 'string') || (gift.description == '')) errors.push('Required description is missing') ;

            //  8) open_graph_url => {:type => %w(undefined string) },
            if (gift.open_graph_url) {
                if (typeof gift.open_graph_url != 'string') errors.push('Open graph link is invalid. Must be an http url') ;
                else if (!gift.open_graph_url.match(/^https?:\/\//)) errors.push('Open graph link is invalid. Must be an http url') ;
                else if (!gift.open_graph_title && !gift.open_graph_description && !gift.open_graph_image) errors.push('Open graph link is invalid. Open graph must have a title, a description and/or an image') ;
            }

            //  9) open_graph_title => {:type => %w(undefined string) },
            if (gift.open_graph_title && (typeof gift.open_graph_title != 'string')) errors.push('Invalid open graph title. Must be blank or a string') ;

            // 10) open_graph_description => {:type => %w(undefined string) },
            if (gift.open_graph_description && (typeof gift.open_graph_description != 'string')) errors.push('Invalid open graph description. Must be blank or a string') ;

            // 11) open_graph_image => {:type => %w(undefined string) },
            if (gift.open_graph_image) {
                if (typeof gift.open_graph_image != 'string') errors.push('Open graph image is invalid. Must be an http url') ;
                else if (!gift.open_graph_image.match(/^https?:\/\//)) errors.push('Open graph image is invalid. Must be an http url') ;
            }
            
            // 12) like - todo: must be changed to an array with user ids and like/unlike timestamps
            
            // 13) deleted_at_client => {:type => %w(undefined integer), :minimum => uid_from, :maximum => uid_to},
            if (gift.deleted_at_client) {
                if (gift.deleted_at_client < from_unix_timestamp) errors.push('Invalid deleted_at_client unix timestamp') ;
                else if (gift.deleted_at_client > to_unix_timestamp) errors.push('Invalid deleted_at_client unix timestamp') ;
            }
            
            // 14) accepted_cid => {:type => %w(undefined string), :pattern => uid_pattern},
            if (gift.accepted_cid) {
                if (typeof gift.accepted_cid != 'string') errors.push('Invalid accepted cid (unique comment id). Cid must be a string with 20 digits') ;
                else if (!gift.accepted_cid.match(/^[0-9]{20}$/)) errors.push('Invalid accepted cid (unique comment id). Cid must be a string with 20 digits') ;
                else if (parseInt(gift.accepted_cid.substr(0,10)) < from_unix_timestamp) errors.push('Invalid accepted cid (unique comment id). The first 10 digits must be a valid unix timestamp') ;
                else if (parseInt(gift.accepted_cid.substr(0,10)) > to_unix_timestamp) errors.push('Invalid accepted cid (unique comment id). The first 10 digits must be a valid unix timestamp') ;
                else if (!gift.comments || (gift.comments.length == 0)) errors.push('Unknown accepted cid (unique comment id). Accepted deal proposal was not found') ;
                else {
                    var accepted_comment = null, comment ;
                    for (var i=0 ; i<gift.comments.length ; i++) {
                        if (gift.comments[i].cid == gift.accepted_cid) accepted_comment = gift.comments[i] ;
                    }
                    if (!accepted_comment) errors.push('Unknown accepted cid (unique comment id). Accepted deal proposal was not found') ;
                    else if (accepted_comment.accepted) errors.push('Invalid accepted cid (unique comment id). Comment is not an accepted deal proposal') ;
                    else if (!accepted_comment.accepted_by_user_ids) errors.push('Invalid accepted cid (unique comment id). Accepted by for accepted deal proposal was not found') ;
                    else {
                        // todo: compare comment.accepted_by_user_ids and gift.giver_user_ids / gift.receiver_user_ids

                    }

                }
            }

            // 15) accepted_at_client => {:type => %w(undefined integer), :minimum => uid_from, :maximum => uid_to},
            if (gift.accepted_at_client) {
                if (gift.accepted_at_client < from_unix_timestamp) errors.push('Invalid accepted_at_client unix timestamp') ;
                else if (gift.accepted_at_client > to_unix_timestamp) errors.push('Invalid accepted_at_client unix timestamp') ;
                else if (accepted_comment && (gift.accepted_at_client != accepted_comment.accepted_at_client)) {
                    errors.push('Invalid accepted_at_client unix timestamp') ;
                    accepted_comment = null ;
                }
            }

            if (accepted_comment) {

            }

            // 16) comments array
            var comments = gift.comments ;
            var no_comments_errors = 0 ;
            if (comments) {
                for (i=0 ; i<comments.length ; i++) if (invalid_comment(comments[i])) no_comments_errors += 1 ;
                if (no_comments_errors > 0) errors.push(no_comments_errors + ' invalid comments') ;
            }

            if (errors.size > 0) console.log(pgm + 'Gift with errors. gift = ' + JSON.stringify(gift)) ;
            return (errors.size == 0 ? null : errors.join('. ')) ;
        };
        var invalid_gift_change = function (old_gift, new_gift) {
            var pgm = service + '.invalid_changed_gift: ' ;
            console.log(pgm + 'Not implemented') ;
            return null ;
        };

        // calculate sha256 value for comment. used when comparing gift lists between clients. replicate gifts with changed sha256 value between clients
        // readonly fields used in server side sha256 signature - update is NOT allowed - not included in sha256 calc for comment
        // - created_at_client    - readonly- used in client path of server side sha256 signature - not included in comment sha256 calculation
        // - comment              - readonly- used in client path of server side sha256 signature - not included in comment sha256 calculation
        // - price                - readonly- used in client path of server side sha256 signature - not included in comment sha256 calculation
        // - currency             - readonly- used in client path of server side sha256 signature - not included in comment sha256 calculation
        // - user_ids             - readonly- used in server side sha256 signature - not included in comment sha256 calculation
        // - created_at_server    - server number - returned from new comments request and not included in comment sha256 calculation
        // - new_deal             - boolean: null or true. null: comment. true: new deal proposal - can be cancelled - include in comment sha256 calculation
        // - deleted_at_client    - deleted at client unix timestamp - include in comment sha256 calculation
        // - accepted             - accepted boolean: null: comment, true: accepted deal, false: rejected deal - include in comment sha256 calculation
        // - accepted_at_client   - accepted at client unix timestamp - accepted deals only - include in comment sha256 calculation
        // - accepted_by_user_ids - accepted by user ids - accepted deals only - subset of gift creators - include in comment sha256 calculation
        // - rejected_at_client   - rejected at client unix timestamp - rejected deals only - include in comment sha256 calculation
        // - rejected_by_user_ids - rejected by user ids - rejected deals only - subset of gift creators - include in comment sha256 calculation
        var calc_sha256_for_comment = function (comment) {
            var pgm = service + '.calc_sha256_for_comment: ';
            if (!comment.hasOwnProperty('created_at_server')) return null; // wait - no server side sha256 signature

            var accepted_by_user_ids;
            if (!comment.hasOwnProperty('accepted_by_user_ids') || (typeof comment.accepted_by_user_ids == 'undefined') || (comment.accepted_by_user_ids == null)) accepted_by_user_ids = [];
            else {
                accepted_by_user_ids = userService.get_external_user_ids(comment.accepted_by_user_ids);
                if (!accepted_by_user_ids) return null;
                accepted_by_user_ids = accepted_by_user_ids.sort ;
            }
            accepted_by_user_ids.unshift(accepted_by_user_ids.length);
            accepted_by_user_ids = accepted_by_user_ids.join(',');

            var rejected_by_user_ids;
            if (!comment.hasOwnProperty('rejected_by_user_ids') || (typeof comment.rejected_by_user_ids == 'undefined') || (comment.rejected_by_user_ids == null)) rejected_by_user_ids = [];
            else {
                rejected_by_user_ids = userService.get_external_user_ids(comment.rejected_by_user_ids);
                if (!rejected_by_user_ids) return null;
                rejected_by_user_ids = rejected_by_user_ids.sort ;
            }
            rejected_by_user_ids.unshift(rejected_by_user_ids.length);
            rejected_by_user_ids = rejected_by_user_ids.join(',');
            return Gofreerev.sha256(comment.new_deal, comment.deleted_at_client, comment.accepted, comment.accepted_at_client,
                                    comment.accepted_by_user_ids, comment.rejected_at_client, comment.rejected_by_user_ids);
        }; // calc_sha256_for_comment

        // calculate sha256 value for gift. used when comparing gift lists between clients. replicate gifts with changed sha256 value between devices
        // - readonly fields used in server side sha256 signature - update is NOT allowed - not included in sha256 calc for gift
        //   created_at_client, description, open_graph_url, open_graph_title, open_graph_description and open_graph_image,
        //   direction, giver_user_ids and receiver_user_ids
        //   direction=giver: giver_user_ids can not be changed, receiver_user_ids are added later, use receiver_user_ids in sha256 value
        //   direction=receiver: receiver_user_ids can not be changed, giver_uds_ids are added latter, use receiver user ids in sha256 value
        // - created_at_server timestamp is readonly and is returned from ping/new_gifts response - not included in sha256 value
        // - price and currency - should not change, but include in sha256 value
        // - likes - change to array or object and keep last like/unlike for each user - include in sha256 value
        // - follow - change to array and keep last follow/unfollow for each logged in users - not included in sha256 value
        //   find some other way to replicate follow/unfollow between logged in users - not shared with friends
        // - show - device only field or logged in user only field - replicate hide to other devices with identical logged in users? - not included in sha256 value
        // - deleted_at_client - included in sha256 value
        // - comments - array with comments - included comments sha256_values in gift sha256 value
        var calc_sha256_for_gift = function (gift) {
            var pgm = service + '.sha256_gift: ';
            if ((typeof gift.created_at_server == 'undefined') || (gift.created_at_server == null)) return [null,null,null]; // no server side sha256 signature
            // other participant in gift. null until closed/given/received
            var other_participant_internal_ids = gift.direction == 'giver' ? gift.receiver_user_ids : gift.giver_user_ids;
            if ((typeof other_participant_internal_ids == 'undefined') || (other_participant_internal_ids == null)) other_participant_internal_ids = [];
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
            // deleted_at_client
            // comments. string with sha256 value for each comment
            var comments, comment_sha256_temp;
            if ((typeof gift.comments == 'undefined') || (gift.comments == null)) comments = [];
            else comments = gift.comments;
            var comments_sha256 = [], s;
            for (i = 0; i < comments.length; i++) {
                s = calc_sha256_for_comment(comments[i]);
                if (!s) return [null,null,null]; // error in sha256 calc. error has been written to log
                comments_sha256.push(s);
            }
            comments_sha256.unshift(comments.length.toString());
            var comments_str = comments_sha256.join(',');
            // return an array with 3 sha256 values. sha256 is the real sha256 value for gift. sha256_gift and sha256_comments are sub sha256 values used in gifts sync between devices
            var sha256 = Gofreerev.sha256(other_participant_str, gift.price, gift.currency, likes_str, gift.deleted_at_client, gift.accepted_cid, gift.accepted_at_client, comments_str);
            var sha256_gift = Gofreerev.sha256(other_participant_str, gift.price, gift.currency, likes_str, gift.deleted_at_client, gift.accepted_cid, gift.accepted_at_client);
            var sha256_comments = Gofreerev.sha256(comments_str);
            return [sha256, sha256_gift, sha256_comments];
        }; // sha256_gift

        var sort_by_gid = function (a, b) {
            if (a.gid < b.gid) return -1;
            if (a.gid > b.gid) return 1;
            return 0;
        }; // sort_by_gid

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
                sha256_values = calc_sha256_for_gift(gift);
                gift.sha256 = sha256_values[0];
                gift.sha256_gift = sha256_values[1]; // sub sha256 values used in gifts sync between devices
                gift.sha256_comments = sha256_values[2]; // sub sha256 values used in gifts sync between devices
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
            var gift = JSON.parse(JSON.stringify(gift));
            // remove temp gift properties before save
            var keep_gift_property = {
                gid: true, giver_user_ids: true, receiver_user_ids: true, created_at_client: true,
                created_at_server: true, price: true, currency: true, direction: true, description: true,
                open_graph_url: true, open_graph_title: true, open_graph_description: true, open_graph_image: true,
                like: true, follow: true, show: true, deleted_at_client: true, deleted_at_server: true,
                accepted_cid: true, accepted_at_client: true, accepted_at_server: true, comments: true
            };
            for (var key in gift) {
                if (gift.hasOwnProperty(key) && !keep_gift_property[key]) delete gift[key];
            }
            // remove temp comment properties before save
            if (!gift.hasOwnProperty('comments')) gift.comments = [];
            var comment;
            var keep_comment_property = {
                cid: true, user_ids: true, price: true, currency: true, comment: true, created_at_client: true,
                created_at_server: true, new_deal: true, deleted_at_client: true, deleted_at_server: true,
                accepted: true, accepted_at_client: true, accepted_at_server: true, accepted_by_user_ids: true,
                rejected_at_client: true, rejected_by_user_ids: true
            } ;
            for (var i = 0; i < gift.comments.length; i++) {
                comment = gift.comments[i] ;
                for (var key in comment) {
                    if (comment.hasOwnProperty(key) && !keep_comment_property[key]) delete comment[key];
                }
            }
            return gift;
        }

        // add new gift to 1) js array and to 2) localStorage. new gift has already been validated in GiftsCtrl.create_new_gift
        var save_new_gift = function (gift) {
            var pgm = service + '.save_new_gift: ';

            // 1: add new gift to js array
            if (gid_to_gifts_index.hasOwnProperty(gift.gid)) {
                console.log(pgm + 'error. gift with gid ' + gift.gid + ' is already in gifts array');
                return;
            }
            gifts.unshift(gift);
            init_gifts_index();

            // 2: add any new givers/receivers to localStorage.
            if (!gift.hasOwnProperty('created_at_server')) {
                userService.add_new_login_users(gift.giver_user_ids) ;
                userService.add_new_login_users(gift.receiver_user_ids) ;
            }

            // 3: add new gift to localStorage
            var gift = prepare_gift_for_save(gift) ;
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
        // send in load_gifts, validate_send_gifts_message etc
        function add_user_ids_to_array (user_ids, array) {
            if (!user_ids) return ;
            if (user_ids.length == 0) return ;
            var i, user_id ;
            for (i=0 ; i<user_ids.length ; i++) {
                user_id = user_ids[i] ;
                if (array.indexOf(user_id) == -1) array.push(user_id) ;
            }
        } // add_user_ids_to_array

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
            
            // todo: data migration. collect user ids used in gifts and comments and add to migration_user_id
            var migration_user_ids = [] ; 

            // loop for all gifts
            var gift, j, comment, migration, seq, k ;
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
                // gift data migration - change gift.created_at_server from a unix timestamp to an integer - server number - 1 for current server
                //if (gift.hasOwnProperty('created_at_server')) {
                //    if (gift.created_at_server.toString().length == 10) {
                //        gift.created_at_server = 1 ;
                //        migration = true ;
                //    }
                //}
                // comment data migration - change comment.created_at_server from a unix timestamp to an integer - server number - 1 for current server
                //if ((gift.hasOwnProperty('comments')) && (typeof gift.comments == 'object') && (gift.comments.length > 0)) {
                //    for (j=0 ; j<gift.comments.length ; j++) {
                //        comment = gift.comments[j] ;
                //        if (comment.hasOwnProperty('created_at_server')) {
                //            if (comment.created_at_server.toString().length == 10) {
                //                comment.created_at_server = 1 ;
                //                migration = true ;
                //            }
                //        }                    }
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

                if (gift.gid == '14315906760737834203') {
                    // cleanup after testrun-22
                    console.log(pgm + 'delete remote gift ' + gift.gid) ;
                    Gofreerev.removeItem(keys[i]) ;
                    continue ;
                }
                
                // migration_user_ids - friends used in gifts and comments must be in users
                add_user_ids_to_array(gift.giver_user_ids, migration_user_ids) ;
                add_user_ids_to_array(gift.receiver_user_ids, migration_user_ids) ;
                if (gift.comments) for (j=0 ; j<gift.comments.length ; j++) {
                    comment = gift.comments[j] ;
                    add_user_ids_to_array(comment.user_ids, migration_user_ids) ;
                }

                // migration. change created_at_server from 1 to 0. gifts and comments. 0 = current server
                //if (gift.created_at_server == 1) {
                //    gift.created_at_server = 0 ;
                //    migration = true ;
                //}
                //if (gift.comments) for (j=0 ; j<gift.comments.length ; j++) {
                //    comment = gift.comments[j] ;
                //    if (comment.created_at_server == 1) {
                //        comment.created_at_server = 0 ;
                //        migration = true ;
                //    }
                //}

                // save migrated gift
                if (migration) Gofreerev.setItem(keys[i], JSON.stringify(gift)) ;

                gifts.push(gift);
                gid_to_seq[gift.gid] = seq ;
                seq_to_gid[seq] = gift.gid ;

            }
            console.log(pgm + 'gifts.length = ' + gifts.length);
            init_gifts_index();

            // data migration. add missing users from friends to users array. todo: remove
            // console.log(pgm + 'migration_user_ids = ' + migration_user_ids.join(', ')) ;
            var user_id, migration_user ;
            for (i=migration_user_ids.length-1 ; i>= 0 ; i--) {
                user_id = migration_user_ids[i] ;
                migration_user = userService.get_user(user_id) ;
                if (migration_user) {
                    // already in users array
                    console.log(pgm + 'user_id ' + user_id + ' already in users array') ;
                    migration_user_ids.splice(i,1) ;
                    continue ;
                }
                migration_user = userService.get_friend(user_id) ;
                if (!migration_user) {
                    console.log(pgm + 'user_id ' + user_id + ' is missing in users array but was not found in friends array') ;
                    migration_user_ids.splice(i,1) ;

                }
                // keep in migration_user_ids array
            } // for i (migration_user_ids)
            console.log(pgm + 'migration_user_ids.length = ' + migration_user_ids.length) ;
            if (migration_user_ids.length > 0) userService.add_friends_to_users(migration_user_ids) ;
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
                    // todo: add server side comment.sha256_deleted and comment.sha256_accepted. almost as gifts, but a comment cannot be both accepted and deleted
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
            // todo: add server side comment.sha256_deleted and comment.sha256_accepted. almost as gifts, but a comment cannot be both accepted and deleted
            // todo: it should be enough with one client side deleted_at_server=accepted_at_server field
            if (comment.user_ids != comments[index].user_ids) comment.user_ids = comments[index].user_ids;
            if (comment.price != comments[index].price) comment.price = comments[index].price;
            if (comment.currency != comments[index].currency) comment.currency = comments[index].currency;
            if (comment.comment != comments[index].comment) comment.comment = comments[index].comment;
            if (comment.created_at_client != comments[index].created_at_client) comment.created_at_client = comments[index].created_at_client;
            if (comment.created_at_server != comments[index].created_at_server) comment.created_at_server = comments[index].created_at_server;
            if (comment.new_deal != comments[index].new_deal) comment.new_deal = comments[index].new_deal;
            if (comment.deleted_at_client != comments[index].deleted_at_client) comment.deleted_at_client = comments[index].deleted_at_client;
            if (comment.accepted != comments[index].accepted) comment.accepted = comments[index].accepted;
            if (comment.accepted_at_client != comments[index].accepted_at_client) comment.accepted_at_client = comments[index].accepted_at_client;
            if (comment.accepted_by_user_ids != comments[index].accepted_by_user_ids) comment.accepted_by_user_ids = comments[index].accepted_by_user_ids;
            if (comment.rejected_at_client != comments[index].rejected_at_client) comment.rejected_at_client = comments[index].rejected_at_client;
            if (comment.rejected_by_user_ids != comments[index].rejected_by_user_ids) comment.rejected_by_user_ids = comments[index].rejected_by_user_ids;
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
            for (var i = new_gifts.length - 1; i >= 0; i--) {
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
        // 1) errors from delete gifts response. delete failed. gift was "undeleted"
        var remove_old_link_errors = function () {
            var pgm = service + '.remove_old_link_errors: ' ;
            var now = Gofreerev.unix_timestamp() ;
            var i, gift ;
            for (i=0 ; i<gifts.length ; i++) {
                gift = gifts[i] ;
                if (!gift.hasOwnProperty('link_error_at')) continue ;
                if (now - gift.link_error_at < 60) continue ;
                delete gift.link_error ;
                delete gift.link_error_at ;
            }
        }; // remove_old_link_errors


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
            return signature;
        }; // gift_signature_for_server


        // send meta-data for newly created gifts to server and get gift.created_at_server response (boolean) from server.
        // called from UserService.ping
        var new_gifts_request = function () {
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
        
        var new_gifts_response = function (response) {
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
                    if (gift.created_at_server == 0) null; // ok - received in an other browser session
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


        // check sha256 server signature for gifts received from other clients before adding or merging gift on this client
        // input is gifts in verify_gifts from send_gifts message pass 1 (receive_message_send_gifts)
        // gifts in verify_gifts array are moved to verify gifts buffer
        // unique sequence seq is used in verify gifts requests.
        // positive seq is used for local gifts where response in immediate
        // negative seq (from sequence) is used for remote gifts where response will come in a later verify_gifts_response
        // server verifies if gift sha256 server signature is valid and returns a created_at_server timestamp if ok or null if not ok
        // output is created_at_server timestamp received in verify_gifts_response (added as gift.verified_at_server)
        // output is used in send_gifts message pass 2 (receive_message_send_gifts)
        var verify_gifts = []; // array with gifts for next verify_gifts request - there can be doublets in array if a gift is received from multiple clients
        // verify gifts buffer - index by seq and key
        var verify_gifts_key_to_seq = {} ; // helper: array with keys, key = gid+sha256+userids
        var verify_gifts_seq_to_gifts = {} ; // helper: from seq to one or more gifts
        var verify_gifts_online = true ; // todo: set to false if ping does not respond - set to true if ping respond
        var verify_gifts_old_remote_seq = Gofreerev.getItem('seq') ; // ignore old remote gift verifications

        // add gift to verify_gifts array. called from receive_message_send_gifts once each pass/loop
        var verify_gifts_add = function (gift) {
            var pgm = service + '.verify_gifts_add: ' ;
            if (gift.in_verify_gifts) return ;
            gift.in_verify_gifts = Gofreerev.unix_timestamp() ;
            verify_gifts.push(gift) ;
            console.log(pgm + 'added gid ' + gift.gid + ' to verify gifts buffer') ;
        };

        var verify_gifts_request = function () {
            var pgm = service + '.verify_gifts_request: ';
            // check buffer for "old gifts". should normally be empty except for gifts with negative seq (remote gifts)
            // local gifts are allowed if device is offline or if server does not respond
            var local_seq = 0 ;
            var seq, local_gifts = 0, remote_gifts = 0 ;
            var request = [] ;
            for (seq in verify_gifts_seq_to_gifts) {
                // console.log(pgm + 'seq = ' + seq + '(' + typeof seq + ')') ;
                if (parseInt(seq) >= 0) {
                    // found "old" local new gift in buffer. should only be the case if device is offline or server is not responding
                    local_gifts += 1;
                    if (parseInt(seq) > local_seq) local_seq = parseInt(seq) ;
                    request.push(verify_gifts_seq_to_gifts[seq].request) ; // resend old request
                }
                else remote_gifts += 1 ; // ok - remote verification can take some time
            }
            if (verify_gifts_online && (local_gifts + remote_gifts > 0)) {
                console.log(pgm + 'Warning. Found ' + local_gifts + ' local and ' + remote_gifts + ' remote not yet verified gifts in buffer.') ;
            }

            if (verify_gifts.length == 0) return (request.length == 0 ? null : request) ; // no new gifts for verification

            // loop for new gifts in verify_gifts array
            var no_new_gifts = verify_gifts.length ;
            var already_verified = 0 ;
            var waiting_for_verification = 0 ;
            var old_request = request.length ; // resend old requests
            var new_request = 0 ;
            var verify_gift, sha256_client, hash, key ;
            var signatures ;
            console.log(pgm + 'verify_gifts.length = ' + verify_gifts.length) ;
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
                // prepare request - using same client sha256 calculations as in new_gifts_request
                //sha256_client = Gofreerev.sha256(
                //    verify_gift.created_at_client.toString(), verify_gift.description, verify_gift.open_graph_url,
                //    verify_gift.open_graph_title, verify_gift.open_graph_description, verify_gift.open_graph_image);
                //hash = {
                //    gid: verify_gift.gid,
                //    sha256: signatures.sha256_client
                //};
                // calculate 1-3 client side signatures (sha256, sha256_accepted and/or sha256_deleted)
                signatures = gift_signature_for_server(verify_gift) ;
                hash = { gid: verify_gift.gid, sha256: signatures.sha256 };
                if (signatures.sha256_accepted) hash.sha256_accepted = signatures.sha256_accepted ;
                if (signatures.sha256_deleted) hash.sha256_deleted = signatures.sha256_deleted ;
                // add user ids
                if (verify_gift.giver_user_ids.length > 0) hash.giver_user_ids = verify_gift.giver_user_ids ;
                if (verify_gift.receiver_user_ids.length > 0) hash.receiver_user_ids = verify_gift.receiver_user_ids ;
                // add server id (only gifts for remote verification)
                if (verify_gift.created_at_server != 0) hash.server_id = verify_gift.created_at_server ;
                // check verify gifts buffer
                key = JSON.stringify(hash);
                seq = verify_gifts_key_to_seq[key];
                if (seq) {
                    // key already in verify gifts buffer.
                    verify_gift.verify_seq = seq ;
                    verify_gifts_seq_to_gifts[seq].gifts.push(verify_gift);
                }
                else {
                    // new request. add to verify gifts buffer and request array
                    if (verify_gift.created_at_server == 0) {
                        // local verification. positive seq. gift created on this gofreerev server
                        local_seq += 1;
                        hash.seq = local_seq ;
                    }
                    else hash.seq = -Gofreerev.get_next_seq() ; // remote verification. negative seq. gift created in an other Gofreerev server
                    verify_gift.verify_seq = hash.seq ;
                    verify_gifts_key_to_seq[key] = hash.seq ;
                    verify_gifts_seq_to_gifts[hash.seq] = {
                        gid: verify_gift.gid,
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

            if (response.error) {
                console.log(pgm + response.error) ;
                return ;
            }

            // seq must be unique i response and all positive seq must be in verify gifts buffer
            var seqs = [], i, not_unique_seq = 0, seq, invalid_local_seq = 0, old_remote_seq = [], invalid_remote_seq = 0, invalid_gid = 0, new_gift  ;
            for (i=0 ; i<response.gifts.length ; i++) {
                new_gift = response.gifts[i] ;
                seq = new_gift.seq;
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
                            if (-seq <= verify_gifts_old_remote_seq) old_remote_seq.push(seq) ; // ignore old remove verifications (js variables have been resetted)
                            else invalid_remote_seq += 1 ;
                        }
                    }
                    else if (verify_gifts_seq_to_gifts[seq].gid != new_gift.gid) invalid_gid += 1 ;
                }
                else not_unique_seq += 1 ;
            }
            seqs = null ;

            // receipt - abort if errors in verify gifts response
            if (not_unique_seq > 0) console.log(pgm + 'Error. ' + not_unique_seq + ' not unique seq in verify gifts response.') ;
            if (invalid_local_seq > 0) console.log(pgm + 'Error. ' + invalid_local_seq + ' invalid local seq in verify gifts response.') ;
            if (invalid_remote_seq > 0) console.log(pgm + 'Error. ' + invalid_remote_seq + ' invalid remote seq in verify gifts response.') ;
            if (invalid_gid > 0) console.log(pgm + invalid_gid + ' invalid unique gift id (gid) in verify gifts response.') ;
            if (old_remote_seq.length > 0) console.log(pgm + 'Warning. ' + old_remote_seq + ' old unknown remote seq in verify gifts response') ;
            if (not_unique_seq + invalid_local_seq + invalid_remote_seq + invalid_gid > 0) return ;

            // loop for each row in verify gifts response
            var gift_verification, gid, new_gifts, key, no_verifications = 0, no_gifts = 0, no_valid = 0, no_invalid = 0 ;
            while (response.gifts.length > 0) {
                gift_verification = response.gifts.shift();
                seq = gift_verification.seq ;
                if (old_remote_seq.indexOf(seq) != -1) continue ; // ignore old remote gift verification
                no_verifications += 1 ;
                new_gifts = verify_gifts_seq_to_gifts[seq].gifts;
                while (new_gifts.length > 0) {
                    no_gifts += 1 ;
                    new_gift = new_gifts.shift() ;
                    new_gift.verified_at_server = gift_verification.verified_at_server ;
                    if (identical_values(new_gift.created_at_server, new_gift.verified_at_server)) no_valid += 1 ;
                    else no_invalid += 1 ;

                }
                // remove from verify gifts buffer
                key = verify_gifts_seq_to_gifts[seq].key ;
                delete verify_gifts_seq_to_gifts[seq] ;
                delete verify_gifts_key_to_seq[key] ;
            } // while response.length > 0

            // receipt
            console.log(pgm + 'Received ' + no_verifications + ' verifications for ' + no_gifts + ' gifts (' + no_valid + ' valid and ' + no_invalid + ' invalid).') ;

        }; // verify_gifts_response


        // todo: remember delete request for remote gifts? this is gifts with created_at_server != 1. verification of remote gifts can take some time

        // send meta-data for deleted gifts to server and get gift.deleted_at_server response (boolean) from server.
        // called from UserService.ping
        var delete_gifts_request = function () {
            var pgm = service + '.delete_gifts_request: ' ;
            var request = [];
            var gift, hash, signatures ;
            for (var i = 0; i < gifts.length; i++) {
                gift = gifts[i];
                if (!gift.deleted_at_client) continue ;
                if (!gift.deleted_at_server) {
                    signatures = gift_signature_for_server(gift);
                    hash = {gid: gift.gid, sha256: signatures.sha256, sha256_deleted: signatures.sha256_deleted};
                    if (signatures.sha256_accepted) hash.sha256_accepted = signatures.sha256_accepted ;
                    if (gift.giver_user_ids && (gift.giver_user_ids.length > 0)) hash.giver_user_ids = gift.giver_user_ids;
                    if (gift.receiver_user_ids && (gift.receiver_user_ids.length > 0)) hash.receiver_user_ids = gift.receiver_user_ids;
                    request.push(hash);
                } // if
            } // for i
            return (request.length == 0 ? null : request);
        }; // delete_gifts_request

        var delete_gifts_response = function (response) {
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
                    if (gift.deleted_at_server == 1) null; // ok - response received in an other browser session
                    else console.log(pgm + 'System error. Gift ' + gid + ' deleted signature was created on server but deleted_at_server property for gift was setted to an invalid value between delete gifts request and delete gifts response. Expected deleted_at_server = 1. Found deleted_at_server = ' + gift.deleted_at_server + '.');
                    continue;
                }
                gift.deleted_at_server = 1;
                save_gift(gift) ;
                save = true;
            } // for i
        }; // delete_gifts_response

        // check sha256 server signature for comments received from other devices before adding comment on this device
        // input is comments from send_gifts message pass 1 (receive_message_send_gifts)
        // output is used in send_gifts message pass 2 (receive_message_send_gifts)
        // server verifies if comment sha256 signature is valid and returns a created_at_server timestamp if ok or null if not ok
        var verify_comments = []; // array with comments for next verify_gifts request - there can be doublets if same gift is received from multiple devices
        // todo: use comment.sha256 as a hash key? for quick lookup of identical new comments!
        var verify_comments_request = function () {
            var pgm = service + '.verify_comments_request: ';
            console.log(pgm + 'Not implemented.');
        };
        var verify_comments_response = function (response) {
            var pgm = service + '.verify_comments_response: ';
            console.log(pgm + 'Not implemented.');
        };

        // send meta-data for new comments to server and get comment.created_at_server boolean.
        // called from UserService.ping
        var new_comments_request_index = {}; // from cid to [gift,comment] - used in new_comments_response for quick comment lookup
        var new_comments_request = function () {
            var pgm = service + '.new_comments_request: ';
            var request = [];
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
                    sha256_client = Gofreerev.sha256(gift.gid, comment.created_at_client.toString(), comment.comment, comment.price, comment.currency);
                    hash = {cid: cid, user_ids: comment.user_ids, sha256: sha256_client};
                    request.push(hash);
                    // cid to gift+comment helper - used in new_comments_response for quick gift and comment lookup
                    new_comments_request_index[cid] = [gift, comment];
                } // for j
            } // for i
            return (request.length == 0 ? null : request);
        }; // new_comments_request
        var new_comments_response = function (response) {
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
                }
                if (comment.hasOwnProperty('created_at_server')) {
                    console.log(pgm + 'System error. Comment ' + cid + ' signature was created on server but created_at_server property was setted between new comments request and new comments response.') ;
                    continue ;
                }
                // todo: add refresh_comment method
                // refresh_comment(comment) ;
                if (comment.hasOwnProperty('created_at_server')) {
                    // thats is ok if multiple browser sessions with identical login / identical client user id
                    if (comment.created_at_server == 0) null; // ok - received in an other browser session
                    else console.log(pgm + 'System error. Comment ' + cid + ' signature was created on server but created_at_server property for comment was set to an invalid value between new comments request and new comments response. Expected created_at_server = 0. Found created_at_server = ' + comment.created_at_server + '.');
                    continue;
                }
                comment.created_at_server = 0;
                save_gift(gift) ;
            } // for i
            new_comments_request_index = {};
        }; // new_comments_response
        

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

        var post_symmetric_password_setup = function () {
            var pgm = service + '.post_symmetric_password_setup: ';
            var now = (new Date).getTime();
            var device, elapsed;
            for (var did in devices) {
                device = devices[did];
                if (!device.password_at) continue;
                elapsed = now - device.password_at;
                if (elapsed < 60000) continue; // wait - less when 60 seconds since password setup was completed
                // free some js variables
                delete device.password1;
                delete device.password1_at;
                delete device.password2;
                delete device.password2_at;
                delete device.password_md5;
                delete device.password_at;
                // console.log(pgm + 'elapsed = ' + elapsed + ', device = ' + JSON.stringify(device)) ;
            } // for did
        }; // post_symmetric_password_setup


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
                        users: JSON.parse(JSON.stringify(new_mutual_friends))
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
                    // first outgoing message - sent when symmetric password is ready
                    // communication step 2 - compare sha256 checksum for mutual friends
                    hash = {
                        mid: Gofreerev.get_new_uid(),
                        msgtype: 'users_sha256',
                        users: JSON.parse(JSON.stringify(mailbox.mutual_friends))
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
            // cleanup after symmetric password setup
            post_symmetric_password_setup();
        }; // update_mailboxes

        // get/set pubkey for unique device - called in ping - used in client to client communication
        // note that public keys for remote devices sometimes are returned in a later pubkeys_response
        // number of rows in response < number of rows in request
        // public key has to be requested in a server to server pubkeys request
        // client continues to request remote public key until it is returned
        var pubkeys_request = function () {
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

        // setup password for symmetric communication. password1 from this device and password2 from other device
        // password_md5 is used in control for identical symmetric password in communication between the two devices
        var setup_device_password = function (device) {
            var pgm = service + '.setup_device_password: ';
            if (!device.password1) {
                // todo: jsencrypt. check problems with max length for rsa message. Limit about 128 characters is not correct for a 2048 bit key
                device.password1 = Gofreerev.generate_random_password(40); // 42 characters password to long for RSA
                device.password1_at = (new Date).getTime();
                console.log(pgm + 'symmetric password setup: generated password1') ;
            }
            if (!device.password1_at || !device.password2_at) {
                delete device.password_md5;
                return;
            }
            if (device.password1_at <= device.password2_at) {
                device.password = device.password1 + device.password2;
            }
            else {
                device.password = device.password2 + device.password1;
            }
            console.log(pgm + 'device.password = ' + device.password) ;
            device.password_at = (new Date).getTime();
            device.password_md5 = CryptoJS.MD5(device.password).toString(CryptoJS.enc.Latin1);
            device.ignore_invalid_gifts = [];
        }; // setup_device_password

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
                for (i=0 ; i<users_sha256_message.users.length ; i++) user_ids.push(users_sha256_message.users[i].user_id) ;
                if (!userService.user_ids_to_remote_sha256(user_ids, mailbox.server_id, msg, false)) {
                    // translate error. see log
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
            var password;
            for (var i = 0; i < mailboxes.length; i++) {
                mailbox = mailboxes[i];
                did = mailbox.did;
                device = devices[did];
                if (!device || !device.pubkey) {
                    console.log(pgm + 'Wait. Public key has not yet been received for device ' + did);
                    continue;
                }
                if (!device.password) {
                    // communication step 1 - setup password for symmetric encryption
                    if (!mailbox.online) {
                        // wait - not online
                        console.log(pgm + 'symmetric password setup: wait. mailbox not online') ;
                        continue;
                    }
                    // send password1 to other device using public/private key encryption (rsa)
                    if (!device.password1) {
                        // todo: jsencrypt. check problems with max length for rsa message. Limit about 128 characters is not correct for a 2048 bit key
                        device.password1 = Gofreerev.generate_random_password(40); // 42 characters password to long for RSA
                        device.password1_at = (new Date).getTime();
                        console.log(pgm + 'symmetric password setup: generated password1') ;
                    }
                    setup_device_password(device);
                    message = [0,device.password1, device.password1_at]; // 0: password setup in progress
                    if (device.password_md5) message.push(device.password_md5); // verify complete symmetric password (password1+password2) for device
                    // message => json => rsa encrypt
                    message_csv = message.join(',');
                    // console.log(pgm + 'rsa encrypt using public key ' + devices[did].pubkey);
                    encrypt.setPublicKey(devices[did].pubkey);
                    // RSA encrypt with default values - CBC and Pkcs7 (https://code.google.com/p/crypto-js/#Block_Modes_and_Padding)
                    message_csv_rsa_enc = encrypt.encrypt(message_csv);
                    // add envelope - used in rails message buffer - each message have sender, receiver, encryption and message
                    message_with_envelope = {
                        receiver_did: mailbox.did,
                        receiver_sha256: mailbox.sha256,
                        server: false,
                        encryption: 'rsa',
                        message: message_csv_rsa_enc
                    };
                    console.log(pgm + 'symmetric password setup: sending rsa message') ;
                    // todo: server_id for remote gofreerev server added to ping :online response. Not tested!
                    // if (mailbox.hasOwnProperty('server_id')) message_with_envelope.receiver_server_id = mailbox.server_id ;
                    response.push(message_with_envelope);
                    // debug
                    // console.log(pgm + 'message_json = ' + message_json) ;
                    // console.log(pgm + 'message_json_rsa_enc = ' + message_json_rsa_enc) ;
                    // console.log(pgm + 'message_with_envelope = ' + JSON.stringify(message_with_envelope)) ;
                    // wait with any messages in outbox until symmetric password setup is complete
                    continue;
                }
                console.log(pgm + 'device.password = ' + device.password) ; // todo: remove
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
                // encrypt message in mailbox using symmetric encryption
                password = device.password;
                message_with_envelope = {
                    receiver_did: mailbox.did,
                    receiver_sha256: mailbox.sha256,
                    server: false,
                    encryption: 'sym',
                    message: Gofreerev.encrypt(JSON.stringify(message), password)
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
            var mailbox;
            for (var i = 0; i < mailboxes.length; i++) {
                mailbox = mailboxes[i];
                for (var j = 0; j < mailbox.sending.length; j++) {
                    mailbox.sent.push(mailbox.sending[j]);
                    if (mailbox.sent.length > 5) mailbox.sent.shift(); // keep last 5 sent messages
                } // for j
                mailbox.sending.length = 0;
            } // for i
        }; // messages_sent

        // ping error response. move messages from mailbox.sending to mailbox.outbox
        var messages_not_sent = function () {
            var mailbox;
            for (var i = 0; i < mailboxes.length; i++) {
                mailbox = mailboxes[i];
                for (var j = 0; j < mailbox.sending.length; j++) mailbox.outbox.push(mailbox.sending[j]);
                mailbox.sending.length = 0;
            } // for i
        }; // messages_sent

        // manage device.ignore_invalid_gifts list - filter messages with invalid gifts
        var is_gift_on_ignore_list = function (device, gid) {
            if (device.ignore_invalid_gifts.indexOf(gid) == -1) return false;
            console.log(pgm + 'Error. Gift ' + gid + ' is in ignore list. See previous error message in log.');
            return true;
        };
        var add_gift_to_ignore_list = function (device, gid) {
            if (device.ignore_invalid_gifts.indexOf(gid) != -1) ;
            device.ignore_invalid_gifts.push(gid);
        };

        // communication step 1 - receive symmetric password (part 2) from other device
        // rails: see Message.receive_message (server to server)
        var receive_message_password = function (device, msg) {
            var pgm = service + '.receive_message_password: ';
            // console.log(pgm + 'device = ' + JSON.stringify(device)) ;
            // console.log(pgm + 'msg = ' + JSON.stringify(msg));
            // msg is an array with password, password_at and optional md5 for complete password
            // password setup is complete when received md5 in msg and password md5 for device are identical
            var done = msg[0] ; // password setup done on other client?
            device.password2 = msg[1];
            device.password2_at = msg[2];
            // calc password_md5 if possible
            setup_device_password(device);
            console.log(pgm + 'device.password = ' + device.password) ;
            // check of the two devices agree about password
            var md5_ok = (device.password_md5 && (msg.length == 4) && (device.password_md5 == msg[3]));
            if (md5_ok) console.log(pgm + 'symmetric password setup completed.');
            else console.log(pgm + 'symmetric password setup in progress.');
            console.log(pgm + 'done = ' + done + ', md5_ok = ' + md5_ok) ;
            if (!md5_ok || !done) delete device.password; // resend rsa password message to other client in next ping
        }; // receive_message_password;


        // move previous message from sent to done or error
        var move_previous_message = function (pgm, mailbox, request_mid, request_msgtype, done) {
            if (!request_mid) return false ; // no previous message to move
            if ((typeof done == 'undefined') || (done == null)) done = true ;
            var folder = done ? mailbox.done : mailbox.error ;
            var foldername = done ? 'done' : 'error' ;
            var msg;
            // check sent folder
            for (var i = 0; i < mailbox.sent.length; i++) {
                if ((mailbox.sent[i].mid == request_mid) && (mailbox.sent[i].msgtype == request_msgtype)) {
                    console.log(pgm + 'Moving old ' + request_msgtype + ' message ' + request_mid + ' from sent to ' + foldername + '.');
                    msg = mailbox.sent.splice(i, 1);
                    folder.push(msg[0]);
                    return true ;
                }
            }
            // check outbox folder - normally not the case - sent messages should be in sent folder
            for (var i = 0; i < mailbox.outbox.length; i++) {
                if ((mailbox.outbox[i].mid == request_mid) && (mailbox.outbox[i].msgtype == request_msgtype)) {
                    console.log(pgm + 'Warning. Moving old ' + request_msgtype + ' message ' + request_mid + ' from outbox to ' + foldername + '.');
                    msg = mailbox.outbox.splice(i, 1);
                    folder.push(msg[0]);
                    return true ;
                }
            }
            console.log(pgm + 'Error. Old ' + request_msgtype + ' message with mid ' + request_mid + ' was not found in mailbox.');
            return false ;
        }; // move_previous_message


        // communication step 2 - receive "users_sha256" message from other device. one user.sha256 signature for each mutual friend
        var receive_message_users_sha256 = function (device, mailbox, msg) {
            var pgm = service + '.receive_message_users_sha256: ' ;
            var error ;
            console.log(pgm + 'mailbox = ' + JSON.stringify(mailbox)) ;
            console.log(pgm + 'msg     = ' + JSON.stringify(msg)) ;

            // validate users_sha256 message before processing message
            if (Gofreerev.is_json_message_invalid(pgm,msg,'users_sha256','')) {
                // return JSON error to other device
                var json_error = JSON.parse(JSON.stringify(tv4.error));
                delete json_error.stack;
                var json_errors = JSON.stringify(json_error) ;
                error = 'users_sha256 message rejected by receiver. JSON schema validation errors: ' + json_errors ;
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

            // abort if response to request msg.mid is already in mailbox
            for (i=0 ; i<mailbox.outbox.length ; i++) {
                if (mailbox.outbox[i].request_mid == msg.mid) {
                    console.log(pgm + 'Error. Response to users_sha256 message ' + msg.mid + ' is already in outbox.') ;
                    return ;
                }
            } // for i
            for (i=0 ; i<mailbox.done.length ; i++) {
                if (mailbox.done[i].request_mid == msg.mid) {
                    console.log(pgm + 'Error. Response to users_sha256 message ' + msg.mid + ' is already in done.') ;
                    return ;
                }
            } // for i
            for (i=0 ; i<mailbox.error.length ; i++) {
                if (mailbox.error[i].request_mid == msg.mid) {
                    console.log(pgm + 'Error. Response to users_sha256 message ' + msg.mid + ' is already in error.') ;
                    return ;
                }
            } // for i

            // check for users_sha256 message from client on other Gofreerev server (using sha256 signature as user_id)
            var unknown_sha256_user_ids = [], i, user_id, index, friend, msg_users_old ;
            if (mailbox.hasOwnProperty('server_id')) {
                console.log(pgm + 'users_sha256 message from client on an other Gofreerev server. Translate sha256 signatures in msg.users to internal user ids') ;
                console.log(pgm + 'msg.users (1) = ' + JSON.stringify(msg.users)) ;

                // keep a copy of old sha256 user ids before translation (for debug and error messages)
                var msg_users_sha256 = [] ;
                var i ;
                for (i=0 ; i<msg.users.length ; i++) {
                    user_id = msg.users[i].user_id ;
                    msg_users_sha256.push(user_id) ;
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
                for (i=msg.users.length-1 ; i>= 0 ; i--) {
                    user_id = msg.users[i].user_id ;
                    friend = userService.get_friend_by_sha256(user_id) ;
                    if (friend) {
                        console.log(pgm + 'translating sha256 user_id ' + user_id + ' to internal user_id ' + friend.user_id) ;
                        msg.users[i].user_id = friend.user_id ;
                    }
                    else {
                        console.log(pgm + 'unknown sha256 user_id ' + user_id) ;
                        unknown_sha256_user_ids.push(msg.users[i].user_id) ;
                        msg.users.splice(i,1) ;
                    }
                }
                console.log(pgm + 'msg.users (2) = ' + JSON.stringify(msg.users)) ;
                if (unknown_sha256_user_ids.length > 0) console.log(pgm + 'unknown_sha256_user_ids = ' + JSON.stringify(unknown_sha256_user_ids)) ;
            } // if

            // compare mailbox.mutual_friends and msg.users. list of users in msg must be a sublist of mutual friends
            var my_mutual_friends = mailbox.mutual_friends ;
            var msg_users = [] ;
            var i ;
            for (i=0 ; i<msg.users.length ; i++) {
                user_id = msg.users[i].user_id ;
                msg_users.push(user_id) ;
            } // for i
            var invalid_user_ids = $(msg_users).not(my_mutual_friends).get() ;
            console.log(pgm + 'msg_users = ' + JSON.stringify(msg_users) + ', my_mutual_friends = ' + JSON.stringify(my_mutual_friends) + ', invalid_user_ids = ' + JSON.stringify(invalid_user_ids));
            // msg_users = [2,3], my_mutual_friends = [920], invalid_user_ids  = [2,3]" gofreerev.js:4220:0
            if (invalid_user_ids.length + unknown_sha256_user_ids.length > 0) {
                // unknown or invalid user in users_sha256 message:
                error = (invalid_user_ids.length + unknown_sha256_user_ids.length) + ' rejected users(s) in users_sha256 message' ;
                if (msg_users_sha256) error += '. Received sha256 user signatures: ' + msg_users_sha256.join(', ') ;
                if (unknown_sha256_user_ids.length > 0) error += '. Unknown sha256 user signatures: ' + unknown_sha256_user_ids.join(', ') ;
                error += '. Received internal user ids: ' + msg_users.join(', ') ;
                if (invalid_user_ids.length > 0) {
                    error += '. Expected user ids: ' + my_mutual_friends.join(', ');
                    error += '. Unknown mutual friends: ' + invalid_user_ids.join(', ');
                }
                console.log(pgm + error) ;
                // continue with users_sha256 message if possible
                msg_users = $(msg_users).not(invalid_user_ids).get() ;
                console.log(pgm + 'msg_users.length = ' + msg_users.length) ;
                if (msg_users.length == 0) {
                    console.log(pgm + 'Could not receive users_sha256 message. User ids in message and mutual users in mailbox does not match') ;
                    mailbox.outbox.push({
                        mid: Gofreerev.get_new_uid(),
                        request_mid: msg.mid,
                        msgtype: 'error',
                        error: error
                    }) ;
                    return ;
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
            var oldest_gift_at = 0 ; // todo: max oldest_gift_at on this device and msg.oldest_gift_at
            var ignore_invalid_gifts = []; // todo: merge msg.ignore_invalid_gifts and device.ignore_invalid_gifts gids

            // compare sha256 values for msg.users - continue gift sync until sha256 values are identical todo: or endless loop is detected
            var sha256_array = calc_sha256_for_users(msg_users, oldest_gift_at, ignore_invalid_gifts) ;
            var sha256_hash = {} ;
            for (i=0 ; i<sha256_array.length ; i++) {
                user_id = sha256_array[i].user_id ;
                sha256_hash[user_id] = { my_sha256: sha256_array[i].sha256 } ;
            } // for i
            for (i=0 ; i<msg.users.length ; i++) {
                user_id = msg.users[i].user_id ;
                if (invalid_user_ids.indexOf(user_id) != -1) continue ; // skip "invalid" users (devices on two different Gofreerev servers dont have to agree 100% about mutual friends)
                // if (mutual_friends.indexOf(user_id) == -1) continue ;
                sha256_hash[user_id].msg_sha256 = msg.users[i].sha256 ;
            } // for i
            console.log(pgm + 'sha256_hash = ' + JSON.stringify(sha256_hash)) ;
            //sha256_hash = {"1126":{"my_sha256":null,
            //                       "msg_sha256":null},
            //               "920": {"my_sha256":"\u0011½ åìÊ~\u000b\u0007Y\u000bá\\>é\u0013ìÞOì\\ÏwÆJ+K\nª\n",
            //                       "msg_sha256":"aÕÛPîÂ\t¬B!\u001cíÌÁ2\"ò®\u000fvEUO\u000fåuÙ"}}

            // find users with sha256 difference
            var user_ids = [] ;
            for (user_id in sha256_hash) {
                if ((sha256_hash[user_id].my_sha256 == null) && (sha256_hash[user_id].msg_sha256 == null)) continue ;
                if (sha256_hash[user_id].my_sha256 != sha256_hash[user_id].msg_sha256) user_ids.push(parseInt(user_id)) ;
            }
            if (user_ids.length == 0) {
                console.log(pgm + 'mutual gifts for this device are up-to-date.') ;
                return ;
            }
            user_ids.sort() ;
            console.log(pgm + 'user_ids = ' + user_ids.join(', ')) ;

            // find sha256 values for relevant gifts (msg.users)
            var gifts_sha256_hash = {}, j, gift ;
            for (i=0 ; i<user_ids.length ; i++) {
                user_id = user_ids[i] ;
                if (!user_id_to_gifts.hasOwnProperty(user_id)) {
                    console.log(pgm + 'No gifts was found for user id ' + user_id) ;
                    continue ;
                }
                console.log(pgm + 'user_id_gifts_index[' + user_id + '].length = ' + user_id_to_gifts[user_id].length) ;
                for (j=0 ; j<user_id_to_gifts[user_id].length ; j++) {
                    gift = user_id_to_gifts[user_id][j] ;
                    if (!gift.sha256) continue; // no server gift signature or sha256 gift calculation error
                    // todo: add gift.updated_at_client property - apply oldest_gift_at filter
                    if (!gifts_sha256_hash[gift.gid]) gifts_sha256_hash[gift.gid] = gift.sha256 ;
                } // for j
            } // for i
            console.log(pgm + 'gifts_sha256_hash = ' + JSON.stringify(gifts_sha256_hash)) ;
            //gifts_sha256_hash =
            //    {"14239781692770120364":"ä Ùh¿G×Ñâô9ÔÀ4ÀXèk\u0010N~,\nB]M",
            //     "14239781692770348983":",F¯Ø\"Lo\u0004ö5é_Ï%p\\T¡(j{ï³o",
            //        ...
            //     "14244941900636888171":"¨Yr¤ï9ÉÀðn\u0000K JýôNèÅMêÛûCô"}

            var gifts_sha256_array = [] ;
            for (var gid in gifts_sha256_hash) {
                gifts_sha256_array.push({gid: gid, sha256: gifts_sha256_hash[gid]}) ;
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
            if (oldest_gift_at > 0) gifts_sha256_message.oldest_gift_at = oldest_gift_at ;

            if (mailbox.hasOwnProperty('server_id')) {
                // translate internal user ids to sha256 signatures before sending gifts_sha256 message
                console.log(pgm + 'gifts_sha256_message (1) = ' + JSON.stringify(gifts_sha256_message));
                //gifts_sha256_message =
                //{"mid":"14273774200608483113","request_mid":"14273773969082891666","msgtype":"gifts_sha256",
                //    "ignore_invalid_gifts":[],
                //    "users":[920],
                //    "gifts":[{"gid":"14253148989837740200","sha256":"9mÙ@¥ÔÖûÊ\u0010B«î¶Q:È\u0007k\u0013[´\u0019vCÛ\u0014Pm"},{"gid":"14253152345973353338","sha256":"9mÙ@¥ÔÖûÊ\u0010B«î¶Q:È\u0007k\u0013[´\u0019vCÛ\u0014Pm"},{"gid":"14253163835441202510","sha256":"9mÙ@¥ÔÖûÊ\u0010B«î¶Q:È\u0007k\u0013[´\u0019vCÛ\u0014Pm"},{"gid":"14253166119353097472","sha256":"9mÙ@¥ÔÖûÊ\u0010B«î¶Q:È\u0007k\u0013[´\u0019vCÛ\u0014Pm"},{"gid":"14253170024715544645","sha256":"gµï\u0015îé;;¯Æ'åéz²¦]^ý£ß½Rõl\"l\"ö"},{"gid":"14254791174816684686","sha256":"Çî\u0002t 31gõ¤7NÈªãÃÏ\u0018ÂØ\u0013 ×Ü*á\u0013ùÑ"},{"gid":"14255660363225768616","sha256":"·ï^ýEª0W\u0000Ê\u001cãC%âÝ=râ=p[rïYµ²¯¸"},{"gid":"14255663264284720316","sha256":"ÉÛ5}y­\u001cÓÙhuÂÈýËmêFÉê¥±\u0000ýÞ\\\u0015¦"},{"gid":"14255666249033078430","sha256":"yå·¾à¿ÒX\u0013¼\u0005þ8J|¼±¡`|Ýªy¨98ÉJ°"},{"gid":"14255715337351272927","sha256":":# ÅÚ¹Ì\u0015ûì\bJ{Ø\u000eø\u001e/\u001d\u000fÕý³U\u001d«"},{"gid":"14258782920140696549","sha256":"9mÙ@¥ÔÖûÊ\u0010B«î¶Q:È\u0007k\u0013[´\u0019vCÛ\u0014Pm"}]}" gofreerev.js:4504:0
                if (!userService.user_ids_to_remote_sha256(gifts_sha256_message.users, mailbox.server_id, gifts_sha256_message, false)) {
                    // todo: send error msg to client that sent users_sha256 message. user_ids_to_remote_sha256 should return error message
                    return ;
                } // translate error
                // translate ok
                console.log(pgm + 'gifts_sha256_message (2) = ' + JSON.stringify(gifts_sha256_message));
            }

            // validate gifts_sha256 message before adding to outbox
            if (Gofreerev.is_json_message_invalid(pgm,gifts_sha256_message,'gifts_sha256','')) {
                // error message has already been written to log
                // todo: error debugging - no mutual friends was found
                console.log(pgm + 'users = ' + JSON.stringify(user_ids)) ;
                console.log(pgm + 'gifts = ' + JSON.stringify(gifts_sha256_array)) ;
                console.log(pgm + 'user_id_to_gifts = ' + JSON.stringify(user_id_to_gifts)) ;
                // send error message to other device
                var json_error = JSON.parse(JSON.stringify(tv4.error));
                delete json_error.stack;
                var json_errors = JSON.stringify(json_error) ;
                error = 'Error when processing users_sha256 message. JSON schema validation error in following gifts_sha256 message. ' + json_errors ;
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

            // abort if identical gifts_sha256 message is already in outbox.
            var folders = { outbox: mailbox.outbox, sent: mailbox.sent}, folder, old_msg ;
            var sent_at, elapsed_time ;
            for (folder in folders) {
                for (i=0 ; i<folders[folder].length ; i++) {
                    old_msg = folders[folder][i] ;
                    if (old_msg.msgtype == 'gifts_sha256') {
                        console.log(pgm + 'Warning. Found old gifts_sha256 message in ' + folder ) ;
                        console.log(pgm + 'mailbox = ' + JSON.stringify(mailbox)) ;
                        console.log(pgm + 'gifts_sha256 message = ' + JSON.stringify(gifts_sha256_message)) ;
                        sent_at = parseInt(old_msg.mid.substr(0,13)) ;
                        elapsed_time = new Date().getTime() - sent_at ;
                        console.log(pgm + 'sent_at = ' + sent_at + ', elapted_time = ' + elapsed_time) ;
                        if ((elapsed_time < 60000) && (old_msg.users.join(',') == gifts_sha256_message.users.join(','))) {
                            // new identical gifts_sha256 response less than 1 minute ago
                            error = 'Ignoring doublet users_sha256 request ' + msg.mid + '. Gifts_sha256 response ' + old_msg.mid + ' has already been sent less than 1 minute ago' ;
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
                } // for i
            } // for folder (outbox, sent)

            mailbox.outbox.push(gifts_sha256_message) ;


        }; // receive_message_users_sha256


        // logical validate "send_gifts" message before send (receive_message_sync_gifts) and after receive (receive_message_send_gifts)
        // called after json validation but before sending send_gifts message / processing information in received send_gifts message
        // returns nil or error message
        // params: send: true: sending message, false: receiving message
        var validate_send_gifts_message = function (mailbox, send_gifts, send) {
            var pgm = service + '.validate_send_gifts_message: ' ;
            if (send) console.log(pgm + 'validating send_gifts message before send') ;
            else console.log(pgm + 'validating send_gifts message after received') ;

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
                    add_user_ids_to_array(new_gift.giver_user_ids, expected_user_ids) ;
                    add_user_ids_to_array(new_gift.receiver_user_ids, expected_user_ids) ;
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
                        add_user_ids_to_array(new_comment.user_ids, expected_user_ids);
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
                if (send) {
                    // sending send_gifts message using remote sha256 signatures for users
                    mutual_friends = JSON.parse(JSON.stringify(mailbox.mutual_friends)) ;
                    userService.user_ids_to_remote_sha256(mutual_friends, mailbox.server_id, send_gifts, false) ;
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


        // communication step 3 - compare sha256 values for gifts (mutual friends)
        var receive_message_gifts_sha256 = function (device, mailbox, msg) {
            var pgm = service + '.receive_message_gifts_sha256: ' ;
            console.log(pgm + 'mailbox = ' + JSON.stringify(mailbox)) ;
            console.log(pgm + 'msg     = ' + JSON.stringify(msg)) ;

            // validate gifts_sha256 message before processing message
            if (Gofreerev.is_json_message_invalid(pgm,msg,'gifts_sha256','')) {
                // move previous users_sha256 message to error folder
                if (!move_previous_message(pgm, mailbox, msg.request_mid, 'users_sha256', false)) return ; // ignore - not found in mailbox
                // return JSON error to other device
                var json_error = JSON.parse(JSON.stringify(tv4.error));
                delete json_error.stack;
                var json_errors = JSON.stringify(json_error) ;
                var error = 'Receiver rejected gifts_sha256 message. JSON schema validation errors: ' + json_errors ;
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

            // abort if response to request msg.mid is already in mailbox
            for (i=0 ; i<mailbox.outbox.length ; i++) {
                if (mailbox.outbox[i].request_mid == msg.mid) {
                    console.log(pgm + 'Error. Response to gifts_sha256 message ' + msg.mid + ' is already in outbox.') ;
                    return ;
                }
            } // for i
            for (i=0 ; i<mailbox.done.length ; i++) {
                if (mailbox.done[i].request_mid == msg.mid) {
                    console.log(pgm + 'Error. Response to gifts_sha256 message ' + msg.mid + ' is already in done.') ;
                    return ;
                }
            } // for i
            for (i=0 ; i<mailbox.error.length ; i++) {
                if (mailbox.error[i].request_mid == msg.mid) {
                    console.log(pgm + 'Error. Response to gifts_sha256 message ' + msg.mid + ' is already in error.') ;
                    return ;
                }
            } // for i

            // move previous users_sha256 message to done folder
            if (!move_previous_message(pgm, mailbox, msg.request_mid, 'users_sha256', true)) return ; // ignore - not found in mailbox

            // check for gifts_sha256 message from client on other Gofreerev server (using sha256 signature as user_id)
            var unknown_sha256_user_ids = [], i, user_id, index, friend, msg_users_old ;
            if (mailbox.hasOwnProperty('server_id')) {
                console.log(pgm + 'gifts_sha256 message from client on an other Gofreerev server. Translate sha256 signatures in msg.users to internal user ids') ;
                console.log(pgm + 'msg.users (1) = ' + JSON.stringify(msg.users)) ;

                // keep a copy of old sha256 user ids before translation (for debug and error messages)
                var msg_users_sha256 = [] ;
                var i ;
                for (i=0 ; i<msg.users.length ; i++) msg_users_sha256.push(msg.users[i]) ;

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
                for (i=msg.users.length-1 ; i>= 0 ; i--) {
                    user_id = msg.users[i] ;
                    friend = userService.get_friend_by_sha256(user_id) ;
                    if (friend) {
                        console.log(pgm + 'translating sha256 user_id ' + user_id + ' to internal user_id ' + friend.user_id) ;
                        msg.users[i] = friend.user_id ;
                    }
                    else {
                        console.log(pgm + 'unknown sha256 user_id ' + user_id) ;
                        unknown_sha256_user_ids.push(user_id) ;
                        msg.users.splice(i,1) ;
                    }
                }
                console.log(pgm + 'msg.users (2) = ' + JSON.stringify(msg.users)) ;
                if (unknown_sha256_user_ids.length > 0) console.log(pgm + 'unknown_sha256_user_ids = ' + JSON.stringify(unknown_sha256_user_ids)) ;
            } // if

            // compare mailbox.mutual_friends and msg.users. list of users in msg must be a sublist of mutual friends
            var my_mutual_friends = mailbox.mutual_friends ;
            var msg_users = msg.users ;
            var invalid_user_ids = $(msg_users).not(my_mutual_friends).get() ;

            if (invalid_user_ids.length + unknown_sha256_user_ids.length > 0) {
                // unknown or invalid user in users_sha256 message:
                error = (invalid_user_ids.length + unknown_sha256_user_ids.length) + ' rejected users(s) in users_sha256 message' ;
                if (msg_users_sha256) error += '. Received sha256 user signatures: ' + msg_users_sha256.join(', ') ;
                if (unknown_sha256_user_ids.length > 0) error += '. Unknown sha256 user signatures: ' + unknown_sha256_user_ids.join(', ') ;
                error += '. Received internal user ids: ' + msg_users.join(', ') ;
                if (invalid_user_ids.length > 0) {
                    error += '. Expected user ids: ' + my_mutual_friends.join(', ');
                    error += '. Unknown mutual friends: ' + invalid_user_ids.join(', ');
                }
                console.log(pgm + error) ;
                if (msg_users.length == 0) {
                    mailbox.outbox.push({
                        mid: Gofreerev.get_new_uid(),
                        request_mid: msg.mid,
                        msgtype: 'error',
                        error: error
                    }) ;
                    return ;
                }
                // continue without invalid user ids
                msg_users = $(msg_users).not(invalid_user_ids).get() ;
            }

            // todo: users in this gifts_sha256 message should be identical to users in previous users_sha256 message (now in done)

            // find sha256 values for relevant gifts / users (sublist of mutual friends)
            var gifts_sha256_hash = {}, user_id, i, j, k, gift, gid ;
            for (i=0 ; i<msg_users.length ; i++) {
                user_id = msg_users[i] ;
                if (!user_id_to_gifts.hasOwnProperty(user_id)) {
                    // no gifts for this user id
                    console.log(pgm + 'no gifts for user id ' + user_id) ;
                    continue ;
                }
                console.log(pgm + 'user_id_gifts_index[' + user_id + '].length = ' + user_id_to_gifts[user_id].length) ;
                for (j=0 ; j<user_id_to_gifts[user_id].length ; j++) {
                    gift = user_id_to_gifts[user_id][j] ;
                    if (!gift.sha256) continue; // no server gift signature or sha256 gift calculation error
                    gid = gift.gid ;
                    // todo: add gift.updated_at_client property - apply oldest_gift_at filter
                    if (!gifts_sha256_hash[gid]) gifts_sha256_hash[gid] = { my_sha256: gift.sha256, msg_sha256: null } ;
                } // for j
            } // for i
            // add sha256 values received from other device
            for (i=0 ; i<msg.gifts.length ; i++) {
                gid = msg.gifts[i].gid ;
                if (gifts_sha256_hash[gid]) gifts_sha256_hash[gid].msg_sha256 = msg.gifts[i].sha256 ;
                else gifts_sha256_hash[gid] = { my_sha256: null, msg_sha256: msg.gifts[i].sha256 } ;
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
            var request_gids = [], send_gids = [], check_gids = [], ok_gids = [], error_gids = [] ;
            var sha256_values, compare ;
            for (gid in gifts_sha256_hash) {
                sha256_values = gifts_sha256_hash[gid] ;
                compare = (sha256_values.my_sha256 ? '1' : '0') + (sha256_values.msg_sha256 ? '1' : '0') ;
                switch(compare) {
                    case '00':
                        error_gids.push(gid) ;
                        break ;
                    case '01':
                        // request gift from other device
                        request_gids.push(gid) ;
                        break ;
                    case '10':
                        // send new gift to other device
                        send_gids.push(gid) ;
                        break ;
                    case '11':
                        // check gift sha256 value
                        // send sub sha256 values to other device if difference in gift sha256 value
                        // the difference can be in gift and/or in comments
                        if (compare.my_sha256 == compare.msg_sha256) ok_gids.push(gid) ;
                        else check_gids.push(gid) ;
                        break ;
                } // end compare switch
            } // for gid

            // compare gifts resume
            if (request_gids.length > 0) console.log(pgm + 'request_gids = ' + request_gids.join(', ')) ;
            if (send_gids.length    > 0) console.log(pgm + 'send_gids = ' + send_gids.join(', ')) ;
            if (check_gids.length   > 0) console.log(pgm + 'check_gids = ' + check_gids.join(', ')) ;
            if (ok_gids.length      > 0) console.log(pgm + 'ok_gids = ' + ok_gids.join(', ')) ;
            if (error_gids.length   > 0) console.log(pgm + 'error_gids = ' + error_gids.join(', ')) ;
            if (request_gids.length + send_gids.length + check_gids.length == 0) {
                console.log(pgm + 'Gift replication finished. ' + ok_gids.length + ' identical gifts '+ error_gids.length + ' gifts with errors and were found' ) ;
                if (error_gids.length > 0) console.log(pgm + 'Gifts with null sha256 values: ' + error_gids.join(', ')) ;
                // todo: send error or done response to other client
                return ;
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
                users: msg_users,
                send_gifts: null, // optional sub message 1)
                request_gifts: null, // optional sub message 2)
                check_gifts: null // optional sub message 3)
            };

            // - 1) send missing gifts to other device
            if (send_gids.length > 0) {
                var send_gifts_message = {
                    mid: Gofreerev.get_new_uid(),
                    msgtype: 'send_gifts',
                    gifts: [],
                    users: []
                };
                var index, gift_clone, users = [], gift_users = [], user ;
                for (i=0 ; i<send_gids.length ; i++) {
                    gid = send_gids[i];
                    if (!gid_to_gifts_index.hasOwnProperty(gid)) {
                        console.log(pgm + 'Could not send gift ' + gid + ' to other device. Index was not found.') ;
                        continue ;
                    }
                    index = gid_to_gifts_index[gid] ;
                    if ((index < 0) || (index >= gifts.length)) {
                        console.log(pgm + 'Could not send gift ' + gid + ' to other device. Invalid gifts index (1).') ;
                        continue ;
                    }
                    gift = gifts[index] ;
                    if (gift.gid != gid) {
                        console.log(pgm + 'Could not send gift ' + gid + ' to other device. Invalid gifts index (2).') ;
                        continue ;
                    }
                    // validate gift before cloning for send_gifts sub message
                    error = invalid_gift(gift, []) ;
                    if (error) {
                        console.log(pgm + 'Warning. Invalid gift was not added to send_gifts sub message.') ;
                        console.log(pgm + 'Gift ' + gift_clone.gid + ': ' + JSON.stringify(gift_clone));
                        console.log(pgm + 'Error message: ' + error) ;
                        continue ;
                    }

                    // clone gift - some interval properties are not replicated to other devices
                    // todo: 1 - change like from boolean to an array  with user ids and like/unlike timestamps for merge operation
                    // todo: 2 - add server side sha256_deleted signature to gift. Server could validate client_deleted_at and know that gift has been deleted
                    // todo: 3 - add url with optional file attachment (file upload has not been implemented yet)
                    gift_clone =
                    {
                        gid: gift.gid,
                        giver_user_ids: gift.giver_user_ids,
                        receiver_user_ids: gift.receiver_user_ids,
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
                        deleted_at_client: gift.deleted_at_client,
                        // todo: add deleted_at_server (integer)
                        accepted_cid: gift.accepted_cid,
                        accepted_at_client: gift.accepted_at_client
                        // ,sha256: gift.sha256 - // sha256 is not sent - receiver will make gift sha256 calculations
                    };
                    // save relevant userids (giver, receiver and creator of comments) in gift_users buffer
                    add_user_ids_to_array(gift.giver_user_ids, gift_users) ;
                    add_user_ids_to_array(gift.receiver_user_ids, gift_users) ;
                    var comment ;
                    if (gift.comments && (gift.comments.length > 0)) {
                        gift_clone.comments = [] ;
                        for (j=0 ; j<gift.comments.length ; j++) {
                            comment = gift.comments[j] ;

                            // todo: 1 - add server side sha256_deleted and/or sha256_accepted signature
                            //           a comment cannot be both accepted and deleted (delete gift to remove accepted deals)
                            //           it should be enough with one client side deleted_at_server=accepted_at_server field

                            gift_clone.comments.push({
                                cid: comment.cid,
                                user_ids: comment.user_ids,
                                price: comment.price,
                                currency: comment.currency,
                                comment: comment.comment,
                                created_at_client: comment.created_at_client,
                                created_at_server: comment.created_at_server,
                                new_deal: comment.new_deal,
                                deleted_at_client: comment.deleted_at_client,
                                // todo: add deleted_at_server (integer)
                                accepted: comment.accepted,
                                accepted_at_client: comment.accepted_at_client,
                                accepted_by_user_ids: comment.accepted_by_user_ids,
                                rejected_at_client: comment.rejected_at_client,
                                rejected_by_user_ids: comment.rejected_by_user_ids
                                // ,sha256: comment.sha256
                            }) ;
                            // save relevant comment.user_ids in gift_users buffer
                            add_user_ids_to_array(comment.user_ids, gift_users) ;
                        } // for j (comments loop)
                    } // if comments
                    // validate gift_clone before adding gift to send_gifts sub message
                    error = invalid_gift(gift_clone, []) ;
                    if (error) {
                        console.log(pgm + 'System error when adding gift to send_gifts sub message.') ;
                        console.log(pgm + 'Gift ' + gift_clone.gid + ': ' + JSON.stringify(gift_clone));
                        console.log(pgm + 'Error message: ' + error) ;
                        continue ;
                    }
                    send_gifts_message.gifts.push(gift_clone) ;
                } // for i (send_gids loop)

                // add relevant users to send_gifts message - used as fallback information in case of "unknown user" error on receiving client
                for (j=0 ; j<gift_users.length ; j++) {
                    user_id = gift_users[j] ;
                    if (mailbox.mutual_friends.indexOf(user_id) != -1) continue ; // dont include mutual friends in send_gifts.users array
                    user = userService.get_friend(user_id) ;
                    // if (!user) console.log(pgm + 'Warning. Unknown friend user_id ' + user_id) ;
                    if (!user) user = userService.get_user(user_id) ; // fallback to "old" stored user info
                    if (!user) console.log(pgm + 'Error. Cannot add user info for unknown user_id ' + user_id) ;
                    send_gifts_message.users.push({
                        user_id: user.user_id,
                        uid: user.uid,
                        provider: user.provider,
                        user_name: user.user_name,
                        api_profile_picture_url: user.api_profile_picture_url
                    }) ;
                } // for j (gift_users)
                gift_users.length = 0 ;

                if (send_gifts_message.gifts.length > 0) sync_gifts_message.send_gifts = send_gifts_message ;
                else console.log(pgm + 'Error. No send_gifts sub message was added. See previous error messages in log.') ;
            } // if send_gids.length > 0

            // - 2) request missing gifts from other device
            if (request_gids.length > 0) {
                var request_gifts_message = {
                    mid: Gofreerev.get_new_uid(),
                    msgtype: 'request_gifts',
                    gifts: request_gids
                };
                sync_gifts_message.request_gifts = request_gifts_message ;
            } // request_gids.length > 0

            // - 3) send sub sha256 values for changed gifts to other device
            //      other device will check sub sha256 values and return gift, comments or both for gifts with different sha256 values
            if (check_gids.length > 0) {
                var check_gifts_message = {
                    mid: Gofreerev.get_new_uid(),
                    msgtype: 'check_gifts',
                    gifts: []
                } ;
                for (i=0 ; i<check_gids.length ; i++) {
                    gid = send_gids[i];
                    if (!gid_to_gifts_index.hasOwnProperty(gid)) {
                        console.log(pgm + 'Could not send gift ' + gid + ' sha256 values to other device. Index was not found.') ;
                        continue ;
                    }
                    index = gid_to_gifts_index[gid] ;
                    if ((index < 0) || (index >= gifts.length)) {
                        console.log(pgm + 'Could not send gift ' + gid + ' sha256 values to other device. Invalid gifts index (1).') ;
                        continue ;
                    }
                    gift = gifts[index] ;
                    if (gift.gid != gid) {
                        console.log(pgm + 'Could not send gift ' + gid + ' sha256 values to other device. Invalid gifts index (2).') ;
                        continue ;
                    }
                    check_gifts_message.gifts.push({
                        gid: gift.gid,
                        sha256: gift.sha256,
                        sha256_gift: gift.sha256_gift,
                        sha256_comments: gift.sha256_comments
                    }) ;

                } // for i (check_gids loop)
                if (check_gifts_message.gifts.length > 0) sync_gifts_message.check_gifts = check_gifts_message ;
                else console.log(pgm + 'Error. No check_gifts sub message was added. See prevous error messages in log.') ;
            } // if check_gids.length > 0

            console.log(pgm + 'sync_gifts_message = ' + JSON.stringify(sync_gifts_message)) ;
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
                console.log(pgm + 'Error. sync_gifts message was not sent. See previous errors in log.') ;
                return ;
            }

            if (mailbox.hasOwnProperty('server_id')) {

                // sync_gifts message to client on an other Gofreerev server
                // translate internal user ids to sha256 signatures before sending sync_gifts message
                // 1) translate users array in message header
                // 2) send_gifts: translate user ids in giver_user_ids, receiver_user_ids, comment user ids and users
                console.log(pgm + 'sync_gifts_message (1) = ' + JSON.stringify(sync_gifts_message));
                if (!userService.user_ids_to_remote_sha256(sync_gifts_message.users, mailbox.server_id, sync_gifts_message, false)) {
                    // translate error
                    // todo: send error msg to client that sent gifts_sha256 message. user_ids_to_remote_sha256 should return error message
                    return;
                }

                if (sync_gifts_message.send_gifts) {
                    // translate user ids in giver_user_ids, receiver_user_ids and comment user_ids
                    // use remote sha256 signatures for remote users and negative user id for "unknown" users
                    for (i = 0; i < sync_gifts_message.send_gifts.gifts.length; i++) {
                        gift = sync_gifts_message.send_gifts.gifts[i];
                        if (!userService.user_ids_to_remote_sha256(gift.giver_user_ids, mailbox.server_id, sync_gifts_message, true)) {
                            // translate error
                            // todo: send error msg to client that sent gifts_sha256 message. user_ids_to_remote_sha256 should return error message
                            return;
                        }
                        ;
                        if (!userService.user_ids_to_remote_sha256(gift.receiver_user_ids, mailbox.server_id, sync_gifts_message, true)) {
                            // translate error
                            // todo: send error msg to client that sent gifts_sha256 message. user_ids_to_remote_sha256 should return error message
                            return;
                        }
                        ;
                        if (gift.comments) {
                            for (j = 0; j < gift.comments.length; j++) {
                                if (!userService.user_ids_to_remote_sha256(gift.comments[j].user_ids, mailbox.server_id, sync_gifts_message, true)) {
                                    // translate error
                                    // todo: send error msg to client that sent gifts_sha256 message. user_ids_to_remote_sha256 should return error message
                                    return;
                                }
                                ;
                            }
                        }
                    }
                    // translate user ids in users array
                    var user_ids = [];
                    for (i = 0; i < sync_gifts_message.send_gifts.users.length; i++) user_ids.push(sync_gifts_message.send_gifts.users[i].user_id);
                    if (!userService.user_ids_to_remote_sha256(user_ids, mailbox.server_id, sync_gifts_message, true)) {
                        // translate error
                        // todo: send error msg to client that sent gifts_sha256 message. user_ids_to_remote_sha256 should return error message
                        return;
                    }
                    for (i=0 ; i<sync_gifts_message.send_gifts.users.length ; i++) sync_gifts_message.send_gifts.users[i].user_id = user_ids[i] ;
                    // user_id translate ok
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

            } // if server_id

            // JS validate sync_gifts message before placing message in outbox
            if (Gofreerev.is_json_message_invalid(pgm,sync_gifts_message,'sync_gifts','')) {
                // error message has already been written to log
                // send error message to other device
                var json_error = JSON.parse(JSON.stringify(tv4.error));
                delete json_error.stack;
                var json_errors = JSON.stringify(json_error) ;
                var error = 'Could not process gifts_sha256 message. JSON schema validation error in sync_gifts response: ' + json_errors ;
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
                error = validate_send_gifts_message(mailbox, sync_gifts_message.send_gifts, true) ; // true: sending message
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
                }
            }

            // todo: 2) check sub message request_gifts for logical errors

            // todo: 3) check sub message check_gifts for logical errors

            // send sync_gifts message
            mailbox.outbox.push(sync_gifts_message) ;

        }; // receive_message_gifts_sha256


        // communication step 4 - receive message with 1-3 sub messages (send_gifts, request_gifts and check_gifts)
        // verify that request_mid is correct and add sub messages to messages array
        // the 1-3 sub messages will be processed in next steps in for j loop (see receive_messages)
        // params:
        // - device and mailbox - as usual
        // - messages - array with messages received from server
        // - index - index to current "sync_gift" message in messages array
        var receive_message_sync_gifts = function (device, mailbox, msg) {
            var pgm = service + '.receive_message_sync_gifts: ' ;
            // console.log(pgm + 'device   = ' + JSON.stringify(device)) ;
            console.log(pgm + 'mailbox  = ' + JSON.stringify(mailbox)) ;
            console.log(pgm + 'msg      = ' + JSON.stringify(msg)) ;

            // validate sync_gifts message before processing message
            if (Gofreerev.is_json_message_invalid(pgm,msg,'sync_gifts','')) {
                // move previous gifts_sha256 message to error folder
                if (!move_previous_message(pgm, mailbox, msg.request_mid, 'gifts_sha256', false)) return ; // ignore - not found in mailbox
                // send error message to other device
                var json_error = JSON.parse(JSON.stringify(tv4.error));
                delete json_error.stack;
                var json_errors = JSON.stringify(json_error) ;
                var error = 'Receiver rejected gifts_sha256 message. JSON schema validation errors: ' + json_errors ;
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

            // abort if response to request msg.mid is already in mailbox
            for (i=0 ; i<mailbox.outbox.length ; i++) {
                if (mailbox.outbox[i].request_mid == msg.mid) {
                    console.log(pgm + 'Error. Response to gifts_sha256 message ' + msg.mid + ' is already in outbox.') ;
                    return ;
                }
            } // for i
            for (i=0 ; i<mailbox.done.length ; i++) {
                if (mailbox.done[i].request_mid == msg.mid) {
                    console.log(pgm + 'Error. Response to gifts_sha256 message ' + msg.mid + ' is already in done.') ;
                    return ;
                }
            } // for i
            for (i=0 ; i<mailbox.error.length ; i++) {
                if (mailbox.error[i].request_mid == msg.mid) {
                    console.log(pgm + 'Error. Response to gifts_sha256 message ' + msg.mid + ' is already in error.') ;
                    return ;
                }
            } // for i

            // move previous gifts_sha256 message to done folder
            if (!move_previous_message(pgm, mailbox, msg.request_mid, 'gifts_sha256', true)) return ; // ignore - not found in mailbox

            // check for sync_gifts message from client on other Gofreerev server (using sha256 signature as user_id)
            var unknown_sha256_user_ids = [], i, user_id, index, friend, msg_users_old ;
            if (mailbox.hasOwnProperty('server_id')) {
                console.log(pgm + 'sync_gifts message from client on an other Gofreerev server. Translate sha256 signatures in msg.users to internal user ids') ;
                console.log(pgm + 'msg.users (1) = ' + JSON.stringify(msg.users)) ;

                // keep a copy of old sha256 user ids before translation (for debug and error messages)
                var msg_users_sha256 = [] ;
                var i ;
                for (i=0 ; i<msg.users.length ; i++) msg_users_sha256.push(msg.users[i]) ;

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
                for (i=msg.users.length-1 ; i>= 0 ; i--) {
                    user_id = msg.users[i] ;
                    friend = userService.get_friend_by_sha256(user_id) ;
                    if (friend) {
                        console.log(pgm + 'translating sha256 user_id ' + user_id + ' to internal user_id ' + friend.user_id) ;
                        msg.users[i] = friend.user_id ;
                    }
                    else {
                        console.log(pgm + 'unknown sha256 user_id ' + user_id) ;
                        unknown_sha256_user_ids.push(user_id) ;
                        msg.users.splice(i,1) ;
                    }
                }
                console.log(pgm + 'msg.users (2) = ' + JSON.stringify(msg.users)) ;
                if (unknown_sha256_user_ids.length > 0) console.log(pgm + 'unknown_sha256_user_ids = ' + JSON.stringify(unknown_sha256_user_ids)) ;
            } // if

            // compare mailbox.mutual_friends and msg.users. list of users in msg must be a sublist of mutual friends
            var my_mutual_friends = mailbox.mutual_friends ;
            var msg_users = msg.users ;
            var invalid_user_ids = $(msg_users).not(my_mutual_friends).get() ;

            // todo: msg_users must also be a subset of users from previous gifts_sha256 message now in done folder

            if (invalid_user_ids.length + unknown_sha256_user_ids.length > 0) {
                // unknown or invalid user in users_sha256 message:
                error = (invalid_user_ids.length + unknown_sha256_user_ids.length) + ' rejected users(s) in gifts_sync message' ;
                if (msg_users_sha256) error += '. Received sha256 user signatures: ' + msg_users_sha256.join(', ') ;
                if (unknown_sha256_user_ids.length > 0) error += '. Unknown sha256 user signatures: ' + unknown_sha256_user_ids.join(', ') ;
                error += '. Received internal user ids: ' + msg_users.join(', ') ;
                if (invalid_user_ids.length > 0) {
                    error += '. Expected user ids: ' + my_mutual_friends.join(', ');
                    error += '. Unknown mutual friends: ' + invalid_user_ids.join(', ');
                }
                console.log(pgm + error) ;
                if (msg_users.length == 0) {
                    mailbox.outbox.push({
                        mid: Gofreerev.get_new_uid(),
                        request_mid: msg.mid,
                        msgtype: 'error',
                        error: error
                    }) ;
                    return ;
                }
                // continue without invalid user ids
                msg_users = $(msg_users).not(invalid_user_ids).get() ;
            }

            // add sub messages (send_gifts, request_gifts and check_gifts) to inbox
            // keep reference to previous gifts_sha256 message - now in mailbox.done array
            if (msg.send_gifts) {
                msg.send_gifts.request_mid = msg.request_mid ;
                msg.send_gifts.pass = 0 ; // 0: new send_gifts message, 1: waiting for gifts verification, 2: verified - waiting to be processed, 3: done:
                mailbox.inbox.push(msg.send_gifts);
            }
            if (msg.request_gifts) {
                msg.request_gifts.request_mid = msg.request_mid ;
                mailbox.inbox.push(msg.request_gifts) ;
            }
            if (msg.check_gifts) {
                msg.check_gifts.request_mid = msg.request_mid ;
                mailbox.inbox.push(msg.check_gifts) ;
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


        // communication step 4 - sub message from receive_message_sync_gifts
        // password => users_sha256 => gifts_sha256 => sync_gifts
        // has already been json validated in receive_message_sync_gifts
        // receive missing gifts from other device
        // receive_message_send_gifts is called more than once when receiving gifts from other device
        // pass 0: do some initial gift verification without checking
        // between pass 0 and pass 1 - check unknown server sha256 signatures in ping new_servers request/response
        // pass 1: insert new gifts in verify_gifts array for server sha256 signature check in next ping
        // between first and second pass - ping - find unknown servers and verify sha256 signature for new gifts
        // property verify_seq is set in verify_gifts_request and verified_at_server (true/false) is set in verify_gifts_response
        // note that response for remote gifts / remote verification can take some time
        // second pass (msg.pass=2) - finish gift verification including server sha256 signature check - can request additional gift and comment verifications
        // third pass (msg.pass=3) - do actions (insert, update, merge)

        var receive_message_send_gifts = function (device, mailbox, msg) {
            var pgm = service + '.receive_message_send_gifts: ';
            console.log(pgm + 'mailbox  = ' + JSON.stringify(mailbox));
            console.log(pgm + 'msg      = ' + JSON.stringify(msg));
            console.log(pgm + 'msg.pass = ' + msg.pass); // 0: new send_gifts message, 1: waiting for gifts verification, 2: verified - reasy for pass 2, 3: done

            if (msg.pass == 0) {

                // pass 0 - check for some fatal errors before processing send_gifts message
                // 1) gid and cid must be unique
                // 2) users in msg.users array must be unique and be correct (all user ids in msg.users array except mutual friends)
                // 3) sha256 signatures for servers must be in msg.servers array
                var error = validate_send_gifts_message(mailbox, msg, false) ; // false: receiving message
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
                var errors = [], new_gift, i, j, new_comment, comment_error ;
                for (i = 0; i < msg.gifts.length; i++) {
                    new_gift = msg.gifts[i] ;

                    if (mailbox.hasOwnProperty('server_id')) {
                        // gifts from an other Gofreerev server.
                        // user ids have been validated in validate_send_gifts_message and are either
                        // 1) sha256 signatures for remote users or
                        // 2) negative user ids for "unknown" users
                        // translate all received sha256 signatures to internal user ids
                        error = userService.sha256_to_user_ids(new_gift.giver_user_ids, msg) ;
                        if (error) {
                            errors.push('gid=' + new_gift.gid + ', error=giver_user_ids: ' + error ) ;
                            continue ; // next gift
                        }
                        error = userService.sha256_to_user_ids(new_gift.receiver_user_ids, msg) ;
                        if (error) {
                            errors.push('gid=' + new_gift.gid + ', error=receiver_user_ids' + error ) ;
                            continue ; // next gift
                        }
                        comment_error = false ;
                        if (new_gift.comments) {
                            for (j=0 ; j<new_gift.comments.length ; j++) {
                                new_comment = new_gift.comments[j] ;
                                error = userService.sha256_to_user_ids(new_comment.user_ids, msg) ;
                                if (error) {
                                    errors.push('gid=' + new_gift.gid + ', cid=' + new_comment.cid + ', error=' + error ) ;
                                    comment_error = true ;
                                    break ;
                                }
                            } // for j
                        } // if
                        if (comment_error) continue ; // next gift
                        // sha256 signatures were translated without errors
                    } // if server_id

                    // note msg.users as second argument 2 to invalid_gift call
                    // allows gift validation to use msg.users as fallback information in case of unknown users in givers, receivers or comments
                    error = invalid_gift(new_gift, msg.users) ;
                    if (error) errors.push('gid=' + new_gift.gid + ', error=' + error ) ;
                } // for i (gifts)
                if (errors.length > 0) {
                    error = 'Found ' + errors.length + ' gifts with errors in sync_gifts/send_gifts sub message: ' + errors.join(', ');
                    console.log(pgm + error + ' msg = ' + JSON.stringify(msg));
                    mailbox.outbox.push({
                        mid: Gofreerev.get_new_uid(),
                        msgtype: 'error',
                        request_mid: msg.mid,
                        error: error
                    });
                    return;
                }

                // calc sha256 values for new gifts received from other client
                var sha256_calc_errors = 0 ;
                for (i = 0; i < msg.gifts.length; i++) {
                    new_gift = msg.gifts[i] ;
                    sha256_values = calc_sha256_for_gift(new_gift) ;
                    new_gift.sha256 = sha256_values[0] ;
                    new_gift.sha256_gift = sha256_values[1] ;
                    new_gift.sha256_comments = sha256_values[2] ;
                    if (!new_gift.sha256) sha256_calc_errors += 1 ;
                }
                if (sha256_calc_errors > 0) {
                    error = 'Found ' + sha256_calc_errors + ' gifts where sha256 calculation failed.';
                    console.log(pgm + error + ' msg = ' + JSON.stringify(msg));
                    mailbox.outbox.push({
                        mid: Gofreerev.get_new_uid(),
                        msgtype: 'error',
                        request_mid: msg.mid,
                        error: error
                    });
                    return;
                } // if sha256 calc errors

                if (mailbox.hasOwnProperty('server_id')) {
                    // gifts from an other Gofreerev server.
                    // check for any unknown server sha256 signatures
                    // unknown server sha256 signatures must be validated between pass 0 and pass 1
                    var no_unknown_servers = 0, sha256 ;
                    for (i = 0; i < msg.servers.length; i++) {
                        sha256 = msg.servers[i].sha256 ;
                        if (sha256_to_server_id(sha256)) continue ; // known server
                        no_unknown_servers += 1 ;
                        if (!unknown_servers.hasOwnProperty(sha256)) unknown_servers[sha256] = null ;
                        console.log(pgm + 'unknown_servers[' + sha256 + '] = ' + unknown_servers[sha256]) ;
                    } // for i
                    if (no_unknown_servers > 0) {
                        // unknown server. Push back to read folder at check after next ping
                        console.log(pgm + no_unknown_servers + ' unknown servers. wait for new_servers request/response in ping') ;
                        mailbox.read.push(msg);
                        console.log(pgm + 'mailbox.read.length = ' + mailbox.read.length) ;
                        return ;
                    }
                    // no (more) unknown servers. translate server sha256 signatures
                    var other_server_id_to_sha256 = {} ; // from internal server id on other gofreerev server to sha256 signature
                    var server ;
                    for (i=0 ; i<msg.servers.length ; i++) {
                        server = msg.servers[i] ;
                        other_server_id_to_sha256[server.server_id] = server.sha256 ;
                    }
                    console.log(pgm + 'other_server_id_to_sha256 = ' + JSON.stringify(other_server_id_to_sha256)) ;
                    for (i=0 ; i<msg.gifts.length ; i++) {
                        new_gift = msg.gifts[i] ;
                        sha256 = other_server_id_to_sha256[new_gift.created_at_server] ;
                        new_gift.created_at_server = sha256_to_server_id(sha256) ;
                        if (!new_gift.comments) continue ;
                        for (j=0 ; j<new_gift.comments.length ; j++) {
                            new_comment = new_gift.comments[j] ;
                            sha256 = other_server_id_to_sha256[new_comment.created_at_server] ;
                            new_comment.created_at_server = sha256_to_server_id(sha256) ;
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

            var gifts_already_on_ignore_list = [] ; // array with gids - ignore
            var identical_gift_and_comments = []; // array with gids - ignore
            var verify_new_gifts = 0; // number of new gifts that must be server validated
            var verifying_new_gifts = 0; // number of new gifts already in queue for server validation (offline client, remote gifts or errors)
            var new_gifts_invalid_sha = []; // array with gids
            var verify_old_gifts = 0; // number of old gifts that must be server validated (gift changed and new gift is valid)
            var verifying_old_gifts = 0; // number of old gifts already in queue for server validation (offline client, remote gifts or errors)
            var old_gifts_invalid_sha = []; // array with gids
            var verify_new_comments = 0; // number of new comments that must be server validated
            var verifying_new_comments = 0; // number of new comments already in queue for server validation (offline client, remote gifts or errors)
            var new_comments_invalid_sha = []; // array with cids
            var index_system_errors = []; // gid array with gift index system errors - fatal javascript error
            var validation_system_errors = []; // gid array with sha validation system errors - fatal javascript error
            var counterpart_errors = [] ; // gid array with gifts with invalid counter part update (other user) - only allowed when acception a new deal
            var gifts_without_mutual_friends ; // array with gids - new gifts without mutual friends - ignore and report as warning in log
            var gifts_created = [] ; // array with gids - new created gifts

            var gid, index, old_gift, sha256_values, is_mutual_gift, user_id, cid, old_cids;
            var new_gift_creators, old_gift_creators, new_gift_counterpart, old_gift_counterpart;
            var old_gift_accepted, new_gift_accepted, gift_accept_action, gift_delete_action, gift_price_action, gift_like_action;
            var comments_pass, seconds ;


            // gifts loop
            for (i = 0; i < msg.gifts.length; i++) {
                new_gift = msg.gifts[i];
                gid = new_gift.gid;
                if (is_gift_on_ignore_list(device, gid)) {
                    gifts_already_on_ignore_list.push(pid);
                    continue;
                }
                if (gid_to_gifts_index.hasOwnProperty(gid)) {
                    // existing gift
                    index = gid_to_gifts_index[gid];
                    if (!index || (index < 0) || (index >= gifts.length)) {
                        // system error - error in javascript logic
                        index_system_errors.push(gid);
                        continue;
                    }
                    old_gift = gifts[index];
                    if (!old_gift || (old_gift.gid != gid)) {
                        // system error - error in javascript
                        index_system_errors.push(gid);
                        continue;
                    }
                    // compare old (this client) and new gift (from other client)
                    if (old_gift.sha256 == new_gift.sha256) {
                        identical_gift_and_comments.push(gid);
                        continue;
                    }
                    if (old_gift.sha256_gift != new_gift.sha256_gift) {
                        // old gift != new gift when ignoring comments
                        // many gift fields are readonly but update is allowed for a few fields

                        // changed gift - check if readonly fields used in server side sha256 signature have been changed
                        if (new_gift.direction == 'giver') {
                            new_gift_creators = new_gift.giver_user_ids.sort.join(',');
                            new_gift_counterpart = (new_gift.receiver_user_ids || []).sort.join(',');
                        }
                        else {
                            new_gift_creators = new_gift.receiver_user_ids.sort.join(',');
                            new_gift_counterpart = (new_gift.giver_user_ids || []).sort.join(',');
                        }
                        if (old_gift.direction == 'giver') {
                            old_gift_creators = old_gift.giver_user_ids.sort.join(',');
                            old_gift_counterpart = (old_gift.receiver_user_ids || []).sort.join(',');
                        }
                        else {
                            old_gift_creators = old_gift.receiver_user_ids.sort.join(',');
                            old_gift_counterpart = (old_gift.giver_user_ids || []).sort.join(',');
                        }
                        if (!identical_values(old_gift.created_at_client, new_gift.created_at_client) || !identical_values(old_gift.direction, new_gift.direction) || !identical_values(old_gift_creators, new_gift_creators) || !identical_values(old_gift.description, new_gift.description) || !identical_values(old_gift.open_graph_url, new_gift.open_graph_url) || !identical_values(old_gift.open_graph_title, new_gift.open_graph_title) || !identical_values(old_gift.open_graph_description, new_gift.open_graph_description) || !identical_values(old_gift.open_graph_image, new_gift.open_graph_image)) {
                            // changed readonly fields!
                            // fields used in server side sha256 signature are NOT identical for new and old gift
                            // could be a communication error or gift could have been modified by this or by other client
                            if (!new_gift.hasOwnProperty('verify_seq')) {
                                // new gift must be server validated before continuing (between pass 1 and pass 2)
                                verify_new_gifts += 1;
                                verify_gifts_add(new_gift);
                                continue;
                            }
                            if (!new_gift.hasOwnProperty('verified_at_server')) {
                                // new gift already in queue for server verification (offline, server not responding or remote gift)
                                verifying_new_gifts += 1;
                                continue;
                            }
                            if (!new_gift.verified_at_server) {
                                // invalid signature for new gift - changed on other client or not correct in message
                                new_gifts_invalid_sha.push(gid);
                                continue;
                            }
                            // new gift is valid. old gift must be invalid  - changed on this client or not saved correct
                            if (!old_gift.hasOwnProperty('verify_seq')) {
                                // old gift must be server validated before continuing (between pass 1 and pass 2)
                                verify_old_gifts += 1;
                                delete old_gift.verified_at_server;
                                verify_gifts_add(old_gift);
                                continue;
                            }
                            if (!old_gift.hasOwnProperty('verified_at_server')) {
                                // old gift already in queue for server verification (offline, server not responding or remote gift)
                                verifying_old_gifts += 1;
                                continue;
                            }
                            if (!old_gift.verified_at_server) {
                                // invalid signature for gift - old gift must be deleted and new gift accepted
                                old_gifts_invalid_sha.push(gid);
                                continue;
                            }
                            // there is a BIG problem. valid server side sha256 signature for old and new gift - must be a javascript error
                            validation_system_errors.push(gid);
                            continue;
                        } // if changed readonly fields!

                        // pass 2 - gift has been server validated - few changed fields in gift

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
                        gift_like_action = (old_gift.like != new_gift.like);
                        if (!gift_accept_action && (old_gift_counterpart != new_gift_counterpart)) {
                            // counterpart can only be changed when accepting proposal
                            counterpart_errors.push(gid);
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

                    if (old_gift.sha256_comments == new_gift.sha256_comments) {
                        // comments identical - minor changes in gift - merge gift in pass 3
                        merge_gifts.push(gid);
                        continue;
                    }

                    // comments are not identical


                    old_cids = [];
                    if (old_gift.comments) for (j = 0; j < old_gift.comments.length; j++) old_cids.push(old_gift.comments[j].cid);
                    if (new_gift.comments) for (j = 0; j < new_gift.comments.length; j++) {
                        new_comment = new_gift.comments[j];
                        // todo: add device.ignore_invalid_comments list? a gift could be correct except a single invalid comment!
                        if (old_cids.indexOf(new_comment.cid) == -1) {
                            // new comment
                            verify_new_comments += 1; // xxx
                            verify_new_comments.push({gid: gid, comment: new_comment});

                        }
                        else {
                            // existing comment
                        }
                    }
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
                    verify_gifts_add(new_gift);
                    continue; // wait for verify gifts
                }
                if (!new_gift.hasOwnProperty('verified_at_server')) {
                    // new gift already in queue for server verification (offline, server not responding or remote gift)
                    // todo: how long time to wait for:
                    //   a: offline client - no internet connection
                    //   b: server not responding (error or timeout)
                    //   c: remote gift verification (error or remote server not responding)
                    seconds = Gofreerev.unix_timestamp() - new_gift.in_verify_gifts ;
                    console.log(pgm + 'Waited ' + seconds + ' seconds for gift ' + gid + ' verification') ;
                    verifying_new_gifts += 1;
                    continue; // wait for verify gifts
                }
                if (!new_gift.verified_at_server) {
                    // invalid signature for new gift - changed on other client or incorrect in message
                    new_gifts_invalid_sha.push(gid);
                    continue;
                }
                // new gift ok - gift ready for pass 2
                comments_pass = 2 ;
                if (new_gift.comments) {
                    // server validate new comments
                    for (j = 0; j < new_gift.comments.length; j++) {
                        new_comment = new_gift.comments[j];
                        cid = new_comment.cid;
                        // todo: add device.ignore_invalid_comments list? a gift could be correct except a single invalid comment!
                        if (!new_comment.hasOwnProperty('verify_seq')) {
                            // pass 1 - new comment must be server validated before continuing (between pass 1 and pass 2)
                            verify_new_comments += 1;
                            // todo: use a temporary array - move to verify_comments at end of gifts loop if no fatal errors were found in pass 1
                            verify_comments.push({gid: gid, comment: new_comment});
                            comments_pass = 1 ;
                            continue;
                        }
                        if (!new_comment.hasOwnProperty('verified_at_server')) {
                            // between pass 1 and 2 - new comment already in queue for server verification (offline, server not responding or remote gift)
                            verifying_new_comments += 1;
                            comments_pass = 1 ;
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
                } // if
                if (comments_pass == 1) continue ; // wait for verify comments

                // pass 2 - gift and comments have been server validated. no extra validations for new gifts

                if (new_gift.pass == 3) {
                    // gift already created in a previous pass of this send_gifts message
                    gifts_created.push(gid) ;
                    continue ;
                }

                // pass 3 - create gift and valid comments
                console.log(pgm + 'pass 3 - create gift and valid comments. gift = ' + JSON.stringify(new_gift));
                // create gift with created_at_server property (not a new gift)
                var gift = {
                    gid: new_gift.gid,
                    direction: new_gift.direction,
                    giver_user_ids: new_gift.giver_user_ids,
                    receiver_user_ids: new_gift.receiver_user_ids,
                    created_at_client: new_gift.created_at_client,
                    created_at_server: new_gift.created_at_server,
                    price: new_gift.price,
                    currency: new_gift.currency,
                    direction: new_gift.direction,
                    description: new_gift.description,
                    open_graph_url: new_gift.open_graph_url,
                    open_graph_title: new_gift.open_graph_title,
                    open_graph_description: new_gift.open_graph_description,
                    open_graph_image: new_gift.open_graph_image,
                    show: true,
                    new_comment: {comment: ""}
                };
                // extra control. gifts have already been validated in validate_send_gifts_message
                if (errors = invalid_gift(gift, [])) {
                    console.log(pgm + 'Could not create new gift: ' + errors);
                    console.log(pgm + 'gift = ' + JSON.stringify(gift));
                    create_gift_errors.push(new_gift.gid);
                    continue;
                }
                // add new gift to 1) JS array and 2) localStorage
                save_new_gift(gift);
                new_gift.pass = 3 ;
                gifts_created.push(gid) ;

                console.log(pgm + 'pass 3 - todo: create valid comments. gift = ' + JSON.stringify(new_gift));

            } // for i (gifts loop)

            // end gifts loop - pass 1, 2 or 3

            // check result of pass 1, 2 and 3 / continue with next pass if ok

            // check for system errors - write message in log, send error message and abort
            if (index_system_errors.length > 0) {
                // system error - error in javascript logic - abort processing of send_gifts message
                error = 'System error. Invalid gifts index. Gifts: ' + index_system_errors.join(', ');
                console.log(pgm + error + ' msg = ' + JSON.stringify(msg));
                mailbox.outbox.push({
                    mid: Gofreerev.get_new_uid(),
                    msgtype: 'error',
                    request_mid: msg.mid,
                    error: error
                });
                return;
            }
            if (validation_system_errors.length > 0) {
                // system error - error in javascript logic - abort processing of send_gifts message
                // valid server side sha256 signature for old and new gift - must be a javascript error
                error = 'System error. Readonly fields was updated for gift and both old and new gift has a valid sha256 signature. Gifts: ' + validation_system_errors.join(', ');
                console.log(pgm + error + ' msg = ' + JSON.stringify(msg));
                mailbox.outbox.push({
                    mid: Gofreerev.get_new_uid(),
                    msgtype: 'error',
                    request_mid: msg.mid,
                    error: error
                });
                return;
            }

            if (verify_new_gifts + verifying_new_gifts + verify_old_gifts + verifying_old_gifts + verify_new_comments + verifying_new_comments > 0) {
                // between pass 1 and pass 2. waiting for server verification of gifts and comments. check after next ping
                // todo: max number of seconds/minutes to wait for remote gift and comment verification?
                console.log(pgm + 'Waiting for ' + (verify_new_gifts + verifying_new_gifts + verify_old_gifts + verifying_old_gifts) + ' gifts and ' + (verify_new_comments + verifying_new_comments) + ' comments to be server validated.');
                mailbox.read.push(msg);
                console.log(pgm + 'mailbox.read.length = ' + mailbox.read.length);

                // debug
                console.log(pgm + 'verify_gifts = ' + JSON.stringify(verify_gifts));
                console.log(pgm + 'verify_comments = ' + JSON.stringify(verify_comments));
                return;
            }

            // error report in log and send error message. pass should be 3
            console.log(pgm + 'pass = ' + msg.pass + ', error report missing') ;

            if (gifts_already_on_ignore_list.length > 0) console.log(pgm + 'Warning. Received gifts ' + gifts_already_on_ignore_list.join(', ') + ' already in ignore list (invalid on other client)') ;
            if (identical_gift_and_comments.length > 0) console.log(pgm + 'Ok. Received gifts ' + identical_gift_and_comments.join(', ') + ' already up-to-date') ;
            if (new_gifts_invalid_sha.length > 0) console.log(pgm + 'Error. Received gifts ' + new_gifts_invalid_sha.join(', ') + ' with invalid sha256 signature (invalid on other client)') ;
            if (old_gifts_invalid_sha.length > 0) console.log(pgm + 'Error. Replacing gifts ' + old_gifts_invalid_sha.join(', ') + ' invalid on this client with gifts valid in message from other client') ;
            if (counterpart_errors.length > 0) console.log(pgm + 'System error. Received gifts ' + counterpart_errors.join(', ') + ' with invalid counterpart update') ;
            if (gifts_created.length > 0) console.log(pgm + 'Ok. Created gifts ' + gifts_created.join(', ')) ;

        }; // receive_message_send_gifts


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
            move_previous_message(pgm, mailbox, msg.request_mid, request_msgtype, false) ; // xxx
        }; // receive_message_error


        // communication step 4 - sub message from receive_message_sync_gifts
        // missing gifts request from other device
        var receive_message_request_gifts = function (device, mailbox, msg) {
            var pgm = service + '.receive_message_request_gifts: ' ;
            // console.log(pgm + 'device   = ' + JSON.stringify(device)) ;
            console.log(pgm + 'mailbox  = ' + JSON.stringify(mailbox)) ;
            console.log(pgm + 'msg      = ' + JSON.stringify(msg)) ;
            console.log(pgm + 'Error. Not implemented') ;
        }; // receive_message_request_gifts


        // communication step 4 - sub message from receive_message_sync_gifts
        // check gift sha256 sub values and return gift, comments or both to other device
        var receive_message_check_gifts = function (device, mailbox, msg) {
            var pgm = service + '.receive_message_check_gifts: ' ;
            // console.log(pgm + 'device   = ' + JSON.stringify(device)) ;
            console.log(pgm + 'mailbox  = ' + JSON.stringify(mailbox)) ;
            console.log(pgm + 'msg      = ' + JSON.stringify(msg)) ;
            console.log(pgm + 'Error. Not implemented') ;
        }; // receive_message_check_gifts

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
                    console.log(pgm + 'Error. Ignoring message from device '  + msg_server_envelope.sender_did + 'with unknown index ' + index + '. message = ' + JSON.stringify(msg_server_envelope)) ;
                    continue ;
                }
                did = mailbox.did ;
                device = devices[did] ;
                // console.log(pgm + 'did = ' + did  + ', device = ' + JSON.stringify(device)) ;
                if (!device || !device.pubkey) {
                    console.log(pgm + 'Error. Ignoring message from device '  + did + 'with key ' + key + '. Public key has not yet been received. Message = ' + JSON.stringify(msg_server_envelope)) ;
                    continue ;
                }
                if (msg_server_envelope.encryption == 'rsa') {
                    // public/private key decryption (rsa) - password setup for symmetric encryption
                    console.log(pgm + 'message_with_envelope = ' + JSON.stringify(msg_server_envelope)) ;
                    if (!encrypt) {
                        encrypt = new JSEncrypt() ;
                        prvkey = Gofreerev.getItem('prvkey') ;
                        encrypt.setPrivateKey(prvkey);
                    }
                    // rsa => json
                    msg_csv_rsa_enc = msg_server_envelope.message ;
                    msg_csv = encrypt.decrypt(msg_csv_rsa_enc) ;
                    msg = msg_csv.split(',') ;
                    // console.log(pgm + 'rsa decrypt: prvkey = ' + prvkey) ;
                    // console.log(pgm + 'rsa decrypt: msg_json_rsa_enc = ' + msg_json_rsa_enc) ;
                    // console.log(pgm + 'rsa decrypt: msg_json = ' + msg_json) ;
                    // console.log(pgm + 'msg = ' + JSON.stringify(msg)) ;
                    receive_message_password(device, msg) ;
                    console.log(pgm + 'device.password = ' + device.password) ;
                }
                else {
                    // symmetric key decryption - all other messages
                    if (!device.password) {
                        // could be symmetric password setup in progress. keep message and check after next ping. wait for max 2 minutes.
                        if (!msg_server_envelope.hasOwnProperty('received_at')) msg_server_envelope.received_at = Gofreerev.unix_timestamp() ;
                        if (Gofreerev.unix_timestamp() - msg_server_envelope.received_at < 120) {
                            unencrypted_messages.push(msg_server_envelope) ;
                            console.log(pgm + 'Warning. Ignoring message from device '  + did + '. Password for symmetric communication was not found. Message = ' + JSON.stringify(msg_server_envelope)) ;
                        }
                        else {
                            console.log(pgm + 'Error. Ignoring message from device '  + did + '. Password for symmetric communication was not found. Message = ' + JSON.stringify(msg_server_envelope)) ;
                        }
                        continue ;
                    }
                    msg_json_sym_enc = msg_server_envelope.message ;
                    try {
                        msg_csv = Gofreerev.decrypt(msg_json_sym_enc, device.password)
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
                    }
                } // if else (rsa or sym encryption)
            } // for i (one message from each device)
        }; // receive_messages

        // process decrypted messages in mailbox (inbox + read folders)
        var process_messages = function () {
            var pgm = service + '.process_messages: ';
            // loop for all mailbox and process any messages in 1) inbox and 2) read
            // any new "read" messages generated when processing inbox messages will be processed after next ping
            var i, mailbox, old_read_length, msg, did, key, device;
            for (i = 0; i < mailboxes.length; i++) {
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
                            // communication step 4 - sub message from sync_gifts - check gift sub sha256 values and return gift, comments or both
                            receive_message_check_gifts(device, mailbox, msg);
                            break;
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
            gifts: gifts,
            invalid_comment: invalid_comment,
            invalid_comment_change: invalid_comment_change,
            invalid_gift: invalid_gift,
            invalid_gift_change: invalid_gift_change,
            load_gifts: load_gifts,
            refresh_gift: refresh_gift,
            refresh_gift_and_comment: refresh_gift_and_comment,
            save_new_gift: save_new_gift,
            save_gift: save_gift,
            sync_gifts: sync_gifts,
            remove_old_link_errors: remove_old_link_errors,
            new_gifts_request: new_gifts_request,
            new_gifts_response: new_gifts_response,
            new_servers_request: new_servers_request,
            new_servers_response: new_servers_response,
            verify_gifts_request: verify_gifts_request,
            verify_gifts_response: verify_gifts_response,
            delete_gifts_request: delete_gifts_request,
            delete_gifts_response: delete_gifts_response,
            new_comments_request: new_comments_request,
            new_comments_response: new_comments_response,
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
    }])
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
    }])
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
            if ((typeof provider == 'undefined') || (provider == null) || (provider == 'gofreerev')) giftService.load_gifts() ;
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
                giftService.load_gifts() ;
                // send old oauth to server for recheck and copy to session
                // todo: userService should return a promise, and this promise should be used to inject any error messages into auth page
                // console.log(pgm + 'calling send_oauth') ;
                set_login_or_register_error('') ;
                userService.send_oauth().then(function (response) {
                    console.log(pgm + 'send_oauth ok') ;
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
    }])
    .controller('GiftsCtrl', ['$location', '$http', '$document', '$window', '$sce', '$timeout',  'UserService', 'GiftService', 'TextService',
                     function ($location, $http, $document, $window, $sce, $timeout, userService, giftService, textService) {
        var controller = 'GiftsCtrl' ;
        console.log(controller + ' loaded') ;
        var self = this;

        self.texts = textService.texts ;
        self.userService = userService ;
        self.giftService = giftService ;

        var appname = Gofreerev.rails['APP_NAME'];

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
            if (comment.accepted) return false ; // delete accepted proposal is not allow - delete gift is allowed
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
            }
            // console.log(pgm + 'cid = ' + comment.cid + ', deleted_at_client = ' + comment.deleted_at_client) ;
        };

        self.show_cancel_new_deal_link = function (gift,comment) {
            // from rails Comment.show_cancel_new_deal_link?
            if (comment.new_deal != true) return false ;
            if (comment.accepted) return false ;
            var login_user_ids = userService.get_login_userids() ;
            if ($(login_user_ids).filter(comment.user_ids).length == 0) return false ;
            if (gift.direction == 'both') return false ;
            return true ;
        };
        self.cancel_new_deal = function (gift,comment) {
            giftService.refresh_gift_and_comment(gift, comment) ;
            if (!comment.cid) return ; // comment has been deleted
            if (!self.show_cancel_new_deal_link(gift,comment)) return ; // cancel link no longer active
            if (!confirm(self.texts.comments.confirm_cancel_new_deal)) return ;
            comment.new_deal = false ;
            giftService.save_gift(gift) ;
        };

        // user "other" user ids to be used when closing a deal (adding giver or receiver user ids to gift)
        // helper method used in show_accept_new_deal_link and accept_new_deal
        // filter gift creator with login users and compare with creator of new deal proposal
        function get_deal_close_by_user_ids (gift, comment) {
            var pgm = controller + '.get_deal_closed_by_user_ids: ' ;
            if (comment.new_deal != true) return [] ;
            if (typeof comment.accepted != 'undefined') return [] ; // already accepted or rejected
            if (gift.accepted_at_client || gift.accepted_cid) return [] ; // accepted
            // merge login users and creators of gift - minimum one login is required
            var login_user_ids = userService.get_login_userids() ;
            var gift_user_ids = (gift.direction == 'giver') ? gift.giver_user_ids : gift.receiver_user_ids ;
            var user_ids = $(login_user_ids).filter(gift_user_ids) ;
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
            comment.accepted = true ;
            comment.accepted_by_user_ids = user_ids ;
            comment.accepted_at_client = gift.accepted_at_client ;
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
            comment.accepted = false ;
            comment.rejected_by_user_ids = user_ids ;
            comment.rejected_at_client = Gofreerev.unix_timestamp() ;
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

        // new gift default values
        function init_new_gift () {
            self.new_gift = {
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
        }
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
            self.new_gift.errors = null ;
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
            if (errors=giftService.invalid_gift(gift, [])) {
                self.new_gift.errors = 'Could not create new gift: ' + errors ;
                console.log(pgm + 'Could not create gift: ' + self.new_gift.errors) ;
                console.log(pgm + 'gift = ' + JSON.stringify(gift)) ;
                return ;
            }
            // add new gift to 1) JS array and 2) localStorage
            giftService.save_new_gift(gift) ;
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
            // todo: validate new comment - return any errors to UI
            // console.log(pgm + 'cid = ' + new_comment.cid) ;
            // resize comment textarea after current digest cycle is finish
            resize_textarea(new_comment.comment) ;
            // console.log(pgm + 'created_at_client = ' + new_comment.created_at_client) ;
            gift.new_comment.comment = null ;
            gift.new_comment.price = null ;
            gift.new_comment.new_deal = false ;
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
        }; // create_new_comment

        // end GiftsCtrl
    }])
    .filter('formatDateShort', [function () {
        // format date using "date.formats.short"
        // used in formatGiftLinkText filter
        var date_formats_short = I18n.t('date.formats.short') ;
        if (!date_formats_short) date_formats_short = '%b %d' ;
        return function (ts) {
            if (!ts) return ts ;
            return I18n.strftime((new Date(ts*1000)), date_formats_short)  ;
        } ;
        // end formatDateShort filter
    }])
    .filter('formatPrice', [function () {
        // format number using "number.format", optional arg1 = precision (default 3 decimals)
        // used in formatGiftPriceOptional and formatGiftLinkText filters
        var delimiter = I18n.t('number.format.delimiter') ;
        var default_precision = I18n.t('number.format.precision') ;
        var separator = I18n.t('number.format.separator') ;
        var strip_insignificant_zeros= I18n.t('number.format.strip_insignificant_zeros') ;
        return function (p, precision) {
            if (typeof p == 'undefined') return p ;
            if (p == null) return p ;
            if (typeof precision == 'undefined') precision = default_precision ;
            if (precision == null) precision = default_precision ;
            return I18n.toNumber(p,
                {delimiter: delimiter, precision: precision,
                    separator: separator, strip_insignificant_zeros: strip_insignificant_zeros}) ;
        };
        // end formatPrice filter
    }])
    .filter('formatGiftPriceOptional', ['formatPriceFilter', function (formatPrice) {
        // format optional price using "js.gifts.optional_price" format - used in gift link
        // from application_helper.format_gift_param
        // used in formatGiftLinkText filter
        return function (gift, precision) {
            var p = gift.price ;
            if (typeof p == 'undefined') return '' ;
            if (p == null) return '' ;
            return I18n.t('js.gifts.optional_price', {price: formatPrice(p, precision), currency: gift.currency }) ;
        };
        // end formatGiftPriceOptional
    }])
    .filter('formatCommentPriceOptional', ['formatPriceFilter', function (formatPrice) {
        // format optional price using "js.comments.optional_price" format - used in comments
        // from application_helper.format_comment_param
        // used in formatComment filter
        return function (comment, precision) {
            var p = comment.price ;
            if (typeof p == 'undefined') return '' ;
            if (p == null) return '' ;
            return I18n.t('js.comments.optional_price', {price: formatPrice(p, precision) }) ;
        }
    }])
    .filter('formatDirection', ['UserService', function(userService) {
        // format direction - direction with short giver/receiver user name
        // from application_controller.format_direction_with_user
        // used in formatGiftLinkText filter
        return function (gift) {
            // console.log('formatDirection. gift = ' + JSON.stringify(gift)) ;
            var giver = userService.find_giver(gift) ;
            var receiver = userService.find_receiver(gift) ;
            var x = I18n.t('js.gifts.direction_' + gift.direction,
                {givername: giver ? giver.short_user_name : 'no name',
                receivername: receiver ? receiver.short_user_name : 'no name'}) ;
            return x ;
        };
        // end formatCommentPriceOptional
    }])
    .filter('formatGiftLinkText', ['formatDateShortFilter', 'formatGiftPriceOptionalFilter', 'formatDirectionFilter', 'GiftService',
        function (formatDateShort, formatGiftPriceOptional, formatDirection, giftService) {
            // format gift link text using translation js.gifts.gift_link_text: %{date} %{optional_price} / %{direction}
            // html: {{gift.date | formatDateShort}} {{gift | formatGiftPriceOptional:2}} / {{gift | formatDirection}}
            // nested format using 3 sub format filters
            // old rails code was t('.gift_link_text', format_gift_param(api_gift))
            return function (gift, precision) {
                var created_at_client = formatDateShort(gift.created_at_client);
                var optional_price = formatGiftPriceOptional(gift, precision);
                var direction = formatDirection(gift) ;
                return I18n.t('js.gifts.gift_link_text', {date: created_at_client, optional_price: optional_price, direction: direction }) ;
            };
            // end formatGiftLinkText
    }])
    .filter('formatGiftDescription', ['$window', '$sce', function ($window, $sce) {
        return function (description) {
            // workaround for long description + show more text for old browsers (opera 12)
            // opera 12. insert soft hyphen in description
            var pgm = 'GiftsCtrl.formatGiftDescription: ' ;
            if ($window.navigator.userAgent.indexOf('Opera/9.80') == -1) return $sce.trustAsHtml(description) ;
            var shy_description = description.split('').join('&shy;') + '&shy;' ;
            return $sce.trustAsHtml(shy_description) ;
        };
        // end formatGiftDescription
    }])
    .filter('formatBalance', [function () {
        return function (balance) {
            if (typeof balance == 'undefined') return '' ;
            if (balance == null) return '' ;
            // todo 1: format user balance. hash with currencies and amounts
            // todo 2: server side or client side balance calculation?
            return JSON.stringify(balance) ;
        };
        // end formatBalance
    }])
    .filter('formatUserImgTitle', ['formatBalanceFilter', 'UserService', function (formatBalance, userService) {
        return function (user_ids) {
            var pgm = 'GiftsCtrl.formatUserImgTitle: ' ;
            // format mouseover title in user <div><img> tags in gifts/index page etc
            // console.log(pgm + 'user_ids = ' + JSON.stringify(user_ids)) ;
            // console.log(pgm + 'typeof user_ids = ' + (typeof user_ids)) ;
            if ((typeof user_ids == 'undefined') || (user_ids == null) || (user_ids.length == 0)) return null ;
            var user = userService.get_closest_friend(user_ids);
            if (!user) {
                // user(s) not found in users array
                // unknown user in gifts and comments can not be 100% avoided as users are free to select api provider logins
                // users from not logged in api login providers are always unknown
                // could by a previous friend in a closed deal
                // could be a comment from a previous friend
                // could be a comment from a friend from a not logged in provider
                return I18n.t('js.user_div.title_unknown_user', {appname: Gofreerev.rails['APP_NAME']});
            }
            // translation keys js.user_div.title_friends_click etc
            var keys = {
                1: 'friend_click',
                2: 'friend_click',
                3: 'non_friend_click',
                4: 'non_friend_click'
            };
            var key = 'js.user_div.title_' + (keys[user.friend] || 'non_friend');
            // translate
            var username = (user.friend <= 2) ? user.short_user_name : user.user_name;
            var apiname = user.provider;
            var balance = formatBalance(user.balance);
            return I18n.t(key, {username: username, apiname: apiname, balance: balance});
        };
        // end formatUserImgTitle
    }])
    .filter('formatUserImgSrc', ['UserService', function (userService) {
        return function (user_ids) {
            // format scr in user <div><img> tags in gifts/index page etc (giver, receiver and user that has commented gifts)
            var pgm = 'formatUserImgSrc: ' ;
            // console.log(pgm + 'user_ids = ' + JSON.stringify(user_ids)) ;
            if ((typeof user_ids == 'undefined') || (user_ids == null) || (user_ids.length == 0)) return '/images/invisible-picture.gif' ;
            var user = userService.get_closest_friend(user_ids);
            if (!user) {
                // user(s) not found in users array
                // could by a previous friend in a closed deal
                // could be a comment from a previous friend
                // could be a comment from a friend from a not logged in provider
                // console.log(pgm + 'closest user was not found') ;
                return '/images/unknown-user.png';
            }
            // console.log(pgm + 'user with user id ' + user.user_id + ' was found. user.api_profile_picture_url = ' + user.api_profile_picture_url) ;
            return user.api_profile_picture_url;
        };
        // end formatUserImgSrc filter
    }])
    .filter('formatComment', ['formatDateShortFilter', 'formatCommentPriceOptionalFilter', function (formatDateShort, formatCommentPriceOptional) {
        return function (comment, precision) {
            var pgm = 'GiftsCtrl.formatComment: ';
            var date = formatDateShort(comment.created_at_client);
            var optional_price = formatCommentPriceOptional(comment, precision);
            // console.log(pgm + 'date = ' + date) ;
            // console.log(pgm + 'optional_price = ' + optional_price) ;
            // console.log(pgm + 'comment = ' + comment.comment) ;
            return I18n.t('js.comments.comment_text', {
                date: date,
                optional_price: optional_price,
                text: comment.comment
            });
        };
        // end formatComment filter
    }])
    .filter('formatNewProposalTitle', ['UserService', function (userService) {
        return function (gift) {
            var pgm = 'formatNewProposalTitle: gid = ' + gift.gid + '. ' ;
            // see also GiftsCtrl.show_new_deal_checkbox
            if (gift.accepted_at_client || gift.accepted_cid) return '' ; // closed deal
            var login_user_ids = userService.get_login_userids() ;
            // new deal check box is only shown if login user is not creator of gift
            var creator_user_ids ;
            if (gift.direction == 'giver') creator_user_ids = gift.giver_user_ids ;
            else creator_user_ids = gift.receiver_user_ids ;
            var creator = userService.get_closest_friend(creator_user_ids) ;
            // console.log(pgm + 'other_user_id = ' + JSON.stringify(other_user_id)) ;
            // console.log(pgm + 'other_user = ' + JSON.stringify(other_user)) ;
            if (!creator) {
                console.log(pgm + 'system error. creator with user id ' + creator_user_ids.join(', ') + ' was not found') ;
                return '' ;
            }
            var title = I18n.t('js.new_comment.proposal_title', {username: creator.short_user_name}) ;
            // console.log(pgm + 'title = ' + JSON.stringify(title)) ;
            return title ;
        };
        // end formatNewProposalTitle filter
    }])
    .filter('formatInviteFriendsLink', ['$window', '$sce', function ($window, $sce) {
        var pgm = 'GiftsCtrl.formatInviteFriendsLink: ';
        return function (login_user) {
            var appname = Gofreerev.rails['APP_NAME'];
            var apiname = Gofreerev.rails['API_DOWNCASE_NAME'][login_user.provider];
            var link_title = I18n.t('js.gifts.invite_friends_link_title', {appname: appname, apiname: apiname});
            // console.log(pgm + 'appname = ' + appname + ', apiname = ' + apiname + ', link_title = ' + link_title);
            var href;
            if (login_user.provider == 'facebook') {
                // facebook invite friends dialog form
                href = "https://" + Gofreerev.rails['KOALA_CONFIG_DIALOG_HOST'] + "/dialog/apprequests" +
                "?app_id=" + encodeURIComponent(Gofreerev.rails['API_ID'].facebook) +
                "&redirect_uri=" + encodeURIComponent($window.location.href) +
                    // "&title=" + encodeURIComponent(I18n.t('js.gifts.invite_friends_message_title', {appname: Gofreerev.rails['APP_NAME']})) +
                "&message=" + encodeURIComponent(I18n.t('js.gifts.invite_friends_message_body')) +
                "&filters=" + encodeURIComponent("['app_non_users']");
                // console.log(pgm + 'url = ' + href);
            }
            else {
                // mailto link
                var email = I18n.t('js.gifts.invite_friends_mailto_email');
                var subject = I18n.t('js.gifts.invite_friends_mailto_subject', {appname: appname, apiname: apiname});
                var url = $window.location.protocol + '//' + $window.location.host + '/' + I18n.locale + '/gifts' ;
                var body = I18n.t('js.gifts.invite_friends_mailto_body', {
                    appname: appname,
                    apiname: apiname,
                    from_username: login_user.user_name,
                    url: url
                });
                href = "mailto:' + encodeURIComponent(email) +" +
                "?subject=" + encodeURIComponent(subject) +
                "&amp;body=" + encodeURIComponent(body);
            }
            var a = '<a href="' + href + '" title="' + link_title + '">' + apiname + '<a>';
            return $sce.trustAsHtml(a);
        };
        // end formatInviteFriendsLink filter
    }])
    .filter('formatProviderName', [function() {
        var appname = Gofreerev.rails['APP_NAME'] ;
        var providers = Gofreerev.rails['API_CAMELIZE_NAME'] ;
        return function (provider) {
            return (providers[provider] || appname) ;
        };
        // end formatProviderName filter
    }])
    .filter('formatProviderSrc', [function () {
        return function (provider) {
            return '/images/' + (provider || 'gofreerev') + '.png';
        };
        // end formatProviderSrc filter
    }])
    .filter('formatProviderTraficLightSrc', ['UserService', function (userService) {
        return function (trafic_light_status) {
            return '/images/' + trafic_light_status + '.png';
        };
        // end formatProviderTraficLightSrc filter
    }])
    .filter('formatLoginSrc', [function () {
        return function (logged_in) {
            if (logged_in) return '/images/invisible-picture.gif' ;
            else return '/images/connect.png' ;
        };
        // end formatLoginSrc filter
    }])
    .filter('formatLogoutSrc', [function () {
        return function (logged_out) {
            if (logged_out) return '/images/invisible-picture.gif' ;
            else return '/images/disconnect.png' ;
        };
        // end formatLogoutSrc filter
    }])
    .filter('formatProviderLogoutSrc', ['UserService', function (userService) {
        return function (provider) {
            if (userService.is_logged_in_with_provider(provider.provider)) return '/images/disconnect.png';
            else return '/images/invisible-picture.gif';
        };
        // end formatProviderLogoutSrc filter
    }])
    .filter('formatProviderLoginHref', ['UserService', function (userService) {
        return function (provider) {
            return '/auth/' + provider.provider ;
        };
        // end formatProviderLoginHref filter
    }])
    .filter('formatProviderHomeUrl', [function () {
        return function (provider) {
            return Gofreerev.rails['API_URL'][provider.provider] ;
        };
        // end formatProviderHomeUrl filter
    }]) ;
