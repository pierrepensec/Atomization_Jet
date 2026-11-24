/**
 * Simulation DNS-VOF d'un jet liquide rond pulsé avec procédure de
 * Manifold Death (perforation contrôlée des nappes liquides minces sous hc).
 * D'après Kulkarni et al. (JFM, 2025) & Chirco et al. (JCP, 2022).
 */

// Utiliser "grid/octree.h" pour le 3D 
// (Passer à "grid/quadtree.h" désactivera automatiquement le bloc MD en 2D).
#include "grid/octree.h"
#include "navier-stokes/centered.h"
#include "two-phase.h"
#include "tension.h"
#include "fractions.h"
#include "tag.h"

#if dimension == 3
  #define SQUARES        // Perforation par trous carrés (standard Chirco et al.)
  #include "signature.h" // Doit être présent dans le dossier (sandbox/lchirco/signature.h)
#endif

// --- Paramètres géométriques et physiques du jet ---
double radius = 1./12.;   // Rayon de l'injecteur R
double length = 0.025;    // Longueur initiale du noyau liquide dans le domaine
double Re     = 5800.;    // Nombre de Reynolds du jet
double SIGMA  = 3e-5;     // Coefficient de tension superficielle

// --- Paramètres de maillage adaptatif (AMR) ---
int maxlevel  = 9;        // Niveau de raffinement maximal
double uemax  = 0.1;      // Critère d'erreur wavelet sur la vitesse

// --- Paramètres de pulsation à l'injection ---
double u0     = 1.;       // Vitesse moyenne d'injection
double au     = 0.05;     // Amplitude de la modulation sinusoïdale
double T0     = 0.1;      // Période de pulsation

// --- Paramètres du Manifold Death (MD) ---
double hc     = 0.015625; // Épaisseur critique de rupture des nappes (ex: 2 * L0 / 2^8)
int n_holes   = 4;       // Nombre maximal de trous percés par appel de MD
int L_sig     = 8;        // Niveau de grille de signature (calculé depuis hc dans main)

scalar f0[];              // Profil géométrique fixe de l'injecteur

// --- Conditions aux limites ---
// Entrée (gauche) : jet pulsé sur la section circulaire f0[]
u.n[left]  = dirichlet(f0[]*(u0 + au*sin (2.*pi*t/T0)));
u.t[left]  = dirichlet(0.);
#if dimension > 2
u.r[left]  = dirichlet(0.);
#endif
p[left]    = neumann(0.);
f[left]    = f0[];

// Sortie libre (droite)
u.n[right] = neumann(0.);
p[right]   = dirichlet(0.);

int main (int argc, char * argv[])
{
  if (argc > 1)
    maxlevel = atoi (argv[1]);
  if (argc > 2)
    uemax = atof (argv[2]);
  if (argc > 3)
    hc = atof (argv[3]);

  init_grid (64);
  size (2.);              // Taille du domaine cubique L0 = 2
  origin (0., -1., -1.);  // Domaine [0, 2] x [-1, 1] x [-1, 1] (z ignoré en 2D)

  // Calcul du niveau de signature L_sig correspondant à l'épaisseur critique hc :
  // hc ~ 2 * Delta_sig = 2 * L0 / 2^(L_sig)
  L_sig = (int) round (log (3.*L0/hc)/log (2.));
  if (L_sig > maxlevel)
    L_sig = maxlevel;     // L_sig ne peut pas dépasser la résolution maximale du maillage

  // Propriétés des fluides (phase 1 : liquide, phase 2 : gaz ambiant)
  rho1 = 1. [0];
  rho2 = rho1/27.84;
  mu1  = 2.*u0*radius/Re*rho1;
  mu2  = 2.*u0*radius/Re*rho2;
  f.sigma = SIGMA;

  run();
}

// --- Initialisation du champ de fraction volumique et de vitesse ---
event init (t = 0) {
  if (!restore (file = "restart")) {
    // Pré-raffinement autour de la buse d'injection
    refine (x < 1.2*length && sq(y) + sq(z) < 2.*sq(radius) && level < maxlevel);

    // Définition du cylindre d'injection (cercle en 2D car z = 0)
    fraction (f0, sq(radius) - sq(y) - sq(z));
    f0.refine = f0.prolongation = fraction_refine;
    restriction ({f0}); // Nécessaire pour les conditions aux limites multigrilles

    foreach() {
      f[]   = f0[]*(x < length);
      u.x[] = u0*f[];
    }
  }
}

// --- Procédure de Manifold Death (perforation des nappes sous hc) ---
#if dimension == 3
scalar M[]; // Champ scalaire enregistrant le bilan de masse des perforations

event manifold_death (t += 0.2*T0) {
  scalar phii[], s[];
  foreach()
    phii[] = 2.*f[] - 1.;

  // Calcul de la signature topologique au niveau L_sig
  compute_signature_neigh_level (f, phii, s, L_sig);

  // Perforation de max n_holes nappes minces (false = trous de taille 3x3x3 mailles)
  change_topology (f, s, M, L_sig, n_holes, false);
}
#endif

// --- Filtrage des micro-gouttes numériques sous-résolues (< 3 mailles) ---
event filter (i++) {
  remove_droplets (f, 3);
}

// --- Suivi temporel du nombre de gouttes et du diamètre de Sauter ---
event log_metrics (t += 0.1) {
  int n_gouttes = tag (f);

  double volume = 0., area = 0.;
  foreach(reduction(+:volume) reduction(+:area)) {
    volume += f[] * dv(); // Volume liquide (aire en 2D)

    // Calcul de l'aire interfaciale (périmètre en 2D) dans les mailles mixtes
    if (f[] > 1e-6 && f[] < 1. - 1e-6) {
      coord n = mycs (point, f);
      double alpha = plane_alpha (f[], n);
      area += pow(Delta, dimension - 1) * plane_area_center (n, alpha, NULL);
    }
  }

  // Diamètre moyen de Sauter : D32 = 6*V/S en 3D, D21 = 4*A/P en 2D
  double coeff = (dimension == 3) ? 6. : 4.;
  double SMD = area > 0. ? coeff * volume / area : 0.;

  fprintf (stderr, "METRICS: maxlevel=%d uemax=%g hc=%g L_sig=%d t=%g n_gouttes=%d SMD=%g\n",
           maxlevel, uemax, hc, L_sig, t, n_gouttes, SMD);
}

// --- Journaux de performance du solveur ---
event logfile (i++) {
  if (i == 0)
    fprintf (stderr,
             "t dt mgp.i mgpf.i mgu.i grid->tn perf.t perf.speed\n");
  fprintf (stderr, "%g %g %d %d %d %ld %g %g\n",
           t, dt, mgp.i, mgpf.i, mgu.i,
           grid->tn, perf.t, perf.speed);
}

// --- Adaptation dynamique du maillage (AMR) ---
event adapt (i++) {
  adapt_wavelet ({f, u}, {0.01, uemax, uemax, uemax}, maxlevel);
}

// --- Sauvegarde régulière des fichiers binaires dump ---
event snapshot (t = 0.0; t += 2e-2; t <= 3.5) {
  char name[80];
  sprintf (name, "dump-%04d", (int) round (t/2e-2));
  scalar pid[];
  foreach()
    pid[] = fmod(pid()*(npe() + 37), npe());
  dump (name);
}