# -*- cperl -*-

use Test::More;
use Git;
use Net::GitHub;
use constant HITO => 1;

use v5.14; # For say

my $repo = Git->repository ( Directory => '.' );
my $diff = $repo->command('diff','HEAD^1','HEAD');
my $hito_file = "hito-".HITO.".md";
my $diff_regex = qr/a\/proyectos\/$hito_file/;
my $github;

if ($ENV{'GH_TOKEN'} ) {
  say "Usando token GH";
  $github = Net::GitHub->new( access_token => $ENV{'GH_TOKEN'} );
} else {
  $github = Net::GitHub->new();
}

SKIP: {
  skip "No hay envío de proyecto", 5 unless $diff =~ $diff_regex;
  my @files = split(/diff --git/,$diff);
  my ($diff_hito_1) = grep( /$diff_regex/, @files);
  say "Tratando diff\n\t$diff_hito_1";
  my @lines = split("\n",$diff_hito_1);
  my @adds = grep(/^\+[^+]/,@lines);
  is( $#adds, 0, "Añade sólo una línea");
  my $url_repo;
  if ( $adds[0] =~ /\(http/ ) {
    ($url_repo) = ($adds[0] =~ /\((http\S+)\)/);
  } else {
    ($url_repo) = ($adds[0] =~ /^\+.+(http\S+)/s);
  }
  say $url_repo;
  isnt($url_repo,"","El envío incluye un URL");
  like($url_repo,qr/github.com/,"El URL es de GitHub");
  my ($user,$name) = ($url_repo=~ /github.com\/(\S+)\/(.+)/);
  my $repo_dir = "/tmp/$user-$name";
  if (!(-e $repo_dir) or  !(-d $repo_dir) ) {
    mkdir($repo_dir);
    `git clone $url_repo $repo_dir`;
  }
  my $student_repo =  Git->repository ( Directory => $repo_dir );
  my @repo_files = $student_repo->command("ls-files");
  say "Ficheros\n\t→", join( "\n\t→", @repo_files);
  for my $f (qw( README.md .gitignore LICENSE )) {
    isnt( grep( /$f/, @repo_files), 0, "$f presente" );
  }

  # Comprobar hitos e issues
  my $issue = $github->issue;
  $issue->set_default_user_repo($user,$name);
  my $repos = $github->repos;
  $repos->set_default_user_repo($user,$name);
  my @hitos = $issue->milestones({ state => 'open' });
  cmp_ok( $#hitos, ">=", 3, "Número de hitos correcto");
  my @closed_issues = $issue->repos_issues({ state => "closed"});
  cmp_ok( $#closed_issues, ">=", 0, "Hay algún issue cerrado");
  for my $i (@closed_issues) {
    my ($event_id) = ($i->{'url'} =~ m{issues/(\d+)});
    my @events = $issue->events($event_id);
    cmp_ok( $#events, ">=", 1, "Tiene al menos dos eventos");
    my @milestoned = grep(($_->{'event'} eq 'milestoned'), @events);
    cmp_ok( $#milestoned, ">=", 0, "El evento está en un hito");
    my ($closing_event) = grep(($_->{'event'} eq 'closed'), @events);
    my $closing_commit = $repos->commit($closing_event->{'commit_id'});
    is($closing_commit->{'author'}->{'login'}, $user, "Autor commit correcto");
    like($closing_commit->{'commit'}->{'message'}, qr/(closes|fixes)/, "Cierre desde commit")
  }
};

done_testing();