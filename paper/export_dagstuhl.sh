#!/bin/bash

if [[ $(git diff --shortstat 2> /dev/null | tail -n1) != "" ]] ; then
  echo "Cant export - would possibly override stuff"
  exit 0
fi

sed -i '/^%/ d' tdpot.tex

zip dagstuhl.zip \
tdpot.tex \
references.bib \
fig/* \
table/pot_perf.tex

git checkout tdpot.tex
