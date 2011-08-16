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

# Add the Structured Content Wizard menu items only if wizards are defined for
# this blog.
sub update_menus {
    my $app = MT->instance;
    my $menu = {};

    # Wizards only exist as part of a theme, which means they only exist at 
    # the blog level.
    return {} if !$app->blog;

    # Grab any wizards that were defined.
    my $wizards = MT->registry(
        'template_sets', 
        $app->blog->template_set, 
        'structured_content_wizards'
    );

    # Proceed in creating the menu if any wizards were found in this blog.
    if ($wizards) {

        # The 300's seem to be asset-related stuff, so just push the
        # menu options there to match other things.
        my $order = 310;

        # Sort the wizards according to the order key. Then build the menu 
        # items for the wizards.
        foreach my $wizard ( 
            sort { 
                ($wizards->{$a}->{order} || '0') <=> ($wizards->{$b}->{order} || '0') 
            } keys %{$wizards} 
        ) {
            
            # The menu name is kept unique with the wizard key. Use the wizard
            # label for the menu item name, though provide a fallback.
            $menu->{'create:structured_content_' . $wizard} = {
                label       => ($wizards->{$wizard}->{label} || $wizard),
                order       => $order,
                mode => 'start_scw',
                args => {
                    wizard_id => $wizard,
                },
                view        => 'blog',
                condition   => sub {
                    my $app = MT->instance;

                    # Look for any role requirements assigned to this wizard.
                    # Check for "roles" or "role" because mixing them up is easy.
                    my $roles = $wizards->{$wizard}->{roles}
                        || $wizards->{$wizard}->{role}
                        || '';

                    foreach my $role_name ( split(/\s*,\s*/, $roles) ) {
                        my $role = MT->model('role')->load({ name => $role_name })
                            or return 0;

                        my $exists = MT->model('association')->exist({
                            blog_id   => $app->blog->id,
                            author_id => $app->user->id,
                            role_id   => $role->id,
                        });

                        # A system administrator may not specifically have a
                        # user-role-blog association set up, but as a system
                        # administrator they should have permission to get at
                        # the wizards.
                        if ( $app->user->is_superuser ) {
                            $exists = 1;
                        }
                        
                        # The user does not have permission to access this
                        # wizard.
                        return 0 if !$exists;
                    }

                    return 1; # Display the wizard for all users.
                },
            };
            
            $order++;
        }
    }

    return $menu;
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

# The user wants to create some structured content. First we give them
# the chance to select which wizard to use (if more than one wizard
# exists), then we create the "steps" for the wizard based on how it
# was defined.
sub start {
    my $app = MT->instance;

    # Just give up if, for some reason, this isn't a valid blog.
    return unless $app->can('blog');

    my $param  = {};
    my $plugin = MT->component('StructuredContentWizard');

    # If the user is trying to edit an existing SCW asset, we need to use the
    # supplied ID to figure out which wizard they are using.
    my ($asset, $yaml);
    if ( $app->param('id') ) {
        $asset = MT->model('asset')->load( $app->param('id') )
            or return $app->errstr;
        # Grab the YAML where the wizard details were saved.
        $yaml = YAML::Tiny->read_string( $asset->yaml );
        # The data we need is always in the first array of the YAML structure,
        # so just copy it right back to the $yaml variable.
        $yaml = $yaml->[0];
        # Only one key exists at this point--the wizard ID (all saved field
        # data exists inside of the wizard key). Grab that ID and save it
        # so that SCW knows which wizard to use.
        foreach my $wizard_id ( keys %{$yaml} ) {
            $app->param( 'wizard_id', $wizard_id );
        }
        # Lastly, save the ID to be used in the template (we need it to
        # update the existing asset when saving, rather than creating
        # something new.)
        $param->{asset_id} = $app->param('id');
    }
    
    # This is used to track whether to insert the asset into an entry
    # immediately after completion. It is invoked by clicking the "Create
    # Structured Content" toolbar button and creating an asset through there.
    $param->{entry_insert} = $app->param('entry_insert');
    
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
    # Pass the $yaml into _build_wizard_options. If the user is trying to
    # edit an already-saved asset, then $yaml contains the asset contents.
    my @steps = _build_wizard_options($yaml);
    $param->{steps_loop} = \@steps;
    $param->{steps_count} = scalar @steps;

    # Passing the template set ID to wizard_steps makes it easy to save.
    $param->{ts_id} = $app->blog->template_set;
    my $scw_yaml = _load_scw_yaml($app->blog->template_set);
    $param->{wizard_label} = $scw_yaml->{$app->param('wizard_id')}->{label};

    return $app->load_tmpl('wizard_steps.mtml', $param);
}

# Save the submitted wizard content. When saving, the wizard content is
# "poured" into the specified template. That template is then saved as a
# new Asset, which a user can insert into an entry.
sub save {
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
                # Just save the value specified in the field.
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

    # If an ID was supplied, the user is editing an asset. If none, then
    # create a new asset.
    my $asset;
    if ( $app->param('asset_id') ) {

        # This SCW asset is being edited. Load the saved asset and update it.
        $asset = MT->model('asset')->load( $app->param('asset_id') )
            or return $app->errstr;
        $asset->yaml( $yaml->write_string() );
        $asset->modified_by( $app->user->id );
        $asset->save;

        # The asset has been saved. Now just redirect to the Edit Asset page.
        return $app->redirect(
            $app->uri(
                'mode' => 'view',
                'args' => { 
                    '_type'    => 'asset',
                    'id'      => $app->param('asset_id'),
                    'blog_id' => $app->param('blog_id'),
                },
            )
        );
    }

    # Build the asset label. If an asset_label_field was specified in the 
    # wizard YAML, use it. Otherwise, fall back to the wizard label.
    my $asset_label = $data->{ $scw_yaml->{$wizard_id}->{asset_label_field} }
        ? $data->{ $scw_yaml->{$wizard_id}->{asset_label_field} }
        : $app->param('wizard_label');

    # Create a new asset and save the YAML structure
    use MT::Asset::StructuredContent;
    $asset = MT::Asset::StructuredContent->new;
    $asset->label(      $asset_label          );
    $asset->wizard_id(  $wizard_id            );
    $asset->yaml(       $yaml->write_string() );
    $asset->blog_id(    $app->blog->id        );
    $asset->created_by( $app->user->id        );
    $asset->save or die $asset->errstr;

    # Render the template and return the result to the user.
    my $tmpl = MT->model('template')->load({
        blog_id    => $app->blog->id,
        identifier => $scw_yaml->{$wizard_id}->{asset_output_template},
    })
        or die 'The asset output template for this wizard could not be found.';

    require MT::Template::Context;
    my $ctx = MT::Template::Context->new;
    $ctx->stash('asset', $asset);
    my $html = $tmpl->build($ctx) or die $tmpl->errstr;

    # Now that the template has been rendered, insert the result into the 
    # Wizard Complete page for the user to see.
    return $app->load_tmpl( 
        'wizard_complete.mtml', 
        {
            wizard_label      => $app->param('wizard_label'),
            asset_id          => $asset->id,
            asset_label       => $asset->label,
            complete_text     => $scw_yaml->{$wizard_id}->{wizard_complete_text} || '',
            rendered_template => $html,
        }
    )
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
    # If the user is trying to edit an already-saved asset, then the YAML
    # (with all of the saved values) will be passed here.
    my ($yaml) = @_;

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
    foreach my $step_name ( sort keys %{$steps} ) {
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
                # info and use that. Alternatively, the user may be editing a
                # previously-created asset (with $yaml), so we want to present
                # all saved data. If neither of those is true, display the 
                # YAML-supplied default value, then just fall back to a blank
                # field.
                my $value = 
                    $app->param($field_id) 
                    || ( $yaml && $yaml->{$wizard_id}->{ $field->{tag} } )
                    || $field->{default} 
                    || ''; 

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
                        level   => MT::Log::ERROR(),
                        blog_id => $app->blog->id,
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

# Add the "edit this asset in the wizard" link to the Edit Asset screen.
sub xfrm_edit_asset {
    my ($cb, $app, $param, $tmpl) = @_;

    # Give up if this isn't a structured content asset.
    return unless ($param->{asset}->class eq 'structured_content');

    # Load the wizard so that we can get at some important pieces.
    my $scw_yaml  = _load_scw_yaml( $app->blog->template_set );
    my $wizard_id = $param->{asset}->wizard_id;

    # Render the output template and return the result to the user.
    my $output_tmpl = MT->model('template')->load({
        blog_id    => $app->blog->id,
        identifier => $scw_yaml->{$wizard_id}->{asset_output_template},
    })
        or die 'The asset output template for this wizard could not be found.';

    require MT::Template::Context;
    my $ctx = MT::Template::Context->new;
    $ctx->stash('asset', $param->{asset});
    my $rendered_tmpl = $output_tmpl->build($ctx) or die $output_tmpl->errstr;

    # Put the rendered template HTML into the params hash so that it's 
    # available as a variable to display, below.
    $param->{rendered_tmpl} = $rendered_tmpl;

    # Grab the template itself, which we'll use to update the links.
    my $tmpl_text = $tmpl->text;

    # Remove the "View Asset" link (since it doesn't actually do anything)
    # and add a link to open the wizard and edit the asset there.
    my $old = q{<a href="<mt:var name="url" escape="html">"><__trans phrase="View Asset"></a>};
    my $new = <<'HTML';
<p>
    <a href="<mt:Var name="script_uri">?__mode=start_scw&amp;blog_id=<mt:BlogID>&amp;id=<mt:Var name="id">&amp;return_args=__mode%3Dview%26_type%3Dasset%26blog_id%3D<mt:BlogID>%26id%3D<mt:Var name="id">')">
        <__trans phrase="Edit this asset in the wizard">
    </a><br />
    <a href="javascript:void(0)" onclick="toggle('rendered-template');">View this asset rendered in its template</a>
</p>
<div id="rendered-template" class="textarea-wrapper hidden">
    <textarea class="full-width" style="height: 100px;"><mt:Var name="rendered_tmpl"></textarea>
</div>
HTML
    $tmpl_text =~ s/$old/$new/;

    # Remove the "Embed Asset" link (since it's useless for structured
    # content).
    $old = q{<div class="asset-embed">};
    $new = q{<div class="asset-embed hidden">};
    $tmpl_text =~ s/$old/$new/;

    # Now push the updated template back into the context. All done!
    $tmpl->text( $tmpl_text );

    1; # Callbacks should always return true.
}

# Add the Structured Content toolbar button to the editor
sub xfrm_editor {
    my ($cb, $app, $param, $tmpl) = @_;

    # If no structured content wizard has been defined for this blog, just
    # give up.
    return unless MT->registry(
        'template_sets', 
        $app->blog->template_set, 
        'structured_content_wizards'
    );

    # Grab the template itself, which we'll use to update the links.
    my $tmpl_text = $tmpl->text;

    # Find the Insert File icon in the toolbar
    my $old = q{<a href="javascript: void 0;" title="<__trans phrase="Insert File" escape="html">" mt:command="open-dialog" mt:dialog-params="__mode=list_assets&amp;_type=asset&amp;edit_field=<mt:var name="toolbar_edit_field">&amp;blog_id=<mt:var name="blog_id">&amp;dialog_view=1" class="command-insert-file toolbar button"><b>Insert File</b><s></s></a>};

    # Create an Insert Structured Content icon for the toolbar
    my $new = <<'HTML';
<a href="javascript: void 0;" 
    title="<__trans phrase="Insert Structured Content" escape="html">" 
    mt:command="open-dialog" 
    mt:dialog-params="__mode=list_assets&amp;_type=asset&amp;edit_field=<mt:var name="toolbar_edit_field">&amp;blog_id=<mt:var name="blog_id">&amp;dialog_view=1&amp;filter=class&amp;filter_val=structured_content" 
    class="command-insert-structured_content toolbar button">
        <b>Insert Structured Content</b><s></s>
    </a>

<style type="text/css">
    a.button.command-insert-structured_content {
        background-image: url(<mt:PluginStaticWebPath component="structuredcontentwizard">images/toolbar-buttons.png);
    }
    a.button.command-insert-structured_content:hover {
        background-image: url(<mt:PluginStaticWebPath component="structuredcontentwizard">images/toolbar-buttons.png);
        background-position: -22px 0;
    }
    a.button.command-insert-structured_content:active {
        background-image: url(<mt:PluginStaticWebPath component="structuredcontentwizard">images/toolbar-buttons.png);
        background-position: -44px 0;
    }
</style>
HTML

    $tmpl_text =~ s/$old/$new$old/;

    # Now push the updated template back into the context. All done!
    $tmpl->text( $tmpl_text );

    1; # Callbacks should always return true.
}

# After clicking the Structured Content toolbar button the asset list
# pops up. Remove the "Upload..." link and add a "Create a new
# Structured Content asset" link.
sub xfrm_asset_list {
    my ($cb, $app, $param, $tmpl) = @_;

    # Give up if this isn't a structured content asset.
    return unless $app->param('filter_val') 
        && $app->param('filter_val') eq 'structured_content';

    # Grab the template itself, which we'll use to update the links.
    my $tmpl_text = $tmpl->text;

    # Add the "Create Structured Content Asset" link to the dialog
    my $old = q{<div class="panel-header">};
    my $new = <<'HTML';
<img src="<mt:var name="static_uri">images/status_icons/create.gif" alt="<__trans phrase="Create New Structured Content Asset">" width="9" height="9" />
<a href="<mt:var name="script_url">?__mode=start_scw&amp;blog_id=<mt:BlogID>&amp;dialog_view=1&amp;entry_insert=1&amp;edit_field=<mt:var name="edit_field">&amp;return_args=<mt:var name="return_args" escape="url">" target="_parent"><__trans phrase="Create New Structured Content Asset"></a>
HTML

    $tmpl_text =~ s/$old/$new$old/;
    
    # Remove the "Upload..." option from the dialog, because it doesn't make sense in this context.
    $old = q{<mt:var name="upload_new_file_link">};
    $new = '';
    $tmpl_text =~ s/$old/$new/g;

    # Now push the updated template back into the context. All done!
    $tmpl->text( $tmpl_text );

    1; # Callbacks should always return true.
}

1;

__END__
