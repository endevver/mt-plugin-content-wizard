package StructuredContentWizard::CMS;

use strict;
use warnings;

use ConfigAssistant::Util qw( find_theme_plugin process_file_upload );

use StructuredContentWizard::Util;

sub init_app {
    my $plugin = shift;
    my ($app) = @_;
    return if $app->id eq 'wizard';

    # The wizard's fields defined tags that the user can place in templates.
    my $r = $plugin->registry;
    $r->{tags} = sub { _load_tags( $app, $plugin ) };
}

sub update_menus {
    # Add the Structured Content Wizard menu items only if the Structured
    # Content Wizrd is enabled on this blog.
    return {
        'create:structured_content' => {
            label      => 'Structured Content',
            # The 300's seem to be asset-related stuff, so just push the
            # menu option there to match other things.
            order      => '310',
            dialog     => 'start_scw',
            view       => 'blog',
            condition  => sub {
                my $app = MT->instance;
                my $blog = $app->blog;
                return 0 if !$blog;
                my $plugin = MT->component('StructuredContentWizard');
                return if !$plugin;
                # If any wizards were defined, show the menu item.
                my $ts_id   = $blog->template_set;
                return 1 if MT->registry('template_sets', $ts_id, 'structured_content_wizards');
                return 0;
            },
        },
    };
}

sub _load_scw_yaml {
    # Load the wizard YAML. It may be specified inline with the rest of the
    # config.yaml contents, or it may be specified as a separate file. Either
    # way, we want to load it.
    my $app = MT->instance;
    # If a template set ID was provided, grab it. Otherwise get the current
    # template set ID.
    my ($ts_id) = @_ ? shift : $app->blog->template_set;

    my $yaml = $app->registry('template_sets')->{$ts_id}
                    ->{structured_content_wizards};
    # Just fail silently if there are no wizards defined. 
    return unless $yaml;

    if ( $yaml =~ m/^[-\w]+\.yaml$/ ) {
        # This is a reference to another YAML file. Load it and return the
        # contents.
        $yaml = MT->registry('template_sets', $ts_id, 'structured_content_wizards');
    }
    else {
        # This is just plain, inline YAML.
        $yaml = $app->registry('template_sets')->{$ts_id}
                    ->{structured_content_wizards};
    }
}

sub start {
    # The user wants to create some structured content. First we give them
    # the chance to select which wizard to use (if more than one wizard
    # exists), then we create the "steps" for the wizard based on how it
    # was defined.
    my $app    = MT->instance;

    # Just give up if, for some reason, this isn't a valid blog.
    return unless $app->can('blog');

    my $param  = {};
    my $plugin = MT->component('StructuredContentWizard');
    
    # To get started, a wizard must be selected. If many wizards are
    # available, let the user pick which to use. If only one, set it as the
    # default and just move along.
    if ( !$app->param('wizard_id') ) {
        my @wizards_loop = _select_wizard();
        $param->{wizards_loop} = \@wizards_loop;

        if ( scalar @wizards_loop == 1 ) {
            # Only one wizard was found. Just use that as the default.
            $app->param( 'wizard_id', $wizards_loop[0]->{id} );
        }
        else {
            # Many wizards were found, so let the user pick which to use.
            return $app->load_tmpl('wizard_select.mtml', $param);
        }
    }
    
    # At this point we have a valid wizard selected. Use it to build the
    # pages of options.
    $param->{wizard_id} = $app->param('wizard_id');
    my @steps = _build_wizard_options();
    $param->{steps_loop} = \@steps;
    $param->{steps_count} = scalar @steps;

    # Passing the template set ID to wizard_steps makes it easy to save.
    $param->{ts_id} = $app->blog->template_set;
    my $scw_yaml = _load_scw_yaml($app->blog->template_set);
    $param->{wizard_label} = $scw_yaml->{$app->param('wizard_id')}->{label};

    return $app->load_tmpl('wizard_steps.mtml', $param);
}

sub save {
    # Save the submitted wizard content. When saving, the wizard content is
    # "poured" into the specified template. That template is then saved as a
    # new Asset, which a user can insert into an entry.
    my $app = MT->instance;

    # Refer to the wizard's YAML/registry entry to find all of the fields
    # that the user has just worked with. Then save the value the user
    # entered to a new YAML structure that can be saved as an asset.
    my $wizard_id = $app->param('wizard_id');
    my $ts_id     = $app->param('ts_id');
    my $scw_yaml  = _load_scw_yaml($ts_id);
    my $steps     = $scw_yaml->{$wizard_id}->{steps};
    my $data = {};
    # Go through each defined step. We don't really need to do anything here
    # because the fields are what we're really interestd in.
    foreach my $step_name ( keys %{$steps} ) {
        my $step   = $steps->{$step_name};
        my $fields = $step->{fields};
        # Now for each field, get the entered value and set it.
        foreach my $optname ( keys %{$fields} ) {
            # Check that a tag has been defined, because we use the tag name
            # as the YAML key.
            if ( $fields->{$optname}->{tag} ) {
                my $opt = StructuredContentWizard::Util::find_field_def($app, $optname, $wizard_id);
                my $field_id = $wizard_id . '_' . $optname;
                # If this is a file upload, it needs some special handling.
                if ($opt->{type} eq 'file') {
                    my $result = process_file_upload(
                        $app, 
                        $field_id, 
                        'support', # FYI: goes to blog_id '0'
                        $opt->{destination}
                    );
                    if ( $result->{status} == ConfigAssistant::Util::ERROR() ) {
                        return $app->error(
                            "Error uploading file: " . $result->{message} );
                    }
                    next if ($result->{status} == ConfigAssistant::Util::NO_UPLOAD);
                    # The file was successfully uploaded and an asset was
                    # created for it. Now set the asset ID to the tag so
                    # that is can be used later.
                    $data->{ $fields->{$optname}->{tag} } = $result->{asset}->{id};
                }
                else {
                    my $value = $app->param($field_id);
                    $data->{ $fields->{$optname}->{tag} } = $value;
                }
            }
        }
    }
    # Create the YAML entry to save the data.
    my $yaml = YAML::Tiny->new;
    $yaml->[0]->{$wizard_id} = $data;
    
    # Create a new asset and save the YAML structure
    use MT::Asset::StructuredContent;
    my $asset = MT::Asset::StructuredContent->new;
    $asset->label(       $app->param('wizard_label') );
    $asset->description( "Structured Content"        );
    $asset->wizard_id(   $wizard_id                  );
    $asset->yaml(        $yaml->write_string()       );
    $asset->blog_id(     $app->blog->id              );
    $asset->created_by(  $app->user->id              );
    $asset->save;

    # Push the asset to MT's File Options page. Here the user can specify a
    # label, description, and tags for the new asset, and also choose whether
    # to insert it into a new entry.
    return $app->complete_insert(
        asset => $asset,
    );

}

sub _select_wizard {
    my $app   = MT->instance;
    my $param = {};

    # Grab the current blog's template set ID and use that to determine if
    # any structured content wizards were created.
    my $ts_id = $app->blog->template_set;
    my $yaml  = _load_scw_yaml($ts_id);

    # Sort the wizards. They may have been ordered, so be sure to respect
    # that. Push them into a loop.
    my @wizards_loop;
    foreach my $wizard_id (
        sort {
            ( $yaml->{$a}->{order} || 999 ) <=> ( $yaml->{$b}->{order} || 999 )
        } keys %{$yaml}
      )
    {
        # Grab the wizard definition.
        my $wizard = $yaml->{$wizard_id};
        push @wizards_loop, { 
            id    => $wizard_id, 
            label => $wizard->{label}, 
        };
    }

    return @wizards_loop;
}

# A good deal of this method was copied from the Config Assistant plugin
# (v1.10.3) and tweaked. Because we want to be able to use the fields and
# capabilities already defined within CA, this is a good way to get started!
sub _build_wizard_options {
    my $app = MT->instance;
    my $wizard_id = $app->param('wizard_id');
    
    # Use Config Assistant's config types. This provides a variety of field
    # types that will probably be useful for the wizard interface.
    my $types = $app->registry('config_types');
    
    my @steps_and_fields;
    my @missing_required;
    
    require MT::Template::Context;
    my $ctx = MT::Template::Context->new();
    
    # Grab the wizard definitions
    my $ts_id = $app->blog->template_set;
    my $scw_yaml = _load_scw_yaml($ts_id);
    my $steps = $scw_yaml->{$wizard_id}->{steps};
    
    # Look at each defined Step. Each Step will have it's own "page" to help
    # organize the Wizard into something easy to walk through.
    foreach my $step_name (
        sort { ( $steps->{$a} ) <=> ( $steps->{$b} ) } keys %{$steps}
      )
    {
        my $step = $steps->{$step_name};
        my $label = $step->{label} ne '' ? &{$step->{label}} : '';

        my @fields_data;

        # Build the fields that should appear on this step.
        my $fields = $step->{fields};
        foreach my $optname (
            sort {
                ( $fields->{$a}->{order} || 999 ) <=> ( $fields->{$b}->{order} || 999 )
            } keys %{$fields}
          )
        {
            my $field = $fields->{$optname};
            
            # The $field_id needs to be unique, but something we can grab on
            # to when saving. Prepending the $wizard_id should be a good way
            # to do this.
            my $field_id = $wizard_id . '_' . $optname;
            
            if ( $field->{'type'} eq 'separator' ) {
                # The separator "type" is handled specially here because it's not
                # really a "config type"-- it isn't editable and no data is saved
                # or retrieved. It just displays a separator and some info.
                my $out;
                my $show_label =
                  defined $field->{show_label} ? $field->{show_label} : 1;
                my $label = $field->{label} ne '' ? &{$field->{label}} : '';
                $out .=
                    '  <div id="field-'
                  . $field_id
                  . '" class="field field-top-label pkg field-type-'
                  . $field->{type} . '">' . "\n";
                $out .= "    <div class=\"field-header\">\n";
                $out .= "        <h3>$label</h3>\n" if $show_label;
                $out .= "    </div>\n";
                $out .= "    <div class=\"field-content\">\n";
                if ( $field->{hint} ) {
                    $out .= "       <div>" . $field->{hint} . "</div>\n";
                }
                $out .= "    </div>\n";
                $out .= "  </div>\n";
                push @fields_data, { content => $out };
            }
            elsif ( $types->{ $field->{'type'} } ) {
                # If the user didn't fill in all values, they may have to go
                # back and correct that. So, capture the previously set field
                # info and use that. Then fall back to the default value,
                # then just a blank value.
                my $value = $app->param($field_id) || $field->{default} || '';

                my $out;
                my $label = $field->{label} ne '' ? &{$field->{label}} : '';
                my $required = $field->{required} ? 'required' : '';
                if ($required) {
                    if (!$value) {
                        # There is no value for this field, and it's a required
                        # field, so we need to tell the user to fix it!
                        push @missing_required, { label => $label };
                    }
                    # Append the required flag.
                    $label .= ' <span class="required-flag">*</span>';
                }
                $out .=
                    '  <div id="field-'
                  . $field_id
                  . '" class="field field-left-label pkg field-type-'
                  . $field->{type} . ' ' . $required . '">' . "\n";
                $out .= "    <div class=\"field-header\">\n";
                $out .=
                    "      <label for=\"$field_id\">"
                  . $label
                  . "</label>\n";
                $out .= "    </div>\n";
                $out .= "    <div class=\"field-content\">\n";
                my $hdlr =
                  MT->handler_to_coderef( $types->{ $field->{'type'} }->{handler} );
                $out .= $hdlr->( $app, $ctx, $field_id, $field, $value );

                if ( $field->{hint} ) {
                    $out .=
                      "      <div class=\"hint\">" . $field->{hint} . "</div>\n";
                }
                $out .= "    </div>\n";
                $out .= "  </div>\n";
                push @fields_data, { content => $out };
            }
            else {
                MT->log(
                    {
                        message => 'Structured Content Wizard encountered '
                            . 'an unknown config type: ' . $field->{'type'}
                    }
                );
            }
        }

        # Push all of the steps and fields along with the label and hint to
        # create the "step" for the user to interact with.
        push @steps_and_fields, {
            label       => $label,
            hint        => $step->{hint},
            fields_loop => \@fields_data,
        };
    }

    return @steps_and_fields;
}

# A good deal of this method was copied from the Config Assistant plugin
# (v1.10.3) and tweaked. Because we want to be able to use the fields and
# capabilities already defined within CA, this is a good way to get started!
sub _load_tags {
    my $app  = shift;
    my $tags = {};
    
    # To parse the link-group config type tags.
    require JSON;
    # Now register template tags for each of the template set options.
    for my $sig ( keys %MT::Plugins ) {
        my $plugin = $MT::Plugins{$sig};
        my $obj    = $MT::Plugins{$sig}{object};
        my $r      = $obj->{registry};
    
        # Look through each template set for any wizards that might be defined.
        my @sets = keys %{ $r->{'template_sets'} };
        foreach my $ts_id (@sets) {
            my $scw_yaml = _load_scw_yaml($ts_id);
            if ( $scw_yaml ) {
                # At least one wizard has been defined for this theme.
                foreach my $wizard_id ( keys %{ $scw_yaml } ) {
                    my $wizard_id = $wizard_id;
                    my $steps     = $scw_yaml->{$wizard_id}->{steps};

                    foreach my $step_name ( keys %{ $steps } ) {
                        my $step   = $steps->{$step_name};
                        my $fields = $step->{fields};
                        # Now for each field, get the entered value and set it.
                        foreach my $optname ( keys %{$fields} ) {
                            my $option = $fields->{$optname};

                            # If the option does not define a tag name,
                            # then there is no need to register one
                            next if ( !defined( $option->{tag} ) );
                            my $tag = $option->{tag};

                            # TODO - there is the remote possibility that a template set
                            # will attempt to register a duplicate tag. This case needs to be
                            # handled properly. Or does it?
                            # Note: the tag handler takes into consideration the blog_id, the
                            # template set id and the option/setting name.
                            if ( $tag =~ s/\?$// ) {
                                # This is a conditional blog tag
                                $tags->{block}->{$tag} = sub {
                                    # Since this is an asset, we first need to verify that an asset context
                                    # exists. Then load the YAML and grab the appropriate tag, and return the
                                    # value.
                                    my ( $ctx, $args ) = @_;
                                    my $a = $ctx->stash('asset')
                                        or return $ctx->_no_asset_error();
                                    my $yaml = YAML::Tiny->read_string( $a->yaml );
                                    my $value = $yaml->[0]->{$wizard_id}->{$tag};

                                    if ($value) {
                                        return $ctx->_hdlr_pass_tokens(@_);
                                    }
                                    else {
                                        return $ctx->_hdlr_pass_tokens_else(@_);
                                    }
                                };
                            }
                            elsif ( $tag ne '' ) {
                                $tags->{function}->{$tag} = sub {
                                    # Since this is an asset, we first need to verify that an asset context
                                    # exists. Then load the YAML and grab the appropriate tag, and return the
                                    # value.
                                    my ( $ctx, $args ) = @_;
                                    my $a = $ctx->stash('asset')
                                        or return $ctx->_no_asset_error();
                                    if ($a->class ne 'structured_content') {
                                        # Other assets (uploaded with the "file" config type) will just
                                        # return the asset id--for now, at least. It's easy, and I'm not
                                        # sure how many people *don't* use the ...Asset block, anyway.
                                        return $a->id;
                                    }
                                    else {
                                        my $yaml = YAML::Tiny->read_string( $a->yaml );
                                        my $value = $yaml->[0]->{$wizard_id}->{$tag};
                                        return $value;
                                    }
                                };
                                if ($option->{'type'} eq 'checkbox') {
                                    $tags->{block}->{$tag . 'Loop'} = sub {
                                        # Since this is an asset, we first need
                                        # to verify that an asset context exists.
                                        # Then load the YAML and grab the
                                        # appropriate tag, and return the values.
                                        my ( $ctx, $args, $cond ) = @_;
                                        my $a = $ctx->stash('asset')
                                            or return $ctx->_no_asset_error();
                                        my $yaml = YAML::Tiny->read_string( $a->yaml );
                                        my @values = split(',', $yaml->[0]->{$wizard_id}->{$tag} );

                                        # Since this is a block tag that
                                        # loops, we need to cycle through all
                                        # values.
                                        my $out = '';
                                        my $count = 0;
                                        if (@values > 0) {
                                            my $vars = $ctx->{__stash}{vars};
                                            foreach (@values) {
                                                local $vars->{'value'} = $_;
                                                local $vars->{'__first__'} = ($count++ == 0);
                                                local $vars->{'__last__'} = ($count == @values);
                                                defined( $out .= $ctx->slurp( $args, $cond ) ) or return;
                                            }
                                            return $out;
                                        } else {
                                            require MT::Template::ContextHandlers;
                                            return MT::Template::Context::_hdlr_pass_tokens_else(@_);
                                        }
                                    };
                                    $tags->{block}->{$tag . 'Contains'} = sub {
                                        # Since this is an asset, we first need
                                        # to verify that an asset context exists.
                                        # Then load the YAML and grab the
                                        # appropriate tag, and return the values.
                                        my ( $ctx, $args, $cond ) = @_;
                                        my $a = $ctx->stash('asset')
                                            or return $ctx->_no_asset_error();
                                        my $yaml = YAML::Tiny->read_string( $a->yaml );
                                        my @values = split(',', $yaml->[0]->{$wizard_id}->{$tag} );
                                        
                                        # The argument is the value to test for
                                        my $value = $args->{'value'};
                                        
                                        # Test if the specified value is in the array of
                                        # possibly-checked options.
                                        foreach (@values) {
                                            if ($_ eq $value) {
                                                return $ctx->slurp( $args, $cond );
                                            }
                                        }
                                        require MT::Template::ContextHandlers;
                                        return MT::Template::Context::_hdlr_pass_tokens_else(@_);
                                    };
                                } elsif ($option->{'type'} eq 'file') {
                                    # Create a ...Asset block tag, so that all Asset tags can be used.
                                    $tags->{block}->{$tag . 'Asset'} = sub {
                                        # Since this is an asset, we first need to verify that an asset context
                                        # exists. Then load the YAML and grab the appropriate tag, and return the
                                        # value.
                                        my ( $ctx, $args, $cond ) = @_;
                                        my $a = $ctx->stash('asset')
                                            or return $ctx->_no_asset_error();
                                        my $yaml = YAML::Tiny->read_string( $a->yaml );
                                        # Grab the Asset ID
                                        my $value = $yaml->[0]->{$wizard_id}->{$tag};
                                        
                                        # Check that a value was specified/saved in the wizard. 
                                        # If none was specified we need to skip and give up
                                        # because the newest asset will be loaded by default
                                        # (whatever it may be), and we don't want that!
                                        if ($value) {
                                            # Load the specified asset
                                            my $asset = MT->model('asset')->load( $value );
                                            my $out;
                                            if ($asset) {
                                                local $ctx->{'__stash'}->{'asset'} = $asset;
                                                defined( $out = $ctx->slurp( $args, $cond ) ) or return;
                                                return $out;
                                            } else {
                                                require MT::Template::ContextHandlers;
                                                return MT::Template::Context::_hdlr_pass_tokens_else(@_);
                                            }
                                        }
                                    };
                                } elsif ($option->{'type'} eq 'link-group') {
                                    $tags->{block}->{$tag . 'Links'} = sub {
                                        # Since this is an asset, we first need to verify that an asset context
                                        # exists. Then load the YAML and grab the appropriate tag, and return the
                                        # value.
                                        my ( $ctx, $args, $cond ) = @_;
                                        my $a = $ctx->stash('asset')
                                            or return $ctx->_no_asset_error();
                                        my $yaml = YAML::Tiny->read_string( $a->yaml );
                                        # Grab the link-group JSON
                                        my $value = $yaml->[0]->{$wizard_id}->{$tag};
                                        # The JSON data gets escaped and wrapped in quotes when YAML saves
                                        # it. The complexity it creates means we should just fix the 
                                        # string, before handing it off to create a JSON object.
                                        # Remove extra escpaes
                                        $value =~ s/\\(.)/$1/g;
                                        # Reamove leading quote
                                        $value =~ s/^\"//;
                                        # Remove trailing quote
                                        $value =~ s/\"$//;

                                        # Build the link group.
                                        # Wrapping double quotes around the array breaks the JSON::from_json
                                        # method, so check for an empty array (as in, no links supplied).
                                        $value = '[]' if ($value eq '"[]"' || !$value || $value eq '');
                                        # The following two lines appear in CA. I don't understand what it's
                                        # supposed to prove (or if it matters for SCW) but it breaks the tag
                                        # creation. So, ignoring.
                                        #eval "\$value = $value";
                                        #if ($@) { $value = '[]'; }
                                        my $list = JSON::from_json($value);
                                        if (@$list > 0) {
                                            my $out = '';
                                            my $vars = $ctx->{__stash}{vars};
                                            my $count = 0;
                                            foreach (@$list) {
                                                local $vars->{'link_label'} = $_->{'label'};
                                                local $vars->{'link_url'} = $_->{'url'};
                                                local $vars->{'__first__'} = ($count++ == 0);
                                                local $vars->{'__last__'} = ($count == @$list);
                                                defined( $out .= $ctx->slurp( $args, $cond ) ) or return;
                                            }
                                            return $out;
                                        } else {
                                            require MT::Template::ContextHandlers;
                                            return MT::Template::Context::_hdlr_pass_tokens_else(@_);
                                        }
                                    };
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    
    return $tags;
}


1;

__END__
