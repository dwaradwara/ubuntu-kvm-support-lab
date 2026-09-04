#!/usr/bin/env perl
# log_parser.pl
# Parse Linux logs for common support-relevant error patterns.

use strict;
use warnings;

my $logfile = $ARGV[0] or die "Usage: $0 <logfile>\n";
open(my $fh, '<', $logfile) or die "Cannot open $logfile: $!\n";

my %errors;
my %services;
my $total = 0;
my $oom = 0;
my $disk_full = 0;
my $permission_denied = 0;

while (my $line = <$fh>) {
    $total++;

    if ($line =~ /\b(error|failed|failure|fatal)\b/i) {
        $errors{lc($1)}++;
    }

    if ($line =~ /systemd\[\d+\]:\s+(\S+).*failed/i) {
        $services{$1}++;
    }

    if ($line =~ /out of memory|oom[- ]killer|killed process/i) {
        $oom++;
    }

    if ($line =~ /no space left on device|disk full/i) {
        $disk_full++;
    }

    if ($line =~ /permission denied|apparmor="DENIED"/i) {
        $permission_denied++;
    }
}
close($fh);

print "Log Analysis Report\n";
print "=" x 50, "\n";
print "File: $logfile\n";
print "Total lines: $total\n\n";

print "Error Patterns:\n";
if (%errors) {
    for my $key (sort { $errors{$b} <=> $errors{$a} } keys %errors) {
        printf "  %-20s %d\n", $key, $errors{$key};
    }
} else {
    print "  none detected\n";
}

print "\nFailed Services:\n";
if (%services) {
    for my $service (sort keys %services) {
        printf "  %-30s %d\n", $service, $services{$service};
    }
} else {
    print "  none detected\n";
}

print "\nSupport Signals:\n";
printf "  %-30s %d\n", "OOM-related lines", $oom;
printf "  %-30s %d\n", "Disk-full lines", $disk_full;
printf "  %-30s %d\n", "Permission/AppArmor lines", $permission_denied;
