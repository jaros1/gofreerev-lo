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
            rows[i].id = id
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
    } // window.onbeforeunload


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
    })

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
    // - some values are compressed (users and gifts arrays)
    // - rules (local_storage_rules) are derived from key name
    // - default values are <userid> prefix, no encryption and no compression (write warning in console.log)

    var storage_rules = {
        currency: {session: false, userid: true, compress: false, encrypt: false}, // currency code (ISO 4217)
        did: {session: false, userid: true, compress: false, encrypt: false}, // new unique device id
        gifts: {session: false, userid: true, compress: true, encrypt: true}, // array with user and friends gifts
        password: {session: true, userid: false, compress: false, encrypt: false}, // session password in clear text
        passwords: {session: false, userid: false, compress: false, encrypt: false}, // array with hashed passwords. size = number of accounts
        oauth: {session: false, userid: true, compress: true, encrypt: true}, // login provider oauth authorization
        prvkey: {session: false, userid: true, compress: true, encrypt: true}, // for encrypted user to user communication
        pubkey: {session: false, userid: true, compress: true, encrypt: false}, // for encrypted user to user communication
        secret: {session: false, userid: true, compress: true, encrypt: false}, // client secret - used in device.sha256 signature
        sid: {session: true, userid: false, compress: false, encrypt: false}, // unique session id
        userid: {session: true, userid: false, compress: false, encrypt: false}, // session userid (1, 2, etc) in clear text
        users: {session: false, userid: true, compress: true, encrypt: true} // array with logged in users and friends
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
        for (var storage_flag in storage_flags) {
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
            var storage_options = {compress: 2, encrypt: 1, sequence: 1}
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
                var storage_options = {compress: 2, encrypt: (password ? 1 : 0), sequence: 0}
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
        return key_options ;
    } // get_local_storage_rule

    // get/set item
    function getItem (key) {
        var pgm = 'Gofreerev.getItem: ' ;
        // if (key == 'password') console.log(pgm + 'caller: ' + arguments.callee.caller.toString()) ;
        var rename_uid = (key == 'did') ; // possible rename uid to did (unique device id)
        var rule = get_local_storage_rule(key) ;
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
        if ((typeof value == 'undefined') || (value == null) || (value == '')) {
            if (rename_uid) {
                // <userid>_did was not found - check if <userid>_uid exists
                var key2 = userid + '_uid' ;
                value = localStorage.getItem(key2) ;
                if ((typeof value == 'undefined') || (value == null) || (value == '')) return null ;
                else {
                    // rename uid to did and continue
                    localStorage.removeItem(key2) ;
                    localStorage.setItem(key, value) ;
                }
            }
            else return null ; // key not found
        }

        // todo: remove old data migration. truncate did from 21 to 20 characters
        if (rename_uid && (value.length > 21)) {
            value = value.substr(0,21) ;
            localStorage.setItem(key, value) ;
        }

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
            var password = getItem('password') ;
            if ((typeof password == 'undefined') || (password == null) || (password == '')) {
                console.log(pgm + 'Error. key ' + key + ' is stored encrypted but password was not found') ;
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
        var rename_uid = (key == 'did') ; // possible rename uid to did (unique device id)
        var save_value = value ; // for optional lzma_compress0
        var rule = get_local_storage_rule(key) ;
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
            password = getItem('password') ;
            if ((typeof password == 'undefined') || (password == null) || (password == '')) {
                console.log(pgm + 'Error. key ' + key + ' is stored encrypted but password was not found') ;
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
                                sequence: sequence }
        var bin_key = storage_options_bin_key(storage_options) ;
        var storage_flag = storage_flag_index[bin_key] ;
        if (!storage_flag) {
            console.log(pgm + 'Error. key ' + key + ' was not saved. Could not found storage flag for storage options = ' + JSON.stringify(storage_options)) ;
            return ;
        }
        value = storage_flag + value ;
        // check for uid => did rename
        if (rename_uid) {
            var key2 = userid + '_uid' ;
            if (localStorage.getItem(key2)) localStorage.removeItem(key2) ;
        }
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
        var rule = get_local_storage_rule(key) ;
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
    // arguments: list of fields
    function sha256 () {
        var text = '' ;
        for (var i=0; i < arguments.length; i++) {
            if (i>0) text += ',' ;
            switch(typeof arguments[i]) {
                case 'string' :
                    text += arguments[i] ;
                    break ;
                case 'boolean':
                    text += arguments[i] ;
                    break ;
                case 'number':
                    text += arguments[i].toString();
                    break ;
                case 'undefined':
                    break ;
                default:
                    if (arguments[i] == null) break;
                    text += JSON.stringify(arguments[i]) ;
            } // switch
        };
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
            // save login
            setItem('userid', userid) ;
            setItem('password', password) ;
            if (!getItem('sid')) setItem(Gofreerev.get_new_uid()) ;
            // setup new account
            did = Gofreerev.get_new_uid() ; // unique device id
            // hash password
            passwords_a.push(password_sha256) ;
            passwords_s = JSON.stringify(passwords_a) ;
            // generate key pair for user to user encryption
            crypt = new JSEncrypt({default_key_size: 2048});
            crypt.getKey();
            pubkey = crypt.getPublicKey();
            prvkey = crypt.getPrivateKey();
            // ready to store new account information.
            // save new user account
            setItem('did', did) ; // unique device id
            setItem('prvkey', prvkey) ;
            setItem('pubkey', pubkey) ; // public key
            setItem('passwords', passwords_s) ; // array with hashed passwords. size = number of accounts
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


    // angularJS - used function is used in modal login dialog form, but info in stored in angular UserService
    // temporary get/set function until all login functionality are moved to angularJS
    var is_fb_logged_in_account = false
    var fb_logged_in_account = function () {
        return is_fb_logged_in_account ;
    }
    function set_fb_logged_in_account (boolean) {
        is_fb_logged_in_account = boolean ;
    }

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
        if (tv4.validate(json_request, Gofreerev.rails['JSON_SCHEMA'][json_schema])) return null;
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

    // check if json response is invalid. used in do_tasks, login, logout and ping
    // returns null (ok) or an error message
    function is_json_response_invalid (pgm, json_response, action, msg) {
        if (!msg) msg = '' ;
        // check if schema definition exists
        var json_schema = action + '_response';
        var error ;
        if (!Gofreerev.rails['JSON_SCHEMA'].hasOwnProperty(json_schema)) {
            error = 'JSON schema definition ' + json_schema + ' was not found. ' + action + ' response could not be validated. ' + msg ;
            console.log(pgm + error);
            return error;
        }
        // validate do_tasks response received from server
        if (tv4.validate(json_response, Gofreerev.rails['JSON_SCHEMA'][json_schema])) return null ; // json is valid
        // report error
        var json_error = JSON.parse(JSON.stringify(tv4.error));
        delete json_error.stack;
        var json_errors = JSON.stringify(json_error) ;
        error = 'Error in JSON ' + action + ' response from server. ' + msg ;
        console.log(pgm + error);
        console.log(pgm + 'response: ' + JSON.stringify(json_response));
        console.log(pgm + 'schema: ' + JSON.stringify(Gofreerev.rails['JSON_SCHEMA'][json_schema]));
        console.log(pgm + 'errors : ' + json_errors);
        // return error
        return error + '. ' + json_errors ;
    } // is_json_response_invalid

    // generate password - used in client to client communication (symmetric encryption)
    function generate_random_password (length) {
        var character_set = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ 0123456789![]{}#%&/()=?+-:;_-.,@$|£' ;
        var password = [], index, char ;
        for (var i=0 ; i<length ; i++) {
            index = Math.floor(Math.random()*character_set.length) ;
            char = character_set.substr(index,1) ;
            password.push(char) ;
        } ;
        return password.join('') ;
    } // generate_random_password

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
        // angular helpers
        set_fb_logged_in_account: set_fb_logged_in_account,
        get_new_uid: get_new_uid,
        sha256: sha256,
        client_login: client_login,
        client_sym_encrypt: encrypt,
        client_sym_decrypt: decrypt,
        unix_timestamp: unix_timestamp,
        is_json_request_invalid: is_json_request_invalid,
        is_json_response_invalid: is_json_response_invalid,
        generate_random_password: generate_random_password
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
        $routeProvider
            .when('/gifts/:userid?', {
                templateUrl: 'main/gifts',
                controller: 'GiftsCtrl as ctrl',
                resolve: {
                    check_userid: ['$route', '$location', function ($route, $location) {
                        var userid = get_local_userid();
                        if (userid != $route.current.params.userid) {
                            $location.path('/gifts/' + userid);
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
        }
        self.init_language_constants();

        return {
            language: self.language,
            texts: self.texts,
            init_language_constants: self.init_language_constants
        }
        // end TextService
    }])
    .factory('UserService', ['$window', '$http', '$q', '$locale', function($window, $http, $q, $locale) {
        var self = this ;
        console.log('UserService loaded') ;

        // initialize list with providers. used in validations and in main/auth page
        var providers = [] ;
        (function () {
            var api_names = Gofreerev.rails['API_CAMELIZE_NAME'] ;
            for (var key in api_names) {
                if (api_names.hasOwnProperty(key)) {
                    providers.push(key) ;
                }
            }
            console.log('UserService: providers = ' + JSON.stringify(providers)) ;
        })();

        // users - read from local storage - used in angularJS filter functions
        var users = [] ;
        var users_index_by_user_id = {} ;

        var provider_stat = function (users) {
            if (typeof users == 'undefined') return '' ;
            if (users == null) return '' ;
            if (users.length == 0) return '' ;
            var hash = {} ;
            var i, user, provider ;
            for (i=0 ; i<users.length ; i++) {
                user = users[i] ;
                provider = user.provider
                if (!hash.hasOwnProperty(provider)) hash[provider] = { users: 0, friends: 0} ;
                hash[provider].users += 1 ;
                if (user.friend <= 2) hash[provider].friends += 1 ;
            }
            var stat = '' ;
            for (provider in hash) {
                if (stat != '') stat = stat += ', ' ;
                stat += provider + ' ' + hash[provider].friends + ' (' + hash[provider].users + ')' ;
            }
            return stat ;
        } // provider_stat

        var init_users = function (array) {
            // console.log('UserService.init_users: users = ' + JSON.stringify(array)) ;
            users = array ;
            users_index_by_user_id = {}
            for (var i=0 ; i<users.length ; i++) users_index_by_user_id[users[i].user_id] = i ;

            // todo: temporary inject fb logged in status into Gofreerev - used in model login dialog form
            // remove when all login functionality are moved to UserService and NavCtrl
            Gofreerev.set_fb_logged_in_account(fb_logged_in_account()) ;
        }
        // update users array: replace: true: overwrite/replace old users, false: add/keep old users
        // called from do_tasks after api and device login
        var update_users = function (new_users, replace) {
            // users array returned from util.generic_post_login
            var pgm = 'UserService.update_users: ' ;
            // console.log(pgm + 'new_users = ' + JSON.stringify(new_users)) ;
            var new_providers = [] ;
            for (var i=0 ; i<new_users.length ; i++) if (new_providers.indexOf(new_users[i].provider) == -1) new_providers.push(new_users[i].provider) ;
            // console.log(pgm + 'new providers = ' + JSON.stringify(new_providers)) ;
            // update users array with minimal changes
            // insert or update
            var refresh_index = false ;
            var new_user, j ;
            for (i=0 ; i<new_users.length ; i++) {
                new_user = new_users[i] ;
                j = users_index_by_user_id[new_user.user_id] ;
                if (j) {
                    // existing user - update changed fields
                    if (users[j].user_name != new_user.user_name) users[j].user_name = new_user.user_name ;
                    if (users[j].balance != new_user.balance) users[j].balance = new_user.balance ;
                    if (users[j].api_profile_picture_url != new_user.api_profile_picture_url) users[j].api_profile_picture_url = new_user.api_profile_picture_url
                    if (users[j].friend != new_user.friend) users[j].friend = new_user.friend ;
                    if (users[j].currency != new_user.currency) users[j].currency = new_user.currency ;
                }
                else {
                    // insert new user
                    users_index_by_user_id[new_user.user_id] = users.length ;
                    users.push(new_user) ;
                    refresh_index = true ;
                }

            }
            if (replace) {
                // delete old users
                var no_deleted = 0 ;
                var new_users_index_by_user_id = {} ;
                for (var i=0 ; i<new_users.length ; i++) new_users_index_by_user_id[new_users[i].user_id] = i ;
                var old_user ;
                for (i=users.length-1 ; i >= 0 ; i--) {
                    old_user = users[i] ;
                    if (!new_users_index_by_user_id.hasOwnProperty(old_user.user_id)) {
                        users.splice(i, 1);
                        no_deleted += 1 ;
                        refresh_index = true ;
                    }
                }
            }
            // refresh index
            if (refresh_index) {
                users_index_by_user_id = {}
                for (var i=0 ; i<users.length ; i++) users_index_by_user_id[users[i].user_id] = i ;
            }
            Gofreerev.setItem('users', JSON.stringify(users)) ;
        } // update_users

        var is_logged_in = function () {
            if (typeof users == 'undefined') return false ;
            for (var i=0 ; i< users.length ; i++ ) if (users[i].friend == 1) return true ;
            return false ;
        }
        var client_userid = function() {
            var userid = Gofreerev.getItem('userid') ;
            if (typeof userid == 'undefined') return 0 ;
            if (userid == null) return 0 ;
            if (userid == '') return 0 ;
            userid = parseInt(userid) ;
            return userid ;
        }
        var client_secret = function() {
            if (client_userid() == 0) return null ;
            var secret = Gofreerev.getItem('secret') ;
            if (!secret) {
                secret = (Math.random() + 1).toString(10).substring(2,12) ;
                Gofreerev.setItem('secret', secret) ;
            }
            return secret ;
        }
        var is_logged_in_with_device = function () {
            var user_id = client_userid() ;
            // console.log('is_logged_in_with_device: user_id = ' + user_id) ;
            return (user_id > 0) ;
        }
        // get encrypted oauth hash from local storage - returns null if errors
        var get_oauth = function () {
            var pgm = 'UserService.get_oauth: ' ;
            // get old oauth
            var oauth_str = Gofreerev.getItem('oauth') ;
            var oauth ;
            if ((typeof oauth_str == 'undefined') || (oauth_str == null) || (oauth_str == '')) oauth = {} ;
            else oauth = JSON.parse(oauth_str) ;
            // console.log('UserService.get_oauth: oauth = ' + JSON.stringify(oauth)) ;
            return oauth ;
        } // get_oauth
        var is_logged_in_with_provider = function (provider) {
            if (typeof provider == 'undefined') return is_logged_in_with_device() ;
            if (provider == null) return is_logged_in_with_device() ;
            if (provider == 'gofreerev') return is_logged_in_with_device() ;
            var oauth = get_oauth() ;
            // console.log('UserService.is_logged_in_with_provider: oauth = ' + JSON.stringify(oauth)) ;
            // console.log('UserService.is_logged_in_with_provider: provider = ' + provider) ;
            var is_logged_in = oauth.hasOwnProperty(provider) ;
            // console.log('UserService.is_logged_in_with_provider: ' + provider + ' = ' + is_logged_in) ;
            return is_logged_in ;
        }
        var no_friends = function () {
            if (!is_logged_in()) return false ;
            for (var i=0 ; i< users.length ; i++ ) if (users[i].friend == 2) return false ;
            return true ;
        }
        var get_user = function (user_id) {
            if (typeof users == 'undefined') return null ;
            if (typeof user_id == 'undefined') return null ;
            var i = users_index_by_user_id[user_id] ;
            if (typeof i == 'undefined') return null ;
            var user = users[i] ;
            if (!user.short_user_name) {
                var user_name_a = user.user_name.split(' ') ;
                if (user_name_a.length > 1) user.short_user_name = user_name_a[0] +  ' ' + user_name_a[1].substr(0,1) ;
                else user.short_user_name = user.user_name ;
            }
            // if (user_id == 1016) console.log('UserService.get_user: user = ' + JSON.stringify(user)) ;
            return user ;
        }
        var get_closest_user = function (user_ids) {
            var pgm = 'UserService.get_closest_user: ' ;
            // console.log(pgm + 'user_ids = ' + JSON.stringify(user_ids)) ;
            if (typeof users == 'undefined') return null ;
            if (users == null) return null ;
            if (users.length == 0) return null ;
            if (typeof user_ids == 'undefined') return null ;
            if (user_ids == null) return null ;
            if (user_ids.length == 0) return null ;
            var closest_user = null ;
            var closest_user_friend_status = 9 ;
            var user ;
            for (var i=0 ; i<user_ids.length ; i++) {
                user = get_user(user_ids[i]) ;
                // if (user) console.log(pgm + 'get_user(' + user_ids[i] + ').friend = ' + user.friend) ;
                // else console.log(pgm + 'user with id ' + user_ids[i] + ' was not found') ;
                if (user && (user.friend < closest_user_friend_status)) {
                    closest_user = user ;
                    closest_user_friend_status = user.friend ;
                }
            }
            // if (closest_user) console.log(pgm + 'found user with user id ' + closest_user.user_id) ;
            // else console.log(pgm + 'closest user was not found') ;
            return closest_user ;
        } // get_closest_user
        var get_userids_friend_status = function (user_ids) {
            var user = get_closest_user(user_ids) ;
            if (!user) return null ;
            return user.friend ;
        } // get_userids_friend_status
        var get_login_users = function () {
            var pgm = 'UserService. get_login_users: ' ;
            var login_users = [] ;
            if (typeof users == 'undefined') return login_users ;
            for (var i=0 ; i<users.length ; i++) {
                if (users[i].friend == 1) login_users.push(users[i]) ;
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
        }
        var get_login_userids = function () {
            var pgm = 'UserService.get_login_userids: ' ;
            if (typeof users == 'undefined') return [] ;
            var userids = [] ;
            // console.log(pgm + 'users.length = ' + users.length) ;
            for (var i=0 ; i<users.length ; i++) {
                // console.log(pgm + 'users[i] = ' + JSON.stringify(users[i])) ;
                // console.log(pgm + 'users[' + i + '].friend = ' + users[i].friend) ;
                if (users[i].friend == 1) userids.push(users[i].user_id) ;
            }
            // console.log(pgm + 'userids.length = ' + userids.length) ;
            return userids ;
        }
        // get default currency from locale. use for new user accounts. for example en-us => usd
        var get_default_currency = function () {
            var pgm = 'UserService.get_default_currency: ' ;
            var default_language = 'en' ;
            var default_currency = 'usd' ;
            var id = $locale.id ;
            var language = id ? id.substr(0,2) : default_language ;
            var currency = Gofreerev.rails['COUNTRY_TO_CURRENCY'][language] || default_currency ;
            if (Gofreerev.rails['ACTIVE_CURRENCIES'].indexOf(currency) == -1) currency = default_currency ;
            // console.log(pgm + '$locale.id = ' + id + ', language = ' + language + ', currency = ' + currency) ;
            return currency ;
        }
        var get_currency = function  () {
            var currency = Gofreerev.getItem('currency') ;
            if (currency) return currency ;
            var currency = get_default_currency() ;
            Gofreerev.setItem('currency', currency) ;
            return currency ;
        }
        var find_giver = function (gift) {
            var giver, user, i ;
            for (i=0 ; i<gift.giver_user_ids.length ; i++) {
                user = get_user(gift.giver_user_ids[i]) ;
                if (user) {
                    if (user.friend == 1) return user ; // giver is a login user
                    if (!giver) giver = user ;
                }
            }
            // giver is not a login in user
            return giver ;
        }
        var find_receiver = function (gift) {
            var receiver, user, i ;
            for (i=0 ; i<gift.receiver_user_ids.length ; i++) {
                user = get_user(gift.receiver_user_ids[i]) ;
                if (user) {
                    if (user.friend == 1) return user ; // receiver is a login user
                    if (!receiver) receiver = user ;
                }
            }
            // receiver is not a login in user
            return receiver ;
        }

        // is one if the logged in users a fb account?
        // used in shared account model form in auth/index page
        // returns: true: use fb notifications, false: use email
        // todo: auth/index page is not yet included in angularJS (users array is empty)
        var fb_logged_in_account = function () {
            return is_logged_in_with_provider('facebook') ;
        }

        // local log out (provider=null) or log in provider log out (provider facebook,  google+, linkedin etc)
        var logout = function (provider) {
            var pgm = 'UserService.logout: ' ;
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
            else {
                // log in provider log out
                // remove users
                // console.log(pgm + 'debug 3') ;
                var old_length = users.length ;
                var old_stat = provider_stat(users) ;
                // console.log(pgm + 'removing ' + provider + ' users. old users.length = ' + users.length) ;
                for (var i=users.length-1 ; i >= 0 ; i--) {
                    if (users[i].provider == provider) {
                        // console.log(pgm + 'remove user ' + users[i].user_name + ' + with index ' + i) ;
                        users.splice(i, 1);
                    }
                }
                users_index_by_user_id = {} ;
                for (i=0 ; i<users.length ; i++) users_index_by_user_id[users[i].user_id] = i ;
                var new_length = users.length ;
                var new_stat = provider_stat(users) ;
                console.log(pgm + 'removed ' + (new_length-old_length) + ' ' + provider + ' users. new users.length = ' + new_length) ;
                console.log(pgm + 'old stat: ' + old_stat) ;
                console.log(pgm + 'new stat: ' + new_stat) ;
                Gofreerev.setItem('users', JSON.stringify(users)) ;
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
        } // logout

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
        // init_users(JSON.parse(Gofreerev.getItem('users')) || test_users) ;
        // console.log('UserService: getItem("users") = ' + Gofreerev.getItem('users')) ;
        if (Gofreerev.getItem('users')) init_users(JSON.parse(Gofreerev.getItem('users'))) ;
        else Gofreerev.setItem('users', JSON.stringify([])) ;

        var save_oauth = function (oauth) {
            var pgm = 'UserService.save_oauth: ' ;
            // console.log(pgm + 'debug 1') ;
            // encrypt and save updated oauth
            var oauth_str = JSON.stringify(oauth) ;
            console.log(pgm + 'UserService.save:oauth: oauth = ' + oauth_str) ;
            Gofreerev.setItem('oauth', oauth_str) ;
            // console.log(pgm + 'debug 3') ;
        }

        // cache some oauth information - used in ping
        self.expires_at = {} ; // unix timestamps for oauth access tokens
        self.refresh_tokens = {} ; // true/false - only used for google+ offline access
        var cache_oauth_info = function () {
            var oauth = get_oauth() ;
            for (var provider in oauth) {
                if (!oauth.hasOwnProperty(provider)) continue ;
                // todo: remove after debug
                if ((typeof provider == 'undefined') || (provider == null) || (provider == 'undefined')) {
                    console.log('UserService: error in oauth hash. oauth = ' + JSON.stringify(oauth)) ;
                    delete oauth[provider] ;
                    save_oauth(oauth) ;
                    continue ;
                }
                self.expires_at[provider] = oauth[provider].expires_at ;
                self.refresh_tokens[provider] = oauth[provider].hasOwnProperty('refresh_token') ;
            }
        } // init_expires_at
        cache_oauth_info() ;

        // save oauth received from server into oauth in local storage
        // oauth authorization are stored on server and in client (encrypted with passwords stored in client)
        var add_oauth = function (new_oauth) {
            var pgm = 'UserService.add_oauth: ' ;
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
        } // add_oauth

        var remove_oauth = function (provider) {
            var pgm = 'UserService.remove_oauth: ' ;
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
        } // remove_oauth

        // process expired tokens response - used in login and ping response processing
        var expired_tokens_response = function (expired_tokens) {
            var pgm = 'expired_tokens_response: ' ;
            if (!expired_tokens) return ;
            var provider, i ;
            for (i=0 ; i<expired_tokens.length ; i++) {
                provider = expired_tokens[i] ;
                console.log(pgm + 'log off for ' + provider + '. access token was expired') ;
                remove_oauth(provider) ;
            }
        } // expired_tokens_response

        // convert oauth hash/array - saved as hash but sent/received (json) as array
        var oauth_array_to_hash = function (oauth_array) {
            var oauth, oauth_hash = {} ;
            for (var i=0 ; i<oauth_array.length ; i++) {
                oauth = oauth_array[i] ;
                oauth_hash[oauth.provider] = oauth ;
                delete oauth_hash[oauth.provider].provider ;
            }
            return oauth_hash ;
        } // oauth_array_to_hash
        var oauth_hash_to_array = function (oauth_hash) {
            var oauth, oauth_array = [] ;
            for (var provider in oauth_hash) {
                if (!oauth_hash.hasOwnProperty(provider)) continue ;
                oauth = oauth_hash[provider] ;
                oauth.provider = provider ;
                oauth_array.push(oauth) ;
            }
            return oauth_array ;
        } // oauth_hash_to_array

        // process oauths array response - used in login and ping response processing
        var oauths_response = function (oauth_array) {
            var pgm = 'oauths_response: ' ;
            if (!oauth_array) return ;
            // convert from array to an hash before calling add_oauth
            console.log(pgm + 'oauth_array = ' + JSON.stringify(oauth_array)) ;
            var oauth_hash = oauth_array_to_hash(oauth_array) ;
            console.log(pgm + 'oauth_hash = ' + JSON.stringify(oauth_hash)) ;
            add_oauth(oauth_hash) ;

        } // oauths_response
        
        // after local login - send local oauth to server
        // server checks tokens and inserts tokens into server session (encrypted in session table and secret in session cookie)
        var send_oauth = function () {
            var pgm = 'UserService.send_oauth: ' ;
            // console.log(pgm + 'oauth = ' + JSON.stringify(new_oauth)) ;
            // get client_userid and password for current local login
            var userid = client_userid() ;
            if (userid == 0) {
                console.log(pgm + 'device userid was not found. oauth was not saved') ;
                return ;
            }
            //var password = client_password() ;
            //if (password == '') {
            //    console.log(pgm + 'device password was not found. oauth was not saved') ;
            //    return ;
            //}
            // get old oauth
            var oauth_str = Gofreerev.getItem('oauth') ;
            if ((typeof oauth_str == 'undefined') || (oauth_str == null) || (oauth_str == '')) {
                console.log(pgm + 'no oauth to send to server') ;
                return $q.reject('') ; // empty promise error response
            }
            // console.log(pgm + 'oauth_str = ' + oauth_str) ;
            var oauth = JSON.parse(oauth_str) ;
            // send oauth hash (authorization for one or more login providers) to server
            // oauth authorization is validated on server by fetching fresh friends info (api_client.gofreerev_get_friends)
            var login_request = {
                client_userid: userid,
                client_secret: client_secret(),
                client_timestamp: (new Date).getTime(),
                oauths: oauth_hash_to_array(oauth),
                did: Gofreerev.getItem('did'),
                pubkey: Gofreerev.getItem('pubkey')} ;
            // validate json login request before sending request to server
            var json_errors ;
            if (json_errors=Gofreerev.is_json_request_invalid(pgm, login_request, 'login')) return $q.reject(json_errors) ;
            return $http.post('/util/login.json', login_request)
                .then(function (response) {
                    // console.log(pgm + 'post login response = ' + JSON.stringify(response)) ;
                    if (response.data.error) console.log(pgm + 'post login error = ' + response.data.error) ;
                    // validate login response received from server
                    var json_errors ;
                    if (json_errors=Gofreerev.is_json_response_invalid(pgm, response.data, 'login', '')) return $q.reject(json_errors) ;
                    // check expired access token (server side check)
                    if (response.data.expired_tokens) expired_tokens_response(response.data.expired_tokens) ;
                    // check for new oauth authorization (google+ only)
                    if (response.data.oauths) oauths_response(response.data.oauths) ;
                    // check users array
                    if (response.data.users) {
                        // fresh user info array was received from server
                        console.log(pgm + 'ok response. users = ' + JSON.stringify(response.data.users)) ;
                        // insert relevant user info info js array
                        init_users(response.data.users) ;
                        // save in local storage
                        // todo: note that users array can by big and maybe have to be stripped for irrelevant users
                        Gofreerev.setItem('users', JSON.stringify(response.data.users)) ;
                    }
                    // promise - continue with success or error?
                    if (response.data.error || !response.data.users) return $q.reject(response.data.error) ;
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
        } // check_logged_in_providers

        return {
            providers: providers,
            is_logged_in: is_logged_in,
            is_logged_in_with_device: is_logged_in_with_device,
            is_logged_in_with_provider: is_logged_in_with_provider,
            no_friends: no_friends,
            get_login_users: get_login_users,
            get_login_userids: get_login_userids,
            get_user: get_user,
            get_currency: get_currency,
            get_closest_user: get_closest_user,
            get_userids_friend_status: get_userids_friend_status,
            find_giver: find_giver,
            find_receiver: find_receiver,
            logout: logout,
            client_userid: client_userid,
            client_secret: client_secret,
            update_users: update_users,
            oauth_array_to_hash: oauth_array_to_hash,
            add_oauth: add_oauth,
            remove_oauth: remove_oauth,
            send_oauth: send_oauth,
            cache_oauth_info: cache_oauth_info,
            check_logged_in_providers: check_logged_in_providers,
            expired_tokens_response: expired_tokens_response,
            oauths_response: oauths_response
        }
        // end UserService
    }])
    .factory('GiftService', ['UserService', function(userService) {
        var self = this ;
        var service = 'GiftService' ;
        console.log(service + ' loaded') ;


        // calculate sha256 value for comment. used when comparing gift lists between devices. replicate gifts with changed sha256 value between devices
        // readonly fields used in server side sha256 signature - update is NOT allowed - not included in sha256 calc for comment
        // - created_at_client - used in client path of server side sha256 signature - not included in comment sha256 calculation
        // - comment           - used in client path of server side sha256 signature - not included in comment sha256 calculation
        // - price             - used in client path of server side sha256 signature - not included in comment sha256 calculation
        // - currency          - used in client path of server side sha256 signature - not included in comment sha256 calculation
        // - user_ids          - used in server side sha256 signature - not included in comment sha256 calculation
        // - created_at_server - returned from new comments request and not included in comment sha256 calculation
        // - new_deal          - boolean: null or true. null: comment. true: new deal proposal - include in comment sha256 calculation
        // - deleted_at        - deleted at client timestamp - - include in comment sha256 calculation
        // - accepted          - accepted boolean - true if accepted by creator of gift - false if rejected by creator of gift - include in comment sha256 calculation
        // - updated_by        - user id list for users that have accepted or rejected proposal - must be a subset of creators of gift - include in comment sha256 calculation
        var calc_sha256_for_comment = function (comment) {
            var pgm = service + '.calc_sha256_for_comment: ' ;
            if ((typeof comment.created_at_server == 'undefined') || (comment.created_at_server == null)) return null ; // no server side sha256 signature
            var updated_by_internal_ids ;
            if ((typeof comment.updated_by == 'undefined') || (comment.updated_by == null)) updated_by_internal_ids = [] ;
            else updated_by_internal_ids = comment.updated_by ;
            var updated_by_external_ids = [];
            var user ;
            for (var i=0 ; i<updated_by_internal_ids.length ; i++) {
                user = userService.get_user(updated_by_internal_ids[i]) ;
                if (!user) {
                    console.log(pgm + 'Cannot calculate sha256 for comment ' + comment.cid + '. Unknown internal user id ' + updated_by_internal_ids[i]) ;
                    return null ;
                } ;
                updated_by_external_ids.push(user.uid + '/' + user.provider) ;
            }
            updated_by_external_ids = updated_by_external_ids.sort() ;
            updated_by_external_ids.unshift(updated_by_external_ids.length.toString()) ;
            var updated_by_str = updated_by_external_ids.join(',') ;
            return Gofreerev.sha256(comment.new_deal, comment.deleted_at, comment.accepted, updated_by_str) ;
        } // calc_sha256_for_comment

        // calculate sha256 value for gift. used when comparing gift lists between devices. replicate gifts with changed sha256 value between devices
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
        // - deleted_at - included in sha256 value
        // - comments - array with comments - included comments sha256_values in gift sha256 value
        var calc_sha256_for_gift = function (gift) {
            var pgm = service + '.sha256_gift: ' ;
            if ((typeof gift.created_at_server == 'undefined') || (gift.created_at_server == null)) return null ; // no server side sha256 signature
            // other participant in gift. null until closed/given/received
            var other_participant_internal_ids = gift.direction == 'giver' ? gift.receiver_user_ids : gift.giver_user_ids ;
            if ((typeof other_participant_internal_ids == 'undefined') || (other_participant_internal_ids == null)) other_participant_internal_ids == [] ;
            var other_participant_external_ids = [];
            var user ;
            for (var i=0 ; i<other_participant_internal_ids.length ; i++) {
                user = userService.get_user(other_participant_internal_ids[i]) ;
                if (!user) {
                    console.log(pgm + 'Cannot calculate sha256 for gift ' + gift.gid + '. Unknown internal user id ' + other_participant_internal_ids[i]) ;
                    return null ;
                } ;
                other_participant_external_ids.push(user.uid + '/' + user.provider) ;
            }
            other_participant_external_ids = other_participant_external_ids.sort() ;
            other_participant_external_ids.unshift(other_participant_external_ids.length.toString()) ;
            var other_participant_str = other_participant_external_ids.join(',') ;
            // price and currency
            // likes - todo: change like from boolean to an array of like and unlike with user id and timestamp
            var likes_str = '' ;
            // deleted_at
            // comments. string with sha256 value for each comment
            var comments, comment_sha256_temp ;
            if ((typeof gift.comments == 'undefined') || (gift.comments == null)) comments = [] ;
            else comments = gift.comments ;
            var comments_sha256 = [], s ;
            for (i=0 ; i<comments.length ; i++) {
                s = calc_sha256_for_comment(comments[i]) ;
                if (!s) return null ; // error in sha256 calc. error has been written to log
                comments_sha256.push(s) ;
            } ;
            comments_sha256.unshift(comments.length.toString()) ;
            var comments_str = comments_sha256.join(',') ;
            return Gofreerev.sha256(other_participant_str, gift.price, gift.currency, likes_str, gift.deleted_at, comments_str) ;
        } // sha256_gift

        var gifts = [];
        var gifts_index = {} ;
        var init_gifts_index = function () {
            gifts_index = {} ;
            for (var j=0 ; j<gifts.length ; j++) gifts_index[gifts[j].gid] = j ;
        }

        // save_gifts are called after any changes in a gift (like, follow, hide, delete etc)
        var save_gifts = function() {
            // remove some session specific attributes before save
            // also remove sha256 calculation - no reason to keep sha256 calculations in localStorage
            var gifts_clone = JSON.parse(JSON.stringify(gifts)) ;
            var gift, comments ;
            for (var i=0 ; i<gifts_clone.length ; i++) {
                gift = gifts_clone[i] ;
                if (gift.hasOwnProperty('show_no_comments')) delete gift.show_no_comments ;
                if (gift.hasOwnProperty('new_comment')) delete gift.new_comment ;
                if (gift.hasOwnProperty('sha256')) delete gift.sha256 ;
                if (!gift.hasOwnProperty('comments')) gift.comments = [] ;
                comments = gift.comments ;
                for (var j=0 ; j<comments.length ; j++) {
                    if (comments[j].hasOwnProperty('sha256')) delete comments[i].sha256 ;
                }
            }
            // save
            Gofreerev.setItem('gifts', JSON.stringify(gifts_clone)) ;
        } // save_gifts

        // load/reload gifts and comments from localStorage - used at startup and after login/logout
        var load_gifts = function () {
            var pgm = service + '.load_gifts: ' ;
            var new_gifts = [] ;
            if (Gofreerev.getItem('gifts')) new_gifts = JSON.parse(Gofreerev.getItem('gifts')) ;
            else Gofreerev.setItem('gifts', JSON.stringify([])) ;
            gifts.length = 0 ;
            gifts_index = {} ;
            var gift ;
            var migration = false ;
            var j, comment ;
            for (var i=0 ; i<new_gifts.length ; i++) {
                gift = new_gifts[i] ;
                // data migration - rename date to created_at_client - todo: remove data migration
                if (gift.hasOwnProperty('date')) {
                    gift.created_at_client = gift.date ;
                    delete gift.date ;
                    migration = true ;
                }
                // error cleanup - remove doublets from gifts array - todo: remove data migration
                if (gifts_index.hasOwnProperty(gift.gid)) {
                    console.log(pgm + 'Error. removed gift doublet with gid ' + gift.gid) ;
                    migration = true ;
                    continue ;
                }
                // data migration. server side sha256 signature is invalid after 4 open graph fields have been added to client side part of signature - todo: remove data migration
                if ((typeof gift.open_graph_url != 'undefined') && (gift.open_graph_url != null) && (gift.open_graph_url != '') && (gift.hasOwnProperty('created_at_server'))) {
                    // gift with open graph attributes.
                    var old_gid = gift.gid ;
                    gift.gid = Gofreerev.get_new_uid() ;
                    delete gift.created_at_server ;
                    console.log(pgm + 'migration after sha256 signature change. old gid = ' + old_gid + ', new gid = ' + gift.gid) ;
                    migration = true ;
                }
                // data migration. rename comment.created_at to created_at_client - todo: remove data migration
                if ((gift.hasOwnProperty('comments')) && (typeof gift.comments == 'object') && (gift.comments.length > 0)) {
                    for (j=0 ; j<gift.comments.length ; j++) {
                        comment = gift.comments[j] ;
                        if (comment.hasOwnProperty('created_at')) {
                            comment.created_at_client = comment.created_at ;
                            delete comment.created_at ;
                            migration = true ;
                        }
                    }
                }
                // calc sha256 signatures from gift and comments
                gift.sha256 = calc_sha256_for_gift(gift) ;
                if (!gift.sha256) console.log(pgm + ' could not calculate sha256 for gift ' + gift.gid) ;
                gifts_index[gift.gid] = gifts.length ;
                gifts.push(gift) ;
            }
            if (migration) save_gifts() ;
            console.log('GiftService.load_gifts: gifts.length = ' + gifts.length) ;
        }
        load_gifts() ;

        // add missing gid (unique gift id) - todo: remove
        for (i=0 ; i<gifts.length ; i++) if (!gifts[i].gid) {
            gifts[i].gid = Gofreerev.get_new_uid() ;
            init_gifts_index() ;
        }
        // add missing cid (unique comment id) - todo: remove
        for (i=0 ; i<gifts.length ; i++) {
            if (gifts[i].hasOwnProperty('comments')) {
                var comments = gifts[i].comments ;
                for (var j=0 ; j<comments.length ; j++) if (!comments[j].cid) comments[j].cid = Gofreerev.get_new_uid() ;
            }
        }

        var comments_debug_info = function (comments) {
            var text = 'length = ' + comments.length ;
            for (var i=0 ; i<comments.length ; i++) text += ', ' + comments[i].comment + ' (' + comments[i].cid + ')' ;
            return text ;
        } // comments_debug_info

        // todo: ok always to add new comments to end of comments array?
        // refresh gift comments from localStorage before update (changed in an other browser tab)
        var refresh_comments = function (comments, new_comments) {
            var pgm = service +  '.refresh_comments: ' ;
            // console.log(pgm + 'input: comments.length = ' + comments.length + ', new_comments.length = ' + new_comments.length) ;
            // console.log(pgm + 'old comments: ' + comments_debug_info(comments)) ;
            // console.log(pgm + 'new comments: ' + comments_debug_info(new_comments)) ;
            // insert and update comments
            var comments_index ;
            var init_comments_index = function () {
                comments_index = {} ;
                for (var j=0 ; j<comments.length ; j++) comments_index[comments[j].cid] = j ;
            }
            init_comments_index() ;
            var cid, comment_index ;
            for (var i=0 ; i<new_comments.length ; i++) {
                cid = new_comments[i].cid ;
                if (comments_index.hasOwnProperty(cid)) {
                    // update comment
                    comment_index = comments_index[cid] ;
                    if (comments[comment_index].user_ids != new_comments[i].user_ids) comments[comment_index].user_ids = new_comments[i].user_ids ;
                    if (comments[comment_index].price != new_comments[i].price) comments[comment_index].price = new_comments[i].price ;
                    if (comments[comment_index].currency != new_comments[i].currency) comments[comment_index].currency = new_comments[i].currency ;
                    if (comments[comment_index].comment != new_comments[i].comment) comments[comment_index].comment = new_comments[i].comment ;
                    if (comments[comment_index].created_at_client != new_comments[i].created_at_client) comments[comment_index].created_at_client = new_comments[i].created_at_client ;
                    if (comments[comment_index].new_deal != new_comments[i].new_deal) comments[comment_index].new_deal = new_comments[i].new_deal ;
                    if (comments[comment_index].deleted_at != new_comments[i].deleted_at) comments[comment_index].deleted_at = new_comments[i].deleted_at ;
                    if (comments[comment_index].accepted != new_comments[i].accepted) comments[comment_index].accepted = new_comments[i].accepted ;
                    if (comments[comment_index].updated_by != new_comments[i].updated_by) comments[comment_index].updated_by = new_comments[i].updated_by ;
                }
                else {
                    // insert comment.
                    // console.log(pgm + 'insert new comment ' + new_comments[i].comment) ;
                    comments.push(new_comments[i]) ;
                    init_comments_index() ;
                }
            } // for i
            // delete comments - todo: not implemented
            // console.log(pgm + 'output: comments.length = ' + comments.length + ', new_comments.length = ' + new_comments.length) ;
        } // refresh_comments

        // refresh gift from localStorage before update (changed in an other browser tab)
        // called before adding change to js object in this browser tab
        var refresh_gift = function (gift) {
            var pgm = service + '.refresh_gift: ' ;
            var new_gifts = JSON.parse(Gofreerev.getItem('gifts')) ;
            var new_gift ;
            for (var i=0 ; (!new_gift && (i<new_gifts.length)) ; i++) {
                if (gift.gid == new_gifts[i].gid) new_gift = new_gifts[i] ;
            }
            if (!new_gift) {
                console.log(pgm + 'error. refresh failed. gift with gid ' + gift.gid + ' was not found in localStorage') ;
                return ;
            }
            if (gift.giver_user_ids != new_gift.giver_user_ids) gift.giver_user_ids = new_gift.giver_user_ids ;
            if (gift.receiver_user_ids != new_gift.receiver_user_ids) gift.receiver_user_ids = new_gift.receiver_user_ids ;
            if (gift.created_at_client != new_gift.created_at_client) gift.created_at_client = new_gift.created_at_client ;
            if (gift.created_at_server != new_gift.created_at_server) gift.created_at_server = new_gift.created_at_server ;
            if (gift.price != new_gift.price) gift.price = new_gift.price ;
            if (gift.currency != new_gift.currency) gift.currency = new_gift.currency ;
            if (gift.direction != new_gift.direction) gift.direction = new_gift.direction ;
            if (gift.description != new_gift.description) gift.description = new_gift.description ;
            if (gift.open_graph_url != new_gift.open_graph_url) gift.open_graph_url = new_gift.open_graph_url ;
            if (gift.open_graph_title != new_gift.open_graph_title) gift.open_graph_title = new_gift.open_graph_title ;
            if (gift.open_graph_description != new_gift.open_graph_description) gift.open_graph_description = new_gift.open_graph_description ;
            if (gift.open_graph_image != new_gift.open_graph_image) gift.open_graph_image = new_gift.open_graph_image ;
            if (gift.like != new_gift.like) gift.like = new_gift.like ;
            if (gift.follow != new_gift.follow) gift.follow = new_gift.follow ;
            if (gift.show != new_gift.show) gift.show = new_gift.show ;
            if (gift.deleted_at != new_gift.deleted_at) gift.deleted_at = new_gift.deleted_at ;
            // todo: should merge comments and keep sequence - not overwrite arrays
            if (!gift.hasOwnProperty('comments')) gift.comments = [] ;
            if (!new_gift.hasOwnProperty('comments')) new_gift.comments = [] ;
            if (gift.comments != new_gift.comments) refresh_comments(gift.comments, new_gift.comments) ;
        } // refresh_gift

        // fresh gift and comment before update (changed in an other browser tab)
        var refresh_gift_and_comment = function (gift, comment) {
            var pgm = service + '.refresh_gift_and_comment: ' ;
            var cid = comment.cid ;
            var old_comments_length = (gift.comments || []).length ;
            refresh_gift(gift) ;
            var comments = gift.comments || [] ;
            var new_comments_length = comments.length ;
            var index = -1 ;
            for (var i=0 ; i<comments.length ; i++) if (cid == comments[i].cid) index = i ;
            if (index == -1) {
                // comment has been physically deleted - return empty comment {}
                for (var key in comment) if (comment.hasOwnProperty(key)) delete comment[key] ;
                return ;
            }
            // refresh comment
            if (comment.user_ids != comments[index].user_ids) comment.user_ids = comments[index].user_ids ;
            if (comment.price != comments[index].price) comment.price = comments[index].price ;
            if (comment.currency != comments[index].currency) comment.currency = comments[index].currency ;
            if (comment.comment != comments[index].comment) comment.comment = comments[index].comment ;
            if (comment.created_at_client != comments[index].created_at_client) comment.created_at_client = comments[index].created_at_client ;
            if (comment.new_deal != comments[index].new_deal) comment.new_deal = comments[index].new_deal ;
            if (comment.deleted_at != comments[index].deleted_at) comment.deleted_at = comments[index].deleted_at ;
            if (comment.accepted != comments[index].accepted) comment.accepted = comments[index].accepted ;
            if (comment.updated_by != comments[index].updated_by) comment.updated_by = comments[index].updated_by ;
        }

        // less that <ping_interval> milliseconds (see ping) between util/ping for client_userid
        // there must be more than one browser tab open with identical client login
        // js array gifts could be out of sync
        // sync changes in gifts array in local storage with js gifts array
        var sync_gifts = function () {
            var pgm = service + '. sync_gift: ' ;
            console.log(pgm + 'start') ;
            var new_gifts = JSON.parse(Gofreerev.getItem('gifts')) ;
            // todo: remove - index should normally always be up-to-date
            init_gifts_index() ;
            // insert and update gifts (keep sequence)
            var gid ;
            var insert_point = new_gifts.length ;
            for (var i=new_gifts.length-1 ; i>=0 ; i--) {
                gid = new_gifts[i].gid ;
                if (gifts_index.hasOwnProperty(gid)) {
                    // update gift
                    // match between gift id in localStorage and gift in js array gifts. insert new gift before this gift
                    insert_point = gifts_index[gid] ;
                    // copy any changed values from new_gifts into gifts
                    if (gifts[insert_point].giver_user_ids != new_gifts[i].giver_user_ids) gifts[insert_point].giver_user_ids = new_gifts[i].giver_user_ids ;
                    if (gifts[insert_point].receiver_user_ids != new_gifts[i].receiver_user_ids) gifts[insert_point].receiver_user_ids = new_gifts[i].receiver_user_ids ;
                    if (gifts[insert_point].created_at_client != new_gifts[i].created_at_client) gifts[insert_point].created_at_client = new_gifts[i].created_at_client ;
                    if (gifts[insert_point].created_at_server != new_gifts[i].created_at_server) gifts[insert_point].created_at_server = new_gifts[i].created_at_server ;
                    if (gifts[insert_point].price != new_gifts[i].price) gifts[insert_point].price = new_gifts[i].price ;
                    if (gifts[insert_point].currency != new_gifts[i].currency) gifts[insert_point].currency = new_gifts[i].currency ;
                    if (gifts[insert_point].direction != new_gifts[i].direction) gifts[insert_point].direction = new_gifts[i].direction ;
                    if (gifts[insert_point].description != new_gifts[i].description) gifts[insert_point].description = new_gifts[i].description ;
                    if (gifts[insert_point].open_graph_url != new_gifts[i].open_graph_url) gifts[insert_point].open_graph_url = new_gifts[i].open_graph_url ;
                    if (gifts[insert_point].open_graph_title != new_gifts[i].open_graph_title) gifts[insert_point].open_graph_title = new_gifts[i].open_graph_title ;
                    if (gifts[insert_point].open_graph_description != new_gifts[i].open_graph_description) gifts[insert_point].open_graph_description = new_gifts[i].open_graph_description ;
                    if (gifts[insert_point].open_graph_image != new_gifts[i].open_graph_image) gifts[insert_point].open_graph_image = new_gifts[i].open_graph_image ;
                    if (gifts[insert_point].like != new_gifts[i].like) gifts[insert_point].like = new_gifts[i].like ;
                    if (gifts[insert_point].follow != new_gifts[i].follow) gifts[insert_point].follow = new_gifts[i].follow ;
                    if (gifts[insert_point].show != new_gifts[i].show) gifts[insert_point].show = new_gifts[i].show ;
                    if (gifts[insert_point].deleted_at != new_gifts[i].deleted_at) gifts[insert_point].deleted_at = new_gifts[i].deleted_at ;
                    if (!gifts[insert_point].hasOwnProperty('comments')) gifts[insert_point].comments = [] ;
                    if (!new_gifts[i].hasOwnProperty('comments')) new_gifts[i].comments = [] ;
                    if (gifts[insert_point].comments != new_gifts[i].comments) refresh_comments(gifts[insert_point].comments, new_gifts[i].comments) ;
                }
                else {
                    // insert gift
                    console.log(pgm + 'insert gid ' + gid + ' from localStorage into js gifts array at index ' + insert_point) ;
                    if (new_gifts[i].hasOwnProperty('gift.show_no_comments')) delete new_gifts[i]['gift.show_no_comments'] ;
                    new_gifts[i].new_comment = {comment: ""} ;
                    gifts.splice(insert_point, 0, new_gifts[i]);
                    init_gifts_index() ;
                }
            }
            // remove deleted gifts
            var new_gifts_index = {} ;
            for (i=0 ; i<new_gifts.length ; i++) new_gifts_index[new_gifts[i].gid] = i ;
            for (i=gifts.length-1 ; i>= 0 ; i--) {
                gid = gifts[i].gid
                if (!new_gifts_index.hasOwnProperty(gid)) gifts.splice(i, 1) ;
            }
        }; // sync_gifts

        var unshift_gift = function (gift) {
            var pgm = service + '.unshift_gift: '
            if (gifts_index.hasOwnProperty(gift.gid)) {
                console.log(pgm + 'error. gift with gid ' + gift.gid + ' is already in gifts array') ;
                return ;
            }
            gifts.unshift(gift) ;
            init_gifts_index() ;
        } // unshift_gift

        // send meta-data for newly created gifts to server and get gift.created_at_server unix timestamps from server.
        // called from UserService.ping
        // gift timestamps: created_at_client (set by client) and created_at_server (returned from server)
        var new_gifts_request = function () {
            var request = [];
            var gift, hash, text_client, sha256_client ;
            for (var i = 0; i < gifts.length; i++) {
                gift = gifts[i];
                if (!gift.created_at_server) {
                    // send meta-data for new gift to server and generate a sha256 signature for gift on server
                    sha256_client = Gofreerev.sha256(
                        gift.created_at_client.toString(), gift.description, gift.open_graph_url,
                        gift.open_graph_title, gift.open_graph_description, gift.open_graph_image) ;
                    hash = {gid: gift.gid, sha256: sha256_client} ;
                    if (gift.giver_user_ids && (gift.giver_user_ids.length > 0)) hash.giver_user_ids = gift.giver_user_ids ;
                    if (gift.receiver_user_ids && (gift.receiver_user_ids.length > 0)) hash.receiver_user_ids = gift.receiver_user_ids ;
                    request.push(hash) ;
                } // if
            } // for i
            return (request.length == 0 ? null : request) ;
        }; // created_at_server_request
        var new_gifts_response = function (response) {
            var pgm = service + '.new_gifts_response: ' ;
            // console.log(pgm + 'response = ' + JSON.stringify(response)) ;
            if (response.hasOwnProperty('error')) console.log(pgm + response.error) ;
            if (response.hasOwnProperty('no_errors') && (response.no_errors>0)) console.log(pgm + response.no_errors + ' gifts was not created') ;
            if (!response.hasOwnProperty('data')) return ;
            var new_gifts = response.data ;
            var new_gift, gid, index, gift, created_at_server ;
            var save = false ;
            for (var i=0 ; i<new_gifts.length ; i++) {
                new_gift = new_gifts[i] ;
                // validate new_gift in response.data array
                if (!new_gift.hasOwnProperty('gid')) {
                    // invalid json response
                    console.log(pgm + 'Invalid response. gid property was missing error in data[' + i + '] = ' + JSON.stringify(new_gift)) ;
                    continue ;
                }
                gid = new_gift.gid ;
                if (new_gift.hasOwnProperty('error')) {
                    // report error from server validation
                    console.log(pgm + 'data[' + i + '].error = ' + new_gift.error) ;
                    // todo: delete gift and display error message in page header
                    continue ;
                }
                if (!gifts_index.hasOwnProperty(gid)) {
                    console.log(pgm + 'Invalid response. Unknown gid in data[' + i + ' = ' + JSON.stringify(new_gift)) ;
                    continue ;
                }
                index = gifts_index[gid] ;
                gift = gifts[index] ;
                if (!new_gift.hasOwnProperty('created_at_server')) {
                    console.log(pgm + 'Invalid response. created_at_server property was missing error in data[' + i + '] = ' + JSON.stringify(new_gift)) ;
                }
                if (gift.hasOwnProperty('created_at_server')) {
                    if (new_gift.created_at_server == gift.created_at_server) console.log(pgm + 'Warning. Created_at_server property in data[' + i + '] has been received earlier.') ;
                    else console.log(pgm + 'Invalid response. Has already received an other created_at_server timestamp for gift.');
                    continue ;
                }
                refresh_gift(gift) ;
                if (gift.hasOwnProperty('created_at_server')) {
                    if (new_gift.created_at_server == gift.created_at_server) null ; // ok - received in an other browser session
                    else console.log(pgm + 'Invalid response. Has already received an other created_at_server timestamp for gift.');
                    continue ;
                }
                gift.created_at_server = new_gift.created_at_server ;
                save = true ;
            } // for i
            if (save) save_gifts() ;
        }; // new_gifts_response

        // send meta-data for newly created comments to server and get comment.created_at_server unix timestamps from server.
        // called from UserService.ping
        var new_comments_request_index = {} ; // from cid to comment - used in new_comments_response for quick comment lookup
        var new_comments_request = function () {
            var pgm = service + '.new_comments_request: ' ;
            var request = [];
            new_comments_request_index = {} ;
            var gift, comment, hash, sha256_client, cid ;
            for (var i = 0; i < gifts.length; i++) {
                if (!gifts[i].comments) continue ;
                gift = gifts[i] ;
                comments = gifts[i].comments ;
                for (var j=0 ; j<comments.length ; j++) {
                    if (comments[j].created_at_server) continue ;
                    comment = comments[j] ;
                    cid = comment.cid ;
                    // send meta-data for new comment to server and generate a sha256 signature for comment on server
                    sha256_client = Gofreerev.sha256(gift.gid, comment.created_at_client.toString(), comment.comment, comment.price, comment.currency) ;
                    hash = {cid: cid, user_ids: comment.user_ids, sha256: sha256_client} ;
                    request.push(hash) ;
                    // cid to comment index - used in new_comments_response for quick comment lookup
                    new_comments_request_index[cid] = comment ;
                } // for j
            } // for i
            return (request.length == 0 ? null : request) ;
        }; // new_comments_request
        var new_comments_response = function (response) {
            var pgm = service + '.new_comments_response: ' ;
            // console.log(pgm + 'response = ' + JSON.stringify(response)) ;
            if (response.hasOwnProperty('error')) console.log(pgm + response.error) ;
            if (response.hasOwnProperty('no_errors') && (response.no_errors>0)) console.log(pgm + response.no_errors + ' comments was not created') ;
            if (!response.hasOwnProperty('data')) return ;
            var new_comments = response.data ;
            var new_comment, cid, comment, created_at_server ;
            var save = false ;
            for (var i=0 ; i<new_comments.length ; i++) {
                new_comment = new_comments[i] ;
                // validate new_comment in response.data array
                if (!new_comment.hasOwnProperty('cid')) {
                    // invalid json response
                    console.log(pgm + 'Invalid response. cid property was missing error in data[' + i + '] = ' + JSON.stringify(new_comment)) ;
                    continue ;
                }
                cid = new_comment.cid ;
                if (new_comment.hasOwnProperty('error')) {
                    // report error from server validation
                    console.log(pgm + 'data[' + i + '].error = ' + new_comment.error) ;
                    // todo: delete comment and display error message in page header or in inbox
                    continue ;
                }
                if (!new_comments_request_index.hasOwnProperty(cid)) {
                    console.log(pgm + 'Invalid response. Unknown cid in data[' + i + ' = ' + JSON.stringify(new_comment)) ;
                    continue ;
                }
                if (!new_comment.hasOwnProperty('created_at_server')) {
                    console.log(pgm + 'Invalid response. created_at_server property was missing error in data[' + i + '] = ' + JSON.stringify(new_comment)) ;
                    continue ;
                }
                comment = new_comments_request_index[cid] ;
                if (comment.hasOwnProperty('created_at_server')) {
                    if (new_comment.created_at_server == comment.created_at_server) console.log(pgm + 'Warning. Created_at_server property in data[' + i + '] has been received earlier.') ;
                    else console.log(pgm + 'Invalid response. Has already received an other created_at_server timestamp for comment.');
                    continue ;
                }
                // todo: add refresh_comment method
                // refresh_comment(comment) ;
                if (comment.hasOwnProperty('created_at_server')) {
                    if (new_comment.created_at_server == comment.created_at_server) null ; // ok - received in an other browser session
                    else console.log(pgm + 'Invalid response. Has already received an other created_at_server timestamp for comment.');
                    continue ;
                }
                comment.created_at_server = new_comment.created_at_server ;
                save = true ;
            } // for i
            if (save) save_gifts() ;
            new_comments_request_index = {} ;
        }; // new_comments_response

        // list of mailboxes for other devices (online and offline)
        // key = did+sha256 is used as mailbox index.
        var mailboxes = [] ; // list with online and offline devices
        var key_mailbox_index = {} ; // from key (did+sha256) to index
        var devices = {} ; // hash with public key and symmetric password for each unique device (did)
        var user_mailboxes = {} ; // list with relevant mailboxes for each user id (mutual friend) - how to notify about changes in gifts

        var update_key_mailbox_index = function () {
            var pgm = service + '.update_key_mailbox_index: ' ;
            key_mailbox_index = {} ; // one index for each device
            user_mailboxes = {} ; // one index for each userid
            var mailbox, i, j, mutual_friend_userid ;
            for (i=0 ; i<mailboxes.length ; i++) {
                mailbox = mailboxes[i] ;
                key_mailbox_index[mailbox.key] = i ;
                // list with relevant mailboxes for mutual friend
                // a kind of listeners - mailbox (device) get notifications for relevant gift
                for (j=0 ; j<mailbox.mutual_friends.length ; j++) {
                    mutual_friend_userid = mailbox.mutual_friends[j] ;
                    if (!user_mailboxes[mutual_friend_userid]) user_mailboxes[mutual_friend_userid] = [] ;
                    user_mailboxes[mutual_friend_userid].push(i) ; // index to mailboxes array
                } // for j
            } // for j
            // console.log(pgm + 'user_mailboxes = ' + JSON.stringify(user_mailboxes)) ;
        };
        update_key_mailbox_index() ;

        // mailbox actions:
        // - online => offline - continue to buffer messages in javascript arrays
        // - old offline => online - deliver old messages in next ping
        // - new device online - exchange symmetric key and request gift info for mutual friends
        // - new mutual friend for online device - request gift info for new mutual friend
        // - removed mutual friend for online device - continue to buffer messages, but don't deliver in next  ping
        var update_mailboxes = function (new_mailboxes) {
            var pgm = service + '.update_mailboxes: ' ;
            // console.log(pgm + 'new_mailboxes = ' + JSON.stringify(new_mailboxes)) ;
            // add index
            var i ;
            var new_mailboxes_index = {}, new_mailbox ;
            for (i=0 ; i<new_mailboxes.length ; i++) {
                new_mailbox = new_mailboxes[i] ;
                new_mailbox.key = new_mailbox.did + new_mailbox.sha256 ; // unique mailbox index
                new_mailboxes_index[new_mailbox.key] = i ;
            }
            // update old mailboxes
            var j, new_mutual_friends, mailbox ;
            for (i=0 ; i<mailboxes.length ; i++) {
                mailbox = mailboxes[i] ;
                mailbox.online = new_mailboxes_index.hasOwnProperty(mailbox.key) ;
                if (!mailbox.online) continue ;
                j = new_mailboxes_index[mailbox.key] ;
                if (!mailbox.password) {
                    // symmetric communication has not yet been established
                    mailbox.mutual_friends = new_mailboxes[j].mutual_friends ;
                    continue  ;
                }
                // symmetric communication has been established - check for changes in mutual friends
                new_mutual_friends = $(new_mailboxes[j].mutual_friends).not(mailbox.mutual_friends).get() ;
                mailbox.mutual_friends = new_mailboxes[j].mutual_friends ;
                if (new_mutual_friends.length > 0) {
                    // step 2 - compare sha256 values for mutual friends
                    mailbox.outbox.push({
                        mid: Gofreerev.get_new_uid(),
                        msgtype: 'users_sha256',
                        mutual_friends: JSON.parse(JSON.stringify(new_mutual_friends))
                    }) ;
                }
            }
            // add new mailboxes - symmetric password will be added in rsa handshake
            for (i=0 ; i<new_mailboxes.length ; i++) {
                mailbox = new_mailboxes[i] ;
                mailbox.online = true ;
                mailbox.outbox = [] ;
                if (!key_mailbox_index.hasOwnProperty(mailbox.key)) mailboxes.push(mailbox) ;
            }
            update_key_mailbox_index() ;
            // console.log(pgm + 'mailboxes = ' + JSON.stringify(mailboxes)) ;
            // console.log(pgm + 'device_pubkey = ' + JSON.stringify(device_pubkey)) ;
        }; // update_mailboxes

        // get/set pubkey for unique device - called in ping - used in client to client communication
        var pubkeys_request = function () {
            var request = [] ;
            var mailbox, did ;
            for (var i=0 ; i<mailboxes.length ; i++) {
                mailbox = mailboxes[i] ;
                did = mailbox.did ;
                if ((!devices.hasOwnProperty(did) || !devices[did].pubkey) && (request.indexOf(did)==-1)) {
                    request.push(did);
                    devices[did] = {} ;
                }
            }
            return request.length == 0 ? null : request ;
        };
        var pubkeys_response = function (response) {
            var pgm = service + '.pubkeys_response: ' ;
            console.log(pgm + 'pubkeys = ' + JSON.stringify(response)) ;
            var did ;
            for (var i=0 ; i<response.length ; i++) {
                did = response[i].did ;
                if (devices[did] && devices[did].pubkey) console.log(pgm + 'invalid pubkeys response from ping. pubkey for device ' + did + ' has already been received from server') ;
                else devices[did].pubkey = response[i].pubkey ;
            } // for
        }; // pubkeys_response

        // setup password for symmetric communication. password1 from this device and password2 from other device
        var setup_device_password = function (device) {
            var pgm = service + '.setup_device_password: ' ;
            if (!device.password1_at || !device.password2_at) {
                delete device.password_sha256 ;
                return ;
            }
            if (device.password1_at <= device.password2_at) {
                device.password = device.password1 + device.password2 ;
            }
            else {
                device.password = device.password2 + device.password1 ;
            }
            device.password_md5 = CryptoJS.MD5(device.password).toString(CryptoJS.enc.Latin1) ;
        }; // setup_device_password

        // send "users_sha256" message to mailbox/other device. one sha256 signature for each mutual friend
        var send_message_users_sha256 = function (msg) {
            var pgm = service + '.send_message_users_sha256: ' ;
            console.log(pgm + 'message = ' + JSON.stringify(msg)) ;
            return msg ;
        }; // send_message_users_sha256

        // send/receive messages to/from other devices
        var send_messages = function () {
            var pgm = service + '.send_messages: ' ;
            var response = [] ;
            var mailbox, did, messages, msg, message, message_json, message_json_com, message_json_rsa_enc, message_with_envelope ;
            var encrypt = new JSEncrypt();
            var password ;
            for (var i=0 ; i<mailboxes.length ; i++) {
                mailbox = mailboxes[i] ;
                did = mailbox.did ;
                if (!mailbox.password) {
                    // step 1 - setup password for symmetric encryption
                    if (!devices.hasOwnProperty(did) || !devices[did].pubkey) {
                        console.log(pgm + 'Wait. Public key has not yet been received for device ' + did) ;
                        continue ;
                    }
                    // send password1 to other device using public/private key encryption (rsa)
                    if (!mailbox.online) continue ; // wait
                    if (!mailbox.password1) {
                        mailbox.password1 = Gofreerev.generate_random_password(42) ; // 44 characters password to long for RSA
                        mailbox.password1_at = (new Date).getTime() ;
                    } ;
                    setup_device_password(mailbox) ;
                    message = { msgtype: 'pw', pw: [mailbox.password1, mailbox.password1_at]} ;
                    if (mailbox.password_md5) message.pw.push(mailbox.password_md5) ; // verify complete password (password1+password2)
                    // message => json => rsa encrypt
                    message_json = JSON.stringify(message) ;
                    // console.log(pgm + 'rsa encrypt using public key ' + devices[did].pubkey);
                    encrypt.setPublicKey(devices[did].pubkey);
                    message_json_rsa_enc = encrypt.encrypt(message_json) ;
                    // add envelope - used in rails message buffer - each message have sender, receiver, encryption and message
                    message_with_envelope = {
                        receiver_did: mailbox.did,
                        receiver_sha256: mailbox.sha256,
                        encryption: 'rsa',
                        message: message_json_rsa_enc
                    } ;
                    response.push(message_with_envelope);
                    // debug
                    // console.log(pgm + 'message_json = ' + message_json) ;
                    // console.log(pgm + 'message_json_rsa_enc = ' + message_json_rsa_enc) ;
                    // console.log(pgm + 'message_with_envelope = ' + JSON.stringify(message_with_envelope)) ;
                    // wait with any messages in outbox until symmetric password setup is complete
                    continue ;
                }
                if (!mailbox.hasOwnProperty('outbox')) {
                    console.log(pgm + 'Error. Outbox was not found in mailbox. did = ' + mailbox.did) ;
                    continue ;
                }
                if (mailbox.outbox.length == 0) continue ; // no new messages for this mailbox

                // send continue with symmetric key communication
                console.log(pgm + 'send messages in outbox for device ' + mailbox.did + ' with key ' + mailbox.key) ;
                messages = [] ;
                for (var j=0 ; j<mailbox.outbox.length ; j++) {
                    msg = mailbox.outbox[j] ;
                    console.log(pgm + 'outbox[' + j + '] = ' + JSON.stringify(msg)) ;
                    // outbox[0] = {"msgtype":"users_sha256","mutual_friends":[1126,920]}"
                    switch(msg.msgtype) {
                        case 'users_sha256':
                            messages.push(send_message_users_sha256(msg)) ;
                            break ;
                        default:
                            console.log(pgm + 'Unknown msgtype ' + msg.msgtype + ' in ' + JSON.stringify(mailbox)) ;
                    } // end msgtype switch
                } // for j (mailbox.outbox)
                // todo: add more header fields in message?
                message = {
                    created_at_client: (new Date).getTime(),
                    messages: messages // array with messages
                };
                console.log(pgm + 'unencrypted message = ' + JSON.stringify(message)) ;
                // encrypt message in mailbox using symmetric encryption
                password = mailbox.password ; //
                message_with_envelope = {
                    receiver_did: mailbox.did,
                    receiver_sha256: mailbox.sha256,
                    encryption: 'sym',
                    message: Gofreerev.encrypt(JSON.stringify(message), password)
                };
                // send encrypted message
                response.push(message_with_envelope);
                console.log(pgm + 'encrypted message = ' + JSON.stringify(message_with_envelope)) ;
                // todo: empty mailbox.outbox or move to mailbox.sending while sending messages to server. reinsert into outbox if send messages fails (ping/error)
            } // for i (mailboxes)
            return (response.length == 0 ? null : response) ;
        }; // send_messages

        // receive symmetric password (part 2) from other device
        var receive_message_pw = function (device, msg) {
            var pgm = service + 'receive_message_pw: ' ;
            // console.log(pgm + 'device = ' + JSON.stringify(device)) ;
            // console.log(pgm + 'msg = ' + JSON.stringify(msg)) ;
            // msg.pw is an array with password, password_at and optional md5 for complete password
            // password setup is complete when received md5 in msg and password md5 for device are identical
            device.password2 = msg.pw[0] ;
            device.password2_at = msg.pw[1] ;
            // calc password_md5 if possible
            setup_device_password(device) ;
            // check of the two devices agree about password
            if (device.password_md5 && msg.pw.length == 3 && (device.password_md5 == msg.pw[2])) {
                console.log(pgm + 'symmetric password setup completed.') ;
                // console.log(pgm + 'symmetric password setup completed. device = ' + JSON.stringify(device)) ;
            }
            else {
                console.log(pgm + 'symmetric password setup in progress.') ;
                // console.log(pgm + 'symmetric password setup in progress. device = ' + JSON.stringify(device)) ;
                delete device.password;
            }
        }; // receive_message_password;

        // receive messages from other devices
        var receive_messages = function (response) {
            var pgm = service + '.receive_messages: ' ;
            // console.log(pgm + 'receive ' + JSON.stringify(response)) ;
            var encrypt, prvkey ;
            var message_with_envelope, key, index, mailbox, msg, msg_json_rsa_enc, msg_json, msg_json_sym_enc ;
            for (var i=0 ; i<response.length ; i++) {
                message_with_envelope = response[i] ;
                key = message_with_envelope.sender_did + message_with_envelope.sender_sha256 ;
                if (!key_mailbox_index.hasOwnProperty(key)) {
                    console.log(pgm + 'Error. Ignoring message from device ' + message_with_envelope.sender_did + ' with unknown key ' + key + '. message = ' + JSON.stringify(message_with_envelope)) ;
                    continue ;
                };
                index = key_mailbox_index[key] ;
                mailbox = mailboxes[key_mailbox_index[key]] ;
                if (!mailbox) {
                    console.log(pgm + 'Error. Ignoring message from device '  + message_with_envelope.sender_did + 'with unknown index ' + index + '. message = ' + JSON.stringify(message_with_envelope)) ;
                    continue ;
                } ;
                if (message_with_envelope.encryption == 'rsa') {
                    // public/private key decryption (rsa) - must be password setup for symmetric encryption
                    console.log(pgm + 'message_with_envelope = ' + JSON.stringify(message_with_envelope)) ;
                    if (!encrypt) {
                        encrypt = new JSEncrypt() ;
                        prvkey = Gofreerev.getItem('prvkey') ;
                        encrypt.setPrivateKey(prvkey);
                    } ;
                    // rsa => json
                    msg_json_rsa_enc = message_with_envelope.message ;
                    msg_json = encrypt.decrypt(msg_json_rsa_enc) ;
                    // console.log(pgm + 'rsa decrypt: prvkey = ' + prvkey) ;
                    console.log(pgm + 'rsa decrypt: msg_json_rsa_enc = ' + msg_json_rsa_enc) ;
                    console.log(pgm + 'rsa decrypt: msg_json = ' + msg_json) ;
                }
                else {
                    // symmetric key decryption
                    if (!mailbox.password) {
                        console.log(pgm + 'Error. Ignoring message from device '  + message_with_envelope.sender_did + 'with key ' + key + '. Password for symmetric communication was not found. Message = ' + JSON.stringify(message_with_envelope)) ;
                        continue ;
                    }
                    msg_json_sym_enc = message_with_envelope.message ;
                    msg_json = Gofreerev.decrypt(msg_json_sym_enc, mailbox.password) ;
                    console.log(pgm + 'sym decrypt: msg_json_sym_enc = ' + msg_json_sym_enc) ;
                    console.log(pgm + 'sym decrypt: msg_json = ' + msg_json) ;
                } ;
                msg = JSON.parse(msg_json) ;
                // console.log(pgm + 'msg = ' + msg) ;
                switch(msg.msgtype) {
                    case 'pw':
                        receive_message_pw(mailbox, msg) ;
                        break ;
                    default:
                        console.log(pgm + 'Unknown msgtype ' + msg.msgtype + ' in message ' + JSON.stringify(message_with_envelope) + '. msg = ' + JSON.stringify(msg)) ;
                } // end msgtype switch
            } ;
        }; // receive_messages

        return {
            gifts: gifts,
            load_gifts: load_gifts,
            refresh_gift: refresh_gift,
            refresh_gift_and_comment: refresh_gift_and_comment,
            save_gifts: save_gifts,
            sync_gifts: sync_gifts,
            unshift_gift: unshift_gift,
            new_gifts_request: new_gifts_request,
            new_gifts_response: new_gifts_response,
            new_comments_request: new_comments_request,
            new_comments_response: new_comments_response,
            pubkeys_request: pubkeys_request,
            pubkeys_response: pubkeys_response,
            update_mailboxes: update_mailboxes,
            send_messages: send_messages,
            receive_messages: receive_messages
        };

        // end GiftService
    }])
    .controller('NavCtrl', ['TextService', 'UserService', 'GiftService', '$timeout', '$http', '$q', function(textService, userService, giftService, $timeout, $http, $q) {
        console.log('NavCtrl loaded') ;
        var self = this ;
        self.userService = userService ;
        self.texts = textService.texts ;

        // less that 60 seconds between util/ping for client_userid
        // there must be more than one browser tab open with identical client login
        // sync changes in users array in local storage with js users array
        var sync_users = function () {
            var pgm = 'NavCtrl.sync_users: ' ;
            var old_length = users.length ;
            var old_stat = provider_stat(users) ;
            var new_users = JSON.parse(Gofreerev.getItem('users')) ;
            userService.update_users(new_users, true) ;
            var new_length = users.length ;
            var new_stat = provider_stat(users) ;
            //console.log(
            //    pgm + 'sync users. ' + (new_length-old_length) + ' users was inserted/deleted. ' +
            //    'old JS users = ' + old_length + ', new JS users = ' + new_length + '. ' +
            //    'there was ' + new_users.length + ' users in localstorage.') ;
            //// "UserService.ping: sync users. 0 users was inserted/deleted. old JS users = 108, new JS users = 108. there was 7 users in localstorage.
            //console.log(pgm + 'old stat: ' + old_stat) ;
            //console.log(pgm + 'new stat: ' + new_stat) ;
        } // sync_users

        // ping server once every minute - server maintains a list of online users / devices
        var ping_interval = Gofreerev.rails['PING_INTERVAL'] ;
        var ping = function (old_ping_interval) {
            var pgm = 'NavCtrl.ping: ' ;
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
            // make ping request
            var sid = Gofreerev.getItem('sid') ;
            var ping_request = {
                client_userid: userid,
                sid: sid,
                client_timestamp: new_client_timestamp,
                new_gifts: giftService.new_gifts_request(),
                new_comments: giftService.new_comments_request(),
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
                    if (response.data.error) console.log(pgm + 'error: ' + response.data.error) ;
                    // check online users/devices - create a mail box for each online device
                    if (response.data.online) giftService.update_mailboxes(response.data.online) ;
                    // check for new public keys for online users/devices
                    if (response.data.pubkeys) giftService.pubkeys_response(response.data.pubkeys) ;
                    // get timestamps for newly created gifts from server
                    if (response.data.new_gifts) giftService.new_gifts_response(response.data.new_gifts) ;
                    // get timestamps for newly created comments from server
                    if (response.data.new_comments) giftService.new_comments_response(response.data.new_comments) ;
                    // check expired access token (server side check)
                    if (response.data.expired_tokens) userService.expired_tokens_response(response.data.expired_tokens) ;
                    // check for new oauth authorization (google+ only)
                    if (response.data.oauths) userService.oauths_response(response.data.oauths) ;
                    // check for new messages from other devices
                    if (response.data.messages) giftService.receive_messages(response.data.messages) ;

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
                    sync_users() ;
                    giftService.sync_gifts() ;
                },
                function (error) {
                    // schedule next ping
                    console.log(pgm + 'error. old_ping_interval = ' + old_ping_interval) ;
                    $timeout(function () { ping(ping_interval); }, ping_interval) ;
                    console.log(pgm + 'error = ' + JSON.stringify(error)) ;
                })
        } // ping
        $timeout(function () { ping(ping_interval); }, ping_interval) ;
        console.log('NavCtrl.start ping process. start up ping interval = ' + ping_interval) ;

        var get_js_timezone = function () {
            return -(new Date().getTimezoneOffset()) / 60.0 ;
        }
        var start_do_tasks_spinner = function ()
        {
            var spinner_id = 'ajax-tasks-spinner' ;
            var spinner = document.getElementById(spinner_id) ;
            if (spinner) spinner.style.display = '' ;
            else Gofreerev.add2log('start_do_tasks_spinner: spinner was not found') ;
        } // start_do_tasks_spinner
        var stop_do_tasks_spinner = function ()
        {
            var spinner_id = 'ajax-tasks-spinner' ;
            var spinner = document.getElementById(spinner_id) ;
            if (spinner) spinner.style.display = 'none' ;
            else Gofreerev.add2log('stop_tasks_form_spinner: spinner was not found') ;
        } // stop_tasks_form_spinner

        // post page task - execute some post-page / post-login ajax tasks and get fresh json data from server (oauth and users)
        var do_tasks = function () {
            var pgm = 'NavCtrl.do_tasks: ' ;
            var userid = userService.client_userid() ;
            if (userid == 0) return ; // only relevant for logged in users
            console.log(pgm + 'start');
            var secret = userService.client_secret() ;
            var do_tasks_request = {client_userid: userid, client_secret: secret, timezone: get_js_timezone()} ;
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
                    var new_users = response.data.users ;
                    if (new_users) {
                        // new user and friends info received from util.generic_post_login task
                        console.log('post login. new users = ' + new_users) ;
                        userService.update_users(new_users, false) ; // replace=false - add new users
                    }
                },
                function (error) {
                    stop_do_tasks_spinner() ;
                    console.log(pgm + 'error = ' + JSON.stringify(error)) ;
                }) ;

        }
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
        }
        self.login = function (provider) {
            if (userService.is_logged_in_with_provider(provider)) return ;
            var userid = Gofreerev.getItem('userid') ;
            $window.location.href = '/auth/' + provider + '?client_userid=' + userid ;
        };
        self.is_logged_off = function (provider) {
            return !userService.is_logged_in_with_provider(provider)
        }
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
        }
        self.trafic_light_status = function (provider) {
            if (userService.is_logged_in_with_provider(provider)) return 'connected' ;
            else return 'disconnected' ;
        }
        self.register_disabled = function() {
            var device_password = $window.document.getElementById('device_password').value ;
            if (device_password.length < 10) return true ;
            if (device_password.length > 50) return true ;
            var confirm_device_password = $window.document.getElementById('confirm_device_password').value ;
            return (device_password != confirm_device_password) ;
        }
        self.login_or_register_error = '' ;
        var set_login_or_register_error = function (error) {
            // todo: not working - error from userService.send_oauth is NOT injected into view!
            self.login_or_register_error = error ;
            // workaround - use old tasks error table in page header
            if (error != '') Gofreerev.add_to_tasks_errors(error) ;
        }
        set_login_or_register_error('') ;
        self.login_or_register = function() {
            var pgm = 'AuthCtrl.login_or_register: ' ;
            var create_new_account = (self.register != '') ;
            var userid = Gofreerev.client_login(self.device_password, create_new_account) ;
            if (userid == 0) {
                alert('Invalid password');
            }
            else {
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
        }
        // end AuthCtrl
    }])
    .controller('GiftsCtrl', ['$location', '$http', '$document', '$window', '$sce', '$timeout',  'UserService', 'GiftService', 'TextService',
                     function ($location, $http, $document, $window, $sce, $timeout, userService, giftService, textService) {
        console.log('GiftsCtrl loaded') ;
        var self = this;

        self.texts = textService.texts ;
        self.userService = userService ;
        self.giftService = giftService ;

        var appname = Gofreerev.rails['APP_NAME'];

        self.default_no_comments = 3 ;

        self.is_logged_in = function () {
            return userService.is_logged_in() ;
        }
        self.no_friends = function () {
            return userService.no_friends() ;
        }
        self.login_users = function () {
            return userService.get_login_users() ;
        }
        self.login_user_ids = function () {
            return userService.get_login_userids() ;
        }

        // gifts filter. hide deleted gift. hide hidden gifts. used in ng-repeat
        self.gifts_filter = function (gift, index) {
            var show_gift = true ;
            if (gift.deleted_at) return false ;
            if (!gift.show) return false ;
            // check friend status. giver or receiver must be login user or a friend of login user
            var friend ;
            friend = userService.get_userids_friend_status(gift.giver_user_ids) ;
            // console.log('GiftsCtrl.gifts_filer: gid = ' + gift.gid + ', giver_user_ids = ' + JSON.stringify(gift.giver_user_ids) + ', receiver_user_ids = ' + JSON.stringify(gift.receiver_user_ids) + 'friend status = ' + friend) ;
            if (friend && (friend <= 2)) return true ;
            friend = userService.get_userids_friend_status(gift.receiver_user_ids) ;
            if (friend && (friend <= 2)) return true ;
            return false ;
        }

        self.no_gifts = function() {
            if (typeof giftService.gifts == 'undefined') return true  ;
            if (typeof giftService.gifts.length == 'undefined') return true ;
            return (giftService.gifts.length == 0) ;
        }

        // comments filter. hide deleted comments. used in ng-repeat
        self.comments_filter = function (comment, index) {
            var pgm = 'GiftsCtrl.comments_filter: ' ;
            var show ;
            if (comment.deleted_at) show = false ;
            else show = true ;
            // console.log(pgm + 'cid = ' + comment.cid + ', show = ' + show) ;
            return show ;
        }


        self.user_div_on_click = function (user_ids) {
            var pgm = 'GiftsCtrl.user_div_on_click ' ;
            console.log(pgm + 'user_ids = ' + JSON.stringify(user_ids)) ;
            if (typeof user_ids == 'undefined') {
                // error - user_id array not found in users array
                console.log(pgm + 'error: user_ids is undefined') ;
                return;
            }
            var user_id = user_ids[0] ;
            var user = userService.get_user(user_id) ;
            if (!user) return ; // error - user not found in users array
            if (!user.friend) return ; // error - no friend status was found
            if ([1,2,3,4].indexOf(user.friend) == -1) return ; // ok - not clickable div
            var locale = I18n.currentLocale() || I18n.defaultLocale ;
            // ok - redirect to users/show page
            // todo: use windows redirect or angular single page app?
            // $location.url('/' + locale + '/users/' + user_id) ;
            window.top.location.assign('/' + locale + '/users/' + user_id) ;
        } // user_div_on_click

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
        } // vertical_overflow

        // gift link + description - show "show-more-text" link if long gift description with vertical text overflow 
        // return false if small text without vertical overflow
        // link 1: above image (picture attachment), link 2: together with other gift links (no picture attachment)
        self.show_full_gift_link = function (gift, link) {
            var pgm = 'GiftsCtrl.show_full_gift_link: ' ;
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
        } // show_full_gift_link

        // show "show-more-text" link if long comment description with vertical text overflow
        self.show_full_comment_link = function (comment) {
            var pgm = 'commentsCtrl.show_full_comment_link: ' ;
            // find overflow div
            var text_id = comment.cid + "-overflow-text" ;
            var x = vertical_overflow(text_id) ;
            if (comment.cid == '14229743962942303238') console.log(pgm + 'vertical_overflow("' + text_id + '") = ' + x) ; // todo: debug
            return x ;
        } // show_full_comment_link

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
        } // show_full_gift_click

        // show full comment description. remove style maxHeight and overflow from div container
        self.show_full_comment_click = function(comment) {
            // show full text for div with overflow
            var pgm = 'commentsCtrl.show_full_comment_click: ' ;
            console.log(pgm + 'cid = ' + comment.cid) ;
            // find overflow div
            var text_id = comment.cid + "-overflow-text" ;
            var text = document.getElementById(text_id) ;
            if (!text) return ; // error - div with comment link and description was not found
            // remove max height ( and hide show-more-text link)
            text.style.maxHeight = 'none' ;
            text.style.overflow = 'visible' ;
        } // show_full_comment_click

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
        } // show_api_picture_url

        // show/hide table row with gift open graph image
        self.show_open_graph_image = function (gift) {
            if ((typeof gift.open_graph_image != 'undefined') && (gift.open_graph_image != null)) return true ;
            else return false ;
        }

        // show/hide table row with gift open graph title
        self.show_open_graph_title = function (gift) {
            if ((typeof gift.open_graph_title != 'undefined') && (gift.open_graph_title != null)) return true ;
            else return false ;
        }

        // show/hide table row with gift open graph description
        self.show_open_graph_description = function (gift) {
            if ((typeof gift.open_graph_description != 'undefined') && (gift.open_graph_description != null)) return true ;
            else return false ;
        }

        self.like_gift = function (gift) {
            giftService.refresh_gift(gift);
            gift.like = true ;
            giftService.save_gifts() ;
        }
        self.unlike_gift = function (gift) {
            giftService.refresh_gift(gift);
            gift.like = false ;
            giftService.save_gifts() ;
        }

        self.follow_gift = function (gift) {
            giftService.refresh_gift(gift);
            gift.follow = true ;
            giftService.save_gifts() ;
        }
        self.unfollow_gift = function (gift) {
            giftService.refresh_gift(gift);
            gift.follow = false ;
            giftService.save_gifts() ;
        }

        // delete gift. show delete link if login user(s) is giver or receiver of gift
        self.show_delete_gift = function (gift) {
            if (!self.gifts_filter(gift, null)) return false ; // gift already removed from page
            var user = userService.find_giver(gift) ;
            if (user && (user.friend == 1)) return true ;
            user = userService.find_receiver(gift) ;
            if (user && (user.friend == 1)) return true ;
            return false ;
        }
        self.delete_gift = function (gift) {
            var pgm = 'GiftsCtrl.delete_gft: ' ;
            giftService.refresh_gift(gift);
            if (!self.show_delete_gift(gift)) return ;
            var confirm_options = { price: gift.price, currency: gift.currency }
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
                    keyno = 1
                    confirm_options['user_name'] = is_giver ? receiver.user_name : giver.user_name ;
                }
            }
            else keyno = 2 ; // simple confirm
            // confirm dialog
            var confirm_key = "js.gifts.confirm_delete_gift_" + keyno ;
            var confirm_text = I18n.t(confirm_key, confirm_options) ;
            if (!confirm(confirm_text)) return ;
            gift.deleted_at = (new Date).getTime() ;
            giftService.save_gifts() ;
        } // delete_gift

        self.hide_gift = function (gift) {
            giftService.refresh_gift(gift);
            if (!self.gifts_filter(gift, null)) return ; // already removed from page
            var confirm_text = I18n.t("js.gifts.confirm_hide_gift") ;
            if (!confirm(confirm_text)) return ;
            gift.show = false ;
            giftService.save_gifts() ;
        }

        self.show_older_comments = function (gift) {
            return ((gift.show_no_comments || self.default_no_comments) < (gift.comments || []).length) ;
        }
        self.show_older_comments_text = function (gift) {
            var old_no_rows = gift.show_no_comments || self.default_no_comments ;
            var new_no_rows = Math.min((gift.comments || []).length, old_no_rows + 10) ;
            var no_older_comments = new_no_rows - old_no_rows ;
            if (no_older_comments <= 1) return I18n.t('js.gifts.show_older_comment') ;
            else return I18n.t('js.gifts.show_older_comments', {no_older_comments: no_older_comments}) ;
        }
        self.show_older_comments_click = function (gift) {
            if (!gift.show_no_comments) gift.show_no_comments = self.default_no_comments ;
            gift.show_no_comments = gift.show_no_comments + 10 ;
        }

        self.show_delete_comment_link = function (gift, comment) {
            // from rails Comment.show_delete_comment_link?
            var pgm = 'GiftsCtrl.show_delete_comment_link. gid = ' + gift.gid + ', cid = ' + comment.cid + '. ';
            if (comment.accepted) return false ; // delete accepted proposal is not allow - delete gift is allowed
            if (comment.deleted_at) return false ; // comment has already been marked as deleted
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
        }

        self.delete_comment = function (gift, comment) {
            var pgm = 'GiftsCtrl.delete_comment: ' ;
            giftService.refresh_gift_and_comment(gift, comment) ;
            if (!comment.cid) {
                console.log(pgm + 'Comment removed in refresh_gift_and_comment') ;
                return ;
            } // comment has been deleted
            if (!self.show_delete_comment_link(gift,comment)) return ; // delete link no longer active
            if (confirm(self.texts.comments.confirm_delete_comment)) {
                comment.deleted_at = Gofreerev.unix_timestamp() ;
                if (typeof gift.show_no_comments != 'undefined') gift.show_no_comments = gift.show_no_comments - 1 ;
                giftService.save_gifts() ;
            }
            // console.log(pgm + 'cid = ' + comment.cid + ', deleted_at = ' + comment.deleted_at) ;
        }

        self.show_cancel_new_deal_link = function (gift,comment) {
            // from rails Comment.show_cancel_new_deal_link?
            if (comment.new_deal != true) return false ;
            if (comment.accepted) return false ;
            var login_user_ids = userService.get_login_userids() ;
            if ($(login_user_ids).filter(comment.user_ids).length == 0) return false ;
            if (gift.direction == 'both') return false ;
            return true ;
        }
        self.cancel_new_deal = function (gift,comment) {
            giftService.refresh_gift_and_comment(gift, comment) ;
            if (!comment.cid) return ; // comment has been deleted
            if (!self.show_cancel_new_deal_link(gift,comment)) return ; // cancel link no longer active
            if (!confirm(self.texts.comments.confirm_cancel_new_deal)) return ;
            comment.new_deal = false ;
            giftService.save_gifts() ;
        }

        self.show_accept_new_deal_link = function (gift,comment) {
            // from rails Comment.show_accept_new_deal_link?
            if (comment.new_deal != true) return false ;
            if (typeof comment.accepted != 'undefined') return false ; // true or false
            var login_user_ids = userService.get_login_userids() ;
            if (gift.direction == 'both') return false ;
            var gift_user_ids = (gift.direction == 'giver') ? gift.giver_user_ids : gift.receiver_user_ids ;
            var user_ids = $(login_user_ids).filter(gift_user_ids) ;
            if (user_ids.length == 0) return false ;
            // login user is creator of gift.
            // check friend relation with creator of new proposal/comment
            // friends relation can have changed - or maybe not logged in with provider or correct provider user
            var user = userService.get_closest_user(comment.user_ids);
            if (typeof user == 'undefined') return false ;
            if (user == null) return false ;
            return (user.friend <= 2) ;
        }
        self.accept_new_deal = function (gift,comment) {
            giftService.refresh_gift_and_comment(gift, comment) ;
            if (!comment.cid) return ; // comment has been deleted
            if (!self.show_accept_new_deal_link(gift,comment)) return false ; // accept link no longer active!
            if (!confirm(self.texts.comments.confirm_accept_new_deal)) return ; // operation cancelled
            // from utilController.
            var login_user_ids = userService.get_login_userids() ;
            var gift_user_ids = (gift.direction == 'giver') ? gift.giver_user_ids : gift.receiver_user_ids ;
            comment.accepted = true ;
            comment.updated_by = $(login_user_ids).filter(gift_user_ids) ;
            giftService.save_gifts() ;
        }

        self.show_reject_new_deal_link = function (gift,comment) {
            return self.show_accept_new_deal_link(gift,comment) ;
        }
        self.reject_new_deal = function (gift,comment) {
            giftService.refresh_gift_and_comment(gift, comment) ;
            if (!comment.cid) return ; // comment has been deleted
            if (!self.show_reject_new_deal_link(gift,comment)) return false ; // reject link no longer active!
            if (!confirm(self.texts.comments.confirm_reject_new_deal)) return ; // operation cancelled
            // from utilController.reject_new_deal
            comment.accepted = false ;
            comment.updated_by = userService.get_login_userids() ;
            giftService.save_gifts() ;
        }

        self.show_new_deal_checkbox = function (gift) {
            // see also formatNewProposalTitle
            if (gift.direction == 'both') return false ; // closed deal
            var login_user_ids = userService.get_login_userids() ;
            if (gift.direction == 'giver') {
                if ($(login_user_ids).filter(gift.giver_user_ids).length > 0) return false ; // login user(s) is giver
            }
            else {
                if ($(login_user_ids).filter(gift.receiver_user_ids).length > 0) return false ; // login user(s) is receiver
            }
            return true ;
        }

        // new gift default values
        function init_new_gift () {
            self.new_gift = {
                direction: 'giver',
                currency: userService.get_currency(),
                file_upload_title: function () {
                    if (userService.is_logged_in()) return I18n.t('js.new_gift.file_title_true', {appname: appname}) ;
                    else return I18n.t('js.new_gift.file_title_false', {appname: appname}) ;
                },
                show: function () {
                    var currency = userService.get_currency() ;
                    // console.log('currency = ' + JSON.stringify(currency)) ;
                    return (currency != null) ; // logged in with one or more login providers?
                }
            }
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
        }

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
            var pgm = 'GiftsCtrl.create_new_gift: ' ;
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
            giftService.sync_gifts() ;
            giftService.unshift_gift(gift) ;
            // resize description textarea after current digest cycle is finish
            resize_textarea(gift.description) ;
            // reset new gift form
            init_new_gift() ;
            // update gifts in local storage - now with created gift in first row
            giftService.save_gifts() ;
        } // self.create_new_gift

        // new comment ng-submit
        self.create_new_comment = function (gift) {
            var pgm = 'GiftsCtrl.create_new_comment: ' ;
            // console.log(pgm + (gift.comments || []).length + ' comments before refresh') ;
            giftService.refresh_gift(gift) ;
            // console.log(pgm + (gift.comments || []).length + ' comments after refresh') ;
            // $window.alert(pgm + 'gift = ' + JSON.stringify(gift) + ', new_comment = ' + JSON.stringify(gift.new_comment)) ;
            if (typeof gift.comments == 'undefined') gift.comments = [] ;
            var new_comment = {
                cid: Gofreerev.get_new_uid(),
                user_ids: userService.get_login_userids(),
                comment: gift.new_comment.comment,
                price: gift.new_comment.price,
                currency: userService.get_currency(),
                created_at_client: Gofreerev.unix_timestamp(),
                new_deal: gift.new_comment.new_deal
            } ;
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
            giftService.save_gifts() ;
        } // create_new_comment

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
        }
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
        }
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
        }
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
                if (!created_at_client) {
                    // fix data migration error (date renamed to created_at_client). todo: remove
                    console.log('formatGiftLinkText: gift = ' + JSON.stringify(gift)) ;
                    gift.created_at_client = Math.round((new Date).getTime()/1000) ;
                    giftService.save_gifts() ;
                }
                var optional_price = formatGiftPriceOptional(gift, precision);
                var direction = formatDirection(gift) ;
                return I18n.t('js.gifts.gift_link_text', {date: created_at_client, optional_price: optional_price, direction: direction }) ;
            }
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
        }
        // end formatGiftDescription
    }])
    .filter('formatBalance', [function () {
        return function (balance) {
            if (typeof balance == 'undefined') return '' ;
            if (balance == null) return '' ;
            // todo 1: format user balance. hash with currencies and amounts
            // todo 2: server side or client side balance calculation?
            return JSON.stringify(balance) ;
        }
        // end formatBalance
    }])
    .filter('formatUserImgTitle', ['formatBalanceFilter', 'UserService', function (formatBalance, userService) {
        return function (user_ids) {
            var pgm = 'GiftsCtrl.formatUserImgTitle: ' ;
            // format mouseover title in user <div><img> tags in gifts/index page etc
            // console.log(pgm + 'user_ids = ' + JSON.stringify(user_ids)) ;
            // console.log(pgm + 'typeof user_ids = ' + (typeof user_ids)) ;
            if ((typeof user_ids == 'undefined') || (user_ids == null) || (user_ids.length == 0)) return null ;
            var user = userService.get_closest_user(user_ids);
            if (!user) {
                // user(s) not found in users array
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
            }
            var key = 'js.user_div.title_' + (keys[user.friend] || 'non_friend');
            // translate
            var username = (user.friend <= 2) ? user.short_user_name : user.user_name;
            var apiname = user.provider;
            var balance = formatBalance(user.balance);
            return I18n.t(key, {username: username, apiname: apiname, balance: balance});
        }
        // end formatUserImgTitle
    }])
    .filter('formatUserImgSrc', ['UserService', function (userService) {
        return function (user_ids) {
            // format scr in user <div><img> tags in gifts/index page etc (giver, receiver and user that has commented gifts)
            var pgm = 'formatUserImgSrc: ' ;
            // console.log(pgm + 'user_ids = ' + JSON.stringify(user_ids)) ;
            if ((typeof user_ids == 'undefined') || (user_ids == null) || (user_ids.length == 0)) return '/images/invisible-picture.gif' ;
            var user = userService.get_closest_user(user_ids);
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
        }
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
        }
        // end formatComment filter
    }])
    .filter('formatNewProposalTitle', ['UserService', function (userService) {
        return function (gift) {
            var pgm = 'GiftsCtrl.formatNewProposalTitle: gid = ' + gift.gid + '. ' ;
            // see also GiftsCtrl.show_new_deal_checkbox
            if (gift.direction == 'both') {
                // console.log(pgm + 'error. invalid direction') ;
                return '' ;
            }
            var login_user_ids = userService.get_login_userids() ;
            // console.log(pgm + 'login_user_ids = ' + login_user_ids) ;
            var other_user_ids ;
            if (gift.direction == 'giver') other_user_ids = $(login_user_ids).not(gift.giver_user_ids) ;
            else other_user_ids = $(login_user_ids).not(gift.receiver_user_ids) ;
            if (other_user_ids.length == 0) {
                // console.log(pgm + 'error. other_user_ids.length = 0') ;
                return '' ;
            }
            var other_user_id = other_user_ids[0] ;
            var other_user = userService.get_user(other_user_id) ;
            // console.log(pgm + 'other_user_id = ' + JSON.stringify(other_user_id)) ;
            // console.log(pgm + 'other_user = ' + JSON.stringify(other_user)) ;
            if (!other_user) {
                console.log(pgm + 'error. other user with user id ' + other_user_id + ' does not exists') ;
                return '' ;
            }
            var title = I18n.t('js.new_comment.proposal_title', {username: other_user.short_user_name}) ;
            // console.log(pgm + 'gid = ' + gift.gid + ', title = ' + JSON.stringify(title)) ;
            return title ;
        }
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
            var a = '<a href="' + href + '" title="' + link_title + '">' + apiname + '<a>'
            return $sce.trustAsHtml(a);
        }
        // end formatInviteFriendsLink filter
    }])
    .filter('formatProviderName', [function() {
        var appname = Gofreerev.rails['APP_NAME'] ;
        var providers = Gofreerev.rails['API_CAMELIZE_NAME'] ;
        return function (provider) {
            return (providers[provider] || appname) ;
        }
        // end formatProviderName filter
    }])
    .filter('formatProviderSrc', [function () {
        return function (provider) {
            return '/images/' + (provider || 'gofreerev') + '.png';
        }
        // end formatProviderSrc filter
    }])
    .filter('formatProviderTraficLightSrc', ['UserService', function (userService) {
        return function (trafic_light_status) {
            return '/images/' + trafic_light_status + '.png';
        }
        // end formatProviderTraficLightSrc filter
    }])
    .filter('formatLoginSrc', [function () {
        return function (logged_in) {
            if (logged_in) return '/images/invisible-picture.gif' ;
            else return '/images/connect.png' ;
        }
        // end formatLoginSrc filter
    }])
    .filter('formatLogoutSrc', [function () {
        return function (logged_out) {
            if (logged_out) return '/images/invisible-picture.gif' ;
            else return '/images/disconnect.png' ;
        }
        // end formatLogoutSrc filter
    }])
    .filter('formatProviderLogoutSrc', ['UserService', function (userService) {
        return function (provider) {
            if (userService.is_logged_in_with_provider(provider.provider)) return '/images/disconnect.png';
            else return '/images/invisible-picture.gif';
        }
        // end formatProviderLogoutSrc filter
    }])
    .filter('formatProviderLoginHref', ['UserService', function (userService) {
        return function (provider) {
            return '/auth/' + provider.provider ;
        }
        // end formatProviderLoginHref filter
    }])
    .filter('formatProviderHomeUrl', [function () {
        return function (provider) {
            return Gofreerev.rails['API_URL'][provider.provider] ;
        }
        // end formatProviderHomeUrl filter
    }]) ;
