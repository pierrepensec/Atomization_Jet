#!/bin/bash
set -e

# Compilation avec OpenMP pour la parallélisation
qcc -O2 -Wall -fopenmp atomisation.c -o atomisation -lm

# Allocation stricte de 3 cœurs pour les calculs
export OMP_NUM_THREADS=3

echo "maxlevel uemax temps n_gouttes D32" > metriques_comparatives.dat

for lvl in 8 9 10; do
  for ue in 0.1 0.05 0.01; do
    echo "Lancement: maxlevel=$lvl, uemax=$ue sur 3 coeurs"
    ./atomisation $lvl $ue 2>> metriques_comparatives.dat
  done
done