#!/bin/bash

# pre-computed checksum
MD5SUM="8d7ecdf761f2241346a7859251f7877f"

# run mlm2 on sample dataset
# R CMD INSTALL --preclean --no-multiarch --with-keep.source ../mlm
# R -e "library(mlm); fit <- mlm2(biomarkers ~ .^2, data = patients); save(fit, file = 'ci/fit.rda')"
# [[ $(md5sum ci/fit.rda | awk '{$0=$1}1') == $MD5SUM ]]