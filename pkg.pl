#! /usr/bin/perl
# ex:ts=8 sw=4:
#
# Copyright (c) 2019-2022 Aaron Beiber <abieber@openbsd.org>
# Copyright (c) 2010 Marc Espie <espie@openbsd.org>
#
# Permission to use, copy, modify, and distribute this software for any
# purpose with or without fee is hereby granted, provided that the above
# copyright notice and this permission notice appear in all copies.
#
# THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
# WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
# MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
# ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
# WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
# ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
# OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.

use strict;
use warnings;
use DBI;

$| = 1;

my @l = qw(add check create delete info search pkginfo);
my %a = (
    "del"     => "delete",
    "i"       => "add",
    "install" => "add",
    "rm"      => "delete",

    "inf" => "info",
    "pi"  => "pkginfo",
    "s"   => "search"
);

my $srcDBfile = '/usr/local/share/sqlports';
my $dbfile    = '/tmp/sqlports.fts';
my $dbh;

sub run_sql {
    my ( $dbh, $sql ) = @_;

    my $sth = $dbh->prepare($sql) or die $dbh->errstr . "\n$sql\n";
    $sth->execute()               or die $dbh->errstr;
    return $sth;
}

if ( !-e $dbfile ) {
    print STDERR "Creating full text database...";
    my $dbh = DBI->connect( "dbi:SQLite:dbname=:memory:", "", "" );
    $dbh->sqlite_backup_from_file($srcDBfile)
      or die "Can't copy sqlports to memory!";
    run_sql(
        $dbh, q{
	CREATE VIRTUAL TABLE
	    ports_fts
	USING fts5(
	    FULLPKGNAME,
	    FULLPKGPATH,
	    COMMENT,
	    DESCRIPTION);
    }
    );
    run_sql(
        $dbh, q{
	INSERT INTO
	    ports_fts
	(FULLPKGNAME, FULLPKGPATH, COMMENT, DESCRIPTION)
	select
	    FULLPKGNAME,
	    FULLPKGPATH,
	    COMMENT,
	    DESCR_CONTENTS
	FROM Ports;
    }
    );

    $dbh->sqlite_backup_to_file($dbfile)
      or die "Can't copy sqlports to memory!";
    $dbh->disconnect();
    print STDERR "Done.\n";
}

$dbh = DBI->connect( "dbi:SQLite:dbname=$dbfile", "", "" );

sub run {
    my ( $cmd, $name ) = @_;
    my $module = "OpenBSD::Pkg\u$cmd";
    eval "require $module;";
    if ($@) {
        die $@;
    }
    exit( $module->parse_and_run($name) );
}

for my $i (@l) {
    if ( $0 =~ m/\/?pkg_$i$/ ) {
        run( $i, "pkg_$i" );
    }
}

if (@ARGV) {
    for my $i (@l) {
        $ARGV[0] = $a{ $ARGV[0] } if defined $a{ $ARGV[0] };
        if ( $ARGV[0] eq $i ) {
            shift;
            if ( $i eq "pkginfo" ) {

                # Take a FULLPKGNAME and return DESCR_CONTENTS and COMMENT
                my $ssth = $dbh->prepare(
                    q{
		    SELECT
			COMMENT,
			DESCRIPTION
		    FROM ports_fts
		    WHERE
			FULLPKGNAME = ?;
		}
                );
                $ssth->bind_param( 1, join( " ", @ARGV ) );
                $ssth->execute();
                while ( my $row = $ssth->fetchrow_hashref ) {
                    print "Comment:\n$row->{COMMENT}\n\n";
                    print "Description:\n$row->{DESCRIPTION}\n";
                }
                exit();
            }
            if ( $i eq "search" ) {

                # TODO: what would be a better UX for displaying this stuff?
                my $ssth = $dbh->prepare(
                    q{
		    SELECT
			FULLPKGNAME,
			FULLPKGPATH,
			COMMENT,
			DESCRIPTION,
			highlight(ports_fts, 2, '[', ']') AS COMMENT_MATCH,
			highlight(ports_fts, 3, '[', ']') AS DESCR_MATCH
		    FROM ports_fts
		    WHERE ports_fts MATCH ? ORDER BY rank;
		}
                );
                $ssth->bind_param( 1, join( " ", @ARGV ) );
                $ssth->execute();
                while ( my $row = $ssth->fetchrow_hashref ) {

                    #print "$row->{FULLPKGNAME}\n";
                    my $l = 20 - length( $row->{FULLPKGNAME} );
                    $l = 1 if $l <= 0;
                    print(
                        $row->{FULLPKGNAME},   " " x $l,
                        $row->{COMMENT_MATCH}, "\n"
                    );
                }
                exit();
            }
            else {
                run( $i, "pkg $i" );
            }
        }
    }
}

print STDERR "Usage: pkg [", join( "|", @l ), "] [args]\n";
exit(1);
