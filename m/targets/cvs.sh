#!/bin/bash

echo "## This script will try to update this Zoidberg source tree from CVS" &&
echo "## It is possible this won't work due to changes in the structure," &&
echo "##  especially when this tree is older then the last release" &&
echo "## Type <return> when prompted for a password" &&
cd ..               &&
ls -d Zoidberg-cvs  &&
cvs -d:pserver:anonymous@cvs.zoidberg.sourceforge.net:/cvsroot/zoidberg login  &&
cvs -z3 -d:pserver:anonymous@cvs.zoidberg.sourceforge.net:/cvsroot/zoidberg co Zoidberg-cvs &&
echo "## You should run 'perl Makefile.PL' again now."
