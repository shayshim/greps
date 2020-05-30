greps (grep subset)
-------------------
version: 0.82

Description
-----------
greps extends your installed grep with new options that can make the search faster and return more relevant results (or less non-relevant results).
Basically what it does is allowing you to choose also patterns or extentions of desired files. Then it executes find for finding such files and executes grep on these files (find ... | xargs grep ...).

Install
-------
chmod a+r,a+x greps

cp greps /usr/local/bin

Note: was tested only on Ubuntu and Red Hat.

Usage
-----
To see all the available options that greps adds to your installed grep - call greps --help.

Examples
--------
greps what where/ -- -i

Recursively search for the word what with option -i enabled (owned by grep) in directory where/. This will behave exactly the same as grep -R what -i where/. Note that you can pass options to grep if you put them after --. Also note that the search is recursive by default.

greps what where1/ where2/ -X h -- -inw --color

Recursively search what in directories where1/ where2/ with options -i -n -w --color enabled (owned by grep) in h files. 

greps "what what" --name='a\*','b\*' where/

Recursively search for phrase "what what" in where/ in files that their name starts with a or b.

greps what -X java --abs-path where/

Recursively search for what in directory where/ in Java files, and cause grep to print the absolute path of each file in result.

greps --perl what where/ --and -N 'c*'

Recursively search what in where/ in Perl files that their name starts with c. Note that expressions don't have to be grouped next to each other (the exprssions here  are  --perl,  --and,  -N 'c*').

greps what \\( --c --or --perl \\) --and -N 'd*' where/

Recursively search for what in where/ in C and Perl files that their name starts with d. Note that the --or option could be actualy removed and thus implicitely used.

greps --perl what --or --shell where/ --and -N '*e'

Recursively search what in where/ in (any) Perl files, and in Shell files that their name ends with e. Note that the --or option could be actualy removed and thus implicitely used.

greps what where/ --cpp --max-files-per-grep=60 --max-grep-processes=2

Recursively search what in where/ in C++ files. Execution is done with at most 2 grep instances at a time, and with at most 60 files as arguments for each grep instance.
