package WWW::Extractor;
use strict;
$WWW::Extractor::VERSION = '0.1';


=head1 NAME

WWW::Extractor - Semi-automated extraction of records from WWW pages

=head1 SYNOPSIS

   use strict;
   use WWW::Extractor;

   my($extractor) = WWW::Extractor->new();

   $extractor->process($string);

=head1 DESCRIPTION

WWW::Extractor is a tool for semi automated extraction of records from
a string containing HTML.  One record within the string is marked up
with extraction markups and the modules uses a pattern matching
algorithm to match up the remaining records.

=head2 Extraction markup

The user markups up one record withing the HTML stream with the
following symbols.

=over 4

=item (((BEGIN))) 

Begin a record

=item (((fieldname))) 

Begin a field named fieldname

=item [[[literal string]]] 

This identifies a block of text that the
extractor attempts to match.  This string is dumped out when the
records are extracted.

=item {{{literal string}}} 

This identifies a block of text that the
extractor attempts to match.  This string is not dumped out when
the records are extracted.

=item (((nodump))) 

This marks an area of text that is not to be dumped out.

=item (((/nodump)))

This ends a section of text that is not to be dumped out.

=item (((END)))

End a record.

=back

=head1 ALGORITHM

The algorithm used is based on the edit distance wrapper generation
method described in

@inproceedings{ chidlovskii00automatic,
    author = "Boris Chidlovskii and Jon Ragetli and Maarten de Rijke",
    title = "Automatic Wrapper Generation for Web Search Engines",
    booktitle = "Web-Age Information Management",
    pages = "399-410",
    year = "2000",
    url = "citeseer.nj.nec.com/chidlovskii00automatic.html" }

but with two major enhancements.

=over

=item 1 Before calculating edit distance, the system divides the tokens
into different classification groups.

=item 2 Instead of creating a general grammar from all of the records in a
file, the data extractor creates one grammar from the sample entry and
then matches the rest of the text to that one grammar.

=back

=head1 DISCUSSION AND DEVELOPMENT

A wiki on this module is located at

http://www.gnacademy.org/twiki/bin/view/Gna/AutomatedDataExtraction

Please contact gna@gnacademy.org for ideas on improvements.

=head1 COPYRIGHT AND LICENSE

Copyright 2002, 2003 Globewide Network Academy

Redistributed under the terms of the Lesser GNU Public License

=cut

use PDL::Lite;
use Data::Dumper;
use strict;
use integer;
use English;

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self = {};
    bless ($self, $class);
    $self->{'debug'} = 0;
    $self->{'exact_tables'} = 1;
    $self->{'start_tags'} =  2;
    $self->{'end_tags'} = 1;
    return $self;
}

sub process {
    my ($self, $lp) = @_;
    my ($ap) = $self->tokenize($lp);
    my ($g, $context) = $self->initialize($ap);
    if ($self->{'debug'} > 250) {
	print "Initial grammar: ", Dumper($g), "\n";
	print "Initial content: ", Dumper($context), "\n";
    }
    
    my ($i, $gp, $w);
    
    my ($finish_tag) = $self->find_indices($ap, [q/(((END)))/]);

    my ($end_tag) = scalar(@{$ap});
    my(@ap) = @{$ap};

    while (1) {
	my($score, $i) = $self->find_next_item(\@ap, $g);
	
	if ($self->{'debug'} > 150) {
	    print $score, Dumper($i);
	}
	if (!$i) {
	    last;
	}
	my($g, $context) = $self->incorporate_item($g, $i);
	$self->dump($context);
    }
}

sub tokenize {
    my($self, $lp) = @_;
    my($i) = $lp;
    my (@match_token) = ();
    my(@imatch_token) = ();

    while ($i =~ m/\[\[\[([^\]]+)\]\]\]/s) {
	if ($self->{'debug'} > 1000) {
	    print "added $1 to match tokens\n";
	}
	push(@match_token, $1);
	$i = $POSTMATCH;
    }


    $i = $lp;
    while ($i =~ m/\{\{\{([^\}]+)\}\}\}/s) {
	if ($self->{'debug'} > 1000) {
	    print "added $1 to imatch tokens\n";
	}
	push(@imatch_token, $1);
	$i = $POSTMATCH;
    }

    if ($self->{'debug'} > 500) {
	print Dumper(\@match_token);
	print Dumper(\@imatch_token);
    }

    $lp =~ s/\[\[\[(.*?)\]\]\]/$1/gs;
    $lp =~ s/\{\{\{(.*?)\}\}\}/$1/gs;

    foreach $i (@match_token) {
	$lp =~ s/$i/[[[$i]]]/gs;
    }

    foreach $i (@imatch_token) {
	$lp =~ s/$i/{{{$i}}}/gs;
    }

    push(@match_token, @imatch_token);
    my (@lp) = split(/\s*(\(\(\([^\)]+?\)\)\)|\[\[\[[^\]]+?\]\]\]|\{\{\{[^\}]+?\}\}\}|<[^>]+>|\-\s+|\n\s+|\&\#183|\;|\|)\s*/, $lp);
		     @lp = grep {$_ ne ""} @lp;
    return \@lp;
}

sub classify {
    my ($self, $item) = @_;
    if ($item =~ /^\s+$/is) {
	return "B";
    }

    $item =~ s/\s+$//i;
    if ($item =~ /^<t.*>$/is && $self->{'exact_tables'}) {
	return lc($item);
    }
    if ($item =~ /^\[\[\[.*?\]\]\]$/s) {
	return $item;
    }

    if ($item =~ /^\(\(\(.*?\)\)\)$/s) {
	return $item;
    }

    if ($item =~ /^\{\{\{.*?\}\}\}$/s) {
	return $item;
    }

    if ($item =~ /^<([^>\s]+)\s*.*>$/is) {
	return "<" . lc($1) . ">";
    }
    if ($item =~ /^\-/) {
	return "-";
    }
    if ($item =~ /^\(/) {
	return "(";
    }
    if ($item =~ /^&/) {
	return $item;
    } 
    if ($item =~ /^\)/) {
       return ")";
    }
    if ($item =~ /^\|/) {
	return "|";
    } 
    if ($item =~ /^\;/) {
	return ";";
    }
    return "C";
}



sub initialize {
    my ($self, $ap) = @_;
    if ($self->{'debug'} > 50) {
	print "initializing\n";
    }
    my ($start, $finish) = $self->find_indices($ap, [q/(((BEGIN)))/,
						     q/(((END)))/]);

    if ($self->{'debug'} > 100) {
	print "start finish $start $finish\n";
    }
    my (@out) = @{$ap}[($start+1)..($finish-1)];
    my (@out_grammar) = @out;
    return (\@out_grammar, \@out);
}


sub edit_distance {
    my ($self, $s1, $s2) = @_;
    my ($item, @s1p, @s2p);
    @s1p = grep {$self->classify($_) !~ /\(\(\(.*\)\)\)/} @$s1;
    @s2p = grep {$self->classify($_) !~ /\(\(\(.*\)\)\)/} @$s2;
    
    my ($m) = $self->edit_distance_matrix(\@s1p, \@s2p);
    my (@a) = $m->dims();
    return $m->at($a[0] - 1, $a[1] - 1);
}

sub edit_distance_matrix {
    my ($self, $s1p, $s2p) = @_;
    if ($self->{'debug'} > 10) {
	print "**** Edit distance matrix " .
	    (scalar(@$s1p) + 1) . " by " . (scalar(@$s2p) + 1) . "\n";
    }
    my ($j, $i);
    my ($m) = PDL->zeroes (scalar(@$s1p) + 1, scalar(@$s2p) + 1);
    PDL::set($m, 0, 0, 0);
    for ($j=1; $j <= scalar(@$s2p); $j++) {
	PDL::set ($m, 0, $j, $m->at(0, $j-1) - 0 + 1);
    }
    for ($i=1; $i <= scalar(@$s1p) ; $i++) {
	PDL::set ($m, $i, 0, $m->at($i-1, 0) - 0 +1);
	for ($j=1; $j <= scalar(@$s2p) ; $j++) {

	    my ($diag) = $m->at($i-1, $j-1);
	    if ($self->classify($s1p->[$i-1]) ne
		$self->classify($s2p->[$j-1])) {
		$diag++;
	    }
	    my ($item) = $diag;
	    if ($item > $m->at($i-1, $j) + 1) {
		$item = $m->at($i-1, $j) + 1;
	    }
	    if ($item > $m->at($i, $j-1) + 1) {
		$item = $m->at($i, $j-1) + 1;
	    }
	    PDL::set($m, $i, $j, $item);
	}
    }
    return $m;
}

sub find_next_item {
    my ($self, $ap, $g) = @_;
    my ($dnewlocal, $dlocal, $dbest) = 
	(998, 999, 1000);
    my ($ib, $ie, $newib) = (0, 0, 0);
    my ($local_best_item, $best_item) = 
	("", "");
    my (@gprocessed) = grep {$self->classify($_) !~ /\(\(\(.*\)\)\)/} @{$g};
    my (@start_tags) = @gprocessed[0..($self->{'start_tags'})-1];
    my ($glim) = scalar(@gprocessed);
    my (@end_tags) = @gprocessed[$glim-$self->{'end_tags'}..$glim-1];

    while ($dlocal < $dbest) {
	$dbest = $dlocal;

	if ($self->{'debug'} > 200) {
	    print "Start find indices for ",
	    Dumper(\@start_tags), "\n";
	}
	($newib) = $self->find_indices ($ap, [\@start_tags], $ib+1);
	if ($self->{'debug'} > 500) {
	    print "Newib: $newib\n";
	}
	if ($newib < 0) {
	    last;
	}
	$ie = $newib;
	while(1) {
	    if ($self->{'debug'} > 500) {
		print "Entering loop starting at $ie.  Searching for ",
		Dumper(\@end_tags), "\n";
	    }
	    my($newie) = $self->find_indices($ap, [\@end_tags], $ie+1);
	    if ($self->{'debug'} > 500) {
		print "newie: $newie\n";
	    }
	    if ($newie < 0) {
		last;
	    }
	    $dlocal = $dnewlocal;

	    my(@new_local_best_item) =
		@{$ap}[$newib .. $newie];
	    my($new_local_best_item) = 
		\@new_local_best_item;
	    if ($self->{'debug'} > 250) {
		print Dumper($new_local_best_item);
	    }

	    $dnewlocal = $self->edit_distance($g,
					$new_local_best_item);
	    if ($self->{'debug'} > 150) {
		print "Edit distance ", $dnewlocal, "\n";
	    }
	    if ($dnewlocal > $dlocal) {
		last;
	    }
	    $ie = $newie;
	    $local_best_item = $new_local_best_item;
	}
	$best_item = $local_best_item;
    }

    my (@ap) = @$ap;
    @{$ap} = @ap[($ie+1)..$#ap];
    return ($dbest, $best_item);
}

sub incorporate_item {
    my ($self, $g, $item) = @_;
    my ($i, $j, $gitem, $iprocess);
    my (@greturn) = ();
    my (@gprocessed) = ();
    my (@lbrace) = ();
    my (@rbrace) = ();
    my (@tag) = ();
    my ($ginopt) = (0, 0);
    my ($newginopt) = 0;
    my(@g) = @{$g};
    my(@item) = grep {$self->classify($_) !~ /\(\(\(.*?\)\)\)/} @{$item};
    if ($self->{'debug'} > 10) {
	print Dumper(\@g);
    }

    $iprocess = 0;
    foreach $gitem (@g) {
	if ($gitem =~ /\(\(\((.*?)\)\)\)/) {
	    $tag[$iprocess] = $gitem;
	} else {
	    push (@gprocessed, $gitem);
	    $iprocess++;
	}   
    }
    my (@gblock, @iblock, $addtag);
    my ($m) = $self->edit_distance_matrix(\@gprocessed, \@item);
    if ($self->{'debug'} > 10) {
	print $m, "\n";
    }
    $i = scalar(@gprocessed);
    $j = scalar(@item);

    while ($i > 0 && $j > 0) {
	my ($direction) = "";
	my ($dump_block) = 0;
	my ($oldi) = $i;
        if ($m->at($i-1, $j) + 1 == $m->at($i, $j)) {
	    $direction = "w";
	    $i--;
	} elsif ($m->at($i, $j-1) + 1 == $m->at($i, $j)) {
	    $direction = "n";
	    $j--;
	    @greturn = ($item[$j], @greturn);
	} elsif ($m->at($i-1, $j-1) + 1 == $m->at($i, $j)) {
	    $direction = "nw";
	    $i--;
	    $j--;
	    @greturn = ($item[$j], @greturn);
	} elsif ($m->at($i-1, $j-1) == $m->at($i, $j) &&
	    $self->classify($gprocessed[$i-1]) eq 
		 $self->classify($item[$j-1])) {
	    $direction = "eq";
	    $i--;
	    $j--;
	    @greturn = ($item[$j], @greturn);
	} else {
	    print "ERROR:";
	}
	if ($tag[$oldi] && ($oldi != $i)) {
	    @greturn = ($tag[$oldi],  @greturn);
	}
    }

    return ($g, \@greturn);
}

sub find_indices {
    my ($self, $list, $itemref, $index) = @_;
    my ($i, $j, @out);
    my ($current_item) = 0;

    if ($self->{'debug'} > 100) {
	print "start find indices\n", Dumper($itemref), "\n";
    }

    if ($index eq undef) {
	$index = 0;
    }

  loop:
    for ($i=$index; $i < scalar(@$list); $i++) {
	if (ref($itemref->[$current_item]) eq "ARRAY") {
	    for ($j = 0; $j < scalar(@{$itemref->[$current_item]}); $j++) {
		if (($i + $j) >= scalar(@$list)) {
		    next loop;
		}
		if ($self->{'debug'} > 1024) {
		    print "Comparing ", 
		    $itemref->[$current_item]->[$j], 
		    " and ", $list->[$i + $j], " at $i $j\n";
		}
		if ($self->classify($itemref->[$current_item]->[$j])
		    ne $self->classify($list->[$i + $j])) {
		    next loop;
		}
	    }
	    if ($self->{'debug'} > 500) {
		print "Match at $i\n";
	    }
	    push (@out, $i);
	    $current_item++;
	    if ($current_item > scalar(@{$itemref})) {
		last loop;
	    }
	} else {
	    if ($self->{'debug'} > 1024) {
		print "Comparing ", 
		$itemref->[$current_item], 
		" and ", $list->[$i], " at $i\n";
	    }

	    if ($self->classify($list->[$i]) eq 
		$self->classify($itemref->[$current_item])) {
		push (@out, $i);
		$current_item++;
		if ($current_item > scalar(@{$itemref})) {
		    last loop;
		}
	    }
	}
    }
    for ($i=$current_item; $i <= scalar(@{$itemref}); $i++) {
	push (@out, -1);
    }
    return @out;
}

sub dump {
    my ($self, $context) = @_;
    if ($self->{'debug'} > 200) {
	print "Dumping: ";
	print Dumper($context);
    }
    my ($item);
    my ($returnval) = "";
    my ($dump) = 1;
    foreach $item (@{$context}) {
	my ($class) = $self->classify($item);
	if ($class eq "(((nodump)))") {
	    $dump = 0;
	} 

     	if ($dump) {
	    if ($class =~ /\(\(\((.*?)\)\)\)/) {
		my($tag) = $1;
		$returnval =~ s/\s+$//gi;
		$returnval .= "\n$tag  ";
	    } elsif ($class =~ /\[\[\[(.*?)\]\]\]/) {
		$returnval .= "$1";
	    } elsif ($class =~ /<a>/) {
		if ($item =~ /href/i) {
		    $item =~ /href=\"(.*?)\"/i;
		    $returnval .= "   $1 ";
		}
	    } elsif ($class =~ /<img>/) {
		if ($item =~ /src/i) {
		    $item =~ /src=\"(.*?)\"/i;
		    $returnval .= "   $1 ";
		}
	    } elsif ($class eq "C") {
		$item =~ s/\n/\n   /gis;
		$returnval .= $item;
	    } elsif ($class =~ /<.*?>/) {
		$returnval .= " ";
	    } elsif ($class eq "B") {
		$returnval .= " ";
	    } elsif ($class !~ /\{\{\{(.*?)\}\}\}/s) {
		$returnval .= $item;
	    }
	}
	if ($class eq "(((/nodump)))") {
	    $dump = 1;
	}
    }
    $returnval =~ s/\n(\s*\n)+/\n/gis;
    print "$returnval\n\n";
}

sub debug {
    my($self, $debug) = @_;
    if (defined($debug)) {
	$self->{'debug'} = $debug;
    }
    return $self->{'debug'};
}

