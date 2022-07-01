#!/bin/bash

if [[ $(git diff --shortstat 2> /dev/null | tail -n1) != "" ]] ; then
  echo "Cant export - would possibly override stuff"
  exit 0
fi

sed -i '/^%/ d' tdpot.tex
sed -i 's/bibliography{references}/input{tdpot.bbl}/' tdpot.tex

zip arxiv.zip \
tdpot.tex \
tdpot.bbl \
lipics-v2021.cls \
fig/* \
table/pot_perf.tex

git checkout tdpot.tex
