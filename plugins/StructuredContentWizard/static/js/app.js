$(document).ready(function() { 
    // Paginate the steps with the jQuery.evtpaginate plugin.
    var wrap = $('ul#steps');

    $('#previous-step-button').click(function(){
        // Data doesn't really need to be validated when moving back--only forward.
        wrap.trigger('prev.evtpaginate');
        return false;
    });

    $('#next-step-button').click(function(){
        // Before moving on verify that the data on this step is valid.
        if ( _validate_fields() ) {
            // All required fields have been filled in.
            wrap.trigger('next.evtpaginate');
        }
        return false;
    });

    $('#submit-wizard').click(function(){
        // The user has clicked the Complete Wizard button. We need to verify
        // the contents of the current step, then submit the form.
        if ( _validate_fields() ) {
            // All required fields have been filled in, so we can submit the
            // form now. Also show the "processing" spinner, and set the
            // target to the page, not the dialog box.
            $('img#processing').show();
            if ( $('input[name="asset_id"]').val() )
                $('form#wizard_steps').attr('target','_top');
            $('#wizard_steps').submit();
        }
        return false;
    });
    
    // Hide and show the appropriate buttons
    wrap.bind( 'finished.evtpaginate', function(e, num, isFirst, isLast ){ 
        if (isFirst && isLast) {
            // A one-page wizard.
            $('#previous-step-button').addClass('hidden');
            $('#next-step-button').addClass('hidden');
            $('#submit-wizard').removeClass('hidden');
        }
        else if (isFirst) {
            // This is the first page. Hide the "Previous" pagination button.
            $('#previous-step-button').addClass('hidden');
            $('#next-step-button').removeClass('hidden');
            $('#submit-wizard').addClass('hidden');
        }
        else if (isLast) {
            // This is the last page. Hide the "Next" button and show the submit button.
            $('#previous-step-button').removeClass('hidden');
            $('#next-step-button').addClass('hidden');
            $('#submit-wizard').removeClass('hidden');
        }
        else {
            // Somewhere in the middle--show both pagination buttons and hide the submit.
            $('#previous-step-button').removeClass('hidden');
            $('#next-step-button').removeClass('hidden');
            $('#submit-wizard').addClass('hidden');
        }
    });

    // call the jQuery.evtpaginate plugin. This is responsible for only
    // showing one step at a time.
    wrap.evtpaginate({perPage:1});

    function _validate_fields() {
        // Validate the fields on the current step. If a field is marked as
        // required, ensure that a value is present. Return notification of a
        // problem so that the user can correct it and the step doesn't change.
        var requireds_missing = 0;
        // Clear the status bar of any notifications, and hide it by default.
        $('.step:visible .msg').html('');
        $('.step:visible .msg').addClass('hidden');
        // Check each field on this step. If it's marked as required, verify
        // something has been entered.
        $('.step:visible input, .step:visible select, .step:visible textarea').each(function() {
            // Reset the field title display to normal. If the data is being
            // revalidated we want the display to be accurate.
            $('label[for='+$(this).attr('name')+']').removeClass('required_missing');

            // Is this a required field? Does it have a value?
            if ( $(this).parent().parent().hasClass('required') ) {
                if ( $(this).val() == '' ) {
                    // This field is required, and is not entered. Notify the
                    // user and make them fix it.
                    $('label[for='+$(this).attr('name')+']').addClass('required_missing');
                    var old_msg = $('.step:visible .msg').html();
                    // Grab the field title and remove the " *" that marks it
                    // as required, just to display cleanly in the msg bar.
                    var field_title = $('label[for='+$(this).attr('name')+']').text();
                    field_title = field_title.replace(' *', '');
                    var new_msg = '<div>The field <strong>'+field_title
                            +'</strong> is a required field but has no value.</div>';
                    $('.step:visible .msg').html(old_msg+new_msg);
                    // Update the requireds_missing var so that the step doesn't
                    // change and the user can fix the problem.
                    requireds_missing = 1;
                }
            }
        });
        if (requireds_missing) {
            // If there are required fields without data, show the message
            // to the user so they can correct it.
            $('.step:visible .msg').removeClass('hidden');
            return false;
        }
        else {
            // Fields validated and are ok!
            return true;
        }
    }

});
