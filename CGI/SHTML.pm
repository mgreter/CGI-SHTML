$VERSION = "1.26";
package CGI::SHTML;
our $VERSION = "1.26";

# -*- Perl -*-		# Thu Apr 22 14:45:41 CDT 2004 
#############################################################################
# Written by Tim Skirvin <tskirvin@ks.uiuc.edu>
# Copyright 2001-2004, Tim Skirvin and UIUC Board of Trustees.  
# Redistribution terms are below.
#############################################################################

=head1 NAME

CGI::SHTML - a CGI module for parsing SSI

=head1 SYNOPSIS

  use CGI::SHTML;
  my $cgi = new CGI::SHTML;

  # Print a full page worth of info
  print $cgi->header();
  print $cgi->start_html('internal', -title=>"SAMPLE PAGE");
  # Insert content here
  print $cgi->end_html('internal', -author=>"Webmaster", 
		        -address=>'webserver@ks.uiuc.edu');

  # Just parse some SSI text
  my @text = '<!--#echo var="TITLE"-->';
  print CGI::SHTML->parse_shtml(@text);

  # Use a different configuration file
  BEGIN { $CGI::SHTML::CONFIG = "/home/tskirvin/shtml.pm"; }
  use CGI::SHTML;

Further functionality is documented with the CGI module.

=head1 DESCRIPTION

In order to parse SSI, you generally have to configure your scripts to be
re-parsed through Apache itself.  This module eliminates that need by
parsing SSI headers itself, as best it can.   

=head2 VARIABLES

=over 2

=item $CGI::SHTML::CONFIG

Defines a file that has further configuration for your web site.  This is
useful to allow the module to be installed system-wide without actually
requiring changes to be internal to the file.  Note that you'll need to
reset this value *before* loading CGI::SHTML if you want it to actually
make any difference; it's loaded when you load the module.

=back

=cut

use strict;
use Time::Local;
use CGI;
use vars qw( @ISA $EMPTY $ROOTDIR %REPLACE %CONFIG %HEADER %FOOTER $CONFIG );

### User Defined Variables ####################################################
$CONFIG	 ||= "/home/webserver/conf/shtml.pm";
$ROOTDIR   = $ENV{'DOCUMENT_ROOT'} || "/Common/WebRoot";
$EMPTY 	   = "";	# Edit this for debugging
%REPLACE   = ( );
%CONFIG    = ( 'timefmt'	=>	"%D",);
%HEADER		  = (
        'internal'      =>      '/include/header-info.shtml',
        'generic'       =>      '/include/header-generic.shtml',
		    );
%FOOTER 	  = (
        'internal'      =>      '/include/footer-info.shtml',
        'generic'       =>      '/include/footer-generic.shtml',
		    );
###############################################################################

# Set some environment variables that are important for SSI
$ENV{'DATE_GMT'}      = gmtime(time);
$ENV{'DATE_LOCAL'}    = localtime(time);
$ENV{'DOCUMENT_URI'}  = join('', "http://", 
			 $ENV{'SERVER_NAME'} || "localhost", 
			 $ENV{'SCRIPT_NAME'} || $0 ) ;
$ENV{'LAST_MODIFIED'} = CGI::SHTML->_flastmod( $ENV{'SCRIPT_FILENAME'} || $0 );
delete $ENV{'PATH'};

@ISA = "CGI";

if ( -r $CONFIG ) { warn "Running $CONFIG\n"; do $CONFIG } 

=head2 SUBROUTINES 

=over 2

=item parse_shtml ( LINE [, LINE [, LINE ]] )

Parses C<LINE> as if it were an SHTML file.  Returns the parsed set of 
lines, either in an array context or as a single string suitable for 
printing.  All of the work is actually done by C<ssi()>.

=cut

sub parse_shtml {
  my ($self, @lines) = @_;
  map { s%<!--\#(\w+)\s+(.*)\s*-->% $self->ssi($1, $2) || "" %egx } @lines;
  wantarray ? @lines : join("\n", @lines);
}

=item ssi ( COMMAND, ARGS )

Does the work of parsing an SSI statement.  C<COMMAND> is one of the
standard SSI "tags" - 'echo', 'include', 'fsize', 'flastmod', 'exec',
'set', 'config', 'odbc', 'email', 'if', 'goto', 'label', and 'break'.
C<ARGS> is a string containing the rest of the SSI command - it is parsed
by this function.

Note: not all commands are implemented.  In fact, all that is implemented
is 'echo', 'include', 'fsize', 'flastmod', 'exec', and 'set'.  These are
all the ones that I've actually had to use to this point.

=cut

sub ssi {
  my ($self, $command, $args) = @_;
  my %hash;

  while ($args) { 		# Parse $args
    $args =~ s%^(\w+)=(\"[^\"]*\"|'.*'|\S+)\s*%%;
    last unless defined($1);
    my $item = lc $1; my $val = $2;  
    $val =~ s%^\"|\"$%%g; 
    $hash{$item} = $val if defined($val); 
  }

  if (lc $command eq 'include') {
    if ( defined $hash{'virtual'} ) { $self->_file(_vfile( $hash{'virtual'} )) }
    elsif ( defined $hash{'file'} ) { $self->_file( $hash{'file'} ) }
    else { return "No filename offered" };
  } elsif (lc $command eq 'set') {
    my $var = $hash{'var'} || return "No variable to set";
    my $value = $hash{'value'} || ""; 
    $value =~ s/\{(.*)\}/$1/g;
    $value =~ s/^\$(\S+)/$ENV{$1} || $EMPTY/egx;
    $ENV{$var} = $value; return "";
  # Should do something with "config"
  } elsif (lc $command eq 'echo') {
    $hash{'var'} =~ s/\{(.*)\}/$1/g;
    return $ENV{$hash{'var'}} || $EMPTY;
  } elsif (lc $command eq 'exec') {
    if    ( defined $hash{'cmd'} ) { $self->_execute( $hash{'cmd'} ) || ""  }
    elsif ( defined $hash{'cgi'} ) { $self->_execute( _vfile($hash{'cgi'}) ) }
    else { return "No filename offered" };
  } elsif (lc $command eq 'fsize') { 
    if    ( defined $hash{'virtual'}) { $self->_fsize(_vfile($hash{'virtual'}))}
    elsif ( defined $hash{'file'})    { $self->_fsize( $hash{'file'} ) }
    else { return "No filename offered" };
  } elsif (lc $command eq 'flastmod') { 
    if (defined $hash{'virtual'})  { $self->_flastmod(_vfile($hash{'virtual'}))}
    elsif ( defined $hash{'file'}) { $self->_flastmod( $hash{'file'} ) }
    else { return "No filename offered" };
  } 
  return "";
}

=item start_html ( TYPE, OPTIONS )

Invokes C<CGI::start_html>, and includes the appropriate header file.
C<OPTIONS> is passed directly into C<CGI::start_html>, after being parsed
for the 'title' field (which is specially set).  C<TYPE> is used to decide
which header file is being used; the possibilities are in
C<$CGI::SHTML::HEADER>.

=cut

sub start_html {
  my ($self, $type, %hash) = @_;
  $type = lc $type;  $type ||= 'default';
  
  foreach my $key (keys %hash) {
    if (lc $key eq '-title') { $ENV{'TITLE'} = $hash{$key} }
  }
  
  my $command = "<!--#include virtual=\"$HEADER{$type}\"-->";

  return join("\n", CGI->start_html(\%hash), $self->parse_shtml($command) );
}

=item end_html ( TYPE, OPTIONS )

Loads the appropriate footer file out of C<$CGI::SHTML::FOOTER>, and invokes
C<CGI::end_html>.

=cut

sub end_html {
  my ($self, $type, %hash) = @_;
  $type = lc $type;  $type ||= 'default';
  
  my $command = "<!--#include virtual=\"$FOOTER{$type}\"-->";

  join("\n", $self->parse_shtml($command), CGI->end_html(\%hash));
}

### _vfile ( FILENAME )
# Gets the virtual filename out of FILENAME, based on ROOTDIR.  Also
# performs the substitutions in C<REPLACE>.

sub _vfile {
  my $filename = shift || return undef;
  my $hostname = $ENV{'HTTP_HOST'} || $ENV{'HOSTNAME'};  
  foreach my $replace (keys %REPLACE) {
    next if ($hostname =~ /^www/);	# Hack 
    $filename =~ s%$replace%$REPLACE{$replace}%g;
  }
  my $newname;
  if ($filename =~ m%^~(\w+)/(.*)$%) { $newname = "/home/$1/public_html/$2"; } 
  elsif ( $filename =~ m%^[^/]% ) { 
    my ($directory, $program) = $0 =~ m%^(.*)/(.*)$%;
    $newname = "$directory/$filename" 
  } 
  else { $newname = "$ROOTDIR/$filename" }
  $newname =~ s%/+%/%g;  # Remove doubled-up /'s
  $newname;
}

## _file( FILE )
# Open a file and parse it with parse_shtml().
sub _file {
  my ($self, $file) = @_;
  open( FILE, "<$file" ) or warn "Couldn't open $file: $!\n" && return "";
  my @list = <FILE>;
  close (FILE);
  map { chomp } @list;
  return $self->parse_shtml(@list);
}

## _execute( CMD )
# Run a command and get the information about it out.  This isn't as
# secure as we'd like it to be...
sub _execute {
  my ($self, $cmd) = @_;
  delete @ENV{qw(IFS CDPATH ENV BASH_ENV PATH)};
  my ($command) = $cmd =~ /^(.*)$/;	# Not particularly secure
  open ( COMMAND, "$command |" ) or warn "Couldn't open $command\n";
  my @list = <COMMAND>;
  close (COMMAND);
  map { chomp } @list;
  return "" unless scalar(@list) > 0;	# Didn't return anything
  # Take out the "Content-type:" part, if it's a CGI - note, THIS IS A HACK
  if ( scalar(@list) > 1 && $list[0] =~ /^Content-type: (.*)$/i) { 
    shift @list;  shift @list; 
  }
  wantarray ? @list : join("\n", @list);
}

## _flastmod( FILE )
## _fsize( FILE )
# Last modification and file size of the given FILE, respectively.
sub _flastmod { localtime( (stat($_[1]))[9] || 0 ); }
sub _fsize    { 
  my $size = ((stat($_[1]))[7]) || 0;
  if ($size >= 1048576) {
    sprintf("%4.1fMB", $size / 1048576);
  } elsif ($size >= 1024) {
    sprintf("%4.1fKB", $size / 1024);
  } else {
    sprintf("%4d bytes", $size);
  }
}

=back

=head1 NOTES

This module was generated for a single research group at UIUC.  Its goal
was simple: parse the SSI header and footers that were being used for the
rest of the web site, so that they wouldn't have to be re-implemented
later.  Ideally, we would liked to just have Apache take care of this, but
it wasn't an option at the time (and as far as I know it still isn't one.)  

I mention the above because it's worth understanding the problem before
you think about its limitations.  This script will not offer particularly
high performance for reasonably-sized sites that use a lot of CGI; I doubt
it would work at all well with mod_perl, for instance.  But it has done
the job just fine for our research group, however; and if you want to copy
our general website layout, you're going to need something like this to
help you out.

Also of note is that this has been designed for use so that if headers and
footers are not being included, you can generally fall back to the default
CGI.pm fairly easily enough.

=head1 SEE ALSO

C<CGI.pm>

=head1 TODO

Implement the rest of the SSI functions.  It might be nice to make this
more object-oriented as well; as it stands this wouldn't stand a chance
with mod_perl.

=head1 AUTHOR

Written by Tim Skirvin <tskirvin@ks.uiuc.edu>

=head1 LICENSE

This code is distributed under the University of Illinois Open Source
License.  See
C<http://www.ks.uiuc.edu/Development/MDTools/uiuclicense.html> for
details.

=head1 COPYRIGHT

Copyright 2000-2004 by the University of Illinois Board of Trustees and
Tim Skirvin <tskirvin@ks.uiuc.edu>.

=cut

###############################################################################
### Version History ###########################################################
###############################################################################
# v1.0 		Thu Apr 13 13:30:30 CDT 2000
### Documented it, and put this module into its proper home.  
# v1.1 		Thu Apr 20 09:25:28 CDT 2000
### Updated for new page layout, included better counter capabilities, and
### put in the possiblity of hooks for when we need to update this for all 
### of the web pages.
# v1.11 	Thu Apr 20 13:48:28 CDT 2000
### Further updates, added NOCOUNTER flag for error messages
# v1.12 	Tue Apr 25 13:28:15 CDT 2000
### More updates of the header/footer files
# v1.2 		Tue Jun 13 09:42:11 CDT 2000
### Now just parses the header/footer files from the main directory, and 
### includes a "parse_shtml" function set.  Hopefully at some point I'll
### finish off parse_shtml to do all SSI functions.
# v1.21 	Wed Jun 28 10:56:26 CDT 2000
### Fixed the CGI handlings to trim out the Content-type header.
# v1.22 	Wed Oct 31 09:46:16 CST 2001
### Fixed _vfile() to do local directory checks properly.
### Changed execute() behaviour to not worry about tainting - probably a 
###   bad idea, but necessary for now.
# v1.23 	Mon Dec 10 11:58:25 CST 2001
### Created $EMPTY.  Updated 'set' to use variables in its code.
# v1.24 	Tue Apr  2 13:05:12 CST 2002
### Changed parse_shtml() to remove a warning
# v1.25 	Tue Mar 11 10:47:36 CST 2003 
### Updated to be a more generic name - CGI::SHTML.  This will make things
### a lot easier to distribute.  Have to make a real package now.  Eliminated 
### the COUNTER stuff, because it's not in use and was silly anyway.  Put 
### in 'default' values in the headers/footers
# v1.26		Thu Apr 22 15:00:51 CDT 2004 
### Making fsize(), flastmod(), etc into internal functions.  

1;
