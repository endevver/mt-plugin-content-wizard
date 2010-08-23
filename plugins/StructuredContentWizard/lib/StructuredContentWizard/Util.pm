package StructuredContentWizard::Util;

use strict;

sub find_field_def {
    # Receive the Wizard ID and Field ID, and use that to find the field
    # definition. Then return that field definition.
    my ( $app, $field_id, $wizard_id ) = @_;
    my $opt;

    if ( $app->blog ) {
        my $ts_id = $app->blog->template_set;
        my $r = $app->registry('template_sets');
        my $steps = $r->{$ts_id}->{structured_content_wizards}
                        ->{$wizard_id}->{steps};
        # Go through each defined step. We don't really need to do anything
        # here because the fields are what we're really interested in.
        foreach my $step_name ( keys %{$steps} ) {
            my $step   = $steps->{$step_name};
            my $fields = $step->{fields};
            # Now for each field, check to see if the supplied field_id
            # matches the current field. If it is a match, return that
            # field definition.
            foreach my $optname ( keys %{$fields} ) {
                if ($optname eq $field_id) {
                    $opt = $fields->{$field_id};
                }
            }
        }
    }
    return $opt;
}

1;

__END__

