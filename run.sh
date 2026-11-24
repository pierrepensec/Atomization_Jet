#!/bin/bash

# Compilation unique avec optimisation
qcc -O2 extract.c -o extract -lm

# Liste des répertoires contenant les dumps
dossiers=("run-L10-np3-ue0.001")

# "run-L8-np3-ue0.1" "run-L8-np3-ue0.001" "run-L9-np3-ue0.1" "run-L9-np3-ue0.001" "run-L10-np3-ue0.1" 

# Boucle d'exécution
for dir in "${dossiers[@]}"; do
    ./extract "$dir" "donnees_D21_$dir.txt"
done