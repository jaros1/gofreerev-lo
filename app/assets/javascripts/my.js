// some global JS variables - see app layout and shared/show_more_rows partial
// var debug_ajax, get_more_rows_interval, get_more_rows_table ;


// allow running ajax to complete before leaving page / executing new http request
// http://stackoverflow.com/questions/1906023/jquery-ajaxerror-handler-fires-if-user-leaves-page-before-page-finishes-loadin
// todo: this solution gives a nice message when user clicks on a http link (leaving page). It could be nice with a solution that also gives a nice message for ajax request (not leaving page).
var ajaxing ;
$(document).ajaxStart(function() {
    ajaxing = true;
});
$(document).ajaxStop(function() {
    ajaxing = false;
});
var leaving_page = false ;
$(document).ready(function () {
    leaving_page = false ;
});
window.onbeforeunload = function() {
    if (typeof(ajaxing) != 'undefined' && ajaxing) {
        // Waiting for some finish some unfinished business to finish. Please wait.
        // todo: second click re-flash effect not working
        if (leaving_page) ajax_flash_new_table_rows('tasks_errors', 1) ;
        else add_to_tasks_errors(I18n.t('js.general.ajax_leave_page', {location: 1, debug: 0})) ;
    }
    leaving_page = true;
}

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

//// freeze user_currency when user enters text for new gift (auto submit when currency changes)
//function gifts_index_disabled_user_currency() {
//    var currency_id;
//    currency_id = document.getElementById('user_currency');
//    alert('gifts_index_disabled_user_currency, isDisabled = ' + currency_id.isDisabled);
//
//    currency_id.disabled = true;
//    var field_id;
//    field_id = document.getElementById('gift_price');
//    if (field_id.value != '') {
//        currency_id.disabled = true;
//        return
//    }
//    field_id = document.getElementById('gift_description');
//    if (field_id.value != '') {
//        currency_id.disabled = true;
//        return
//    }
//    field_id = document.getElementById('gift_file');
//    if (field_id.value != '') {
//        currency_id.disabled = true
//    }
//} // gifts_index_disabled_user_currency


// functions used in page header. Update user currency and return to current page
function default_pre_update_currency() {
    // use this function to check for other pending changes in currency page before submit
    // eg a confirm popup or maybe copy not saved information to hidden variables in update_currency_form before submit
    return true; // continue
    return false; // stop
} // default_pre_update_currency
pre_update_currency = default_pre_update_currency ;
function update_currency(self) {
    // check if submit is ok (are there other unsaved data in page?)
    var user_currency_old_id;
    user_currency_old_id = document.getElementById('user_currency_old');
    if (!pre_update_currency()) {
        // unsaved pending data - abort currency change
        self.value = user_currency_old_id.value ;
        return;
    }
    // get selected currency
    var user_currency_new;
    var update_currency_div_id;
    var update_currency_form_id;
    var user_currency_id;
    user_currency_new = self.value;
    // copy selected currency to hidden form and submit
    update_currency_div_id = document.getElementById('update_currency_div');
    update_currency_form_id = update_currency_div_id.getElementsByTagName('Form')[0];
    user_currency_id = document.getElementById('user_new_currency');
    user_currency_id.value = user_currency_new;
    update_currency_form_id.submit();
} // update_currency_submit

// Version of pre_update_currency to be used in gifts controller pages
var pending_gift_msg = 'Update currency?';
function gifts_pre_update_currency() {
    // get selected currency
    var user_currency_new_id;
    var user_currency_new;
    var update_currency_div_id;
    var update_currency_form_id;
    var user_currency_id;
    user_currency_new_id = document.getElementById('user_currency_new');
    user_currency_new = user_currency_new_id.value;
    if (user_currency_new == '<%= @users.first.currency %>') return false;
    // check for pending new gift
    var pending_data = false;
    field_id = document.getElementById('gift_price');
    if (field_id.value != '') pending_data = true;
    field_id = document.getElementById('gift_description');
    if (field_id.value != '') pending_data = true;
    field_id = document.getElementById('gift_file');
    if (field_id.value != '') pending_data = true;
    if (!pending_data) return true; // no pending gift
    // confirm box
    return (confirm(pending_gift_msg));
} // gifts_pre_update_currency()


// Client side validations
// https://github.com/bcardarella/client_side_validations gem was not ready for rails 4 when this app was developed
function csv_empty_field (id)
{
    var value = document.getElementById(id).value ;
    if (!value) return true ;
    if ($.trim(value) == '') return true ;
    return false ;
} // csv_required_field

// Check price - allow decimal comma/point, max 2 decimals. Thousands separators not allowed
// used for price in gift and comment
// should be identical to ruby function invalid_price? in application controller
function csv_invalid_price (id)
{
    var pgm = 'csv_invalid_price: ' ;
    if (csv_empty_field(id)) return false ; // empty field - ok
    var price = document.getElementById(id).value ;
    // add2log(pgm + 'id = ' + id + ', price = ' + price) ;
    price = $.trim(price);
    var r = /^[0-9]*((\.|,)[0-9]{0,2})?$/ ;
    // add2log('price = ' + price + ', r = ' + r + ', r.test(price) = ' + r.test(price)) ;
    if (!r.test(price) || (price == '.') || (price == ',')) return true ;
    return false ;
} // csv_invalid_price

// Client side validation for new gift
function csv_gift() {
    // ie fix. check if submit bottom has been disabled
    var submit_buttons = document.getElementsByName('commit_gift') ;
    add2log('submit_buttons.length = ' + submit_buttons.length) ;
    for (var i=0 ; i< submit_buttons.length ; i++) {
        add2log('csv_gift: submit_buttons[' + i + '].disabled = ' + submit_buttons[i].disabled) ;
        if (submit_buttons[i].disabled) {
            // ie8 fix - submit new gift must be in progress - ignore
            add2log('csv_gift: ie8 fix - submit new gift must be in progress - ignore click') ;
            return false ;
        }
    }

    // check required description
    if (csv_empty_field('gift_description')) {
        alert(I18n.t('js.gifts.description_required_text'));
        return false;
    }
    // check optional price. Allow decimal comma/point, max 2 decimals. Thousands separators not allowed
    if (csv_invalid_price('gift_price')) {
        alert(I18n.t('js.gifts.price_invalid_text'));
        return false;
    }
    // gift is ok. ready for submit

    // clear any old (error) messages in page header
    clear_flash_and_ajax_errors() ;

    if (!Modernizr.meter) return true; // process bar not supported
    var progressbar_div = document.getElementById('progressbar-div') ;
    if (!progressbar_div) return true ; // no progressbar found in page

    progressbar_div.style.display = 'block';
    // start upload process bar
    // http://www.hongkiat.com/blog/html5-progress-bar/
    var progressbar = $('#progressbar'),
        max = progressbar.attr('max'),
        time = (1000 / max) * 5,
        value = 0;

    var loading = function () {
        value += 3;
        addValue = progressbar.val(value);

        $('.progress-value').html(value + '%');

        if (value >= max) {
            clearInterval(animate);
            progressbar_div.style.display = 'none';
        }
    };

    var animate = setInterval(function () {
        loading();
    }, time);

    return true;
} // csv_gift


// Client side validation for new comment
function csv_comment(giftid)
{
    // ie fix. check if submit bottom has been disabled
    if (is_comment_submit_disabled(giftid)) return false ;
    // check required comment
    if (csv_empty_field("gift-" + giftid + "-comment-new-textarea")) {
        alert(I18n.t('js.gifts.comment_comment_required_text'));
        return false;
    }
    // check optional price. Allow decimal comma/point, max 2 decimals. Thousands separators not allowed
    if (csv_invalid_price('gift-' + giftid + '-comment-new-price')) {
        alert(I18n.t('js.gifts.comment_price_invalid_text'));
        return false;
    }
    // comment is ok - add post ajax handler and submit
    var table_id = 'gift-' + giftid + '-comment-new-errors' ;
    var table = document.getElementById(table_id) ;
    if (table) clear_ajax_errors(table_id) ;
    clear_flash_and_ajax_errors() ;
    post_ajax_add_new_comment_handler(giftid) ;
    // comment_submit_disable(giftid);
    return true ;
} // csv_comment

// prevent double comment submit
function comment_submit_disable (giftid) {
    add2log('comment_submit_disable: disabling submit for gift id. ' + giftid) ;
    var submit_id, submit ;
    for (var i=1 ; i<= 2 ; i++) {
        submit_id = "gift-" + giftid + "-comment-new-submit-" + i ;
        submit = document.getElementById(submit_id) ;
        if (submit) submit.disabled = true ;
    }
} // comment_submit_disable
function is_comment_submit_disabled (giftid) {
    add2log('is_comment_submit_disabled: checking if submit is disabled') ;
    var submit_id, submit ;
    for (var i=1 ; i<= 2 ; i++) {
        submit_id = "gift-" + giftid + "-comment-new-submit-" + i ;
        submit = document.getElementById(submit_id) ;
        if (submit && submit.disabled) return true ;
    }
    return false ;
} // is_comment_submit_disabled
function comment_submit_enable (giftid) {
    add2log('comment_submit_enable: enabling submit for gift id. ' + giftid) ;
    var submit_id, submit ;
    for (var i=1 ; i<= 2 ; i++) {
        submit_id = "gift-" + giftid + "-comment-new-submit-" + i ;
        submit = document.getElementById(submit_id) ;
        if (submit) submit.disabled = false ;
    }
} // comment_submit_enable

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

// ajax flash for row table rows - for example new rows in ajax_task_errors table
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

// long gift description is hidden inside div with max-height and overflow
// show-more-text link under text is used to remove max-height from div (show full text)
// find_overflow is called at startup, after show-more-rows and after ajax injecting new or changed gifts into page
// class overflow is used to identify text and link in web page
// expects id <key>-text and <key>-link ( id="gift-1298-overflow-text" and id="gift-1298-overflow-link" )
// class "wrapword" is used for text. word-break: break-all is used.
// word-break: break-all works best on small width screens but not on wide screens
// but it is hard to find a solution that looks good on all devices

// show full text for div with overflow
function show_overflow(overflow_link) {
    var pgm = 'show_overflow: ' ;
    overflow_link = overflow_link.parentNode ;
    var link_id = overflow_link.id ;
    if (!link_id) {
        add2log(pgm + 'overflow link without id') ;
        return false ;
    }
    var link_id_split = link_id.split('-') ;
    var pos = link_id_split.length-1 ;
    if (link_id_split[pos] != 'link') {
        add2log(pgm + 'overflow link id ' + link_id + ' is invalid') ;
        return false ;
    } // error - id should be gift-<nnn>-overflow-link
    link_id_split[pos] = 'text' ;
    var text_id = link_id_split.join('-') ;
    var overflow_text = document.getElementById(text_id) ;
    if (!overflow_text) {
        add2log(pgm + 'overflow text id ' + text_id + ' was not found') ;
        return false ;
    } // error - overflow text was not found
    // var tempScrollTop = $(window).scrollTop();
    // add2log(pgm + 'empScrollTop = ' + tempScrollTop) ;
    overflow_link.display = 'none' ;
    overflow_text.style.maxHeight = 'none' ;
    overflow_text.style.overflow = 'visible' ;
    overflow_link.style.display = 'none' ;
    // $(window).scrollTop(tempScrollTop);
    return false ;
} // show_overflow

// find div with overflow - show link
// opera 12 fix for missing word-break=break-all support-
// insert soft hyphen in div text - expects format link + text
function hyphenate_div (div) {
    var pgm = 'find_overflow: ' ;
    var shy_div = document.createElement('DIV') ;
    shy_div.innerHTML = '&shy;' ;
    var shy = shy_div.innerHTML ;
    var innerHTML = div.innerHTML ;
    if (innerHTML.indexOf(shy) != -1) return ;
    var pos = innerHTML.indexOf('</a>') ; // expected format: link + text
    // add2log(pgm + 'pos = ' + pos) ;
    var link, text ;
    if (pos == -1) {
        link = '' ;
        text = innerHTML ;
    }
    else if (pos + 4 == innerHTML.length) return ;
    else {
        link = innerHTML.substr(0, pos+4) ;
        text = innerHTML.substr(pos+4) ;
    }
    text = text.split('').join(shy) ;
    div.innerHTML = link + text ;
} // hyphenate_div

// find div with hidden overflow - display show-more-text link
function find_overflow () {
    var pgm = 'find_overflow: ' ;
    // fix for old browsers that does not support word break = break all (opera 12).
    var hyphenate = false ;
    if (navigator.userAgent.indexOf('Opera/9.80') != -1) hyphenate = true ;
    if (hyphenate) add2log(pgm + 'hyphenate text (opera 12)') ;
    var shy_div = document.createElement('DIV') ;
    shy_div.innerHTML = '&shy;' ;
    var shy = shy_div.innerHTML ;
    // find overflow texts and links in page - one array with texts - one array with hidden links
    var divs ;
    if (document.getElementsByClassName) divs = document.getElementsByClassName('overflow') ;
    else if (document.querySelectorAll) divs = document.querySelectorAll('.overflow') ;
    else return ; // IE8 running in compatibility mode - ignore div overflow
    var overflow_link = {} ;
    var overflow_text = {} ;
    var div, id, id_split, id_type, key, key, div_type ;
    for (var i=0 ; i<divs.length ; i++) {
        div = divs[i] ;
        id = div.id ;
        id_split = id.split('-') ;
        div_type = id_split.pop() ;
        key = id_split.join('-') ;
        if (div_type == 'text') overflow_text[key] = i ;
        else if (div_type == 'link') {
            if (div.style.display == 'none') overflow_link[key] = i ;
        }
        else add2log(pgm + 'invalid overflow id ' + id) ;
    } // i
    // fix word break = break all in old browser (opera 12) - insert soft hyphen in text
    if (hyphenate) {
        for (key in overflow_text) {
            text = divs[overflow_text[key]] ;
            if (text.innerHTML.indexOf(shy) == -1) {
                // add2log(pgm + 'key = ' + key + ', hyphenate ' + text.children.length + ' children') ;
                hyphenate_div(text) ;
            }
        }
    }
    // check for vertical hidden overflow - display show-more-text link if overflow
    var text, link, text_max_height ;
    var screen_width = (document.width !== undefined) ? document.width : document.body.offsetWidth;
    var screen_width_factor = screen_width / 320.0 ;
    if (screen_width_factor < 1) screen_width_factor = 1 ;
    // add2log('screen_width = ' + screen_width + ', screen_width_factor = ' + screen_width_factor) ;
    var skip_keys = [] ;
    for (key in overflow_link) {
        // add2log(pgm + 'key = ' + key + ', text = ' + overflow_text[key] + ', link = ' + overflow_link[key]) ;
        text = divs[overflow_text[key]] ;
        if (!text) {
            add2log(pgm + 'error. overflow text with key ' + key + ' was not found.') ;
            continue ;
        }
        link = divs[overflow_link[key]] ;
        if (!link) {
            add2log(pgm + 'error. overflow link with key ' + key + ' was not found.') ;
            continue ;
        }
        if (!text.style.maxHeight) {
            add2log(pgm + 'error. found overflow text key ' + key + ' without maxHeight') ;
            continue ;
        }
        text_max_height = parseInt(text.style.maxHeight) ;
        // add2log(pgm + 'key = ' + key + ', text.style.maxHeight = ' + text_max_height +
        //        ', text.client height = ' + text.clientHeight + ', text.scroll height = ' + text.scrollHeight +
        //        ', link.style.display = ' + link.style.display) ;
        if (text.scrollHeight * screen_width_factor < text_max_height) {
            // small text - overflow is not relevant - skip in next call
            skip_keys.push(key) ;
            continue ;
        }
        if (text.scrollHeight <= text.clientHeight) continue ; // not relevant with actual screen width
        // show link
        link.style.display = '' ;
        skip_keys.push(key) ;
    } // key
    // blank overflow class for text and links not to check next call (show-more-rows request)
    // add2log('skip_keys = ' + skip_keys.join(', ')) ;
    for (i=0 ; i<skip_keys.length ; i++) {
        key = skip_keys[i] ;
        text = document.getElementById(key + '-text') ;
        if (text) text.className = '' ;
        else add2log(pgm + 'error. key ' + key + '-text was not found') ;
        link = document.getElementById(key + '-link') ;
        if (link) link.className = '' ;
        else add2log(pgm + 'error. key ' + key + '-link was not found') ;
    } // key
} // find_overflow

$(document).ready(function() {
    find_overflow () ;
})



// check for new messages once every 15, 60 or 300 seconds
// once every 15 seconds for active users - once every 5 minutes for inactive users
// onclick event on remote link new_messages_count_link
var check_new_messages_interval ; // interval in seconds between each new messages check
var check_new_messages_interval_id ; // interval id for setInterval function
var last_user_ajax_comment_at ; // timestamp (JS Date) for last new comment created by user

function calculate_new_messages_interval()
{
    var difference ;
    // how often should client check for new messages?
    if (!last_user_ajax_comment_at)
        check_new_messages_interval = 300 ;
    else {
        difference = ((new Date).getTime() - last_user_ajax_comment_at.getTime()) / 1000 ;
        if (difference < 120) check_new_messages_interval = 15 ;
        else if (difference > 600) check_new_messages_interval = 300 ;
        else check_new_messages_interval = 60  ;
    }
    return check_new_messages_interval ;
} // calculate_new_messages_interval

function start_check_new_messages()
{
    $(document).ready(
        function () {
            var interval = calculate_new_messages_interval() ;
            check_new_messages_interval_id = setInterval(function () {
                // call util/new_messages_count and insert response in new_messages_buffer_div in page header
                // information about number off unread messages
                // + new gifts to be inserted in top of page gifts/index page
                // + new comments to be inserted in gifts/index page
                // + todo: changed gifts and comments to be replaced in gifts/index page
                // is post ajax processed in #new_messages_count_link::ajax:success event handler
                // (update_new_messages_count, update_title, insert_new_comments and insert_update_gifts)
                var check_new_messages_link = document.getElementById("new_messages_count_link");
                // update newest_gift_id and newest_status_update_at before ajax request.
                // only newer gifts (>newest_gift_id) are ajax inserted in gifts/index page
                // only gifts and comments with > newest_status_update_at are ajax replaced into gifts/index page
                // update newest_gift_id
                var newest_gift_id = document.getElementById("newest-gift-id");
                var newest_gift_id_new_value ;
                if (newest_gift_id && (newest_gift_id.value != '')) newest_gift_id_new_value = newest_gift_id.value ;
                else newest_gift_id_new_value = '0' ;
                var href = check_new_messages_link.href ;
                href = href.replace(/newest_gift_id=[0-9]+/, 'newest_gift_id=' + newest_gift_id_new_value) ;
                // update newest_status_update_at
                var newest_status_update_at = document.getElementById("newest-status-update-at");
                var newest_status_update_at_new_value ;
                if (newest_status_update_at && (newest_status_update_at.value != '')) newest_status_update_at_new_value = newest_status_update_at.value ;
                else newest_status_update_at_new_value = '0' ;
                // replace and click => ajax request to util/new_messages_count => update page
                href = href.replace(/newest_status_update_at=[0-9]+/, 'newest_status_update_at=' + newest_status_update_at_new_value) ;
                check_new_messages_link.href = href ;
                check_new_messages_link.click();
            }, interval * 1000);
        });
} // start_check_new_messages


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



// new_messages_count ajax event handlers
// ajax:error - catch server side errors
// ajax:success - catch any errors in post ajax JS code
$(document).ready(function() {
    var id = "#new_messages_count_link" ;
    var pgm ;
    $(id).unbind("ajax:error") ;
    $(id).bind("ajax:error", function(jqxhr, textStatus, errorThrown){
        pgm = id + '::ajax:error: ' ;
        try {
            if (leaving_page) return ;
            var err = add2log_ajax_error(pgm, jqxhr, textStatus, errorThrown) ;
            add_to_tasks_errors(I18n.t('js.new_messages_count.ajax_error', {error: err, location: 2, debug: 0})) ;
        }
        catch (err) {
            add2log(pgm + 'failed with JS error: ' + err) ;
            add_to_tasks_errors(I18n.t('js.new_messages_count.js_error', {error: err, location: 3, debug: 0})) ;
        }
    }) // ajax:error
    $(id).unbind("ajax:success");
    $(id).bind("ajax:success", function (evt, data, status, xhr) {
        pgm = id + '::ajax:success: ' ;
        try {update_new_messages_count() }
        catch (err) {
            add2log(pgm + 'update_new_messages_count failed: ' + err) ;
            add_to_tasks_errors(I18n.t('js.new_messages_count.js_error', {error: err, location: 4, debug: 1})) ;
            return ;
        }
        try { update_title() }
        catch (err) {
            add2log(pgm + 'update_title failed: ' + err) ;
            add_to_tasks_errors(I18n.t('js.new_messages_count.js_error', {error: err, location: 4, debug: 2})) ;
            return ;
        }
        try { insert_new_comments() }
        catch (err) {
            add2log(pgm + 'insert_new_comments failed: ' + err) ;
            add_to_tasks_errors(I18n.t('js.new_messages_count.js_error', {error: err, location: 4, debug: 3})) ;
            return ;
        }
        try { insert_update_gifts() }
        catch (err) {
            add2log(pgm + 'insert_update_gifts failed: ' + err) ;
            add_to_tasks_errors(I18n.t('js.new_messages_count.js_error', {error: err, location: 4, debug: 4})) ;
            return ;
        }
        try { show_more_rows_scroll() }
        catch (err) {
            add2log(pgm + 'show_more_rows_scroll failed: ' + err) ;
            add_to_tasks_errors(I18n.t('js.new_messages_count.js_error', {error: err, location: 4, debug: 5})) ;
            return ;
        }
    }); // ajax:success
})



function restart_check_new_messages()
{
    var old_check_new_messages_interval = check_new_messages_interval ;
    var new_check_new_messages_interval = calculate_new_messages_interval() ;
    if (check_new_messages_interval_id && (old_check_new_messages_interval == new_check_new_messages_interval)) return ; // no change
    if (check_new_messages_interval_id) clearInterval(check_new_messages_interval_id);
    check_new_messages_interval_id = null ;
    start_check_new_messages() ;
} // restart_check_new_messages
// do it
start_check_new_messages() ;


// 3. functions used in util/new_messages_count ajax call.

// update new message count in page header +  insert new comments in page
function update_new_messages_count() {
    // restart setInterval function if refresh period has changed
    var pgm = 'update_new_messages_count: ' ;
    restart_check_new_messages() ;
    var new_messages_count_div = document.getElementById("new_messages_count_div");
    if (!new_messages_count_div) {
        add2log(pgm + 'new_messages_count_div not found') ;
        return;
    }
    // responsive layout - two page header layouts - two new message count divs
    var new_messages_count = document.getElementById("new_messages_count1");
    if (new_messages_count) new_messages_count.innerHTML = new_messages_count_div.innerHTML
    var new_messages_count = document.getElementById("new_messages_count2");
    if (new_messages_count) new_messages_count.innerHTML = new_messages_count_div.innerHTML
}
// update_new_messages_count in page title - displayed in process line on desktop computers
function update_title() {
    var pgm = 'update_title: ' ;
    var new_messages_count_div = document.getElementById("new_messages_count_div");
    if (!new_messages_count_div) {
        add2log(pgm + 'new_messages_count_div not found') ;
        return;
    }
    var no_new_messages = new_messages_count_div.innerHTML ;
    if (no_new_messages == '')
        var new_title = 'Gofreerev';
    else
        var new_title = '(' + no_new_messages + ') Gofreerev';
    document.title = new_title;
} // update_title

function insert_new_comments() {
    var pgm = 'insert_new_comments: ' ;
    var debug = 0 ;
    try {
        var new_comments_tbody, new_comments_trs, new_comment_tr, new_comment_id, new_comment_id_split, new_comment_gift_id, new_comment_comment_id;
        var old_comments_tbody_id, old_comments1_tbody, old_comments1_trs, old_comments1_tr, old_comments1_tr_id;
        var i, j, old_comments2_trs, old_comments2_tr, re1, re2, old_length, old_comments2_length, old_comments2_tr_id;
        var old_comments2_comment_id, inserted, old_comments2_tr_id_split, new_comments_length;
        var summary ; // for debug info.
        var gifts, old_comments2_add_new_comment_tr ;
        add2log(pgm + 'start') ;
        debug = 10 ;
        gifts = document.getElementById("gifts") ;
        if (!gifts) {
            // no gifts table - not gifts/index page
            add2log(pgm + 'no gifts table - not gifts/index page') ;
            return ;
        }
        new_comments_tbody = document.getElementById("new_comments_tbody");
        if (!new_comments_tbody) {
            // add2log(pgm + 'new_comments_tbody was not found');
            // ok - no new comments in new_messages_count response
            return; // ignore error silently
        }
        new_comments_trs = new_comments_tbody.rows;
        new_comments_length = new_comments_trs.length ;
        if (new_comments_length == 0) {
            // no new comments
            add2log(pgm + 'no new comments') ;
            return;
        }
        // old_comments1_tbody = old_comments1_trs[0].parentNode ;
        old_comments1_tbody = document.getElementById("gifts_tbody");
        if (!old_comments1_tbody) {
            // missing tbody or tbody without correct id gifts_tbody
            add2log(pgm + 'gifts_tbody was not foound') ;
            return
        }
        // find old gift rows (gift header, gift links, comments, gift footers)
        old_comments1_trs = old_comments1_tbody.rows ;
        if (old_comments1_trs.length == 0) {
            // no old gifts
            add2log(pgm + 'no old gifts') ;
            return
        }

        // insert new comments in gifts/index page. Loop for each new comment.
        summary = 'Summary. ' +  new_comments_length + ' messages received' ;
        re1 = new RegExp("^gift-[0-9]+-comment-[0-9]+$") ;
        debug = 20 ;
        for (i=new_comments_length-1; i >= 0 ; i--) {
            // find gift id and comment id. id format format: gift-218-comment-174
            debug = 30 ;
            new_comment_tr = new_comments_trs[i];
            new_comment_id = new_comment_tr.id;
            if (!new_comment_id || !new_comment_id.match(re1)) {
                add2log(pgm + 'invalid id format ' + new_comment_id) ;
                continue ;
            }
            new_comment_id_split = new_comment_id.split("-");
            new_comment_gift_id = new_comment_id_split[1];
            new_comment_comment_id = parseInt(new_comment_id_split[3]);
            summary = summary + '. ' + i + ', id = ' + new_comment_id ;
            summary = summary + '. ' + i + ', split[3] = ' + new_comment_id_split[3] ;
            add2log(pgm + 'i = ' + i + ', gift id = ' + new_comment_gift_id + ', comment id = ' + new_comment_comment_id);
            debug = 40 ;
            // find any old comments with format gift-218-comment-174
            re2 = new RegExp("^gift-" + new_comment_gift_id + "-comment-[0-9]+$") ;
            old_comments2_trs = [];
            old_comments2_add_new_comment_tr = null ;
            old_length = old_comments1_trs.length;
            for (j = 0; j < old_length; j++) {
                old_comments1_tr = old_comments1_trs[j];
                old_comments1_tr_id = old_comments1_tr.id;
                if (old_comments1_tr_id.match(re2)) old_comments2_trs.push(old_comments1_tr);
                if (old_comments1_tr_id == "gift-" + new_comment_gift_id + "-comment-new") {
                    // add2log(pgm + 'Found gift-1625-comment-new') ;  // issue 149 debug
                    old_comments2_add_new_comment_tr = old_comments1_tr ;
                }
            } // end old comments loop
            debug = 50 ;
            if (!old_comments2_add_new_comment_tr) {
                // gift was not found - that is ok
                add2log(pgm + 'Gift ' + new_comment_gift_id + ' was not found') ;
                continue ;
            }
            debug = 51 ;
            old_comments2_length = old_comments2_trs.length;
            debug = 52 ;
            // add2log(pgm + 'old length = ' + old_length + ', new length = ' + new_length);
            if (old_comments2_length == 0) {
                // insert first comment for gift before add new comment row
                add2log(pgm + 'insert first comment for gift before add new comment row') ;
                debug = 53 ;
                new_comments_tbody.removeChild(new_comment_tr) ;
                // todo: opera 12 error ==>
                //   Javascript fejl ved indsættelse af nye kommentarer.
                //   NotFoundError: Failed to execute 'insertBefore' on 'Node':
                //   The node before which the new node is to be inserted is not a child of this node. (5,54).
                debug = 54 ;
                add2log(pgm + 'old_comments1_tbody = ' + old_comments1_tbody) ;
                debug = 55 ;
                add2log(pgm + 'new_comment_tr = ' + new_comment_tr) ;
                debug = 56 ;
                add2log(pgm + 'old_comments2_add_new_comment_tr = ' + old_comments2_add_new_comment_tr) ;
                debug = 57 ;
                // Firefox 30.0 error when ajax insert first comment for a gift
                // insert_new_comments: old_comments1_tbody              = [object HTMLTableSectionElement]
                // insert_new_comments: new_comment_tr                   = [object HTMLTableRowElement]
                // insert_new_comments: old_comments2_add_new_comment_tr = [object HTMLTableRowElement]
                // insert_new_comments: failed with JS error [Exception... "Node was not found" code: "8" nsresult: "0x80530008 (NotFoundError)" location: ""], debug = 57
                // #new_messages_count_link::ajax:success: insert_new_comments failed: [Exception... "Node was not found" code: "8" nsresult: "0x80530008 (NotFoundError)" location: ""]
                // Javascript error when inserting new comments. [Exception... "Node was not found" code: "8" nsresult: "0x80530008 (NotFoundError)" location: ""] (5,57).
                old_comments1_tbody.insertBefore(new_comment_tr, old_comments2_add_new_comment_tr);
                // todo: opera 12 error <==
                debug = 58 ;
                ajax_flash(new_comment_tr.id) ;
                debug = 59 ;
                add2log(pgm + 'First comment ' + new_comment_comment_id + ' for gift ' + new_comment_gift_id);
                continue;
            }
            debug = 60 ;
            // insert new comment in old comment table (sorted by ascending comment id)
            inserted = false;
            for (j = old_comments2_length-1; ((!inserted) && (j >= 0)); j--) {
                // find comment id for current row
                debug = 70 ;
                old_comments2_tr = old_comments2_trs[j];
                old_comments2_tr_id = old_comments2_tr.id;
                old_comments2_tr_id_split = old_comments2_tr_id.split('-') ;
                old_comments2_comment_id = parseInt(old_comments2_tr_id_split[3]);
                add2log('j = ' + j + ', new comment id = ' + new_comment_comment_id + ', old comment id = ' + old_comments2_comment_id);
                debug = 80 ;
                if (parseInt(new_comment_comment_id) > parseInt(old_comments2_comment_id)) {
                    // insert after current row
                    new_comments_tbody.removeChild(new_comment_tr) ;
                    old_comments2_tr.parentNode.insertBefore(new_comment_tr, old_comments2_tr.nextSibling);
                    ajax_flash(new_comment_tr.id) ;
                    inserted = true ;
                    summary = summary + '. ' + i + ': comment ' + new_comment_comment_id + ' inserted (b) for gift id ' + new_comment_gift_id  ;
                    continue;
                }
                debug = 90 ;
                if (new_comment_comment_id == old_comments2_comment_id) {
                    // new comment already in old comments table
                    // replace old comment with new comment
                    // add2log('comment ' + new_comment_comment_id + ' is already in page');
                    old_comments2_tr.id = "" ;
                    new_comments_tbody.removeChild(new_comment_tr) ;
                    old_comments2_tr.parentNode.insertBefore(new_comment_tr, old_comments2_tr.nextSibling);
                    ajax_flash(new_comment_tr.id) ;
                    old_comments2_tr.parentNode.removeChild(old_comments2_tr) ;
                    inserted = true;
                    summary = summary + '. ' + i + ': comment ' + new_comment_comment_id + ' inserted (c) for gift id ' + new_comment_gift_id  ;
                    continue;
                }
                // insert before current row - continue loop
            } // end old comments loop
            debug = 100 ;
            if (!inserted) {
                // insert before first old comment
                // add2log('insert new comment ' + new_comment_id + ' first in old comments table');
                old_comments2_tr = old_comments2_trs[0];
                add2log('old_comments2_tr = ' + old_comments2_tr) ;
                new_comments_tbody.removeChild(new_comment_tr) ;
                old_comments2_tr.parentNode.insertBefore(new_comment_tr, old_comments2_tr);
                ajax_flash(new_comment_tr.id) ;
                summary = summary + '. ' + i + ': comment ' + new_comment_comment_id + ' inserted (d) for gift id ' + new_comment_gift_id  ;
            } // if
        } // end new comments loop
        add2log(summary) ;
        // unbind and bind ajax for comment action links
        setup_comment_action_link_ajax() ;
    }
    catch (err) {
        add2log(pgm + 'failed with JS error ' + err + ', debug = ' + debug);
        add_to_tasks_errors(I18n.t('js.insert_new_comments.js_error', {error: err, location: 5, debug: debug})) ;
        throw err;
    }
} // insert_new_comments

// tasks_sleep: missing: no tasks - number: sleep (milliseconds) before executing tasks - for example post status on api walls
function insert_update_gifts (tasks_sleep)
{
    var pgm = 'insert_update_gifts: ' ;
    var debug ;
    try {
        debug = 10 ;
        add2log(pgm + 'start') ;
        // process ajax response received from new_messages_count ajax request
        // response has been inserted in new_messages_buffer_div in page header
        // also used after util/accept_new_deal to ajax replace gift

        // check/update newest_gift_id (id for latest created gift)
        debug = 20 ;
        var new_newest_gift_id = document.getElementById("new-newest-gift-id") ; // from new_messages_buffer_div
        if (!new_newest_gift_id) {
            // ok - not gifts/index page or no new/updated/deleted gifts
            add2log(pgm + 'new-newest-gift-id was not found') ;
            return ;
        }
        if  (new_newest_gift_id.value != "") {
            // util/new_message_count returned new newest giftid
            var newest_gift_id = document.getElementById("newest-gift-id") ;
            if (!newest_gift_id) {
                // error - hidden field was not found i gifts/index page - ignore error silently
                add2log(pgm + 'newest-gift-id as not found') ;
                return
            }
            newest_gift_id.value = new_newest_gift_id.value ;
        }

        // check/update newest_status_update_at (stamp for latest updated or deleted gift )
        debug = 30 ;
        var new_newest_status_update_at = document.getElementById("new-newest-status-update-at") ; // from new_messages_buffer_div
        if (!new_newest_status_update_at) {
            // ok - not gifts/index page or no new/updated/deleted gifts
            add2log(pgm + 'new-newest-status-update-at was not found') ;
            return ;
        }
        if  (new_newest_status_update_at.value != "") {
            // util/new_message_count returned new newest status_update_at
            var newest_status_update_at = document.getElementById("newest-status-update-at") ;
            if (!newest_status_update_at) {
                // error - hidden field was not found i gifts/index page - ignore error silently
                add2log(pgm + 'newest-status-update-at was not found') ;
                return
            }
            newest_status_update_at.value = new_newest_status_update_at.value ;
        }

        // check if new_messages_count response has a table with new gifts (new_messages_buffer_div in page header)
        debug = 40 ;
        var new_gifts_tbody = document.getElementById("new_gifts_tbody") ;
        if (!new_gifts_tbody) {
            // ok - not gifts/index page or no new gifts to error tbody with new gifts was not found
            add2log(pgm + 'new_gifts_tbody was not found') ;
            return ;
        }
        // find gift ids received in new_gifts_tbody table. Any existing old rows with these gift ids must be removed before inserting new rows
        var new_gifts_trs = new_gifts_tbody.rows ;
        var new_gifts_tr ;
        var new_gifts_id ;
        var new_gifts_gift_id ;
        var new_gifts_ids = [] ;
        var re = new RegExp('^gift-[0-9]+-') ;
        debug = 50 ;
        for (var i=0 ; i<new_gifts_trs.length ; i++) {
            debug = 51 ;
            new_gifts_id = new_gifts_trs[i].id ;
            debug = 52 ;
            if (new_gifts_id && new_gifts_id.match(re)) {
                debug = 53 ;
                new_gifts_gift_id = new_gifts_id.split('-')[1] ;
                debug = 54 ;
                if (new_gifts_ids.indexOf(new_gifts_gift_id) == -1) {
                    debug = 55 ;
                    new_gifts_ids.push(new_gifts_gift_id) ;
                }
            } // if
        } // for
        // alert('new_gifts_trs.length = ' + new_gifts_trs.length + ', new_gifts_ids = ' + new_gifts_ids.join(',')) ;
        // old page: find first gift row in gifts table. id format gift-220-header.
        // new gifts from ajax response are to be inserted before this row
        debug = 60 ;
        var old_gifts_table = document.getElementById("gifts_tbody") ;
        if (!old_gifts_table) {
            add2log(pgm + 'gifts_tbody was not found') ;
            return ;
        } // not gifts/index or gifts/show pages - ok
        var old_gifts_trs = old_gifts_table.rows ;
        var old_gifts_tr ;
        var old_gifts_id ;
        var old_gifts_gift_id ;
        debug = 70 ;
        if (new_gifts_ids.length > 0) {
            // remove any old gift rows found in new_gifts_ids array
            // will be replaced by new gift rows from new_messages_buffer_div
            for (i=old_gifts_trs.length-1 ; i>= 0 ; i--) {
                old_gifts_tr = old_gifts_trs[i] ;
                old_gifts_id = old_gifts_tr.id ;
                if (old_gifts_id && old_gifts_id.match(re)) {
                    old_gifts_gift_id = old_gifts_id.split('-')[1] ;
                    if (new_gifts_ids.indexOf(old_gifts_gift_id) != -1) {
                        // remove old row with gift id. old_gifts_gift_id from gifts table
                        old_gifts_tr.parentNode.removeChild(old_gifts_tr) ;
                    } // if
                } // if
            } // for
        } // if
        debug = 80 ;
        add2log(pgm + old_gifts_trs.length + ' gifts lines in old page') ;
        var old_gifts_index = -1 ;
        for (var i=0 ; ((old_gifts_index == -1) && (i<old_gifts_trs.length)) ; i++) {
            if (old_gifts_trs[i].id.match(re)) old_gifts_index = i ;
        } // for
        // add2log(pgm + 'old_gifts_index = ' + old_gifts_index) ;
        // check for first row to be inserted in gifts table - for example for a new gofreerev user
        debug = 90 ;
        if ((old_gifts_index == -1) && (old_gifts_trs.length >= 1) && (old_gifts_trs.length <= 2)) old_gifts_index = old_gifts_trs.length-1 ;
        // add2log(pgm + 'old_gifts_index = ' + old_gifts_index) ;
        if (old_gifts_index == -1) {
            // error - id with format gift-<999>-1 was not found - ignore error silently
            add2log(pgm + 'error - id with format gift-<999>- was not found') ;
            return ;
        }
        var first_old_gift_tr = old_gifts_trs[old_gifts_index] ;
        var old_gifts_tbody = first_old_gift_tr.parentNode ;
        // new gifts from ajax response are to be inserted before first_old_gift_tr
        debug = 100 ;
        for (i=new_gifts_trs.length-1 ; i>= 0 ; i--) {
            new_gifts_tr = new_gifts_trs[i] ;
            if (new_gifts_tr.id.match(re)) {
                // insert before "first_old_gift_tr" and move "first_old_gift_tr" to new inserted row
                new_gifts_tr.parentNode.removeChild(new_gifts_tr) ;
                old_gifts_tbody.insertBefore(new_gifts_tr, first_old_gift_tr) ;
                first_old_gift_tr = new_gifts_tr ;
                ajax_flash(first_old_gift_tr.id) ;
            } // if
        } // for
        // that's it

        debug = 110 ;
        add2log(pgm + 'call find_overflow') ;
        find_overflow();

        add2log(pgm + 'ajax_tasks_sleep = ' + tasks_sleep) ;
        if (!tasks_sleep) return ;
        // execute some more tasks - for example post status on api wall(s)
        debug = 120 ;
        trigger_tasks_form(tasks_sleep);
    }
    catch (err) {
        add2log(pgm + 'failed with JS exception ' + err + ', debug = ' + debug) ;
        add_to_tasks_errors(I18n.t('js.insert_update_gifts.js_error', {error: err, location: 6, debug: debug})) ;
        // throw err ;
    }
} //  insert_update_gifts

// catch load errors  for api pictures. Gift could have been deleted. url could have been changed
// gift ids with invalid picture urls are collected in a global javascript array and submitted to server in 2 seconds
// on error gift.api_picture_url_on_error_at is set and a new picture url is looked up if possible
// JS array with gift ids
var missing_api_picture_urls = [];
// function used in onload for img tags
function imgonload(img) {
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
    var api_gift_id ;
    if (img.dataset) api_gift_id = img.dataset.id ;
    else api_gift_id = img.getAttribute('data-id') ;
    add2log('imgonerror. api gift id = ' + api_gift_id + ', img.width = ' + img.width + ', img.height = ' + img.height +
        ', naturalWidth = ' + img.naturalWidth + ', naturalHeight = ' + img.naturalHeight + ', complete = ' + img.complete) ;
    missing_api_picture_urls.push(api_gift_id);
} // imgonerror


// function to report gift ids with invalid urls. Submitted in end of gifts/index page
function report_missing_api_picture_urls() {
    if (missing_api_picture_urls.length == 0) {
        // no picture urls to check
        add2log('report_missing_api_picture_urls: no picture urls to check') ;
        return;
    }
    // Report ids with invalid picture url
    // add2log('report_missing_api_picture_urls: sending api gift ids to server') ;
    var missing_api_picture_urls_local = missing_api_picture_urls.join();
    $.ajax({
        url: "/util/missing_api_picture_urls.js",
        type: "POST",
        dataType: 'script',
        data: { api_gifts: {ids: missing_api_picture_urls_local } },
        error: function (jqxhr, textStatus, errorThrown) {
            if (leaving_page) return ;
            var pgm = 'missing_api_picture_urls.error: ' ;
            var err = add2log_ajax_error('missing_api_picture_urls.ajax.error: ', jqxhr, textStatus, errorThrown) ;
            add_to_tasks_errors(I18n.t('js.missing_api_picture_urls.ajax_error', {error: err, location: 7, debug: 0})) ;
        }
    });
    missing_api_picture_urls = [];
} // report_missing_picture_urls

// enable ajax submit for new gifts in gifts/index page
$(document).ready(function () {
    var new_gift = document.getElementById('new_gift');
    if (!new_gift) return; // not gifts/index page
    // new_gift.action = '/gifts.js'; // ajax request
    // bind 'myForm' and provide a simple callback function
    // http://malsup.com/jquery/form/#options-object
    $('#new_gift').ajaxForm({
        type: "POST",
        dataType: 'script',
        beforeSubmit: function (formData, jqForm, options) {
            // add2log('#new_gift.beforeSubmit');
            var submit_buttons = document.getElementsByName('commit_gift') ;
            // add2log('submit_buttons.length = ' + submit_buttons.length) ;
            for (var i=0 ; i< submit_buttons.length ; i++) submit_buttons[i].disabled = true ;
        },
        success: function (responseText, statusText, xhr, $form) {
            var debug ;
            try{
                debug = 1 ;
                document.getElementById('progressbar-div').style.display = 'none';
                debug = 2 ;
                var gift_price = document.getElementById('gift_price');
                debug = 3 ;
                if (gift_price) gift_price.value = '';
                debug = 4 ;
                var gift_description = document.getElementById('gift_description');
                debug = 5 ;
                if (gift_description) {
                    gift_description.value = '';
                    autoresize_text_field(gift_description) ;
                }
                debug = 6 ;
                var gift_file = document.getElementById('gift_file');
                debug = 7 ;
                if (gift_file) gift_file.value = '';
                debug = 8 ;
                var disp_gift_file = document.getElementById('disp_gift_file');
                debug = 9 ;
                if (disp_gift_file) disp_gift_file.value = '';
                // clear open graph url and remove preview for open graph url
                debug = 9.1 ;
                var gift_open_graph_url = document.getElementById('gift_open_graph_url1') ;
                if (gift_open_graph_url) gift_open_graph_url.value = '' ;
                debug = 9.2 ;
                var gift_open_graph_url = document.getElementById('gift_open_graph_url2') ;
                if (gift_open_graph_url) gift_open_graph_url.value = '' ;
                debug = 9.3 ;
                var open_graph_url_preview = document.getElementById('open_graph_url_preview') ;
                if (open_graph_url_preview) {
                    debug = 9.4 ;
                    while (open_graph_url_preview.firstChild) {
                        open_graph_url_preview.removeChild(open_graph_url_preview.firstChild);
                    }
                }
                // first gift for a new gofreerev user - show gifts table - hide no api gift found message
                debug = 10 ;
                var gifts = document.getElementById('gifts');
                debug = 11 ;
                if (gifts) gifts.style.display = 'inline';
                debug = 12 ;
                var no_gifts_div = document.getElementById('no-gifts-div');
                debug = 13 ;
                if (no_gifts_div) no_gifts_div.style.display = 'none';
                // IE8 debug - JS code from create.js.erb is not executed
                debug = 14 ;
                var new_messages_buffer_div = document.getElementById('new_messages_buffer_div') ;
                debug = 15 ;
                add2log('new_messages_buffer_div = ' + new_messages_buffer_div.innerHTML) ;
            }
            catch (err) {
                var msg = '#new_gift.success failed with JS error: ' + err + ', debug = ' + debug ;
                add2log(msg);
                add_to_tasks_errors(I18n.t('js.new_gift.js_error', {error: err, location: 9, debug: debug})) ;
                return;
            }
        }, // success
        error: function (jqxhr, textStatus, errorThrown) {
            if (leaving_page) return ;
            document.getElementById('progressbar-div').style.display = 'none';
            var err = add2log_ajax_error('new_gift.ajax.error: ', jqxhr, textStatus, errorThrown) ;
            add_to_tasks_errors(I18n.t('js.new_gift.ajax_error', {error: err, location: 8, debug: 0})) ;
        },
        complete: function() {
            // add2log('#new_gift.complete');
            var submit_buttons = document.getElementsByName('commit_gift') ;
            // add2log('submit_buttons.length = ' + submit_buttons.length) ;
            for (var i=0 ; i< submit_buttons.length ; i++) submit_buttons[i].disabled = false ;
        }
    });
});

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


// post ajax processing after inserting older comments for a gift.
// called from comments/index.js.erb
// new comment lines are surrounded by "gift-<giftid>-older-comments-block-start-<commentid>" and "gift-<giftid>-older-comments-block-end-<commentid>".
// move lines up before "show-older-comments" link and delete link
function post_ajax_add_older_comments(giftid, commentid) {
    var pgm = 'post_ajax_add_older_comments: ' ;
    var table_id = 'gift-' + giftid + '-links-errors' ;
    var msg ;
    // try catch block to avoid "parse error" ajax message
    try {
        // var id = '#gift-' + giftid + '-new-comment-form' ;
        // add2log(pgm + 'giftid = ' + giftid + ', commentid = ' + commentid) ;
        var link_id = 'gift-' + giftid + '-show-older-comments-link-' + commentid;
        // find tr for old link, first added row and last added row
        var first_row_id = "gift-" + giftid + "-older-comments-block-start-" + commentid;
        var last_row_id = "gift-" + giftid + "-older-comments-block-end-" + commentid;
        // find link
        var link = document.getElementById(link_id);
        if (!link) {
            msg = 'System error: link ' + link_id + ' was not found' ;
            add2log(pgm + msg) ;
            add_to_tasks_errors3(table_id, msg);
            return;
        }
        // find tr for link
        var link_tr = link;
        while (link_tr.tagName != 'TR') link_tr = link_tr.parentNode;
        // find first and last added table row
        var first_row = document.getElementById(first_row_id);
        if (!first_row) {
            msg = 'System error: link ' + first_row_id + ' was not found' ;
            add2log(pgm + msg) ;
            add_to_tasks_errors3(table_id, msg);
            return;
        }
        var last_row = document.getElementById(last_row_id);
        if (!last_row) {
            msg = 'System error: link ' + last_row_id + ' was not found' ;
            add2log(pgm + msg) ;
            add_to_tasks_errors3(table_id, msg);
            return;
        }
        // copy table rows to JS array
        var trs = [];
        var tr = first_row.nextElementSibling;
        while (tr.id != last_row_id) {
            if (tr.tagName == 'TR') trs.push(tr);
            tr = tr.nextElementSibling;
        } // while
        // delete table rows from html table
        tr = first_row;
        var next_tr = tr.nextElementSibling;
        do {
            tr.parentNode.removeChild(tr);
            tr = next_tr;
            next_tr = tr.nextElementSibling;
        } while (tr.id != last_row_id) ;
        // insert table rows before old show-older-comments link

        var tbody = link_tr.parentNode;
        while (trs.length > 0) {
            tr = trs.shift();
            tbody.insertBefore(tr, link_tr);
        }
        // delete link  (and this event handler)
        link_tr.parentNode.removeChild(link_tr);
    }
    catch (err) {
        var msg = pgm + 'failed with JS error: ' + err;
        add2log(msg);
        add_to_tasks_errors(msg);
        return;
    }
} // add_post_ajax_new_comment_handler

// show/hide price and currency in new comment table call
function check_uncheck_new_deal_checkbox(checkbox, giftid)
{
    var tr = document.getElementById("gift-" + giftid + "-comment-new-price-tr") ;
    var new_deal_yn = document.getElementById("gift-" + giftid + "-comment-new-deal-yn") ;
    var price = document.getElementById("gift-" + giftid + "-comment-new-price") ;
    if (checkbox.checked) {
        tr.style.display='block' ;
        new_deal_yn.value = 'Y' ;
    }
    else {
        tr.style.display = 'none' ;
        new_deal_yn.value = '' ;
        price.value = '' ;
    }
    // alert(checkbox);
} // check_uncheck_new_deal_checkbox


//$(document).ready(function() {
//    $("#tasks_form").unbind("ajax:error") ;
//    $("#tasks_form").bind("ajax:error", function(jqxhr, textStatus, errorThrown){
//        add2log('#tasks_form.error');
//        add2log('jqxhr = ' + jqxhr);
//        add2log('textStatus = ' + textStatus);
//        add2log('errorThrown = ' + errorThrown);
//        add_to_tasks_errors('tasks_form.error: ' + errorThrown + '. check server log for more information.') ;
//    })
//})


// only current currency is in currency LOV at response time
// download all currencies when user clicks on currency LOV
// for smaller page and faster startup time
// todo: minor problem. User has to click twice on currency LOV to change currency. First to get full currency list and second to change currency
$(document).ready(function() {
    var id = ".user_currency_new" ;
    $(id).unbind('focus') ;
    $(id).bind('focus', function () {
        var id_select = document.getElementById("user_currency_new");
        if (id_select.length > 1) {
            // list of currencies is already initialised
            $(id).unbind('focus');
        }
        else {
            // get full list of currencies from server
            $.ajax({
                type: 'GET',
                url: '/util/currencies.js',
                dataType: "text",
                success: function (msg) {
                    $(id).unbind('focus');
                    var pgm = 'user_currency_new.ajax.success: ' ;
                    if (msg == 0) {
                        // Query returned empty.
                        msg = 'Did not get any currencies from server' ;
                        add2log(pgm + msg);
                        add_to_tasks_errors(msg)
                    } else {
                        // Query Has values.
                        add2log(pgm + 'msg = ' + msg) ;
                        $(id).replaceWith(msg);
                        $(id).click;
                    }
                },
                error: function (jqXHR, textStatus, errorThrown) {
                    $(id).unbind('focus');
                    var pgm = 'user_currency_new.ajax.error: ' ;
                    var msg = 'Error when fetching currencies from server. ' + (errorThrown || textStatus) +
                              '. More information in server log.'
                    add2log(pgm + msg);
                    add2log(pgm + 'jqXHR       = ' + jqXHR) ;
                    add2log(pgm + 'textStatus  = ' + textStatus) ;
                    add2log(pgm + 'errorThrown = ' + errorThrown) ;
                    add_to_tasks_errors(msg)
                }
            });

        }
    }); // $(".user_currency_new").bind('focus', function () {
})

// disable user_currency_new LOV for deep link for not logged in users (gifts/show/<deep_link_id>)
function disable_user_currency_new_lov() {
    setInterval(function() {
        $(".user_currency_new").unbind('focus') ;
    }, 100) ;
} // disable_user_currency_new_lov


// for client side debugging - writes JS messages to debug_log div - only used if DEBUG_AJAX = true
function add2log (text) {
    // if (debug_ajax != true) return ;
    var log = document.getElementById('debug_log') ;
    if (!log) return ;
    log.innerHTML = log.innerHTML + text + '<br>' ;
} // add2log

// http://stackoverflow.com/questions/10944396/how-to-calculate-ms-since-midnight-in-javascript
function getMsSinceMidnight() {
    var d = new Date() ;
    var e = new Date(d);
    return d - e.setHours(0,0,0,0);
} // getMsSinceMidnight
function getSecondsSinceMidnight() {
    return 1.0 * getMsSinceMidnight() / 1000 ;
} // getSecondsSinceMidnight



// implementing show-more-rows ajax / endless expanding page ==>
// used in gifts/index, users/index and users/show pages

// show-more-rows click. Starts ajax request to gifts or users controller
function show_more_rows()
{
    var link = document.getElementById("show-more-rows-link") ;
    if (!link) return ;
    if (link.click) link.click() ;
    else {
        // safari 5 workaround - http://stackoverflow.com/questions/12744202/undefined-is-not-a-function-evaluating-el-click-in-safari
        var click_ev = document.createEvent("MouseEvent");
        click_ev.initEvent("click", true /* bubble */, true /* cancelable */);
        link.dispatchEvent(click_ev);
    }
} // show_more_rows()

// end_of_page - true or false
// true when user is near end of page (get more rows)
// true under an active get more rows ajax request
// is set in $(window).scroll
// is unset in $(document).ready when new rows has been received
// default not active. end_of_page = true. will be overwritten in gifts/index, users/index and users/show pages
var end_of_page = true ;

// check number of rows in table (gifts or users) before and after get more rows ajax event
// do not fire any more get more rows ajax events if no new rows has been received (server side error)
var old_number_of_rows ;

// remember timestamp in milliseconds for last show-more-rows ajax request
// should only request more rows once every 3 seconds
var old_show_more_rows_request_at ;

// scroll event - click show_more_rows when user scrolls to end of page
// table_name should be gifts or users
// interval should be 3000 = 3 seconds between each show-more-rows request
// debug true - display messages for ajax debugging in button of page
function show_more_rows_scroll () {
    if (!document.getElementById('show-more-rows-link')) return ; // ignore - show-more-rows is not relevant in this page  (inbox etc)
    var table_name = get_more_rows_table ;
    if (end_of_page) return; // no more rows, not an ajax expanding page or ajax request already in progress
    if (($(document).height() - $(window).height()) - $(window).scrollTop() < 600) {
        end_of_page = true;
        if (!document.getElementById("show-more-rows-link")) return;
        var table = document.getElementById(table_name);
        if (!table) return; // not
        old_number_of_rows = table.rows.length;
        var now = getSecondsSinceMidnight();
        // There is a minor problem with wait between show-more-rows request
        // Implemented here and implemented in get_next_set_of_rows_error? and get_next_set_of_rows methods in application controller
        // For now wait is 3 seconds in javascript/client and 2 seconds in rails/server
        var twenty_four_hours = 60 * 60 * 24 ;
        var sleep ;
        if (old_show_more_rows_request_at === undefined) sleep = 0 ;
        else {
//            add2log('get_more_rows_interval = ' + get_more_rows_interval + ', now = ' + now +
//                ', old_show_more_rows_request_at = ' + old_show_more_rows_request_at) ;
            var interval = now - old_show_more_rows_request_at ;
            if (interval < 0) interval = interval + twenty_four_hours ;
            sleep = get_more_rows_interval - interval;
            if (sleep < 0) sleep = 0 ;
        }
        var previous_timestamp = old_show_more_rows_request_at ;
        var next_timestamp = now + sleep;
        if (next_timestamp > twenty_four_hours) next_timestamp = next_timestamp - twenty_four_hours ;
        if (debug_ajax) add2log('Sleep ' + sleep + ' seconds' + '. previous timestamp ' + previous_timestamp + ', next timestamp ' + next_timestamp);
        old_show_more_rows_request_at = next_timestamp;
        add2log('show_more_rows_scroll: table_name = ' + table_name + '. call show_more_rows in ' + Math.round(sleep*1000) + ' milliseconds');
        start_show_more_rows_spinner(table_name, debug_ajax) ;
        if (sleep == 0) show_more_rows();
        else setTimeout("show_more_rows()", Math.round(sleep*1000));
    }
} // show_more_rows_scroll

// show more rows - hide spinner
function stop_show_more_rows_spinner() {
    var pgm = 'stop_show_more_rows_spinner: ' ;
    // add2log(pgm + 'stop') ;
    // check if show-more-rows spinner is in page
    var spinner_id = 'show-more-rows-spinner' ;
    var spinner = document.getElementById(spinner_id) ;
    if (!spinner) {
        add2log(pgm + 'show more rows spinner was not found') ;
        return ;
    }
    add2log(pgm + 'spinner.style.display = ' + spinner.style.display) ;
    spinner.style.display = 'none' ;
} // stop_show_more_rows_spinner

// show more rows - show spinner in last table row while fetching more rows
function start_show_more_rows_spinner (table_name, debug)
{
    var pgm = 'start_show_more_rows_spinner: '
    add2log(pgm + 'start') ;
    // check if spinner show-more-rows spinner has already been created
    var spinner_id = 'show-more-rows-spinner' ;
    var spinner = document.getElementById(spinner_id) ;
    if (spinner) {
        spinner.style.display = '' ;
        return ;
    }
    add2log(pgm + 'spinner was not found');
} // start_show_more_rows_spinner

function show_more_rows_success (table_name, debug)
{
    if (table_name == 'gifts') {
        // report any invalid api picture urls - url has changed or picture has been deleted
        // array with gift ids is initialized in img onload="imgonload ..."
        // submitted in 2 seconds to allow pictures in page to load
        // api_picture_url_on_error_at is set for pictures with invalid urls
        // picture urls are checked with api calls by current user and if necessary by picture owner at a later time
        setTimeout(report_missing_api_picture_urls, 2000);
    }
    // find id for last row (nil or id for last row in table)
    var pgm = "#show-more-rows-link.ajax:success: " ;
    var link = document.getElementById("show-more-rows-link") ;
    if (!link) {
        if (debug) add2log(pgm + "show-more-rows-link has already been removed");
        return
    }
    var table = document.getElementById(table_name) ;
    if (!table) {
        if (debug) add2log(pgm + 'error - gifts or users table was not found') ;
        return
    }
    var new_number_of_rows = table.rows.length ;
    if (new_number_of_rows == old_number_of_rows) {
        if (debug) add2log(pgm + 'error - no new rows was returned from get more rows ajax request') ;
        return
    }
    var trs = table.getElementsByTagName('tr') ;
    var tr = trs[trs.length-1] ;
    var tr_id = tr.id ;
    if (tr_id == "") {
        if (debug) add2log(pgm + 'no more rows - remove link') ;
        link.parentNode.removeChild(link);
    }
    else {
        var reg = new RegExp("^last-row-id-[0-9]+$") ;
        if (!tr_id.match(reg)) {
            if (debug) add2log(pgm + 'row with format last-row-id-<n> was not found. id = ' + tr_id);
            return
        }
        var tr_id_a = tr_id.split("-") ;
        var last_row_id = tr_id_a[tr_id_a.length-1] ;
        var href = link.href ;
        // add2log(pgm + 'old href = ' + href)
        href = href.replace(/last_row_id=[0-9]+/, 'last_row_id=' + last_row_id) ;
        link.href = href ;
        // add2log(pgm + 'new href = ' + href)
        end_of_page = false ;
    }
    // show show-more-text for div with text overflow
    find_overflow() ;

    if (table_name == 'gifts') {
        // unbind and bind ajax handlers for comment links (new rows)
        // todo: use jquery on with delegated event handling: https://api.jquery.com/on/
        setup_comment_action_link_ajax() ;
    }

} // show_more_rows_success

function show_more_rows_error(jqxhr, textStatus, errorThrown, debug) {
    if (debug) {
        add2log('show_more_rows.ajax.error');
        add2log('jqxhr = ' + jqxhr);
        add2log('textStatus = ' + textStatus);
        add2log('errorThrown = ' + errorThrown);
    }
    add_to_tasks_errors2('show-more-rows-errors', 'show_more_rows.ajax.error: ' + errorThrown + '. check server log for more information.') ;
} // show_more_rows_error

function show_more_rows_ajax() {
    var table_name = get_more_rows_table ;
    var link = '#show-more-rows-link'
//    $(link).unbind("click") ;
//    $(link).bind("click", function(xhr, settings){
//        var pgm = link + '.click: ' ;
//        try { start_show_more_rows_spinner(table_name, debug_ajax) }
//        catch (err) {
//            var msg = pgm + 'failed with JS error: ' + err;
//            add2log(msg);
//            add_to_tasks_errors(msg);
//            return;
//        }
//    });
    $(link).unbind("ajax:success");
    $(link).bind("ajax:success", function (evt, data, status, xhr) {
        var pgm = link + '.ajax.success: ' ;
        try {
            show_more_rows_success(table_name);
            stop_show_more_rows_spinner();
        }
        catch (err) {
            var msg = pgm + 'failed with JS error: ' + err;
            add2log(msg);
            add_to_tasks_errors(msg);
            return;
        }
    });
    $(link).unbind("ajax:error");
    $(link).bind("ajax:error", function (jqxhr, textStatus, errorThrown) {
        var pgm = link + '.ajax.error: ' ;
        add2log(pgm + 'start') ;
        try {
            if (leaving_page) return ;
            show_more_rows_error(jqxhr, textStatus, errorThrown);
            // add2log_ajax_error('', jqxhr, textStatus, errorThrown, 'show-more-rows-errors') ;
            stop_show_more_rows_spinner();
        }
        catch (err) {
            var msg = pgm + 'failed with JS error: ' + err;
            add2log(msg);
            add_to_tasks_errors(msg);
            return;
        }
    });
} // show_more_rows_ajax

// <== implementing show-more-rows ajax / endless expanding page


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



function get_js_timezone() {
  return -(new Date().getTimezoneOffset()) / 60.0 ;
}

function start_tasks_form_spinner()
{
    var spinner_id = 'ajax-tasks-spinner' ;
    var spinner = document.getElementById(spinner_id) ;
    if (spinner) spinner.style.display = '' ;
    else add2log('start_tasks_form_spinner: spinner was not found') ;
} // start_tasks_form_spinner

function stop_tasks_form_spinner()
{
    var spinner_id = 'ajax-tasks-spinner' ;
    var spinner = document.getElementById(spinner_id) ;
    if (spinner) spinner.style.display = 'none' ;
    else add2log('stop_tasks_form_spinner: spinner was not found') ;
} // stop_tasks_form_spinner


// request server to execute any task in task queue
// called from bottom of application layout and from  insert_update_gifts after gift create (posting on api wall)
// tasks: get currency rates, download api information (picture, permissions, friend list), post on api walls
function trigger_tasks_form (sleep) {
    add2log("trigger_tasks_form: sleep = " + sleep) ;
    if (!sleep) sleep=1000 ;
    var timezone = document.getElementById("timezone") ;
    if (!timezone) {
        add2log('trigger_tasks_form. hidden field with id timezone was not found') ;
        return ;
    }
    timezone.value = get_js_timezone();
    window.setTimeout(function(){start_tasks_form_spinner();$('#tasks_form').trigger('submit.rails');}, sleep);
} // trigger_tasks_form

// error callback for executing tasks - write to debug log + page header
// debug log in bottom of page is shown if DEBUG_AJAX = true (constants.rb)
$(document).ready(function() {
    var id = "#tasks_form" ;
    $(id).unbind("ajax:success");
    $(id).bind("ajax:success", function (evt, data, status, xhr) {
        var pgm = id + '.ajax.success: ' ;
        try {
            stop_tasks_form_spinner();
        }
        catch (err) {
            var msg = pgm + 'failed with JS error: ' + err;
            add2log(msg);
            add_to_tasks_errors(msg);
            return;
        }
    }); // ajax:success
    $(id).unbind("ajax:error") ;
    $(id).bind("ajax:error", function(jqxhr, textStatus, errorThrown){
        var pgm = id + '.ajax.error: ' ;
        try {
            if (leaving_page) return ;
            stop_tasks_form_spinner();
            add2log(pgm);
            add2log('jqxhr = ' + jqxhr);
            add2log('textStatus = ' + textStatus);
            add2log('errorThrown = ' + errorThrown);
            add_to_tasks_errors('tasks_form.error: ' + errorThrown + '. check server log for more information.') ;
        }
        catch (err) {
            var msg = pgm + 'failed with JS error: ' + err;
            add2log(msg);
            add_to_tasks_errors(msg);
            return;
        }
    }) ; // ajax:error
})

// delete old messages before inserting new identical error message
function delete_old_error (table, error) {
  var rows = table.rows ;
  if (rows.length == 0) return ;
  for (var i=rows.length-1 ; i>=0 ; i--) {
      if (rows[i].cells[0].innerHTML == error) table.deleteRow(i) ;
  }
} // delete_old_error

// write ajax error to tasks_errors table in page header
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
        if (!create_gift_links_errors_table(table_id) && !create_new_com_errors_table(table_id) && !create_com_link_errors_table(table_id)) {
            // write to error table in page header
            add_to_tasks_errors(msg + ' (inject not implemented for error message with id ' + table_id + ').');
            return;
        }
        // error table was created
    }
    // add to error table inside page
    add_to_tasks_errors2(table_id, msg);
} // add_to_tasks_errors3


// create missing gift-<giftid>-links-errors table if possible
// is created under current gift link row in gifts table
function create_gift_links_errors_table (table_id) {
    var re1 = new RegExp('^gift-[0-9]+-links-errors$') ;
    if (!table_id.match(re1)) return false ; // not a gift link error
    giftid = table_id.split('-')[1] ;
    add2log('giftid = ' + giftid) ;
    ref_id = 'gift-' + giftid + '-links' ;
    add2log('ref_id = ' + ref_id) ;
    ref = document.getElementById(ref_id) ;
    if (!ref) {
        add2log(ref_id + ' was not found. ') ;
        return false ;
    }
    // add2log(ref_id + ' blev fundet') ;
    ref = ref.nextSibling ;
    if (!ref) {
        add2log('row after ' + ref_id + ' was not found. ') ;
        return false ;
    }
    add2log('create new tr') ;
    new_tr = document.createElement('tr') ;
    new_tr.id = table_id + '-tr' ;
    add2log('insert new td')
    for (j=0 ; j <= 2 ; j++) {
        new_td = new_tr.insertCell(j) ;
        new_td.innerHTML = '' ;
    }
    add2log('initialize tr[2]')
    new_td.innerHTML = '<table><tbody id="' + table_id + '" class="ajax_errors"></tbody></table>' ;
    new_td.setAttribute("colspan",2);
    add2log('insertBefore') ;
    ref.parentNode.insertBefore(new_tr, ref) ;
    // ok - new gift link error table has been created
    add2log('ok. ' + table_id + ' has been created') ;
    return true ;
} // create_gift_links_errors_table

// error callback for gift actions (like, unlike, follow, unfollow, delete, hide, show older comments - write to debug log + page header
$(document).ready(function() {
    var id = ".gift-action-link" ;
    $(id).unbind("click") ;
    $(id).bind("click", function(xhr, settings){
        // clear any old ajax error messages if any
        // clear within page ajax error messages if any
        var pgm = id + '.click: ' ;
        add2log(pgm + 'start') ;
        try {
            // add2log(pgm + 'xhr = ' + xhr + ', settings = ' + settings) ;
            var url = xhr.target ;
            add2log(pgm + 'url = ' + url) ;
            // url = http://localhost/da/util/delete_gift?gift_id=914
            // url = http://localhost/da/comments?first_comment_id=376&gift_id=914
            var url_a = ('' + url + '').split('=') ;
            // add2log(pgm + 'url_a.length = ' + url_a.length) ;
            var giftid = url_a[url_a.length-1] ;
            // add2log(pgm + 'giftid = ' + giftid) ;
            var table_id = 'gift-' + giftid + '-links-errors' ;
            var table = document.getElementById(table_id) ;
            if (table) clear_ajax_errors(table_id) ;
            // else add2log(pgm + table_id + ' was not found.') ;
            // else add2log(pgm + table_id + ' was not found.') ;
            // clear page header error messages if any
            clear_flash_and_ajax_errors() ;
        }
        catch (err) {
            add2log(pgm + 'failed with JS error: ' + err);
            add_to_tasks_errors(I18n.t('js.gift_actions.click_js_error', {error: err, location: 11, debug: 0})) ;
        }
    }) // click
    $(id).unbind("ajax:error") ;
    $(id).bind("ajax:error", function(jqxhr, textStatus, errorThrown){
        var pgm = id + '.ajax.error: ' ;
        var debug = 0 ;
        var url ;
        add2log(pgm + 'start') ;
        try {
            if (leaving_page) return ;
            var err = add2log_ajax_error(pgm,jqxhr,textStatus,errorThrown) ;
            var error = errorThrown + '. check server log for more information.' ;
            // inject gift action ajax error into page if possible. Otherwise use tasks_errors table in page header
            url = '' + jqxhr.target + '' ;
            add2log(pgm + 'url = ' + url) ;
            // http://localhost/da/util/like_gift?gift_id=1478
            // http://localhost/da/util/unlike_gift?gift_id=1478
            // http://localhost/da/util/follow_gift?gift_id=1478
            // http://localhost/da/util/unfollow_gift?gift_id=1478
            // http://localhost/da/util/delete_gift?gift_id=1478
            // http://localhost/da/util/hide_gift?gift_id=1419
            // http://localhost/da/comments?first_comment_id=1029&gift_id=1478
            // find gift_id last in url
            debug = 1 ;
            var url_a = url.split('=') ;
            // add2log(pgm + 'url_a.length = ' + url_a.length) ;
            var giftid = url_a[url_a.length-1] ;
            var url_b = url.split('?')[0] ;
            var url_c = url_b.split('/') ;
            var action = url_c[url_c.length-1] ;
            add2log(pgm + 'url = ' + url + ', giftid = ' + giftid + ', action = ' + action) ;
            debug = 2 ;
            var valid_actions = ["like_gift", "unlike_gift", "follow_gift", "unfollow_gift", "delete_gift", "hide_gift", "comments"] ;
            var key ;
            if (valid_actions.indexOf(action) == -1) key = 'js.gift_actions.ajax_error' ;
            else key = 'js.gift_actions.' + action + '_ajax_error' ;
            var table_id = 'gift-' + giftid + '-links-errors' ;
            var table = document.getElementById(table_id) ;
            debug = 3 ;
            if (!table && !create_gift_links_errors_table(table_id)) {
                // inject ajax error message in page header
                add_to_tasks_errors(I18n.t(key, {error: err, url: url, giftid: giftid})) ;
            }
            else {
                // inject ajax error message in gift link error table in within page
                add_to_tasks_errors2(table_id, I18n.t(key, {error: err, url: url, giftid: giftid})) ;
            }
        }
        catch (err) {
            add2log(pgm + 'failed with JS error: ' + err);
            add_to_tasks_errors(I18n.t('js.gift_actions.js_error', {error: err, location: 10, debug: debug})) ;
            return;
        }
    }) // ajax:error
})

function create_new_com_errors_table(table_id) {
    // table_id = gift-890-comment-new-errors
    var pgm = 'create_new_com_errors_table: ' ;
    var re1 = new RegExp('^gift-[0-9]+-comment-new-errors$') ;
    if (!table_id.match(re1)) return false ; // not a new comment error
    giftid = table_id.split('-')[1] ;
    add2log(pgm + 'giftid = ' + giftid) ;
    ref_id = 'gift-' + giftid + '-comment-new-price-tr' ;
    add2log(pgm + 'ref_id = ' + ref_id) ;
    ref = document.getElementById(ref_id) ;
    if (!ref) {
        add2log(pgm + ref_id + ' was not found. ') ;
        return false ;
    }
    // find table with gift-<giftid>-comment-new-price-tr row
    var tbody = ref.parentNode ;
    var rows = tbody.rows ;
    add2log(pgm + rows.length + ' rows in table') ;
    if (rows.length != 3) {
        add2log(pgm + 'Expected 3 rows in table with ' + ref_id + '. Found ' + rows.length + ' rows.') ;
        return false ;
    }
    // add new table row with table for ajax error messages
    var row = tbody.insertRow(rows.length) ;
    var cell = row.insertCell(0) ;
    cell.setAttribute("colspan",2);
    cell.innerHTML = '<table><tbody id="' + table_id + '" class="ajax_errors"></tbody></table>' ;
    add2log(pgm + table_id + ' has been created') ;
    return true ;
} // create_new_com_errors_table

// post ajax processing after adding a comment.
// comments/create.js.rb inserts new comment as last row i gifts table body
// move new comment from last row to row before new comment row
// clear comment text area and reset frequency for new message check
function post_ajax_add_new_comment_handler(giftid) {
    var id = '#gift-' + giftid + '-new-comment-form';
    // var gifts2 = document.getElementById('gifts') ;
    // add2log(id + '. old gifts.rows = ' + gifts2.rows.length) ;
    $(id).unbind("ajax:send");
    $(id).bind("ajax:send", function() {
        var pgm = id + '.ajax.send: ' ;
        add2log(pgm + 'start. giftid = ' + giftid) ;
        comment_submit_disable(giftid) ;
    }); // complete
    $(id).unbind("ajax:success");
    $(id).bind("ajax:success", function (evt, data, status, xhr) {
        var pgm = id + '.ajax.success: ' ;
        var debug = 0 ;
        try {
            // dump xhr
            // for (var key in xhr) add2log(id + '. ajax.success. xhr[' + key + '] = ' + xhr[key]) ;
            // fix for ie8/ie9 error. ajax response from comment/create was not executed
            // content type in comment/create response is now text/plain
            var checkbox, gifts, trs, re, i, new_comment_tr, id2, add_new_comment_tr, tbody;
            // reset new comment row
            var tempScrollTop = $(window).scrollTop();
            add2log(pgm + 'scrollTop = ' + tempScrollTop) ;
            // $(window).scrollTop(tempScrollTop);
            debug = 1 ;
            document.getElementById('gift-' + giftid + '-comment-new-price').value = '';
            debug = 2 ;
            var textarea_id = 'gift-' + giftid + '-comment-new-textarea' ;
            var textarea = document.getElementById(textarea_id) ;
            debug = 3 ;
            var textarea_old_height = textarea.offsetHeight ;
            add2log(pgm + 'textarea old height (1) = ' + textarea_old_height) ;
            if (textarea_old_height > 150) textarea_old_height = 150 ;
            debug = 4 ;
            add2log(pgm + 'textarea old height (2) = ' + textarea_old_height) ;
            var textarea_old_offset = $('#' + textarea_id).offset().top ;
            add2log(pgm + 'textarea old offset = ' + textarea_old_offset) ;
            debug = 5 ;
            textarea.value = '';
            debug = 6 ;
            autoresize_text_field(textarea) ;
            var textarea_new_height = textarea.offsetHeight ;
            add2log(pgm + 'textarea new height = ' + textarea_new_height) ;
            debug = 7 ;
            document.getElementById('gift-' + giftid + '-comment-new-price-tr').style.display = 'none';
            debug = 8 ;
            checkbox = document.getElementById('gift-' + giftid + '-new-deal-check-box');
            if (checkbox) checkbox.checked = false;
            // find new comment table row last in gifts table
            gifts = document.getElementById("gifts_tbody");
            debug = 9 ;
            trs = gifts.rows;
            // add2log(id + '. ajax.success: new gifts.rows = ' + trs.length) ;
            re = new RegExp("^gift-" + giftid + "-comment-[0-9]+$");
            i = trs.length - 1;
            debug = 10 ;
            for (i = trs.length - 1; ((i >= 0) && !new_comment_tr); i--) {
                id2 = trs[i].id;
                if (id2 && id2.match(re)) new_comment_tr = trs[i];
            } // for
            debug = 11 ;
            if (!new_comment_tr) {
                add2log(pgm + "new comment row with format " + re + " was not found. There could be more information in server log.");
                return;
            }
            add_new_comment_tr = document.getElementById("gift-" + giftid + "-comment-new");
            if (!add_new_comment_tr) {
                add2log(pgm + "gift-" + giftid + "-comment-new was not found");
                return;
            }
            // move new table row up before add new comment table row
            debug = 12 ;
            new_comment_tr.parentNode.removeChild(new_comment_tr);
            // IE8 fix. removeChild + insertBefore did not work in IE8 - todo: recheck this IE8 fix
            var no_gifts = document.getElementById('gifts').rows.length ;
            add_new_comment_tr.parentNode.insertBefore(new_comment_tr, add_new_comment_tr); // error: Node was not found
            // move ok
            debug = 13 ;
            last_user_ajax_comment_at = new Date();
            restart_check_new_messages();
            debug = 14 ;
            // check overflow for new comment - display show-more-text link for comment with long text
            find_overflow();
            debug = 15 ;
            // restore scroll - not working 100% correct - problems with big comments
            var textarea_new_offset = $('#' + textarea_id).offset().top ;
            add2log(pgm + 'textarea new offset = ' + textarea_new_offset) ;
            tempScrollTop = tempScrollTop - textarea_old_offset + textarea_new_offset ; //  - textarea_old_height + textarea_new_height ;
            tempScrollTop = tempScrollTop + textarea_old_height - textarea_old_height ;
            if (tempScrollTop < 0) tempScrollTop = 0 ;
            $(window).scrollTop(tempScrollTop);
            // unbind and bind ajax for comment action links
            debug = 16 ;
            setup_comment_action_link_ajax() ;
        }
        catch (err) {
            var msg = pgm + 'failed with JS error: ' + err;
            add2log(pgm + 'failed with JS error: ' + err);
            add_to_tasks_errors(I18n.t('js.new_comment.js_error', {error: err, location: 12, debug: debug}));
            return;
        }

    }); // ajax:success
    $(id).unbind("ajax:error");
    $(id).bind("ajax:error", function(jqxhr, textStatus, errorThrown){
        var pgm = id + '.ajax.error: ' ;
        try {
            if (leaving_page) return ;
            var err = add2log_ajax_error(pgm, jqxhr, textStatus, errorThrown) ;
            var table_id = 'gift-' + giftid + '-comment-new-errors' ;
            var table = document.getElementById(table_id) ;
            if (!table && !create_new_com_errors_table(table_id)) {
                // inject ajax error message in page header
                add_to_tasks_errors(I18n.t('js.new_comment.ajax_error', {error: err, location: 13, debug: 1})) ;
            }
            else {
                // inject ajax error message in new comment error table in page
                add_to_tasks_errors2(table_id, I18n.t('js.new_comment.ajax_error', {error: err, location: 13, debug: 2})) ;
            }
        }
        catch (err) {
            add2log(pgm + 'failed with JS error: ' + err);
            add_to_tasks_errors(I18n.t('js.new_comment.ajax_error2', {error: err, location: 13, debug: 3})) ;
        }
    }); // ajax:error

    $(id).unbind("ajax:complete");
    $(id).bind("ajax:complete", function() {
        var pgm = id + '.ajax.complete: ' ;
        add2log(pgm + 'start. giftid = ' + giftid) ;
        comment_submit_enable(giftid) ;
    }); // complete

} // post_ajax_add_new_comment_handler

function create_com_link_errors_table(table_id) {
    // table_id = gift-891-comment-729-errors
    var pgm = 'create_new_com_errors_table: ';
    var re1 = new RegExp('^gift-[0-9]+-comment-[0-9]+-errors$');
    if (!table_id.match(re1)) return false; // not a new comment error
    giftid = table_id.split('-')[1];
    commentid = table_id.split('-')[3];
    add2log(pgm + 'gift id ' + giftid + ', comment id ' + commentid);
    // find row with comment
    var ref_id = 'gift-' + giftid + '-comment-' + commentid;
    var ref = document.getElementById(ref_id);
    if (!ref) {
        add2log(pgm + 'Could not find comment row with id ' + ref_id);
        return false;
    }
    var tbody = ref.parentNode;
    add2log(pgm + 'tbody = ' + tbody);
    ref = ref.nextSibling;
    if (!ref) {
        add2log(pgm + 'Could not find row after comment row with id ' + ref_id);
        return false;
    }
    // create new row with error table
    var row = document.createElement('tr');
    var cell = row.insertCell(0);
    cell.setAttribute("colspan", 4);
    cell.innerHTML = '<table><tbody id="' + table_id + '" class="ajax_errors"></tbody></table>';
    // insert new row
    tbody.insertBefore(row, ref);
    // new error table created
    return true;
} // create_com_link_errors_table

// translate comment action url (...) to name for related table for ajax error messages
function comment_action_url_table_id (url) {
    var pgm = 'comment_action_url_table_id: ' ;
    add2log(pgm + 'url = ' + url) ;
    var giftid, commentid ;
    var re1a = new RegExp('/comments/[0-9]+\\?giftid=[0-9]+$') ; // format /comments/729?giftid=891
    var re2a = new RegExp('/util/[a-z]+?_new_deal\\?comment_id=[0-9]+&giftid=[0-9]+$') ; // /util/cancel_new_deal?comment_id=736&giftid=891
    var re_split = new RegExp('[\\?/=&]') ;
    var action ;
    if (url.match(re1a)) {
        add2log(pgm + 'delete comment url') ;
        action = 'delete_comment' ;
        var url_a = url.split(re_split) ;
        add2log(pgm + 'url_a.length = ' + url_a.length) ;
        var url_lng = url_a.length ;
        giftid = url_a[url_lng-1] ;
        commentid = url_a[url_lng-3] ;
    }
    else if (url.match(re2a)) {
        add2log(pgm + 'cancel/reject/accept comment url') ;
        var url_a = url.split(re_split) ;
        add2log(pgm + 'url_a.length = ' + url_a.length) ;
        var url_lng = url_a.length ;
        giftid = url_a[url_lng-1] ;
        commentid = url_a[url_lng-3] ;
        action = url_a[url_lng-5] ;
    }
    var table_id ;
    if (giftid && commentid) {
        add2log(pgm + 'giftid = ' + giftid + ', commentid = ' + commentid) ;
        table_id = 'gift-' + giftid + '-comment-' + commentid + '-errors' ;
    }
    else {
        add2log(pgm + 'giftid and commentid was not found in url') ;
    }
    return [table_id, action] ;
} // comment_action_url_table_id

// comment-action-link bind only works for existing rows in gifts table
// setup_comment_action_link_ajax is called at startup and after adding new comments to gifts/index page
// todo: use jquery on and delegated events: https://api.jquery.com/on/
function setup_comment_action_link_ajax ()
{
    var id = ".comment-action-link" ;
    $(id).unbind("click");
    $(id).bind("click", function (xhr, settings) {
        var pgm = id + '.click: ' ;
        try {
            // add2log(pgm + 'xhr = ' + xhr + ', settings = ' + settings) ;
            var url = '' + xhr.target + '' ;
            add2log(pgm + 'url = "' + url + '"') ;
            // http://localhost/da/da/comments/729?giftid=891
            // find giftid and commentid in url
            var table_id_and_action = comment_action_url_table_id(url) ;
            var table_id = table_id_and_action [0] ;
            add2log(pgm + 'table_id = ' + table_id) ;
            if (table_id && document.getElementById(table_id)) clear_ajax_errors(table_id) ;
            clear_flash_and_ajax_errors();
        }
        catch (err) {
            add2log(pgm + 'failed with JS error: ' + err);
            add_to_tasks_errors(I18n.t('js.comment_actions.click_js_error', {error: err, location: 15, debug: 0}));
        }
    }) // click
    $(id).unbind("ajax:error");
    $(id).bind("ajax:error", function (jqxhr, textStatus, errorThrown) {
        var pgm = id + '.ajax.error: ' ;
        var debug = 0 ;
        try {
            if (leaving_page) return ;
            var err = add2log_ajax_error(pgm, jqxhr, textStatus, errorThrown) ;
            var error = err + '. check server log for more information.' ;
            var url = '' + jqxhr.target + '' ;
            add2log(pgm + 'url = "' + url + '"') ;
            // url:
            // - /comments/1038?giftid=1478 (delete)
            // - /util/cancel_new_deal?comment_id=1038&giftid=1478
            // - /util/reject_new_deal?comment_id=1038&giftid=1478
            // - /util/accept_new_deal?comment_id=1038&giftid=1478
            debug = 10 ;
            var table_id_and_action = comment_action_url_table_id(url) ;
            var table_id = table_id_and_action[0] ;
            var action = table_id_and_action[1] ;
            var valid_actions = ['delete_comment', 'cancel_new_deal', 'reject_new_deal', 'accept_new_deal'] ;
            if (valid_actions.indexOf(action) == -1) key = 'js.comment_actions.ajax_error' ;
            else key = 'js.comment_actions.' + action + '_ajax_error' ;
            var table = document.getElementById(table_id) ;
            debug = 20 ;
            add2log(pgm + 'table_id = ' + table_id + ', action = ' + action) ;
            if (!table && !create_com_link_errors_table(table_id)) {
                // could not find table id and table for ajax error messages could not be created
                debug = 30 ;
                add_to_tasks_errors(I18n.t(key, {error: err, url: url, location: 14, debug: 1}));
            }
            else {
                // could find table_id or table for ajax error messages has been created
                debug = 40 ;
                add_to_tasks_errors2(table_id, I18n.t(key, {error: err, url: url, location: 14, debug: 2})) ;
            }
        }
        catch (err) {
            add2log(pgm + 'failed with JS error: ' + err + ', debug = ' + debug);
            add_to_tasks_errors(I18n.t('js.comment_actions.js_error', {error: err, location: 14, debug: debug}));
        }
    }) // ajax:error
}

// error callback for comment actions (cancel, accept, reject, delete - write to debug log + page header
// using click event instead of beforeSend or ajaxSend as rails confirm box seems to "disable" use of the 2 events
$(document).ready(function () {
    setup_comment_action_link_ajax() ;
})


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


// ajax enable/disable gift file field in gifts/index page
// enable after granting write permission to aåi wall
// disable after revoking last write permission to api wall
function disable_enable_file_upload (gift_file_enabled) {
   // add2log('disable_enable_file_upload: gift_file_enabled = ' + gift_file_enabled) ;
   if (gift_file_enabled === undefined) return;
   var gift_file = document.getElementById('gift_file');
   if (!gift_file) return ;
   gift_file.disabled = !gift_file_enabled ;
   // add2log('gift_file.disabled = ' + gift_file.disabled) ;
} // disable_enable_file_upload


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


// send post_on_wall y/n choice to server - only feedback after ajax errors
// used in auth/index and in users/edit pages
function post_on_wall_ajax(checkbox) {
    var provider = checkbox.name.substr(5) ;
    var post_on_wall = checkbox.checked ;
    // alert('checkbox = provider = ' + provider + ', post_on_wall = ' + post_on_wall) ;
    clear_flash_and_ajax_errors();
    $.ajax({
        url: "/util/post_on_wall_yn.js",
        type: "POST",
        dataType: 'script',
        data: { provider: provider, post_on_wall: post_on_wall },
//        success: function (responseText, statusText, xhr, $form) {
//            var pgm = 'post_on_wall_ajax:success: ' ;
//            add2log(pgm + 'start') ;
//        }, // success
        error: function (jqxhr, textStatus, errorThrown) {
            var pgm = 'post_on_wall_ajax:error: ' ;
            if (leaving_page) return ;
            var err = add2log_ajax_error(pgm, jqxhr, textStatus, errorThrown) ;
            add_to_tasks_errors(I18n.t('js.post_on_wall.ajax_error', {error: err, location: 17, debug: 0}));
        }
    });
} // post_on_wall_ajax



// from https://jqueryui.com/resources/demos/dialog/modal-form.html - Copyright 2014 jQuery Foundation and other contributors; Licensed MIT
// modal dialog form used in share accounts share level 3 and 4
// used must accept that access tokens are stored on server + optional email notifications with friend suggestions
$(function() {

    var dialog, form,

    // From http://www.whatwg.org/specs/web-apps/current-work/multipage/states-of-the-type-attribute.html#e-mail-state-%28type=email%29
        emailRegex = /^[a-zA-Z0-9.!#$%&'*+\/=?^_`{|}~-]+@[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$/,
        email = $( "#share-accounts-email" ),
        allFields = $( [] ).add( email ),
        tips = $( ".validateTips"),
        accept_text = I18n.t('js.share_accounts_dialog.accept'),
        reject_text = I18n.t('js.share_accounts_dialog.reject') ;

    function updateTips( t ) {
        tips
            .text( t )
            .addClass( "ui-state-highlight" );
        setTimeout(function() {
            tips.removeClass( "ui-state-highlight", 1500 );
        }, 500 );
    }

    function checkLength( o, n, min, max ) {
        if ( o.val().length > max || o.val().length < min ) {
            o.addClass( "ui-state-error" );
            updateTips(I18n.t('js.share_accounts_dialog.invalid_length', {field: n, min: min, max: max}));
            return false;
        } else {
            return true;
        }
    }

    function checkRegexp( o, regexp, n ) {
        if ( !( regexp.test( o.val() ) ) ) {
            o.addClass( "ui-state-error" );
            updateTips( n );
            return false;
        } else {
            return true;
        }
    }

    function accept() {
        var pgm='share-accounts-dialog-form.accept: ';
        try {
            var valid = true;
            allFields.removeClass("ui-state-error");
            if ((email.length > 0) && (email.val() != '')) {
                // email exists in dialog form and is not blank
                valid = valid && checkLength(email, I18n.t('js.share_accounts_dialog.email'), 6, 200);

                valid = valid && checkRegexp(email, emailRegex, I18n.t('js.share_accounts_dialog.invalid_email'));
            }

            if (valid) {
                // send ajax request and close dialog
                share_accounts_ajax(true, email.val());
                dialog.dialog("close");
            }
            return valid
        }
        catch (err) {
            add2log(pgm + 'failed with JS error: ' + err);
            add_to_tasks_errors2('share_accounts_errors',I18n.t('js.share_accounts.js_error', {error: err, location: 19, debug: 2}));
            return false;
        }
    } // accept

    function reject() {
        // restore old LOV value without triggering new share accounts dialog form
        var share_level_lov = document.getElementById('share_level_lov') ;
        var old_share_level_lov = document.getElementById('old_share_level_lov') ;
        if (share_level_lov && old_share_level_lov) share_level_lov.value = old_share_level_lov.value ;
        dialog.dialog( "close" );
    }

    dialog = $( "#share-accounts-dialog-form" ).dialog({
        autoOpen: false,
        height: fb_user ? 225 : 300, // only show email for logins without fb account
        width: 350,
        modal: true,
        buttons:[
            {
                text: accept_text,
                click: accept
            },
            {
                text: reject_text,
                click: reject
            }],
        close: function() {
            form[ 0 ].reset();
            allFields.removeClass( "ui-state-error" );
        }
    });

    form = dialog.find( "form" ).on( "submit", function( event ) {
        event.preventDefault();
        accept();
    });

    $( "#share-accounts" ).button().on( "click", function() {
        dialog.dialog( "open" );
    });
});


// set/reset user,share_account_id
// used in shared/share_accounts partial
// used in auth/index and users/index?friends=me tab
// accepted: false when called from LOV. True when called from accept in dialog form. Only relevant for share level 3 and 4
function share_accounts_ajax(accepted, email) {
    var pgm = 'share_accounts_ajax: ' ;
    try {

        var share_level_lov = document.getElementById('share_level_lov');
        if (!share_level_lov) {
            add_to_tasks_errors(I18n.t('js.share_accounts.lov_not_found'));
            return;
        }
        var share_level = share_level_lov.options[share_level_lov.selectedIndex].value;
        clear_ajax_errors('share_accounts_errors');
        add2log(pgm + 'share_level = ' + share_level + ', email = ' + email);
        if (!accepted && ((share_level == '3') || (share_level == 4))) {
            // share level 3 - dynamic friend lists
            // share level 4 - single sign-on
            // Security alert dialog. yes/no to save access tokens on server for offline access
            var share_accounts_button = document.getElementById('share-accounts') ;
            share_accounts_button.click() ;
            return false ;
        }
        $.ajax({
            url: "/util/share_accounts.js",
            type: "POST",
            dataType: 'script',
            data: { share_level: share_level, email: email },
            beforeSend: function () {
                // add2log(pgm + 'beforesend') ;
                share_level_lov.disabled = true;
                share_level_lov.readonly = true;
            },
            error: function (jqxhr, textStatus, errorThrown) {
                var pgm = 'share_accounts_ajax:error: ';
                if (leaving_page) return;
                var err = add2log_ajax_error(pgm, jqxhr, textStatus, errorThrown);
                add_to_tasks_errors(I18n.t('js.share_accounts.ajax_error', {error: err, location: 19, debug: 1}));
            },
            complete: function () {
                // add2log(pgm + 'complete') ;
                share_level_lov.disabled = false;
                share_level_lov.readonly = false;
            }
        });
    }
    catch (err) {
        add2log(pgm + 'failed with JS error: ' + err) ;
        add_to_tasks_errors(I18n.t('js.share_accounts.js_error', {error: err, location: 19, debug: 0})) ;
    }

} // share_accounts_ajax



// show/hide ajax debug log checkbox in bottom of page. Only used if debug_ajax? / DEBUG_AJAX is true
function show_debug_log_checkbox(checkbox) {
    var debug_log = document.getElementById('debug_log') ;
    if (!debug_log) {
        add2log('show_debug_log_checkbox: debug log was no found') ;
        return ;
    }
    if (checkbox.checked) debug_log.style.display = '' ;
    else debug_log.style.display = 'none' ;
}

// catch ajax:error for any grant write ajax links
// gift_posted_3b_html key translate key used for twitter & vkontakte.
$(document).ready(function() {
    var id = ".grant_write_ajax_link" ;
    var pgm, msg ;
    $(id).unbind("ajax:beforeSend") ;
    $(id).bind("ajax:beforeSend", function (xhr, settings) {
        var pgm = id + '.ajax:beforeSend: ' ;
        clear_flash_and_ajax_errors() ;
    })
    $(id).unbind("ajax:error") ;
    $(id).bind("ajax:error", function(jqxhr, textStatus, errorThrown){
        pgm = id + '::ajax:error: ' ;
        try {
            if (leaving_page) return ;
            var err = add2log_ajax_error(pgm, jqxhr, textStatus, errorThrown);
            var url = '' + jqxhr.target + '' ;
            // http://localhost/util/grant_write_vkontakte
            // http://localhost/util/grant_write_twitter
            var url_a = url.split('_') ;
            var provider = url_a[url_a.length-1] ;
            var valid_providers = ['vkontakte', 'twitter'] ;
            if (valid_providers.indexOf(provider) == -1) var key = 'js.grant_write.ajax_error' ;
            else var key = 'js.grant_write.' + provider + '_ajax_error' ;
            add_to_tasks_errors(I18n.t(key, {error: err, url: url, location: 18, debug: 1})) ;
        }
        catch (err) {
            add2log(pgm + 'failed with JS error: ' + err) ;
            add_to_tasks_errors(I18n.t('js.grant_write.js_error', {error: err, location: 18, debug: 2})) ;
        }
    }) // ajax:error
})

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



//
// methods for share gift LOV - client side share link - omniauth providers and other providers with share link functionality
//
// setup:
// 1) add share link provider to ruby hash constant SHARE_GIFT_API_NAME        (config/initializers/omniauth.rb)
// 2) add any max text length to ruby hash constant API_POST_MAX_TEXT_LENGTHS  (config/initializers/omniauth.rb)
// 3) check API_POST_MAX_TEXT_LENGTHS => SHARE_GIFT_MAX_TEXT_LENGTHS ruby code (config/initializers/omniauth.rb)
// 4) add share gift link to translation key en.js.share_gift.href_<provider>  (conig/locales/en.yml)
// 5) check "extra" information in util_controller.share_gift and JS methods get_share_gift_link and share_gift
// 6) test
//

// share gift: disable LOV and show ajax spinner
function share_gift_lov_disable (gift_id) {
    var lov_id = 'share_gift_' + gift_id ;
    var lov = document.getElementById(lov_id) ;
    if (!lov) return ;
    lov.disabled = true ;
    lov.readonly = true ;
    // show ajax spinner
    var img_id = 'share_gift_spinner_' + gift_id ;
    var img = document.getElementById(img_id) ;
    if (!img) {
        // add ajax spinner
        var parent = lov.parentNode ;
        img = document.createElement("img");
        img.id = img_id ;
        img.src = '/images/ajax-loading-18.gif' ;
        img.style.display = 'none' ;
        var next_sib = lov.nextSibling ;
        if (next_sib) parent.insertBefore(img, next_sib) ;
        else parent.appendChild(img) ;
    }
    img.style.display = '' ;
} // share_gift_lov_disable

// share_gift: enable LOV and hide ajax spinner
function share_gift_lov_enable (gift_id) {
    var lov_id = 'share_gift_' + gift_id ;
    var lov = document.getElementById(lov_id) ;
    if (!lov) return ;
    lov.disabled = false ;
    lov.readonly = false ;
    lov.options[0].selected = 'selected' ;
    // hide ajax spinner
    var img_id = 'share_gift_spinner_' + gift_id ;
    var img = document.getElementById(img_id) ;
    if (!img) return ;
    img.style.display = 'none' ;
} // share_gift_lov_enable

// share gift: get deep link for share gift from server. returns ajax error message or calls share_gift
function get_share_gift_link (self) {
    var pgm = 'get_share_gift_link: ' ;
    var debug = 0 ;
    var table_id = 'task_errors' ;
    try {
        debug = 1 ;
        if (self.value == '') return;
        var provider = self.value;
        // alert('self.value = ' + self.value + ', self.id = ' + self.id) ;
        debug = 2 ;
        // id format share_gift_<gift_id>
        if (!self.id || !self.id.match(/^share_gift_\d+$/)) {
            // id missing or invalid. id format must be ....
            add_to_tasks_errors(I18n.t('js.share_gift.invalid_id', {location: 21, debug: debug})) ;
            return ;
        }
        var gift_id = self.id.split('_')[2]; // id format share_gift_<gift_id>
        table_id = 'gift-' + gift_id + '-links-errors' ;
        // check if information for share gift link already is available in page
        // (deep link in url and provider without "extra" information
        var link = window.location.href;
        var pos = link.indexOf('?');
        if (pos != -1) link = link.substr(0, pos); // strip query string
        debug = 3 ;
        if (link.match(/\/gifts\/[a-zA-Z0-9]{30}$/) && (['twitter'].indexOf(provider) == -1)) {
            // all information for share gift link is in current page - skip ajax request to server
            var extra = '';
            debug = 4 ;
            if (provider == 'facebook') extra = $("meta[property='fb:app_id']").attr("content");
            debug = 5 ;
            share_gift(provider, gift_id, link, extra);
            return;
        }
        // send share gift request to server. Returns link or an error message
        debug = 6
        clear_ajax_errors(table_id) ;
        share_gift_lov_disable(gift_id) ;
        $.ajax({
            url: "/util/share_gift.js",
            type: "POST",
            dataType: 'script',
            data: { provider: provider, gift_id: gift_id },
            error: function (jqxhr, textStatus, errorThrown) {
                debug = 7 ;
                if (leaving_page) return;
                var pgm = pgm + '.error: ';
                var err = add2log_ajax_error('share_gift.ajax.error: ', jqxhr, textStatus, errorThrown);
                // inject ajax error message in page header
                add_to_tasks_errors3(table_id, I18n.t('js.share_gift.ajax_error', {error: err, location: 21, provider: provider, debug: debug})) ;
            },
            complete: function() {
                // add2log(pgm + 'complete') ;
                share_gift_lov_enable(gift_id);
            }
        });
    }
    catch (err) {
        add2log(pgm + 'failed with JS error: ' + err) ;
        add_to_tasks_errors3(table_id, I18n.t('js.share_gift.js_error', {error: err, location: 20, debug: debug})) ;
    }
} // get_share_gift_link

// share gift: get text/description for share gift link in current page
function get_share_gift_text (gift_id) {
    var div_id = "gift-" + gift_id + "-overflow-text" ;
    var div = document.getElementById(div_id) ;
    var text ;
    if (div) {
        text = div.innerHTML ;
        var pos = text.indexOf('</a>','\n') ;
        text = text.substr(pos+4) ;
    }
    else text = document.title ;
    text = text.trim().substr(2) ; // remove :
    text = text.replace(/\s*<br>\s*/g,'\n') ; // replace <br> with newline
    return text ;
} // get_gift_text

// share gift: get image for share gift link in current page
function get_share_gift_image_url(gift_id) {
    var image_id = "gift-" + gift_id + "-image";
    var image = document.getElementById(image_id);
    var image_url;
    if (image) image_url = image.src;
    else image_url = '/images/sacred-economics.jpg';
    if (image_url.substr(0,1) == '/') {
        // add protocol and domain to image url
        var url = window.location.href ;
        var url_a = url.split('/') ;
        var domain = url_a[0] + '//' + url_a[2] ;
        image_url = domain + image_url ;
    }
    return image_url ;
} // get_share_gift_image_url

// share gift: callback for util_controller.share gift. Also called direct from get_share_gift_link if all information for share gift link already was available
function share_gift(provider, gift_id, link, extra) {
    var pgm = 'share_gift: ';
    var debug = 0 ;
    var table_id = 'gift-' + gift_id + '-links-errors' ;
    try {
        // alert(pgm + 'provider = ' + provider + ', gift_id = ' + gift_id + ', link = ' + link + ', extra = ' + extra) ;
        debug = 1 ;
        var share_gift = document.getElementById('share_gift');
        if (!share_gift) return; // share gift link was not found
        debug = 2 ;
        var max_lng = SHARE_GIFT_MAX_TEXT_LENGTHS[provider] ;
        if (max_lng === undefined) max_lng = 0 ;
        debug = 3 ;
        if (!gift_id || !('' + gift_id).match(/^\d+$/)) {
            add_to_tasks_errors(I18n.t('js.share_gift.invalid_id', {location: 23, debug: debug})) ;
            return ;
        }
        // todo: tumblr - split text in name and description (https://www.tumblr.com/share/link?url=%{link}&name=%{name}&description=%{description}
        // make share gift link. Setup I18n.t translation
        debug = 4 ;
        var key, text, app_id, redirect_uri, image, href ;
        key = 'js.share_gift.href_' + provider ;
        if (provider == 'twitter') text = extra ; // special server side text truncation (preserve tags)
        else if (max_lng == -1) text = '' ; // text not used
        else {
            text = get_share_gift_text(gift_id) ;
            if ((max_lng > 0) && (text.length > max_lng)) text = text.substr(0, max_lng) ;
        }
        // app_id - only facebook
        debug = 5 ;
        if (['facebook'].indexOf(provider) != -1) app_id = extra ;
        // redirect_uri - only facebook
        if (['facebook'].indexOf(provider) != -1) {
            redirect_uri = window.location.href ;
            var pos = redirect_uri.indexOf('?') ;
            if (pos != -1) redirect_uri = redirect_uri.substr(0,pos) ;
            redirect_uri = redirect_uri + '?share_gift=facebook' ;
        }
        // image - only pinterest
        debug = 6 ;
        if (['pinterest'].indexOf(provider) != -1) image = get_share_gift_image_url(gift_id) ;
        // translate
        debug = 7 ;
        href = I18n.t(key, {link        : encodeURIComponent(link),
            text        : encodeURIComponent(text),
            app_id      : encodeURIComponent(app_id),
            redirect_uri: encodeURIComponent(redirect_uri),
            image       : encodeURIComponent(image),
            locale      : "en"}) ; // always english when translation href_<provider> key
        // check translation
        debug = 8 ;
        if (!href.match(/^https?:\/\//)) {
            add_to_tasks_errors3(table_id, I18n.t('js.share_gift.missing_translation', {provider: provider, location: 23, debug: debug})) ;
            return ;
        }
        // link ready
        debug = 9 ;
        share_gift.href = href ;
        share_gift.target = '_blank';
        if (['facebook'].indexOf(provider) != -1) share_gift.target = '' ;
        // alert('key = ' + key + ', href = ' + href) ;
        debug = 10 ;
        share_gift.click() ;
    }
    catch (err) {
        add2log(pgm + 'failed with JS error: ' + err) ;
        add_to_tasks_errors3(table_id, I18n.t('js.share_gift.js_error', {error: err, location: 22, debug: debug})) ;
    }
} // share_gift


// Fix bug. App is displayed in a iFrame for opera < 12.16
// http://stackoverflow.com/questions/326069/how-to-identify-if-a-webpage-is-being-loaded-inside-an-iframe-or-directly-into-t
function inIframe () {
    try {
        return window.self !== window.top;
    } catch (e) {
        return true;
    }
} // inIframe



// setup new gift link preview in gifts/index page
// fetch open graph meta tags with ajax and display preview information under link
// typing delay 2 seconds.

var gift_open_graph_url_timer;                //timer identifier

// user is done typing - get open graph meta tags in an ajax request - gift_open_graph_url_preview is called in ajax response
function gift_open_graph_url_done () {
    var url = document.getElementById('gift_open_graph_url1').value ;
    if (url == '') return ;
    // setup ajax request
    $.ajax({
        url: "/util/open_graph.js",
        type: "POST",
        dataType: 'script',
        data: { url: url },
        error: function (jqxhr, textStatus, errorThrown) {
            var pgm = 'gift_open_graph_url_done: ajax: error: ' ;
            if (leaving_page) return ;
            var err = add2log_ajax_error(pgm, jqxhr, textStatus, errorThrown) ;
            add_to_tasks_errors(I18n.t('js.open_graph.ajax_error', {error: err, location: 24, debug: 0}));
        }
    });
} // gift_open_graph_url_done

// index/gift page: sync content of gift_open_graph_url1 and gift_open_graph_url2 fields (create new gift)
function gift_open_graph_url_sync (field1) {
    // alert('oninput. id = ' + field1.id + ', value = ' + field1.value) ;
    var id2 ;
    if (field1.id == 'gift_open_graph_url1') id2 = 'gift_open_graph_url2' ;
    else id2 = 'gift_open_graph_url1' ;
    var field2 = document.getElementById(id2) ;
    if (!field2) return ;
    field2.value = field1.value ;
    // setup timer. fire ajax request in 2 seconds
    clearTimeout(gift_open_graph_url_timer);
    if (field1.value != '') {
        gift_open_graph_url_timer = setTimeout(gift_open_graph_url_done, 2000);
    }
} // gift_open_graph_url_sync

// preview link before create new gift
// response from /util/open_graph.js ajax request in gift_open_graph_url_done
function gift_open_graph_url_preview(url, title, description, image) {
    // alert('gift_open_graph_url_preview: url = ' + url + ', title = ' + title + ', description = ' + description + ', image = ' + image);
    var open_graph_url_preview = document.getElementById('open_graph_url_preview') ;
    if (!open_graph_url_preview) return ;
    // create table with image, title (bold) and description
    var table, tbody, tr, td, img, b, t ;
    table = document.createElement('TABLE');
    tbody = document.createElement('TBODY');
    table.appendChild(tbody);
    // add image
    if (image != '') {
        tr = document.createElement('TR') ;
        tbody.appendChild(tr) ;
        td = document.createElement('TD') ;
        tr.appendChild(td) ;
        img = document.createElement('IMG') ;
        img.src = image ;
        img.width = 200 ;
        td.appendChild(img) ;
    }
    // add bold title
    tr = document.createElement('TR') ;
    tbody.appendChild(tr) ;
    td = document.createElement('TD') ;
    tr.appendChild(td) ;
    b = document.createElement('B') ;
    td.appendChild(b) ;
    t = document.createTextNode(title) ;
    b.appendChild(t) ;
    // add description
    tr = document.createElement('TR') ;
    tbody.appendChild(tr) ;
    td = document.createElement('TD') ;
    tr.appendChild(td) ;
    t = document.createTextNode(description) ;
    td.appendChild(t) ;
    // remove any old preview
    while (open_graph_url_preview.firstChild) {
        open_graph_url_preview.removeChild(open_graph_url_preview.firstChild);
    }
    // insert preview
    open_graph_url_preview.appendChild(table) ;
} // gift_open_graph_url_preview



// custom confirm box - for styling
// http://lesseverything.com/blog/archives/2012/07/18/customizing-confirmation-dialog-in-rails/
// http://www.pjmccormick.com/nicer-rails-confirm-dialogs-and-not-just-delete-methods
// tried with coffee script. Tried with javascript. not working.
/*
$.rails.allowAction = function(link) {
    if (!link.attr('data-confirm')) {
        return true;
    }
    $.rails.showConfirmDialog(link);
    return false;
};

$.rails.confirmed = function(link) {
    link.removeAttr('data-confirm');
    return link.trigger('click.rails');
};

$.rails.showConfirmDialog = function(link) {
    var html;
    html = "<div id=\"dialog-confirm\" title=\"Are you sure you want to delete?\">\n  <p>These item will be permanently deleted and cannot be recovered. Are you sure?</p>\n</div>";
    return $(html).dialog({
        resizable: false,
        modal: true,
        buttons: {
            OK: function() {
                $.rails.confirmed(link);
                return $(this).dialog("close");
            },
            Cancel: function() {
                return $(this).dialog("close");
            }
        }
    });
};
*/






