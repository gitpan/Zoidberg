#!/bin/bash

echo "## This script will try to fetch the Zoidberg source tree from CVS" &&
echo "##  and install Zoidberg on your system. Root permission needed." &&
cd .. &&
(
	CVSROOT=:pserver:anonymous@cvs.zoidberg.sourceforge.net:/cvsroot/zoidberg \
		cvs -z3 checkout -P Zoidberg-cvs &&

	cd Zoidberg-cvs/ &&
	perl Makefile.PL &&
	make all &&

	echo "## If all seems well, type 'zoid' to start the Zoidberg shell" 
) || echo "## Something went wrong :(( you're on your own now"

