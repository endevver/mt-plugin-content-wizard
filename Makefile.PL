use ExtUtils::MakeMaker;

use YAML::Any qw(LoadFile);
my $file = "plugins/StructuredContentWizard/config.yaml";
my $version = LoadFile($file)->{version} ||
    die "No version found in $file";

WriteMakefile(
    NAME            => 'Structured Content Wizard',
    VERSION         => $version,
    DISTNAME        => 'StructuredContentWizard',
);
