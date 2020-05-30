#!/usr/bin/perl

# greps (grep subset)

# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details <http://www.gnu.org/licenses/>.

# greps home <https://github.com/shayshim/greps>

use strict;
use warnings;
use Cwd 'abs_path';
use Getopt::Long qw(:config gnu_getopt no_ignore_case);
use File::Basename;
#use Devel::StackTrace;
use constant { 
	VERSION => "0.83",
	PROG_NAME => scalar fileparse($0, qr/\.[^.]*/),
	USAGE_MSG => "Usage: ".scalar fileparse($0, qr/\.[^.]*/)." [OPTION]... PATTERN [FILE]... [-- GREPOPTIONS...]"
};
my $assert_flag = &enable_assert;

# All find expressions that are used should extend AbstractExpression
package AbstractExpression;

sub new {
	my ($class) = @_;
	my $self = {_class => $class};
	bless $self, $class;
	$self->{_find_expression} = $self->greps_to_find_expression;
	return $self;
}

# Returns the expression formatted for find commands
sub get_find_expression {
	return $_[0]->{_find_expression};
}

# Returns the package/class name
sub get_class {
	return $_[0]->{_class};
}

# Helper method used by the constructor
# Tranforms greps expression to find expression
# Each Expression should override this method
sub greps_to_find_expression {
	return $_[0]->get_class;
}
 
package BinaryOperatorExpression;
use base 'AbstractExpression';

sub new {
	my ($class, $operator_str) = @_;
	my $self = {_class => $class, _operator_str => $operator_str};
	bless $self, $class;
	$self->{_find_expression} = $self->greps_to_find_expression;
	return $self;
}

sub greps_to_find_expression {
	my $operator_str = $_[0]->{_operator_str};
	$operator_str =~ s/(.).*/$1/;
	return "-".$operator_str;
}

package BracketOperatorExpression;
use base 'AbstractExpression';

sub new {
	my ($class, $operator_str) = @_;
	my $self = {_class => $class, _operator_str => $operator_str};
	bless $self, $class;
	$self->{_find_expression} = $self->greps_to_find_expression;
	return $self;
}

sub greps_to_find_expression {
	my $operator_str = $_[0]->{_operator_str};
	return "\\\(" if ($operator_str =~ m/paren-open/);
	return "\\\)" if ($operator_str =~ m/paren-close/);
}

package AssignableExpression;
use base 'AbstractExpression';

sub new {
	my ($class, $key, $values, $delimiter) = @_;
	my $self = {_class => $class, _key => $key, _values => $values, _delimiter => $delimiter};
	bless $self, $class;
	$self->{_find_expression} = $self->greps_to_find_expression;
	return $self;
}

sub greps_to_find_expression {
	my ($self) = @_;
	my ($key, $values) = ($self->{_key}, $self->{_values});
	my $left_pad = '';
	if ($key =~ m/ext/) {
		$key =~ s/(i?)ext/$1name/;
		$left_pad='*.';
	}
	my $delimiter = $self->{_delimiter};
	$values =~ s/^$delimiter//;$values =~ s/$delimiter$//;
	my $find_expression = main::get_find_patterns_formatted($values, $key, $left_pad, '', 'o', $self->{_delimiter});
	$find_expression = "\\\( $find_expression \\\)" if (($values =~ s/$delimiter/$delimiter/g) > 0);
	return $find_expression; 
}

package ShebangExpression;
use base 'AbstractExpression';

sub new {
	my ($class, $key, $values, $delimiter) = @_;
	my $self = {_class => $class, _shebangs => $values, _delimiter => $delimiter};
	bless $self, $class;
	$self->{_find_expression} = $self->greps_to_find_expression;
	return $self;
}

sub greps_to_find_expression {
	my ($self) = @_;
	my $shebang_prefix='^[#][!].*[[:space:]/]';
	my $alternate='\\\\\|';
	my $delimiter = $self->{_delimiter};
	my @shebangs = split /$delimiter/, $self->{_shebangs};
	my $shebangs_str = $shebang_prefix.main::get_concatenated_with_delimiter(\@shebangs, $alternate.$shebang_prefix);
	my $grep = "grep -qE \"$shebangs_str\"";
	my $expression_str = "\\\( -perm -u+x -a \\\( -exec sh -c \"head -1 {} | $grep \" \\; \\\) \\\)";
	return $expression_str;
}

package LanguageExpression;
use base 'AbstractExpression';

sub new {
	my ($class, $language, $delimiter, @lang_args) = @_;
	my $self = {_class => $class, _language => $language, _lang_args => \@lang_args, _delimiter => $delimiter};
	bless $self, $class;
	$self->{_find_expression} = $self->greps_to_find_expression;
	return $self;
}

sub greps_to_find_expression {
	my ($self) = @_;
	my ($name_values, $ext_values, $shebang_values) = @{$self->{_lang_args}};
	my $lang_str = "";
	my $counter = 0;
	if ($name_values) {
		$lang_str .= AssignableExpression->new("name", $name_values, $self->{_delimiter})->get_find_expression." -o ";
		$counter++;
	}
	if ($ext_values) {
		$lang_str .= AssignableExpression->new("ext", $ext_values, $self->{_delimiter})->get_find_expression." -o ";
		$counter++;
	}
	if ($shebang_values) {
		$lang_str .= ShebangExpression->new("shebang", $shebang_values, $self->{_delimiter})->get_find_expression." -o ";
		$counter++;
	}
	$lang_str =~ s/ -o $//;
	$lang_str = "\\\( $lang_str \\\)" if ($counter > 1);
	return $lang_str;
}

package ExpressionsFactory;

use File::Glob;
use YAML::Tiny;
use constant {
	ASSIGNABLE_EXPRESSION_OPTIONS => ['name', 'iname', 'ext', 'iext'],
	BINARY_OPERATOR_EXPRESSION_OPTIONS => ['and', 'or'],
	PRUNE_EXPRESSION_OPTIONS => ['prune-name', 'prune-iname', 'prune-path', 'prune-ipath'],
	SHEBANG_EXPRESSION_OPTIONS => ['shebang'],
	BRACKET_OPERATOR_EXPRESSION_OPTIONS => ['paren-open', 'paren-close']
};

my $_instance = 0;
my $prog_yaml_file_name = ".".&main::PROG_NAME.".yaml";

my $yaml_tiny_exists = eval {
  require YAML::Tiny;
  YAML::Tiny->import();
  1;
};

sub new {
	my ($class, $languages_ref, $grep_ref) = @_;
	my $hash_ref = &get_option_to_creator_hash_ref($languages_ref);
	my $self = {_option_to_creator_hash_ref => $hash_ref, _delimiter => 0, _languages => $languages_ref, _grep_config => $grep_ref};
	return bless $self, $class;
}

sub instance {
	if ($_instance == 0) {
		my %config =  %{&read_config};
		my %languages = %{$config{languages}};
		my %grep = %{$config{grep}};
		$_instance = ExpressionsFactory->new(\%languages, \%grep);
	}
	return $_instance;
}

sub get_languages {
	return %{$_[0]->{_languages}};
}

sub get_grep_config {
	return %{$_[0]->{_grep_config}};
}

sub read_config {
	my $home_directory = $ENV{HOME};
	my $config_file = $home_directory."/".$prog_yaml_file_name;
	my %config = (languages => {}, grep => {options => ""});
	if (-e $config_file && $yaml_tiny_exists == 1) {
		my $yaml = YAML::Tiny->read($config_file);
		%config = %{$yaml->[0]};
	}
	return \%config;
}

sub get_option_to_creator_hash_ref {
	my %languages = %{$_[0]};
	my %hash = ();
	my @options = @{&ASSIGNABLE_EXPRESSION_OPTIONS};
	&add_option_handler_pair_to_hash(\@options, \&create_assignable_expression, \%hash);
	@options = @{&BINARY_OPERATOR_EXPRESSION_OPTIONS};
	&add_option_handler_pair_to_hash(\@options, \&create_binary_operator_expression, \%hash);
	@options = keys %languages;
	&add_option_handler_pair_to_hash(\@options, \&create_language_expression, \%hash);
	@options = @{&PRUNE_EXPRESSION_OPTIONS};
	&add_option_handler_pair_to_hash(\@options, \&create_prune_expression, \%hash);
	@options = @{&SHEBANG_EXPRESSION_OPTIONS};
	&add_option_handler_pair_to_hash(\@options, \&create_shebang_expression, \%hash);
	@options = @{&BRACKET_OPERATOR_EXPRESSION_OPTIONS};
	&add_option_handler_pair_to_hash(\@options, \&create_bracket_operator_expression, \%hash);
	return \%hash;
}

sub add_option_handler_pair_to_hash {
	my ($options_array_ref, $handler_ref, $hash_ref) = @_;
	foreach my $option(@$options_array_ref) {
		$hash_ref->{$option} = $handler_ref;
	}
}

sub create {
	my ($self, $option) = @_;
	$option =~ m/([\w-]+)=?/;
	my $hash_ref = $self->{_option_to_creator_hash_ref};
	return &{$hash_ref->{$1}}($option, $self->{_delimiter});
}

sub create_prune_expression {
	$_[0] =~ s/^prune-//;
	return create_assignable_expression($_[0], $_[1]);
}

sub create_assignable_expression {
	$_[0] =~ m/([\w-]+)=(.*)/;
	my $delimiter = $_[1];
	return AssignableExpression->new($1, $2, $delimiter);
}

sub create_shebang_expression {
	$_[0] =~ m/([\w-]+)=(.*)/;
	my $delimiter = $_[1];
	return ShebangExpression->new($1, $2, $delimiter);
}

sub create_binary_operator_expression {
	return BinaryOperatorExpression->new($_[0]);
}

sub create_bracket_operator_expression {
	return BracketOperatorExpression->new($_[0]);
}

sub create_language_expression {
	my ($lang, $delimiter) = @_;
	my %languages = ExpressionsFactory::instance->get_languages;
	my %language_config = %{$languages{$lang}};
	my @extensions = $language_config{extensions};
	my @names = $language_config{names};
	my @shebangs = $language_config{shebangs};
	my $shebang_prefix='^[#][!].*[[:space:]/]';
	my $alternate='\\\\\|';
	return LanguageExpression->new($lang, $delimiter, 
									main::get_concatenated_with_delimiter($names[0], $delimiter), 
									main::get_concatenated_with_delimiter($extensions[0], $delimiter),
									main::get_concatenated_with_delimiter($shebangs[0], $delimiter));
}

sub set_delimiter {
	my ($self, $delimiter) = @_;
	$self->{_delimiter} = $delimiter;
}

package main;

my $status = 0;
my $debug = 0; 
my $tabs_counter = 0;
my $grep_args = "";
my $abs_path = 0;
my @greps_expressions = ();
my @greps_prunes = ();

my %command_specs = %{&read_user_arguments};
my $out = "";
$out = "$out$_ -> $command_specs{$_}, " for (keys %command_specs);
print_debug (__LINE__, "$out");
my $command = &create_command(\%command_specs);
if ($command_specs{print_command} || $command_specs{pretty_print}) {
	print "$command\n" if $command_specs{print_command};
	&pretty_print($command) if $command_specs{pretty_print};
	exit($status);
}
system($command);
my $xargs_exit_status=$?;
print_debug (__LINE__, "xargs_exit_status=$xargs_exit_status");
&print_debug(-1, $command);
&myexit($status, $xargs_exit_status);

#==============================================================================

sub create_command {
	my %command_specs = %{$_[0]};
	my ($max_files_per_grep, $max_grep_procs, $recursive, $follow);
	my $paths = $command_specs{paths};
	my $pattern = "'".$command_specs{pattern}."'";
	$max_files_per_grep = &xargs_handler("max-files-per-grep", $command_specs{max_files_per_grep});
	$max_grep_procs = &xargs_handler("max-grep-procs", $command_specs{max_grep_procs});
	$recursive = "-maxdepth 1" if (! $command_specs{recursive});
	$follow = "-L" if ($command_specs{follow});
	my $expressions_str = &get_find_expressions_string($command_specs{greps_expressions}, $command_specs{delimiter});
	my $prunes_str = &get_find_prunes_string($command_specs{greps_prunes}, $command_specs{delimiter});
	my $prunes_expressions_str = &get_concatenated_with_delimiter($prunes_str, "-type f -a", $expressions_str, " ");
	$prunes_expressions_str = "\\\( $prunes_expressions_str \\\)" if ($expressions_str && $prunes_str);
	$prunes_expressions_str .= " -a" if ($expressions_str);
	my $grep_options = $command_specs{grep_options};
	return &get_concatenated_with_delimiter("find", $follow, $paths, $recursive, $prunes_expressions_str, 
		"\\\! -empty -a -print0 2>/dev/null | xargs -0", $max_files_per_grep, $max_grep_procs, "grep", $grep_options, $pattern, " ");
}

sub read_user_arguments {
	&usage if (scalar(@ARGV) == 0);
	&parentheses_to_options(\@ARGV);
	&fix_petties(\@ARGV);
	my ($max_files_per_grep, $max_grep_procs, $recursive, $follow, $print_command, $pretty_print, $delimiter) = 
	   (          "DEFAULT",       "DEFAULT",          1,       1,              0,                     0,        ',');
	my %hash_options = ('max-files-per-grep=i'=>\$max_files_per_grep, 'max-grep-procs=i'=>\$max_grep_procs, 'recursive|r|R!'=>\$recursive, 
		'follow-symlink|S!'=>\$follow, 'print|p!'=>\$print_command, 'delimiter=s'=>\$delimiter, 'debug|g!'=>\$debug, 'help|?' => \&help_handler,
		'abs-path!'=>\$abs_path, 'ignore-me'=> 0, 'version|V' => \&version_handler, 'pretty-print' => \$pretty_print);
	&add_expression_opts(\%hash_options);
	# not used anymore - uses the -- separator instead to separate the grep options from the greps options, see extract_paths_and_grep_options
	#&add_grep_opts(\%hash_options);
	&set_feedback_handler;
	GetOptions(%hash_options);
        print_debug (__LINE__, "ARGV AFTER GetOptions: @ARGV");
	&usage if (scalar(@ARGV) == 0);
	&check_parentheses(\@greps_expressions);
	&add_missing_ors(\@greps_expressions);
	&check_binary_operators(\@greps_expressions);
	&unmark_all_expression_options(\@greps_expressions);
	my $pattern = shift(@ARGV); #extract the pattern 
	#$pattern='"'.$pattern.'" 'if ($pattern =~ m/\s/  &&  $pattern !~ m/^'.*'$/  &&  $pattern !~ m/^".*"$/);
	my $grep_opts = &get_grep_opts_from_config;
	my ($paths, $grep_options) = &extract_paths_and_grep_options(\@ARGV, $grep_opts);# all next args should be paths of files/dirs to search in, and then grep options
        print_debug (__LINE__, "paths=$paths; grep_options=$grep_options");
	my %command_specs = (max_files_per_grep => $max_files_per_grep, max_grep_procs => $max_grep_procs, recursive => $recursive, 
		follow => $follow, print_command => $print_command, delimiter => $delimiter, paths => $paths, pattern => $pattern, 
		greps_expressions => \@greps_expressions, greps_prunes => \@greps_prunes, pretty_print => $pretty_print, grep_options => $grep_options);
	return \%command_specs;
}

sub read_grep_opts_env_var {
	if (exists $ENV{GREPS_GREP_OPTIONS}) {
		return $ENV{GREPS_GREP_OPTIONS};
	}
	return "";
}

sub get_grep_opts_from_config {
	my %grep_config = ExpressionsFactory::instance->get_grep_config;
	return $grep_config{options};
}

#Return the prunes as string formatted for find command
sub get_find_prunes_string {
        &debug_enter_sub(__LINE__, "@_");
        my ($prunes_ref, $delimiter) = @_;
        my $prunes_str="";
        if (scalar @$prunes_ref > 0) {
                pop @$prunes_ref;
                $prunes_str = &get_find_expressions_string($prunes_ref, $delimiter);
                $prunes_str="\\\( $prunes_str -prune -a -type f \\\) -o";
        }
        &debug_leave_sub;
        return $prunes_str;
}

# Return the expressions as string formatted for find command
sub get_find_expressions_string {
	&debug_enter_sub(__LINE__, "@_");
	my @expression_options = @{$_[0]};
	print_debug (__LINE__, "expression_options=@expression_options");
	my $delimiter = $_[1];
	ExpressionsFactory::instance->set_delimiter($delimiter);
	my $find_expressions_string = "";
	foreach my $exp_opt(@expression_options) {
		$find_expressions_string .= ExpressionsFactory::instance->create($exp_opt)->get_find_expression." ";
	}
	$find_expressions_string =~ s/ $//;
	if (scalar @expression_options > 1) {
		$find_expressions_string = "\\\( $find_expressions_string \\\)";  
	}
	print_debug (__LINE__, "find_expressions_string=$find_expressions_string");
	&debug_leave_sub;
	return $find_expressions_string;
}

sub unmark_all_expression_options {
	my ($expression_options_ref) = @_;
	for (my $i=0; $i<scalar @$expression_options_ref; $i++) {
		$expression_options_ref->[$i] =~ s/^_[a-z_]+_//;
	}
}

sub check_binary_operators {
	my @exp_opts = @{$_[0]};
	return if (scalar @exp_opts == 0);
	if (&is_binary_operator($exp_opts[0])) {
		&error(1, "found a binary operator \'--".&get_unmarked_as_binary_operator($exp_opts[0])."\' with no expression on its left.");
	}		
	for (my $i=1; $i<scalar @exp_opts; $i++) {
		if (&is_binary_operator($exp_opts[$i]) && !&is_operaterable_on_left($exp_opts[$i-1])) {
			&error(1, "found a binary operator \'--".&get_unmarked_as_binary_operator($exp_opts[$i])."\' with no expression on its left.");
		}
		elsif (!&is_operaterable_on_right($exp_opts[$i]) && &is_binary_operator($exp_opts[$i-1])) {
			&error(1, "found a binary operator \'--".&get_unmarked_as_binary_operator($exp_opts[$i-1])."\' with no expression on its right.") 
		}
	}
	&error(1, "found a binary operator \'--".&get_unmarked_as_binary_operator($exp_opts[$#exp_opts])."\' with no expression on its right.") 
		if (&is_binary_operator($exp_opts[$#exp_opts]));
}

sub check_parentheses {
	my $args_ref = $_[0];
	my $balance_status = 0;
	for (my $i=0; $i<scalar @$args_ref; $i++) {
		my $arg = $args_ref->[$i];
		if ($arg eq 'paren-open') {
			$balance_status++;
			&error (1, "found empty parentheses") if (($i+1 < scalar @$args_ref) && ($args_ref->[$i+1] eq 'paren-close'));
		}
		elsif ($arg eq 'paren-close') {
			$balance_status--;
		}   
		&error(1, "found closing parenthesis with no opening one before it") if ($balance_status < 0);
	}
	&error(1, "found too many opening parentheses") if ($balance_status > 0);
} 

sub is_binary_operator {
	return $_[0] =~ m/_binop_/;
}

sub get_marked_as_binary_operator {
	return "_binop_".$_[0];
}

sub get_unmarked_as_binary_operator {
	$_[0] =~ s/_binop_//;
	return $_[0];
}

sub is_evaluative_expression {
	return $_[0] =~ m/_evexp_/;
}

sub get_marked_as_evaluative_expression {
	return "_evexp_".$_[0];
}

sub greps_expression_options_pusher {
	my ($options_ref, @options) = @_;
	push (@$options_ref, @options);
}

sub greps_assignable_expression_handler {
	&greps_expression_options_pusher(\@greps_expressions, &get_marked_as_evaluative_expression("$_[0]=$_[1]"));
}

sub greps_lang_expression_handler {
	&greps_expression_options_pusher(\@greps_expressions, &get_marked_as_evaluative_expression($_[0]));
}

sub greps_binary_operator_expression_handler {
	&greps_expression_options_pusher(\@greps_expressions, &get_marked_as_binary_operator($_[0]));
}

sub greps_prune_expression_handler {
	&greps_expression_options_pusher(\@greps_prunes, $_[0]."=".$_[1], "or");
}

sub greps_bracket_expression_handler {
	&greps_expression_options_pusher(\@greps_expressions, $_[0]);
}

sub version_handler {
    (print "greps ".&VERSION." \n\n") && exit 0;
}

sub xargs_handler {
	my ($key,$value)=@_;
	if ($value eq "DEFAULT") {
		return "";
	}
	my $buttom=-1;
	my $option = "";
	if ($key eq 'max-files-per-grep') {
		$option = "-n $value";
		$buttom=1 if ($value<1);
	}
	elsif ($key eq 'max-grep-procs') {
		$option = "-P $value"; 
		$buttom=0 if ($value<0);
	}
	&error(1,"value for --$key option should be >= $buttom") if ($buttom>-1);
	return $option;
}

# Handler for gathering the installed grep assignable options
sub grep_assignable_opts_handler {
	my $option = "";
	if (length($_[0]) > 1) {
		# this is long form of option
		if ($_[0] =~ m/colou?r/) {
			if (!(("auto" eq $_[1]) || ("always" eq $_[1]) || ("never" eq $_[1]))) {
				unshift(@ARGV, $_[1]) if ($_[1]); #put back the next argument, which mistakenly treated as color value
				$_[1]="auto";
			}
		}
		$option = "--".$_[0]."=".$_[1];
	}
	else {
		$option = "-".$_[0]." ".$_[1];
	}
	$grep_args = &get_concatenated_with_delimiter($grep_args, $option, " ");
}

# Handler for gathring the installed grep boolean options
sub grep_bool_opts_handler {
	my $option = "";
	if (length($_[0]) > 1) {
	# this is long form of option
		$option = "--".$_[0];
	}
	else {
		$option = "-".$_[0];
	}
	$grep_args = &get_concatenated_with_delimiter($grep_args, $option, " ");
}

sub help_handler {
	my $num_of_chars=32;
	my $help=USAGE_MSG."\n";
	$help.="Search for PATTERN in FILE.\n";
	$help.="PATTERN is, by default, a basic regular expression (BRE).\n";
	$help.="Example: greps -rX h,c 'hello world' -- -i -- color\n";
	$help.="\nMiscellaneous:\n";
	$help.=&get_padded_with_spaces("  -V  --version",$num_of_chars)."print version information and exit\n";
	$help.=&get_padded_with_spaces("      --help",$num_of_chars)."display this help and exit\n";
	$help.="\nSubset selection:\n";
	$help.=&get_padded_with_spaces("  -N, --[i]name=NAME",$num_of_chars)."names separeted by commas of files to search in\n";
	$help.=&get_padded_with_spaces("  -X, --[i]ext=EXTENTSION",$num_of_chars)."extensions separeted by commas of files to search in\n";
	$help.=&get_padded_with_spaces("      --and",$num_of_chars)."the expression on left is and'd with the expression on right\n";
	$help.=&get_padded_with_spaces("      --delimiter=DELIMITER",$num_of_chars)."select delimiter for patterns of files and dirs\n";
	$help.=&get_padded_with_spaces("      --or",$num_of_chars)."the expression on left is or'd with the expression on right\n";
	$help.=&get_padded_with_spaces("      --prune-[i]name=NAME",$num_of_chars)."names of dirs seperated by commas to prune\n";
	$help.=&get_padded_with_spaces("      --prune-[i]path=PATH",$num_of_chars)."paths of dirs seperated by commas to prune\n";
	$help.=&get_padded_with_spaces("      --[no]follow-symlink",$num_of_chars)."follow symbolic links (enabled by default)\n";
	$help.=&get_padded_with_spaces("  -r, -R, --[no]recursive",$num_of_chars)."recursively search in listed directories (enabled by default)\n";
	$help.="\nLanguages subsets:\n";
	my %languages = ExpressionsFactory::instance->get_languages;
	foreach my $lang (sort(keys %languages)) {
		my $lang_name = $lang;
		$help.=&get_padded_with_spaces("      --$lang",$num_of_chars)."search in ".ucfirst($lang)." files\n";	
	}
	$help.="\nOutput control:\n";
	$help.=&get_padded_with_spaces("  -g  --debug",$num_of_chars)."execution with debug messages\n";
	$help.=&get_padded_with_spaces("  -p  --print",$num_of_chars)."print the generated command and exit\n";
	$help.=&get_padded_with_spaces("      --[no]abs-path",$num_of_chars)."files of results are showed always in absolute path\n";
	$help.=&get_padded_with_spaces("      --pretty-print",$num_of_chars)."print the generated command with indentations and exit\n";
	$help.="\nPerformance control:\n";
	$help.=&get_padded_with_spaces("      --max-files-per-grep=MAX",$num_of_chars)."use at most MAX files for each grep instance\n";
	$help.=&get_padded_with_spaces("      --max-grep-procs=MAX",$num_of_chars)."run at most MAX grep instances at a time\n";
	$help.="\nType grep --help to see your installed grep options.\n";
	print "$help";
	exit(0);
}

sub myexit {
	my ($primary_status,$seconday_status)=@_;
	if ($primary_status != 0) {
		exit $primary_status;
	}
	elsif ($seconday_status == -1  ||  $seconday_status & 127) {
		exit 2;
	}
	elsif ($seconday_status >> 8) {
		exit 1;
	}
	exit 0;
}

# Set handler on usage error
sub set_feedback_handler {
	$SIG{__WARN__} = sub {
		my $msg=lcfirst($_[0]);
		if ($msg =~ m/option .* is ambiguous \(color, colour\)|option colou?r requires an argument/) {
			&grep_assignable_opts_handler("color","auto");
		}
		else {
			print STDERR &PROG_NAME.": $msg";
			&usage;
		}
	}
}

sub add_expression_opts {
	my $hash_options_ref = $_[0];
	my @pad = ("|N=s", "=s", "|X=s", "=s");
	my @assignable_expressions = @{&get_zipped(&ExpressionsFactory::ASSIGNABLE_EXPRESSION_OPTIONS, \@pad)};
	my @binary_operator_expressions = @{&ExpressionsFactory::BINARY_OPERATOR_EXPRESSION_OPTIONS};
	my %languages = ExpressionsFactory::instance->get_languages;
	my @languages_expressions = keys %languages;
	@pad = ("=s", "=s", "=s", "=s");
	my @prune_expressions = @{&get_zipped(&ExpressionsFactory::PRUNE_EXPRESSION_OPTIONS, \@pad)};
	my @bracket_expressions = @{&ExpressionsFactory::BRACKET_OPERATOR_EXPRESSION_OPTIONS};
	my @expression_families = (\@assignable_expressions, \@binary_operator_expressions, \@languages_expressions, \@bracket_expressions, \@prune_expressions);
	my @expression_handlers = (\&greps_assignable_expression_handler, \&greps_binary_operator_expression_handler, 
		\&greps_lang_expression_handler, \&greps_bracket_expression_handler, \&greps_prune_expression_handler);
	for (my $i=0; $i<scalar @expression_families; $i++) {
		my @expressions = @{$expression_families[$i]};
		foreach my $expression_option (@expressions) {
			$hash_options_ref->{$expression_option} = $expression_handlers[$i];
		}
	}
}

# Add the installed grep options so we can recognize them while reading the command line arguments
sub add_grep_opts {
	my ($hash_options_ref) = @_;
	my $assignable_ref=\&grep_assignable_opts_handler;
	my $bool_ref=\&grep_bool_opts_handler;
	my $grep_help=`grep --help`;
	my @lines=split /\n/, $grep_help;
	foreach my $line(@lines) {
		$line =~ s/\]//g;
		$line =~ s/\[//g;
		if ($line =~ m/^((\s+-([a-zA-Z]),)*\s+--([a-zA-Z-]+)(\=[a-zA-Z]+)?)/) {
			my $pattern=$1;
			next if ($pattern =~ m/--help|--recursive|--version/);
			$pattern =~ s/\s+//g;
			my @opts=split /,/, $pattern;
			my ($short,$long,$is_assignable)="";
			foreach my $opt(@opts) {
				if ($opt =~ m/^-([a-zA-Z])/) {
					$short.=$1."|";
				}
				elsif ($opt =~ m/^--([a-zA-Z-]+)/) {
					$long=$1;
					$is_assignable=($opt =~ m/--[a-zA-Z-]+\=[a-zA-Z]+/);
				}
			}
			if ($is_assignable) {
				#this option is assignable
				$hash_options_ref->{"$short$long=s"}=$assignable_ref;
			}
			else {
				#this option is boolen
				$hash_options_ref->{"$short$long"}=$bool_ref;
			}
		}
		elsif ($line =~ m/^\s+-([a-zA-Z])\s+/) {
			# actually special case for -I
			&print_debug(-2, "$1");
			$hash_options_ref->{$1}=\&grep_bool_opts_handler;
		}
	}
}

sub add_missing_ors {
	my $exp_opts_ref = $_[0];
	return if (scalar @$exp_opts_ref == 0);
	my @tmp = ($exp_opts_ref->[0]);
	for (my $i=1; $i<scalar @$exp_opts_ref; $i++) {
		if (&is_operaterable_on_right($exp_opts_ref->[$i]) && &is_operaterable_on_left($exp_opts_ref->[$i-1])) {
			push(@tmp, &get_marked_as_binary_operator("or"));
		}
		push(@tmp, $exp_opts_ref->[$i]);
	}
	for (my $i=0; $i<scalar @tmp; $i++) {
		$exp_opts_ref->[$i] = $tmp[$i];
	}
}

sub is_operaterable_on_right {
	return (&is_evaluative_expression($_[0]) || ($_[0] eq "paren-open"));
}

sub is_operaterable_on_left {
	return (&is_evaluative_expression($_[0]) || ($_[0] eq "paren-close"));
}

# Returns the grep options, assuming they all have at least one dash in front of each 
# We will find the first dash and cut out the whole thing after it and pass as is to grep
sub extract_grep_optiobs {
		
}

# Returns the paths as given by the user
sub extract_paths_and_grep_options {
	my @arguments = @{$_[0]};
	my $grep_options = "$_[1]";
	my $paths="";
	my $already_in_command_grep_options = 0;
	#push (@arguments, ('.')) if (scalar(@arguments)==0);
	foreach my $arg(@arguments) {
        	print_debug (__LINE__, "current arg=$arg");
		if ($arg =~ /^-/ || $already_in_command_grep_options) {
			$grep_options = &get_concatenated_with_delimiter($grep_options, $arg, " ");
			$already_in_command_grep_options = 1;
		}
		elsif (!(-e $arg)) {
			&error(0,"$arg: No such file or directory");
		}
		else {
			if ($abs_path) {
				$arg=abs_path($arg);
			}
			$paths = &get_concatenated_with_delimiter($paths, $arg, " ");
		}
	}
	if (length($paths) == 0) {
		$paths = ".";
		if ($abs_path) {
			$paths=abs_path($paths);
		}
	}
	return ($paths, $grep_options);
}

# Returns the given greps patterns in the format of find, for example -name '*.cpp' ...
sub get_find_patterns_formatted {
	my $patterns_raw=$_[0]; # the given patterns seperated by commas
	my $selector_type=$_[1]; # the desired selector (name, path, etc)
	my $left_pad=$_[2]; # left pad for each pattern 
	my $right_pad=$_[3]; # right pad for each pattern 
	my $operator=$_[4]; # which binary operator to use between the expressions (o, a) 
	my $delimiter=$_[5];
	my $result="";
	my @patterns=&get_tokens($patterns_raw,$delimiter);
	foreach my $token (@patterns) {
		$result.=" -".$selector_type." '".$left_pad.$token.$right_pad."' -".$operator;
		$result =~ s/^\s//;
		if ($abs_path) {
			# in case of using abs path always anyway we will do special effort to be more liberate with the given dir paths - 
			# that is we will tranforn each dir path to it's absolute path and thus will overcome the prune-path 'problem' in find
			# that is - paths and prunes are all absolute or all relative.
			# Still there is a problem with the Symlinks - When transform symlink dir (for prune) to it's abs form the resulted path might be 
			# almost entirely different then the given path(s) to find in.
			my $a=abs_path($token);
			if ($selector_type eq "path"  &&  (-d $token)  &&  (!($token eq $a))  &&  (!($token eq "$a\/"))) { 
				# when dealing with paths of dirs we must take the absolute form as well (if it is not already absolute)
				# this is because two different reasons:
				# 1. find makes the 'prune test' against the given path(s) to search in, and they must be relative/absolute together (it won't work otherwise).
				#    In this program all the paths are always absolute, so here either.
				# 2. when token is a sysmlink dir or dir that goes thru a symlink, even if the given dir is absolute path already (as actually expected), 
				#    it is different whether the recursive search 
				#    started from above or below the symlink: if it started from above find will ignore the absolute path generated by abs_path and it the user 
				#    responsibility to give absolute path as seen from the 'linked' place, and if it started from below the symlink find will ignore the  
				#    absolute path the user expected to give and will treat the abs_path generation instead.
				$result.=" -".$selector_type." '".$left_pad.abs_path($token).$right_pad."' -".$operator;
			}
		}
	}
	return substr($result, 0, (length($result)-3));
}

sub get_tokens {
	my $string=$_[0];
	my $delimiter=$_[1];
	my @tokens=();
	if ($delimiter eq '/') {
		# remove the last delimiter (actually '/')
		$string=substr($string, 0, length($string)-length($delimiter));
		# the user does not want to use delimiter, but treat the whole string as pattern
		push (@tokens, $string);
	}
	else {
		@tokens=split($delimiter, $_[0]);
	}
	return @tokens;
}

sub get_zipped {
	my ($array_ref1, $array_ref2) = @_;
	my @zipped_array = ();
	for (my $i=0; $i<scalar @$array_ref1; $i++) {
		push (@zipped_array, $array_ref1->[$i].$array_ref2->[$i]);
	}
	return \@zipped_array;
}

sub print_hash {
	my %hash = %{$_[0]};
	print \%hash."(\n";
	foreach my $key(keys %hash) {
		print "\t$key => ".$hash{$key}."\n";
	}
	print ")\n";
}

sub get_concatenated_with_delimiter {
	my @strings = ();
	my $delimiter = pop(@_);
	if (ref($_[0]) eq "ARRAY") {
    		my ($strings_ref) = @_;
    		@strings = @$strings_ref;
	}
	else {
		@strings = @_;
	}
	my $result = "";
    	foreach my $str(@strings) {
		$result .= "$str$delimiter" if ($str);
	}
	$result = substr($result, 0, length($result)-length($delimiter));
	return $result;
}

sub is_word_starts_with {
	my ($a1,$a2)=@_;
	#$a2 =~ m/(.)/;
	#$a2 = '\\'.$a2 if ($1 eq '*');
	return ($a1 =~ m/^$a2/ && $a2 =~ m/\w+/);
}

sub print_debug {
	if ($debug && $_[0]!=-2) {
		&print_tabs(2, $tabs_counter);
		if ($_[0]==-1) {
			printf (STDERR "%s\n", $_[1]);
		}
		else {
			printf (STDERR "%d: %s\n", $_[0], $_[1]);
		}
	}
}

sub error {
	my $is_exit=shift @_;
	my $msg=&PROG_NAME.": @_\n";
	print STDERR $msg;
	$status=2;
	#my $trace = Devel::StackTrace->new;
	#print $trace->as_string; # like carp
	exit 2 if ($is_exit);
}

sub get_padded_with_spaces {
	my ($text,$max_spaces)=@_;
	my $length=length($text);
	for (my $i=0; $i<$max_spaces-$length; $i++) {
		$text.=' ';
	}
	return $text;
}

sub assert {
	if ($assert_flag) {
		my ($condition, $line, $msg) = @_;
		if (!$condition) {
			my $me = ( caller(1) )[3];
			$me =~ s/.*:://;
			print STDERR "$line: $me: $msg\n";
			exit 1;
		}
	}
}

sub debug_enter_sub {
	if ($debug) {
		$_[1] =~ s/=HASH\([0-9a-zA-Z]+\)//g; 
		my $me=( caller(1) )[3];
		$me =~ s/.*:://;
		&print_tabs(2, $tabs_counter);
		my $line=shift;
		print STDERR "$line: $me (@_) {\n";
		$tabs_counter++;
	}
}

sub debug_leave_sub {
	if ($debug) {
		$tabs_counter--;
		&print_tabs(2, $tabs_counter);
		print STDERR "}\n";
	}
}

sub print_tabs {
	my $fh=$_[0];
	my $tabs_counter = $_[1];
	my $tab=' ' x 4;
	for (my $i=0; $i<$tabs_counter; $i++) {
		if ($fh==2) {
			print STDERR $tab;
		}
		else {
			print $tab;
		}
	}
}

sub parentheses_to_options {
	my $arguments_ref = $_[0];
	for (my $i = 0; $i < scalar @{$arguments_ref}; $i++) {
		if ($arguments_ref->[$i] eq '(') {
			$arguments_ref->[$i] = "--paren-open";
		}
		elsif ($arguments_ref->[$i] eq ')') {
			$arguments_ref->[$i] = "--paren-close";
		}
	}
}

sub fix_petties {
	my $arguments_ref = $_[0];
	my $i=0;
	foreach my $arg(@{$arguments_ref}) {
		while ($arg =~ m/^-[^-^\d]*(\d+)[^-]*/) {
			push (@$arguments_ref, ("-C","$1"));
			$arguments_ref->[$i] =~ s/\d+//;
			$arguments_ref->[$i] =~ s/^-$/--ignore-me/;
		}
		$i++;
	}
	#print "arguments_ref=@$arguments_ref\n";
}

sub pretty_print {
	my ($command) = @_;
	my @saved = ();
	my $command_with_stubs = &save_assignable_tests($command, \@saved);
	#print "saved=@saved\n";
	#print "command_with_stubs=$command_with_stubs\n";
	my @splitted = split(/(\\\(|\\\))/, $command_with_stubs);
	my @command_array = ();
	foreach my $item(@splitted) {
		$item =~ s/^ //;
		$item =~ s/ $//;
		if ($item =~ m/^\\\(|\\\)$/) {
			$item =~ s/^\\//;
		}
		else {
			my $stub_pattern = "-saved(\\d+) ?";
			while ($item =~ m/$stub_pattern/ && $1 <= $#saved) {
				$item =~ s/$stub_pattern/$saved[$1]/;
			}
		}
		push (@command_array, $item) if ($item);
	}              

	my $tabs_counter = 0;
	foreach my $item(@command_array) {
		$tabs_counter-- if ($item eq ')');
		&print_tabs(0, $tabs_counter);
		print "$item\n";
		$tabs_counter++ if ($item eq '(');
	}                   
}

# Helper for pretty_print
# save the find tests expressions to protect them from
# a possible split (for example, if they contains a parentheses in the pattern)
sub save_assignable_tests {
	my ($out, $saved_ref) = @_;
	my $index = 0;
	$out =~ s/(find.+?-type f (-a )?)//;
	my $prefix = $1;
	$prefix = &get_saved($prefix, $saved_ref, \$index);
	#print "prefix=$prefix\n";
	$out =~ s/((-a )?\\! -empty -a -print0 2>\/dev\/null \| xargs.+)//;
	my $suffix = $1;
	#print "suffix=$suffix\n";
	$out = &get_saved($out, $saved_ref, \$index);
	return $prefix.$out.$suffix;
}

sub get_saved {
	my ($out, $saved_ref, $index_ref) = @_;
	#print "out=$out\n";
	my $saved_pattern = "(-i?(name|path) .*? )";
	while ($out =~ m/$saved_pattern/) {
		my $to_save = $1;
		#print "to_save=$to_save\n";
		push (@$saved_ref, $to_save);
		$out =~ s/$saved_pattern/-saved$$index_ref /;
		$$index_ref++;
	}
	return $out;
}

sub usage {
	print STDERR USAGE_MSG."\n";
	print STDERR "Try `".&PROG_NAME." --help' for more information.\n";
	exit 2;
}

sub enable_assert {
	my $mac = '00:1a:6b:ce:49:c1';
	my @eth0 = `/sbin/ifconfig eth0 2>/dev/null`;
	return @eth0 && ($eth0[0] =~ m/(([a-fA-F0-9]{2}:){5}[a-fA-F0-9]{2})/) && (($1 eq $mac)?1:0);
}

