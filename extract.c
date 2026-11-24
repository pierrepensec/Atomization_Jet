#include "navier-stokes/centered.h"
#include "fractions.h"

scalar f[];

int main(int argc, char * argv[]) {
    // Vérifie que les arguments sont fournis
    if (argc < 3) return 1;
    
    char * dossier = argv[1];
    char * sortie = argv[2];
    FILE * fp = fopen(sortie, "w");
    
    // Ajuste la limite supérieure selon le nombre maximum de dumps par dossier
    for (int i = 0; i <= 1000; i++) {
        char name[256];
        sprintf(name, "%s/dump-%04d", dossier, i); 
        
        if (!restore(file = name)) break;

        double aire = 0., perimetre = 0.;
        
        foreach(reduction(+:aire)) {
            aire += f[] * dv();
        }
        
        foreach(reduction(+:perimetre)) {
            if (f[] > 1e-6 && f[] < 1. - 1e-6) {
                coord n = mycs (point, f);
                double alpha = plane_alpha (f[], n);
                coord segment[2];
                if (facets (n, alpha, segment) == 2) {
                    double dl = 0.;
                    foreach_dimension()
                        dl += sq(segment[0].x - segment[1].x);
                    perimetre += sqrt(dl) * Delta;
                }
            }
        }
        fprintf(fp, "%g %g %g\n", t, aire, perimetre);
    }
    fclose(fp);
}