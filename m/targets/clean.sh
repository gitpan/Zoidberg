FILES='Makefile b/ m/config.pd'
for F in $FILES; do rm -fr $F && echo removed $F; done;
