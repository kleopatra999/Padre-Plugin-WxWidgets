#!perl

# ABSTRACT: Generates a wxwidgets.pod from wxWidgets HTML documentation 

use 5.006;
use strict;
use warnings;

use File::Temp       ();
use File::Spec       ();
use HTML::Parse      ();
use HTML::FormatText ();

use Getopt::Long     ();
my $help = '';
my $result = Getopt::Long::GetOptions( "help"  => \$help,);

if($help) {
	print <<"HELP";

This is $0, an HTML to POD wxwidgets documentation generator.

Usage:
    $0 [wx-widgets-html-directory]

    The optional 'wx-widgets-html-directory' points to the wxwidgets 
    HTML documentation directory. If this is omitted, the script will
    automatically try to download the HTML documentation from the
    wxWidgets sourceforge website.

HELP
	exit;
}

my $WX_WIGDETS_HTML_ZIP = 'wxWidgets-2.8.10-HTML.zip';

# Step 1: Fetch the wxWidgets HTML documentation zip file if it is not found
die "wxWidget HTML zip file is not found!\n" unless download_wxwidgets_html_zip();

# Step 2: unzip the html zip file
my $dir = File::Temp->newdir;
unzip_file($dir);

# Step 3: Read WX Classes list index file
my $wx_dir = File::Spec->join( $dir, 'docs', 'mshtml', 'wx' );
my @wxclasses = read_wx_classes_list($wx_dir);
print "Found " . @wxclasses . " Wx Classes to parse\n";

# Step 4: Write the final POD while processing all html files
write_pod( $wx_dir, @wxclasses );

# and we're done
exit;

#
# Download wxwidgets HTML documentation zip file
#
sub download_wxwidgets_html_zip {
	unless ( -e $WX_WIGDETS_HTML_ZIP ) {
		my $url = "http://garr.dl.sourceforge.net/project/wxwindows/Documents/2.8.10/$WX_WIGDETS_HTML_ZIP";
		print "Downloading $url. Please wait...\n";
		require LWP::UserAgent;
		require HTTP::Request;
		my $ua  = LWP::UserAgent->new;
		my $req = HTTP::Request->new( GET => $url );
		my $res = $ua->request($req);
		if ( not $res->is_success ) {
			die $res->status_line, "\n";
		}

		# Write download file to disk
		print "Writing $WX_WIGDETS_HTML_ZIP...\n";
		if ( open FILE, '>:raw', $WX_WIGDETS_HTML_ZIP ) {
			print FILE $res->content;
			close FILE;
		} else {
			die "Could not open $WX_WIGDETS_HTML_ZIP for writing\n";
		}
	}

	return -e $WX_WIGDETS_HTML_ZIP;
}

#
# Unzip the HTML zip file
#
sub unzip_file {
	my $dir = shift;

	require Archive::Extract;
	my $zip = Archive::Extract->new( archive => $WX_WIGDETS_HTML_ZIP );
	die "$WX_WIGDETS_HTML_ZIP is not a zip file\n" unless ( $zip->is_zip );
	$zip->extract( to => $dir ) or die $zip->error;
}

exit;

#
# Read WX classes list index from docs/mshtml/wx/wx_classref.html
#
sub read_wx_classes_list {
	my $dir = shift;

	my $wx_classref = File::Spec->join( $dir, 'wx_classref.html' );

	# Stores a list of WX classes filenames
	my @wxclasses = ();

	#Step 1: Read Wx classes list from wx_classref.html
	if ( open( my $fh, $wx_classref ) ) {
		print "Opened $wx_classref\n";
		my $begin;
		while ( my $line = <$fh> ) {
			if ( $line =~ /<H2>Alphabetical class reference<\/H2>/ ) {
				$begin = 1;
			} elsif ( $begin && $line =~ /<A HREF="(.+?)#.+?"><B>(.+)?<\/B><\/A><BR>/ ) {
				my ( $file, $class ) = ( $1, $2 );
				$class =~ s/wx(.+?)/Wx::$1/;
				push @wxclasses, { file => $file, class => $class };
			}
		}
	} else {
		die "Could not open $wx_classref\n";
	}

	return @wxclasses;
}

#
# Process wxClassName HTML file
#
sub process_class {
	my ( $class, $file ) = @_;

	my $oldclass;
	my $pod_text = '';
	if ( open my $html_file, '<', $file ) {
		my $desc = '';
		my $name;
		while ( my $line = <$html_file> ) {
			if ( $line =~ /<H3>(.+?)<\/H3>/ ) {
				$name = $1;
				$name =~ s/wx(.+?)/Wx::$1/;
				if ( $name =~ /^Wx::(.+?)::(.+?)$/ ) {
					my $method = $2;
					if ( $method eq "wx$1" ) {

						# Convert C++ constructor to ::new
						$name = $class . '::new';
					} elsif ( $method =~ /^~.+/ ) {

						# Convert C++ destructor to ::DESTROY
						$name = $class . '::DESTROY';
					} elsif ( $method =~ /^operator.+/ ) {

						# Ignore operators
						$name = undef;
					}
				}
				$desc = '';
			} elsif ( $line =~ /^\s*$/ ) {
				if ($name) {
					if ( !$oldclass || $class ne $oldclass ) {

						# print out new class header
						$pod_text .= "=head1 $class\n\n";
						$oldclass = $class;
					}

					# print out method description
					$desc = HTML::FormatText->new->format( HTML::Parse::parse_html($desc) );
					$pod_text .= "=head2 $name\n\n$desc\n";

					$name = undef;
				}
			} else {
				$desc .= $line;
			}
		}
		close $html_file;
	}

	return $pod_text;
}

#
# Writes wxwidgets.pod... :)
#
sub write_pod {
	my ( $wx_dir, @wxclasses ) = @_;
	my $pod_file = File::Spec->join( $pod_dir, 'wxwidgets.pod' );
	print "Writing $pod_file\n";
	if ( open( my $pod, '>', $pod_file ) ) {
		binmode($pod);
		my $oldclass;
		foreach my $wxclass (@wxclasses) {
			my $file = File::Spec->join( $wx_dir, $wxclass->{file} );
			print $pod process_class( $wxclass->{class}, $file );
		}
		print $pod copyright_pod();
		close $pod;
	} else {
		die "Couldnt write $pod_file\n";
	}

}

#
# Copyright and license POD section
#
sub copyright_pod
{
	return <<'END';
=head1 COPYRIGHT AND LICENSE

Copyright 2010 C<< <ahmad.zawawi at gmail.com> >>

This document was generated by C<parse_wxwidgets_docs.pl> which is found at
L<http://svn.perlide.org/padre/trunk/tools/parse_wxwidgets_docs.pl>. The original 
wxWidgets HTML documentation 
L<http://garr.dl.sourceforge.net/project/wxwindows/Documents/2.8.10/wxWidgets-2.8.10-HTML.zip> 
is copyrighted as the following:

    Copyright (c) 1992-2006 by Julian Smart, Robert Roebling, Vadim Zeitlin
    and other members of the wxWidgets team. Portions (c) 1996 Artificial
    Intelligence Applications Institute.

    The original wxWidgets HTML documentation is licensed under:
      wxWindows Library License version 3.1, http://docs.wxwidgets.org/2.8.10/wx_wxlicense.html
      GNU Library General Public License version 2, http://docs.wxwidgets.org/2.8.10/wx_gnulicense.html

This document is part of free software; you can redistribute it and/or modify it
under the same terms as Perl 5 itself.

END
}

__END__

=head1 DESCRIPTION

This is a simple script to parse WxWidgets HTML documentation into something useful
that we can use of in Padre help system :)