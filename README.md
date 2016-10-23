greps (grep subset)
-------------------
version: 0.81

Description
-----------
greps is a script written in perl which wraps the regular installed grep with new options that can make the search faster and return more relevant results (actully less non-relevant results). .
Basically what it does is allowing you to choose also the patterns or extentions of the desired files. Then it executes find for finding such files and executes grep on those files.
The usage of greps is same as you would use grep (see exceptions in the man).
To see all the available options that greps adds to your installed grep - call greps --help or man greps.

Install
-------
chmod a+r,a+x greps
sudo cp greps /usr/local/bin
sudo cp greps.1.gz /usr/share/man/man1/ # for manpage

Changes included in version 0.8
-------------------------------
* Added support for parentheses
* Changed the behavior of --and,--or to normal - not all the expressions on left are or'd/and'd with the one on right anymore, 
  but, as regularly, only the one close expression on left is or'd/and'd with the expression on right (as you should be used to)
* Added filtering out empty files before the execution of grep
* Fixed bug - exit status was 0 instead of 1 when no matching files where found
  This didn't follow the behavior of grep: when no instance of pattern was found it returns 1
* Added a regular manpage, instead of the Pod::Usage one, thus removing the requirement for it
* Removed (again) the requirement for Getopt::Long version >= 2.37

Changes included in version 0.7.6.1
-------------------------------
* Fixed bug - it was not adding 'or' when there are 2 or more prunes
* Fixed bug - added '-a -type f' together with -prune, so it if the prune test succeeds then the pruned directory will not continue to the next tests
* Added error messages when binary operators are not used correctly
* Added clarification for options --or,--and in the man page for what is considired an expression


Changes included in version 0.7.6
-----------------------------------
* Added new option: --print-commnd-indent
* Moved find's -type f operator to be immediately after the -prune (if there is -prune). This filters out non-files in earlier stage
* Fixed bug - when using number>9 as option it was not received correctly as -C number
* Refactor code

Changes included in version 0.7.5.1
-----------------------------------
* Avoid the usage of GetOptionsFromString of Getopt::Long, which is relatively new and not available on all machines
* Replace the usage of find's -executable operator, which also is relatively new, with -perm -u+x
* Remove find's -a operator after -maxdepth, because old versions of find do not allow 'to and' -maxdepth (and is implicit)

Changes included in version 0.7.5
---------------------------------
* Refactor - improve code modularity
* The command generation works faster
* Added test script

Changes included in version 0.7
----------------------------------
* Fixed a bug in the prune options - should filter out directories *after* the prune operation 
* Improve the manual and help

Changes in included in version 0.6
----------------------------------
* Added languages awk,perl,python,shell,tcl
* Added exit status to greps
* Document these additions in help and man page

First published version is 0.4
