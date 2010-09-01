package MT::Asset::StructuredContent;

use strict;
use base qw( MT::Asset );

__PACKAGE__->install_properties( { class_type => 'structured_content', } );
__PACKAGE__->install_meta( { columns => [ 
        'yaml',
        'wizard_id',
     ], }
);

sub class_label { MT->translate('Structured Content'); }
sub class_label_plural { MT->translate('Structured Content'); }

sub as_html {
    # When an asset is inserted into an Entry/Page, we want to specially-
    # construct what is returned. The asset_output_template gets used to
    # decide what the HTML looks like, and that is inserted into the object.
    my $asset   = shift;
    my ($param) = @_;
    my $app     = MT->instance;
    my $text    = '';
    
    # Grab the YAML where the wizard details were saved.
    my $yaml = YAML::Tiny->read_string( $asset->yaml );
    # The data we need is always in the first array of the YAML structure,
    # so just copy it right back to the $yaml variable.
    $yaml = $yaml->[0];

    # Find which wizard was used to create this asset. There should only be
    # one wizard per asset.
    my ($wizard_id, $tmpl_identifier);
    require StructuredContentWizard::CMS;
    foreach my $wizard ( keys %{$yaml} ) {
        $wizard_id = $wizard;
        # Now look at asset_output_template to find the template identifier
        # to use to render the asset.
        my $ts_id = $app->blog->template_set;
        my $r = $app->registry('template_sets');
        my $scw_yaml = StructuredContentWizard::CMS::_load_scw_yaml($ts_id);
        $tmpl_identifier = $scw_yaml->{$wizard}->{asset_output_template};
    }

    # Now that we've got the template identifier that the wizard is supposed
    # to be using, output the wizard contents to that template.
    use MT::Template::Context;
    my $ctx = MT::Template::Context->new;
    # Place the $asset in the stash so that the template has an asset
    # context, and can publish the template without error (at least, assuming
    # the template is crafted correctly).
    local $ctx->{__stash}{asset} = $asset;
    # Load the specified template. If no template is found, throw an error!
    # Look for both the template identifier or the template name.
    my $tmpl = MT->model('template')->load([
        {
            identifier => $tmpl_identifier,
            blog_id    => $app->blog->id,
            type       => 'custom',
        }
        => -or =>
        {
            name    => $tmpl_identifier,
            blog_id => $app->blog->id,
            type    => 'custom',
        }
    ]);
    if (!$tmpl) {
        return $app->error("The template specified for this Structured "
            . "Content asset could not be found (Wizard: $wizard_id, "
            . "Template Identifier: $tmpl_identifier)."
        );
    }

    # Now build the template, finally.
    my $built_tmpl = $tmpl->build($ctx)
        or $app->error( $tmpl->errstr );

    # The enclose method used here is responsible for encapsulating the
    # asset/markup so that MT can track the asset/entry relationship.
    return $asset->enclose( $built_tmpl );
}

1;

__END__
