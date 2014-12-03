use ExtUtils::MakeMaker;

my $modules = {
  'OCBNET/CGI/SHTML.pm' => '$(INST_LIBDIR)/SHTML.pm',
};

WriteMakefile(
    'NAME'	=> 'OCBNET::CGI::SHTML',
    'VERSION_FROM' => 'OCBNET/CGI/SHTML.pm', # finds $VERSION
    'MAN3PODS'  => { 'OCBNET/CGI/SHTML.pm' => '$(INST_MAN3DIR)/OCBNET::CGI::SHTML.3' },
    'PM'   => $modules,
    'dist' => { COMPRESS => 'gzip', SUFFIX => 'gz' },
);
