#!/usr/bin/perl

#
# (C) Jens Riebold
# jens.riebold (AT) web.de
#

use strict;
use FileHandle;
use File::Basename;
use File::Spec;
use File::PathConvert;
use Archive::Tar;
use Archive::Tar::Constant;
use Cwd;
use File::Type;
use Data::Dumper;

$ENV{PERL5_AT_RESOLVE_SYMLINK} = "none";

foreach my $package (@ARGV)
{
	#print $package;	
	getContent($package);
	
}

sub processFileSO
{
	my ($file) = @_;
	return undef unless (($file =~ m#^/usr/lib/# ) || ($file =~ m#^/lib/#));
	return undef unless ($file =~ /\.so$/);
	my $ft = File::Type->new();
	my $type = $ft->mime_type($file);
	return undef if ($type =~ m#application/x-executable-file#);

	my ($rootPath_volume, $rootPath_dir, $rootPath_file) = File::Spec->splitpath( $file );
	my $fh = FileHandle->new("$file");
	my $content = "";
	while (my $line = <$fh>)
	{
		$line =~ s/\s+$//;
		if ($line =~ /^GROUP/)
		{
			my @parts = split(/\s+/, $line);
			my $newline = "";
			my $count = 0;
			for my $part (@parts)
			{
				$count++;
				$newline .= " " if ($count > 1);

				if ($part =~ m#^/#)
				{
					my $linkPath = File::Spec->rel2abs($part, $rootPath_dir);
					my $relLink = File::Spec->abs2rel($linkPath, $rootPath_dir);
					$newline .= $relLink;
				}
				else
				{
					$newline .= $part; 
				}
			}
			print "$line\n";
			print "$newline\n";
			$content .= $newline . "\n";
		}
		else
		{
			$content .= $line . "\n";
			print "$line\n";
		}
	}
	print "File-Type: $type\n";	
	return $content;
}

sub getContent
{
	my ($package) = @_;
	my $tar = Archive::Tar->new;
	my $fh = FileHandle->new("dpkg -L $package |");
	if (defined $fh)
	{
		my $count = 0;
		while (my $rootPath = <$fh>)
		{
			$rootPath =~ s/\s+$//;
			next unless (( $rootPath =~ m#^/usr/include/# ) || ( $rootPath =~ m#^/usr/lib/# ) || ($rootPath =~ m#^/lib/#));
			$count++;
			print $count . ":" . $rootPath . "\n";
			my ($rootPath_volume, $rootPath_dir, $rootPath_file) = File::Spec->splitpath( $rootPath );
		
			# put all symlinks recursive in the tar file
			my $storePath = {};	
			while ( -l $rootPath )
			{
				# break circular symlinks
				print "rootPath=$rootPath\n";
				last if defined($storePath->{$rootPath});
				$storePath->{$rootPath} = 1;
			 
				($rootPath_volume, $rootPath_dir, $rootPath_file) = File::Spec->splitpath( $rootPath );
				my $link = readlink( $rootPath );
				print "link=$link\n";
				my $linkPath = File::Spec->rel2abs($link, $rootPath_dir);
				print "linkPath=$linkPath\n";
				my ($linkPath_volume, $linkPath_dir, $linkPath_file) = File::Spec->splitpath( $linkPath );
				
				my $opthashref;
				my $relLink = File::Spec->abs2rel($linkPath, $rootPath_dir);
				print "add symlink rootPath=" . $rootPath . " to " . $relLink . "\n";
				$opthashref->{'linkname'} = $relLink;
				$opthashref->{'type'} = Archive::Tar::Constant->SYMLINK;					
				$tar->add_data($rootPath, 0, $opthashref);
				$rootPath = $linkPath
			}
		
			if ( -f $rootPath )
			{
				if (my $content = processFileSO($rootPath))
				{
					print "modified .so file\n";
					$tar->add_data($rootPath, $content);
				}
				else
				{ 
					print "add file " . $rootPath . "\n";
					$tar->add_files($rootPath);
				}
			}
		}
		undef $fh;
	}
	foreach my $entry ($tar->list_files())
	{
		print Data::Dumper->Dump([$entry]) . "\n";
	}
	#print Data::Dumper->Dump([$tar]);

	$tar->write("sysroot-" . $package . ".tar");
}

