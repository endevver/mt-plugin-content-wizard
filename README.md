# Structured Content Wizard Overview

The Structured Content Wizard plugin for Movable Type and Melody makes
structured blogging and creating form-based content easy! Simply create a
step-by-step wizard interface for authors to work with.

* Easily define your wizard with a YAML structure in your theme (no
  programming necessary)!
* Define many unique wizards in a single theme.
* Each step of the wizard interface can have any number and type of fields to
  suit your requirements.
* Create a custom template to output wizard content exactly as needed.
* Wizard content is saved as an Asset that you can insert into an Entry or
  Page, for example.
* Edit content through the same wizard interface where it was created.

Wizards are defined as part of a theme and build off of Config Assistant's
existing simple field definition capabilities. Developers familiar with
creating Theme Options or Plugin Options with Config Assistant will be right
at home with the Structured Content Wizard and will have a working wizard
completed in no time!

# Prerequisites

* Movable Type 4.x
* Config Assistant 1.10 or greater


# Installation

To install this plugin follow the instructions found here:

http://tinyurl.com/easy-plugin-install

This plugin requires a newer version of the `YAML::Tiny` Perl module than is
included with Movable Type. Included with this plugin (in the `extlib/`
folder) is a newer version of YAML::Tiny. Copy from the plugin archive
`extlib/YAML/Tiny.pm` to `$MT_HOME/extlib/YAML/Tiny.pm` to update Movable
Type's copy of this plugin. **This is a required, non-optional step!**


# Configuration

## Create a Wizard

Wizards are defined with YAML, as a part of your theme's `config.yaml`. What
follows is an example wizard, with explanation below.

    template_sets:
        my_awesome_theme:
            structured_content_wizards:
                newsletter:
                    label: 'Our Awesome Newsletter Wizard'
                    asset_output_template: newsletter_wizard
                    order: 1
                    steps:
                        step1:
                            label: 'Newsletter Header'
                            hint: 'The header is made up of a title and custom background image.'
                            fields:
                                title:
                                    type: text
                                    label: 'Title'
                                    hint: 'This is the title of the newsletter.'
                                    required: 1
                                    order: 1
                                    tag: NewsletterTitle
                                image:
                                    type: file
                                    label: 'Background Image'
                                    hint: 'A background image is placed behind the title'
                                    required: 1
                                    order: 2
                                    tag: NewsletterImage
                        step2:
                            label: 'Lead Stories'
                            hint: 'These are the lead stories in our newest newsletter.'
                            fields:
                                story_1_title:
                                    type: text
                                    label: 'Story 1 Title'
                                    order: 1
                                    tag: NewsletterStory1Title
                                story_1_url:
                                    type: text
                                    label: 'Story 1 URL'
                                    order: 2
                                    tag: NewsletterStory1URL
                                story_1_text:
                                    type: textarea
                                    label: 'Story 1 Text'
                                    order: 3
                                    tag: NewsletterStory1Text

The key `my_awesome_theme` is the Theme this wizard targets. Descendants of
the `structured_content_wizards` key define a wizard.

It's not hard to see that a complex wizard could be quite large. You may wish
to move the wizards you define off to a separate YAML file to help keep the
plugin organized. In this case, use the `structured_content_wizards` key, and
place `my_awesome_wizards.yaml` in the plugin envelope with `config.yaml`, as
in this example:

    template_sets:
        my_awesome_theme:
            structured_content_wizards: my_awesome_wizards.yaml

The wizard being defined here is `newsletter`. Inside of the `newsletter`
wizard are a few properties:

* `label` - a friendly name for the wizard.
* `asset_output_template` - specify a template module to be used to output
  your structured content asset when inserted into an Entry or Page. Either a
  template identifier or template name are valid here.
* `order` - if more than one wizard is defined, specify the order they should
  appear in with this key and integer values. This is useful if one wizard is
  most-used because on the Select a Wizard screen the first wizard is
  highlighted by default. This key is optional.
* `steps` - is the parent key to the wizard's steps that the author interacts
  with.

Each "step" is defined inside of the `steps` key. A "step" is a page of the
wizard. In the `newsletter` wizard defined above, only two steps are defined
(`step1` and `step2`), however any number of steps can be defined. Steps are
ordered alphanumerically by their key, so in this example `step1` comes first,
then `step2`.

Each step defines three properties:

* `label` - a friendly name for this step of the wizard.
* `hint` - an optional description of this step and the fields it contains.
* `fields` -  the parent key to this step's fields.

Each field is defined inside of the step's `fields` key. Any number of fields
can exist in a step. In the newsletter example above, `step1` defines two
fields: `title` and `image`, while `step2` defines three fields.

## Field Definitions

Providing useful fields for an author is at the heart of creating a good
wizard. The Structured Content Wizard implements Config Assistant's Field
Types feature. If you've defined Theme Options or Plugin Options with Config
Assistant, you already know how to define a field with the Structured Content
Wizard.

Just as with the wizard and steps, fields are defined with properties. In this
example two fields have been defined (`title` and `image`). Note that your
field keys (in this case `title` and `image`) must be unique within a wizard.
The `tag` key must also be unique to the wizard.

    fields:
        title:
            type: text
            label: 'Title'
            hint: 'This is the title of the newsletter.'
            required: 1
            order: 1
            tag: NewsletterTitle
        image:
            type: file
            label: 'Background Image'
            hint: 'A background image is placed behind the title'
            required: 1
            order: 2
            tag: NewsletterImage

Refer to Config Assistant's detailed explanation of field properties and field
types to craft a field.
[http://github.com/endevver/mt-plugin-configassistant/blob/master/README.md](http://github.com/endevver/mt-plugin-configassistant/blob/master/README.md)

## Output Template Module

In the `asset_output_template` key you specified a template to be used to
publish your wizard's content. Create this template module as you would any
other. Below you can see a very simple template used to output the example
`newsletter` created above.

    <div class="newsletter">
        <h2>Step 1</h2>
        <ul>
            <li><mt:NewsletterTitle></li>
            <li><mt:NewsletterImageAsset>
                <img src="<mt:AssetURL>" />
            </mt:NewsletterImageAsset></li>
        </ul>
        <h2>Step 2</h2>
        <ul>
            <li><mt:NewsletterStory1Title></li>
            <li><mt:NewsletterStory1URL></li>
            <li><mt:NewsletterStory1Text filters="markdown"></li>
        </ul>
    </div>

As you can see, the tags defined in each field are used to output the values
that were entered in the wizard.

The tags defined in your wizard's fields can be used in any template within
the Asset context. On your Main Index, you may want to publish something like
this, for example:

    <mt:Assets type="structured_content" limit="1">
        <mt:NewsletterTitle>
    </mt:Assets>


# Using a Wizard

## Creating Structured Content

If a wizard has been defined for your blog/theme, you will have additional
options in the Create menu naming the available structured content wizards.
Select the wizard from the menu to get started. Alternatively, if you are
editing an entry you will see a new Insert Structured Content button in the
editor toolbar; click the toolbar button and select Create Structured Content
Asset to get started.

If more than one wizard has been defined for a given theme, authors will have
opportunity to select which wizard they want to work with. Make the
appropriate selection and continue.

Fill in the fields of each step. If a field has been marked as "required" an
asterisk will appear next to it, and authors will be required to enter a value
in that field to continue to the next step. Freely jump to the next and
previous steps to complete fields.

At the last step, click Complete Wizard. The contents of the submitted fields
are saved as a new asset, and the familiar Asset Insert dialog is presented:
enter a name, description, and tags for this asset (if desired) and select to
insert this asset into a new entry.

## Inserting Structured Content

If a structured content asset has already been created with a wizard, you can
simply insert it into an existing entry: on the Create/Edit Entry screen click
the Insert Structured Content editor toolbar button (between the Insert Image
and Insert File toolbar buttons), select an asset, and insert it. (Note that
structured content assets do not have any insert options.)

## Managing Structured Content

The Structured Content Wizard creates assets, so managing them is just like
managing other assets: click the Manage > Assets menu option. A Structured
Content Quickfilter can help to sort assets.

The contents of structured content assets can be edited through the same
wizard interface they were created in. Within the Manage Assets screen locate
the asset you want to edit and open it. Below the "thumbnail" you'll see a
link to "edit this asset in the wizard" which takes you to the familiar wizard
interface.


# License

This plugin is licensed under the same terms as Perl itself.

#Copyright

Copyright 2010, Endevver LLC. All rights reserved.
